# -*- coding: utf-8 -*-
"""
Tests for Axis 2: Real-Time Telemetry Dashboard & Web HITL Dual-Signature Engine.
"""

from __future__ import annotations

import os
import tempfile
from typing import Generator

import pytest

from e2e_state_matrix import Iso26262SafetyStateMachine, Iso26262State
from telemetry_dashboard import TelemetryStreamEngine, render_cli_preview


@pytest.fixture
def temp_db() -> Generator[str, None, None]:
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    yield path
    if os.path.exists(path):
        try:
            os.remove(path)
        except OSError:
            pass


def test_telemetry_snapshot_generation(temp_db: str) -> None:
    sm = Iso26262SafetyStateMachine()
    engine = TelemetryStreamEngine(state_machine=sm, db_path=temp_db)

    snap = engine.generate_snapshot()
    assert 0.0 <= snap.bus_load_pct <= 100.0
    assert snap.frame_jitter_us >= 0.0
    assert 0 <= snap.alive_counter <= 15
    assert snap.motor_rpm > 0
    assert snap.pwm_limit_pct == 100.0
    assert snap.safety_state == "STATE_NORMAL"


def test_traffic_light_state_indicator(temp_db: str) -> None:
    sm = Iso26262SafetyStateMachine()
    engine = TelemetryStreamEngine(state_machine=sm, db_path=temp_db)

    # 1. Normal state -> Green
    tag_norm, label_norm, _ = engine.get_traffic_light_color()
    assert "綠燈" in tag_norm
    assert label_norm == "正常運轉"

    # 2. Degraded state -> Yellow
    sm.state = Iso26262State.STATE_DEGRADED
    tag_deg, label_deg, _ = engine.get_traffic_light_color()
    assert "黃燈" in tag_deg
    assert label_deg == "降額運轉"

    # 3. Bus-Off state -> Red
    sm.state = Iso26262State.STATE_BUS_OFF_SAFE
    tag_busoff, label_busoff, _ = engine.get_traffic_light_color()
    assert "紅燈" in tag_busoff
    assert label_busoff == "總線隔離"

    # 4. Hard fault state -> Red
    sm.state = Iso26262State.STATE_HARD_FAULT
    sm.active_dtc = "0xD001"
    tag_fault, label_fault, _ = engine.get_traffic_light_color()
    assert "紅燈" in tag_fault
    assert label_fault == "永久鎖死"


def test_hitl_quick_dual_sig_approval_and_rejection(temp_db: str) -> None:
    sm = Iso26262SafetyStateMachine()
    engine = TelemetryStreamEngine(state_machine=sm, db_path=temp_db)

    # 1. Approve task via brother one-click
    assert engine.approve_task_by_brother("REG_0x4002_LOCK", "親批放行") is True
    assert engine.db.is_approved_by_brother("REG_0x4002_LOCK") is True

    # 2. Reject task via brother one-click
    assert engine.reject_task_by_brother("DANGEROUS_WRITE", "存在越權風險，駁回") is True
    assert engine.db.is_approved_by_brother("DANGEROUS_WRITE") is False

    # 3. Query audit logs
    logs = engine.query_recent_audit_logs(limit=5)
    assert len(logs) == 2
    assert logs[0]["task_id"] == "DANGEROUS_WRITE"
    assert logs[0]["status"] == "REJECTED"
    assert logs[1]["task_id"] == "REG_0x4002_LOCK"
    assert logs[1]["status"] == "APPROVED"


def test_cli_preview_rendering(temp_db: str) -> None:
    sm = Iso26262SafetyStateMachine()
    engine = TelemetryStreamEngine(state_machine=sm, db_path=temp_db)
    engine.approve_task_by_brother("TASK_INIT", "初始化審核通過")
    render_cli_preview(engine)
