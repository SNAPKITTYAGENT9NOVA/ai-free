"""SLA Guard — 心跳檢測與逾時門檻模組.

監控頻率：每 3 秒自動同步節點狀態
逾時閾值：API / 工具執行上限 5 秒，超時判定節點滯留
重試策略：單次失敗後 1 次指數退避重試（1.5 秒），避免瞬態網路抖動誤判
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine

logger = logging.getLogger(__name__)

# ── 常數 ─────────────────────────────────────────────
HEARTBEAT_INTERVAL_S: float = 3.0   # 心跳輪詢間隔
TIMEOUT_THRESHOLD_S: float = 5.0    # API / 工具執行逾時門檻
RETRY_BACKOFF_S: float = 1.5        # 指數退避基底間隔
MAX_RETRIES: int = 1                # 最大重試次數（1 次）


class NodeStatus(Enum):
    """節點健康狀態."""

    HEALTHY = "HEALTHY"
    DEGRADED = "DEGRADED"       # 首次逾時，進入退避重試
    STAGNANT = "STAGNANT"       # 重試後仍逾時，判定滯留
    OFFLINE = "OFFLINE"         # 節點主動下線或連續失敗


@dataclass
class NodeHealth:
    """單一節點的健康紀錄."""

    node_id: str
    status: NodeStatus = NodeStatus.HEALTHY
    last_heartbeat: float = field(default_factory=time.monotonic)
    consecutive_failures: int = 0
    latency_ms: float = 0.0

    def mark_healthy(self, latency_ms: float) -> None:
        """標記節點為健康."""
        self.status = NodeStatus.HEALTHY
        self.last_heartbeat = time.monotonic()
        self.consecutive_failures = 0
        self.latency_ms = latency_ms

    def mark_degraded(self) -> None:
        """標記節點為降級（首次逾時）."""
        self.status = NodeStatus.DEGRADED
        self.consecutive_failures += 1

    def mark_stagnant(self) -> None:
        """標記節點為滯留（重試後仍失敗）."""
        self.status = NodeStatus.STAGNANT
        self.consecutive_failures += 1


# 心跳探針型別：接收 node_id，回傳延遲毫秒數
HeartbeatProbe = Callable[[str], Coroutine[Any, Any, float]]


class SLAGuard:
    """心跳檢測與逾時門檻守衛.

    Example
    -------
    >>> guard = SLAGuard(probe=my_ping_function)
    >>> guard.register("node-alpha")
    >>> await guard.start()          # 開始 3 秒輪詢
    >>> guard.get_health("node-alpha")
    NodeHealth(node_id='node-alpha', status=<NodeStatus.HEALTHY>, ...)
    """

    def __init__(
        self,
        probe: HeartbeatProbe,
        *,
        heartbeat_interval: float = HEARTBEAT_INTERVAL_S,
        timeout_threshold: float = TIMEOUT_THRESHOLD_S,
        retry_backoff: float = RETRY_BACKOFF_S,
        max_retries: int = MAX_RETRIES,
        on_stagnant: Callable[[str], None] | None = None,
    ) -> None:
        self._probe = probe
        self._interval = heartbeat_interval
        self._timeout = timeout_threshold
        self._backoff = retry_backoff
        self._max_retries = max_retries
        self._on_stagnant = on_stagnant
        self._nodes: dict[str, NodeHealth] = {}
        self._task: asyncio.Task[None] | None = None
        self._running = False

    # ── 節點管理 ──────────────────────────────────────

    def register(self, node_id: str) -> None:
        """註冊一個待監控的節點."""
        self._nodes[node_id] = NodeHealth(node_id=node_id)
        logger.info("SLAGuard: 註冊節點 %s", node_id)

    def unregister(self, node_id: str) -> None:
        """移除節點."""
        self._nodes.pop(node_id, None)
        logger.info("SLAGuard: 移除節點 %s", node_id)

    def get_health(self, node_id: str) -> NodeHealth | None:
        """取得節點健康狀態."""
        return self._nodes.get(node_id)

    def get_all_health(self) -> dict[str, NodeHealth]:
        """取得所有節點健康狀態."""
        return dict(self._nodes)

    # ── 單次探測（含重試） ────────────────────────────

    async def _probe_node(self, node_id: str) -> None:
        """對單一節點執行探測，含指數退避重試."""
        health = self._nodes.get(node_id)
        if health is None:
            return

        for attempt in range(1 + self._max_retries):
            try:
                latency_ms = await asyncio.wait_for(
                    self._probe(node_id),
                    timeout=self._timeout,
                )
                # ✅ 探測成功
                health.mark_healthy(latency_ms)
                logger.debug(
                    "SLAGuard: 節點 %s 心跳正常 (%.1fms)",
                    node_id,
                    latency_ms,
                )
                return

            except asyncio.TimeoutError:
                if attempt == 0:
                    # 首次逾時 → 降級，準備重試
                    health.mark_degraded()
                    backoff = self._backoff * (2**attempt)
                    logger.warning(
                        "SLAGuard: 節點 %s 逾時 (>%.1fs)，"
                        "%.1fs 後指數退避重試 (%d/%d)",
                        node_id,
                        self._timeout,
                        backoff,
                        attempt + 1,
                        self._max_retries,
                    )
                    await asyncio.sleep(backoff)
                else:
                    # 重試後仍逾時 → 判定滯留
                    health.mark_stagnant()
                    logger.error(
                        "SLAGuard: 節點 %s 重試後仍逾時，判定為 STAGNANT",
                        node_id,
                    )
                    if self._on_stagnant:
                        self._on_stagnant(node_id)

            except Exception:
                logger.exception(
                    "SLAGuard: 節點 %s 探測異常 (attempt %d)",
                    node_id,
                    attempt,
                )
                if attempt < self._max_retries:
                    await asyncio.sleep(self._backoff * (2**attempt))
                else:
                    health.mark_stagnant()
                    if self._on_stagnant:
                        self._on_stagnant(node_id)

    # ── 輪詢迴圈 ─────────────────────────────────────

    async def _loop(self) -> None:
        """每 3 秒輪詢所有節點."""
        while self._running:
            tasks = [
                self._probe_node(nid) for nid in list(self._nodes)
            ]
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            await asyncio.sleep(self._interval)

    async def start(self) -> None:
        """啟動心跳監控."""
        if self._running:
            return
        self._running = True
        self._task = asyncio.create_task(self._loop())
        logger.info(
            "SLAGuard: 啟動 (間隔=%.1fs, 逾時=%.1fs, 退避=%.1fs)",
            self._interval,
            self._timeout,
            self._backoff,
        )

    async def stop(self) -> None:
        """停止心跳監控."""
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None
        logger.info("SLAGuard: 已停止")

    # ── 同步單次檢測（供外部手動觸發） ────────────────

    async def check_once(self) -> dict[str, NodeHealth]:
        """手動觸發一次全節點檢測，回傳結果."""
        tasks = [self._probe_node(nid) for nid in list(self._nodes)]
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        return self.get_all_health()
