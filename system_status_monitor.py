"""System Status Monitor — 系統狀態總覽模組.

Phase 1：記憶歸檔與 GC（暫存池監控）
Phase 2：SLA 與降級路由（節點探針 + 通道延遲）
整合 SLAGuard + FallbackPipeline 提供統一狀態報告
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

logger = logging.getLogger(__name__)

# ── 常數 ─────────────────────────────────────────────
LATENCY_THRESHOLD_MS: float = 120.0  # 通道延遲正常門檻


class PhaseStatus(Enum):
    """階段運行狀態."""

    NOMINAL = "NOMINAL"         # 正常運行
    WARNING = "WARNING"         # 警告：接近門檻
    CRITICAL = "CRITICAL"       # 危急：超過門檻
    OFFLINE = "OFFLINE"         # 離線


@dataclass
class MemoryGCState:
    """Phase 1：記憶歸檔與 GC 狀態."""

    buffer_pool_size: int = 0           # 暫存池堆積量
    archived_count: int = 0             # 已歸檔筆數
    last_gc_time: float = field(default_factory=time.time)
    gc_cycle_count: int = 0             # GC 執行次數

    @property
    def status(self) -> PhaseStatus:
        """暫存池零堆積 → NOMINAL."""
        if self.buffer_pool_size == 0:
            return PhaseStatus.NOMINAL
        if self.buffer_pool_size <= 10:
            return PhaseStatus.WARNING
        return PhaseStatus.CRITICAL

    def archive(self, count: int = 1) -> None:
        """歸檔記憶項目."""
        self.archived_count += count
        logger.debug("MemoryGC: 歸檔 %d 筆，累計 %d", count, self.archived_count)

    def push_buffer(self, count: int = 1) -> None:
        """推入暫存池."""
        self.buffer_pool_size += count

    def run_gc(self) -> int:
        """執行 GC：清空暫存池並歸檔."""
        swept = self.buffer_pool_size
        self.archived_count += swept
        self.buffer_pool_size = 0
        self.last_gc_time = time.time()
        self.gc_cycle_count += 1
        logger.info("MemoryGC: 第 %d 次 GC 清掃 %d 筆", self.gc_cycle_count, swept)
        return swept


@dataclass
class ProbeResult:
    """單一節點探針結果."""

    node_id: str
    online: bool
    latency_ms: float
    timestamp: float = field(default_factory=time.time)

    @property
    def latency_normal(self) -> bool:
        """延遲是否在 120ms 門檻內."""
        return self.latency_ms < LATENCY_THRESHOLD_MS


@dataclass
class SLARoutingState:
    """Phase 2：SLA 與降級路由狀態."""

    probes: list[ProbeResult] = field(default_factory=list)
    pipeline_mode: str = "PRIMARY"     # PRIMARY | DEGRADED

    @property
    def all_online(self) -> bool:
        """所有探針是否全數上線."""
        return all(p.online for p in self.probes) if self.probes else False

    @property
    def all_latency_normal(self) -> bool:
        """所有通道延遲是否正常 (<120ms)."""
        return all(p.latency_normal for p in self.probes) if self.probes else False

    @property
    def status(self) -> PhaseStatus:
        """綜合狀態判定."""
        if not self.probes:
            return PhaseStatus.OFFLINE
        if self.all_online and self.all_latency_normal:
            return PhaseStatus.NOMINAL
        if self.all_online:
            return PhaseStatus.WARNING
        return PhaseStatus.CRITICAL

    def record_probe(
        self, node_id: str, online: bool, latency_ms: float,
    ) -> ProbeResult:
        """記錄探針結果."""
        result = ProbeResult(
            node_id=node_id, online=online, latency_ms=latency_ms,
        )
        # 更新或新增
        self.probes = [p for p in self.probes if p.node_id != node_id]
        self.probes.append(result)
        return result


class SystemStatusMonitor:
    """系統狀態總覽：整合 Phase 1 + Phase 2.

    Example
    -------
    >>> monitor = SystemStatusMonitor()
    >>> monitor.phase2.record_probe("node-A", True, 45.0)
    >>> report = monitor.generate_report()
    >>> report["phase1"]["status"]
    'NOMINAL'
    """

    def __init__(self) -> None:
        self.phase1 = MemoryGCState()
        self.phase2 = SLARoutingState()

    def generate_report(self) -> dict[str, Any]:
        """產生系統狀態總覽報告."""
        return {
            "timestamp": time.time(),
            "overall": self._overall_status().value,
            "phase1": {
                "name": "記憶歸檔與 GC",
                "status": self.phase1.status.value,
                "buffer_pool_size": self.phase1.buffer_pool_size,
                "archived_count": self.phase1.archived_count,
                "gc_cycle_count": self.phase1.gc_cycle_count,
            },
            "phase2": {
                "name": "SLA 與降級路由",
                "status": self.phase2.status.value,
                "pipeline_mode": self.phase2.pipeline_mode,
                "probes_online": sum(1 for p in self.phase2.probes if p.online),
                "probes_total": len(self.phase2.probes),
                "all_latency_normal": self.phase2.all_latency_normal,
                "probes": [
                    {
                        "node_id": p.node_id,
                        "online": p.online,
                        "latency_ms": round(p.latency_ms, 1),
                        "normal": p.latency_normal,
                    }
                    for p in self.phase2.probes
                ],
            },
        }

    def _overall_status(self) -> PhaseStatus:
        """整體狀態 = 兩個 Phase 中最差的."""
        statuses = [self.phase1.status, self.phase2.status]
        if PhaseStatus.CRITICAL in statuses:
            return PhaseStatus.CRITICAL
        if PhaseStatus.WARNING in statuses:
            return PhaseStatus.WARNING
        if PhaseStatus.OFFLINE in statuses:
            return PhaseStatus.OFFLINE
        return PhaseStatus.NOMINAL
