"""Closed Loop Orchestrator 驗收測試."""

from __future__ import annotations

from closed_loop_orchestrator import (
    ClosedLoopOrchestrator,
    LoopHealth,
)
from system_status_monitor import PhaseStatus


# ── 測試 1：三 Phase 全 NOMINAL → GREEN ──────────────

def test_all_nominal_green() -> None:
    """Phase1 零堆積 + Phase2 全在線低延遲 + Phase3 無待審 → GREEN."""
    orch = ClosedLoopOrchestrator()
    orch.phase2_record_probe("node-A", True, 85.0)
    orch.phase2_record_probe("node-B", True, 95.0)
    orch.phase2_record_probe("node-C", True, 105.0)

    report = orch.status_report()

    assert report.health == LoopHealth.GREEN
    assert report.phases[0].status == PhaseStatus.NOMINAL  # Phase 1
    assert report.phases[1].status == PhaseStatus.NOMINAL  # Phase 2
    assert report.phases[2].status == PhaseStatus.NOMINAL  # Phase 3
    assert report.avg_latency_ms < 120.0
    assert report.pending_interlocks == 0


# ── 測試 2：平均延遲 95ms 驗證 ───────────────────────

def test_avg_latency_95ms() -> None:
    """模擬規格中的 95ms 平均延遲場景."""
    orch = ClosedLoopOrchestrator()
    orch.phase2_record_probe("node-A", True, 90.0)
    orch.phase2_record_probe("node-B", True, 95.0)
    orch.phase2_record_probe("node-C", True, 100.0)

    assert abs(orch.avg_latency_ms - 95.0) < 1.0


# ── 測試 3：GC 清掃後維持乾淨 ────────────────────────

def test_gc_sweep_stays_clean() -> None:
    """GC 清掃後 Phase1 應維持 NOMINAL."""
    orch = ClosedLoopOrchestrator()
    orch.gc.push_buffer(3)
    orch.gc_sweep()

    report = orch.status_report()
    assert report.phases[0].status == PhaseStatus.NOMINAL
    assert "乾淨無污染" in report.phases[0].detail


# ── 測試 4：熔斷觸發 → Phase3 WARNING → YELLOW ──────

def test_interlock_triggers_yellow() -> None:
    """熔斷攔截待審 → Phase3 WARNING → 整體 YELLOW."""
    orch = ClosedLoopOrchestrator()
    orch.phase2_record_probe("node-A", True, 95.0)
    orch.interlock.check("rm -rf /data", "全部數據")

    report = orch.status_report()

    assert report.phases[2].status == PhaseStatus.WARNING
    assert report.health == LoopHealth.YELLOW
    assert report.pending_interlocks == 1


# ── 測試 5：指揮官放行後恢復 GREEN ───────────────────

def test_approve_restores_green() -> None:
    """指揮官確認放行後應恢復 GREEN."""
    orch = ClosedLoopOrchestrator()
    orch.phase2_record_probe("node-A", True, 95.0)
    alert = orch.interlock.check("batch delete logs", "日誌")
    assert alert is not None

    orch.interlock.approve(alert.alert_id, approved_by="Jack")

    report = orch.status_report()
    assert report.health == LoopHealth.GREEN
    assert report.pending_interlocks == 0


# ── 測試 6：節點離線 → RED ───────────────────────────

def test_node_offline_red() -> None:
    """有節點離線 → Phase2 CRITICAL → 整體 RED."""
    orch = ClosedLoopOrchestrator()
    orch.phase2_record_probe("node-A", True, 95.0)
    orch.phase2_record_probe("node-B", False, 0.0)

    report = orch.status_report()
    assert report.health == LoopHealth.RED


# ── 測試 7：execute_with_guard 安全指令放行 ──────────

def test_safe_command_passes() -> None:
    """安全指令應直接放行."""
    orch = ClosedLoopOrchestrator()
    cleared, msg = orch.execute_with_guard("git status")
    assert cleared is True
    assert "全速通行" in msg


# ── 測試 8：execute_with_guard 高危指令攔截 ──────────

def test_dangerous_command_blocked() -> None:
    """高危指令應被攔截."""
    orch = ClosedLoopOrchestrator()
    cleared, msg = orch.execute_with_guard("drop table users", "資料庫")
    assert cleared is False
    assert "熔斷攔截" in msg


# ── 測試 9：閉環報告摘要格式 ─────────────────────────

def test_report_summary_format() -> None:
    """摘要應包含三個 Phase 與健康圖標."""
    orch = ClosedLoopOrchestrator()
    orch.phase2_record_probe("node-A", True, 95.0)

    report = orch.status_report()
    text = report.summary()

    assert "🟢" in text
    assert "Phase 1" in text
    assert "Phase 2" in text
    assert "Phase 3" in text
    assert "95ms" in text
