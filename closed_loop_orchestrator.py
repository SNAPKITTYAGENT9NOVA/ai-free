"""Closed Loop Orchestrator — 全系統閉環運作總成模組.

Phase 1：記憶歸檔與 GC — 運行正常，乾淨無污染
Phase 2：SLA 監控與自動降級 — 探針回報流暢，平均延遲 95ms
Phase 3：安全熔斷 — 保護層掛載，與指揮官及執行端完全對齊
整合 SLAGuard + FallbackPipeline + SystemStatusMonitor + SafetyInterlock
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from fallback_pipeline import FallbackPipeline, PipelineMode
from safety_interlock import ChannelState, SafetyInterlock
from system_status_monitor import MemoryGCState, PhaseStatus, SLARoutingState

logger = logging.getLogger(__name__)


class LoopHealth(Enum):
    """閉環健康等級."""

    GREEN = "GREEN"       # 三 Phase 全數 NOMINAL
    YELLOW = "YELLOW"     # 有 WARNING 但無 CRITICAL
    RED = "RED"           # 有 CRITICAL 或 OFFLINE


@dataclass
class PhaseReport:
    """單一 Phase 狀態報告."""

    phase_id: int
    name: str
    status: PhaseStatus
    detail: str


@dataclass
class ClosedLoopReport:
    """全系統閉環狀態報告."""

    timestamp: float
    health: LoopHealth
    phases: list[PhaseReport]
    avg_latency_ms: float
    pending_interlocks: int
    pipeline_mode: str

    def summary(self) -> str:
        """產生單行狀態摘要."""
        icons = {"GREEN": "🟢", "YELLOW": "🟡", "RED": "🔴"}
        icon = icons.get(self.health.value, "⚪")
        lines = [
            f"{icon} 全系統閉環：{self.health.value}",
            f"   平均延遲：{self.avg_latency_ms:.0f}ms | "
            f"管線：{self.pipeline_mode} | "
            f"待審攔截：{self.pending_interlocks}",
        ]
        for p in self.phases:
            status_icon = "✅" if p.status == PhaseStatus.NOMINAL else "⚠️"
            lines.append(f"   Phase {p.phase_id} {status_icon} {p.name}：{p.detail}")
        return "\n".join(lines)


class ClosedLoopOrchestrator:
    """全系統閉環運作協調器.

    Example
    -------
    >>> orch = ClosedLoopOrchestrator()
    >>> orch.phase2_record_probe("node-A", True, 95.0)
    >>> report = orch.status_report()
    >>> report.health  # LoopHealth.GREEN
    """

    def __init__(
        self,
        *,
        interlock: SafetyInterlock | None = None,
        pipeline: FallbackPipeline | None = None,
    ) -> None:
        self._gc = MemoryGCState()
        self._sla = SLARoutingState()
        self._interlock = interlock or SafetyInterlock()
        self._pipeline = pipeline
        self._boot_time = time.time()

    # ── Phase 1：記憶歸檔與 GC ───────────────────────

    @property
    def gc(self) -> MemoryGCState:
        """Phase 1 GC 狀態."""
        return self._gc

    def gc_sweep(self) -> int:
        """執行 GC 清掃."""
        return self._gc.run_gc()

    # ── Phase 2：SLA 監控 ────────────────────────────

    def phase2_record_probe(
        self, node_id: str, online: bool, latency_ms: float,
    ) -> None:
        """記錄節點探針結果."""
        self._sla.record_probe(node_id, online, latency_ms)
        if self._pipeline:
            self._sla.pipeline_mode = self._pipeline.mode.value

    @property
    def avg_latency_ms(self) -> float:
        """平均延遲（僅計算在線節點）."""
        online = [p for p in self._sla.probes if p.online]
        if not online:
            return 0.0
        return sum(p.latency_ms for p in online) / len(online)

    # ── Phase 3：安全熔斷 ────────────────────────────

    @property
    def interlock(self) -> SafetyInterlock:
        """Phase 3 安全熔斷層."""
        return self._interlock

    def execute_with_guard(
        self, command: str, impact_scope: str = "未知",
    ) -> tuple[bool, str]:
        """受熔斷保護的指令執行.

        Returns
        -------
        (cleared, message)
            cleared=True 表示安全放行可執行；False 表示已攔截待審。
        """
        alert = self._interlock.check(command, impact_scope)
        if alert is None:
            return True, "✅ 安全指令，全速通行"
        return False, alert.to_prompt()

    # ── 閉環狀態報告 ─────────────────────────────────

    def status_report(self) -> ClosedLoopReport:
        """產生全系統閉環狀態報告."""
        p1_status = self._gc.status
        p1_detail = (
            f"運行正常，乾淨無污染"
            if p1_status == PhaseStatus.NOMINAL
            else f"暫存池堆積 {self._gc.buffer_pool_size} 筆"
        )

        p2_status = self._sla.status
        avg_lat = self.avg_latency_ms
        p2_detail = (
            f"探針回報流暢，平均延遲 {avg_lat:.0f}ms"
            if p2_status == PhaseStatus.NOMINAL
            else f"狀態異常：{p2_status.value}，延遲 {avg_lat:.0f}ms"
        )

        pending = len(self._interlock.get_pending())
        p3_status = PhaseStatus.NOMINAL if pending == 0 else PhaseStatus.WARNING
        p3_detail = (
            "保護層已掛載，與指揮官完全對齊"
            if pending == 0
            else f"有 {pending} 筆攔截待指揮官確認"
        )

        phases = [
            PhaseReport(1, "記憶歸檔與 GC", p1_status, p1_detail),
            PhaseReport(2, "SLA 監控與自動降級", p2_status, p2_detail),
            PhaseReport(3, "安全熔斷", p3_status, p3_detail),
        ]

        # 整體健康 = 三 Phase 中最差
        all_statuses = [p.status for p in phases]
        if PhaseStatus.CRITICAL in all_statuses or PhaseStatus.OFFLINE in all_statuses:
            health = LoopHealth.RED
        elif PhaseStatus.WARNING in all_statuses:
            health = LoopHealth.YELLOW
        else:
            health = LoopHealth.GREEN

        pipeline_mode = (
            self._pipeline.mode.value if self._pipeline else "PRIMARY"
        )

        return ClosedLoopReport(
            timestamp=time.time(),
            health=health,
            phases=phases,
            avg_latency_ms=avg_lat,
            pending_interlocks=pending,
            pipeline_mode=pipeline_mode,
        )
