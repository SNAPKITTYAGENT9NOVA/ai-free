"""System Status Monitor 驗收測試."""

from __future__ import annotations

import pytest

from system_status_monitor import (
    LATENCY_THRESHOLD_MS,
    MemoryGCState,
    PhaseStatus,
    SLARoutingState,
    SystemStatusMonitor,
)


# ── 測試 1：Phase 1 暫存池零堆積 = NOMINAL ──────────

def test_phase1_zero_buffer_nominal() -> None:
    """暫存池為 0 → NOMINAL."""
    gc = MemoryGCState()
    assert gc.buffer_pool_size == 0
    assert gc.status == PhaseStatus.NOMINAL


# ── 測試 2：Phase 1 GC 清掃歸檔 ─────────────────────

def test_phase1_gc_sweeps_buffer() -> None:
    """GC 應清空暫存池並計入歸檔."""
    gc = MemoryGCState()
    gc.push_buffer(5)
    assert gc.buffer_pool_size == 5
    assert gc.status == PhaseStatus.WARNING

    swept = gc.run_gc()
    assert swept == 5
    assert gc.buffer_pool_size == 0
    assert gc.archived_count == 5
    assert gc.gc_cycle_count == 1
    assert gc.status == PhaseStatus.NOMINAL


# ── 測試 3：Phase 2 全數上線 + 延遲正常 ──────────────

def test_phase2_all_online_normal_latency() -> None:
    """所有探針上線且延遲 <120ms → NOMINAL."""
    sla = SLARoutingState()
    sla.record_probe("node-A", online=True, latency_ms=45.0)
    sla.record_probe("node-B", online=True, latency_ms=80.0)
    sla.record_probe("node-C", online=True, latency_ms=110.0)

    assert sla.all_online is True
    assert sla.all_latency_normal is True
    assert sla.status == PhaseStatus.NOMINAL


# ── 測試 4：延遲超過 120ms → WARNING ────────────────

def test_phase2_high_latency_warning() -> None:
    """延遲超過 120ms 門檻 → WARNING."""
    sla = SLARoutingState()
    sla.record_probe("node-A", online=True, latency_ms=45.0)
    sla.record_probe("node-B", online=True, latency_ms=150.0)

    assert sla.all_online is True
    assert sla.all_latency_normal is False
    assert sla.status == PhaseStatus.WARNING


# ── 測試 5：節點離線 → CRITICAL ──────────────────────

def test_phase2_node_offline_critical() -> None:
    """有節點離線 → CRITICAL."""
    sla = SLARoutingState()
    sla.record_probe("node-A", online=True, latency_ms=45.0)
    sla.record_probe("node-B", online=False, latency_ms=0.0)

    assert sla.all_online is False
    assert sla.status == PhaseStatus.CRITICAL


# ── 測試 6：120ms 門檻常數 ───────────────────────────

def test_latency_threshold_constant() -> None:
    """延遲門檻應為 120ms."""
    assert LATENCY_THRESHOLD_MS == 120.0


# ── 測試 7：整合報告 Phase1 + Phase2 ─────────────────

def test_integrated_report_nominal() -> None:
    """Phase1 零堆積 + Phase2 全正常 → overall NOMINAL."""
    monitor = SystemStatusMonitor()
    monitor.phase2.record_probe("node-A", online=True, latency_ms=45.0)
    monitor.phase2.record_probe("node-B", online=True, latency_ms=80.0)

    report = monitor.generate_report()

    assert report["overall"] == "NOMINAL"
    assert report["phase1"]["status"] == "NOMINAL"
    assert report["phase1"]["buffer_pool_size"] == 0
    assert report["phase2"]["status"] == "NOMINAL"
    assert report["phase2"]["probes_online"] == 2
    assert report["phase2"]["all_latency_normal"] is True
