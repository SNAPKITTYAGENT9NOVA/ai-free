# -*- coding: utf-8 -*-
"""
Tests for Phase 3 HIL Stress & Boundary Signal Injection Suite.
Verifies:
1. Bus Flooding (>85% load) and MCU watchdog responsiveness.
2. E2E Counter Tamper (3 corrupted frames -> 50% power clamp, 10 good frames -> auto recover).
3. Brownout & Voltage Sag Glitch detection and consistency.
4. Bus-Off 0ms PWM cutoff, 100ms fast restart, 3-strike hard fault (DTC 0xD001), and UDS $14 unlock.
5. Full suite execution and Secretary Xiaomi SQLite audit governance logging.
6. SDK exports from phantom_grid_core.
"""

from __future__ import annotations

import os
import tempfile
from typing import Generator

import pytest
from phantom_grid import (
    HILStressRunner as CoreHILRunner,
)
from phantom_grid import (
    MockCANBus as CoreMockCANBus,
)

from audit_governance import GovernanceDB
from e2e_state_matrix import Iso26262SafetyStateMachine, Iso26262State
from hil_stress_test import HILStressRunner


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


def test_hil_bus_flooding_attack(temp_db: str) -> None:
    sm = Iso26262SafetyStateMachine()
    with HILStressRunner(
        channel="test_flood", bustype="virtual", state_machine=sm, db_path=temp_db
    ) as runner:
        res = runner.test_bus_flooding_attack(duration_sec=0.1, interval_sec=0.0002)
        assert res["status"] == "PASSED"
        assert res["tx_frames"] > 0
        assert res["watchdog_tripped"] is False
        assert sm.state in (Iso26262State.STATE_NORMAL, Iso26262State.STATE_DEGRADED)
        assert not sm.hardware_reset_pin_asserted


def test_hil_e2e_counter_tamper(temp_db: str) -> None:
    sm = Iso26262SafetyStateMachine()
    with HILStressRunner(
        channel="test_tamper", bustype="virtual", state_machine=sm, db_path=temp_db
    ) as runner:
        res = runner.test_e2e_counter_tamper(target_id=0x100, test_recovery=True)
        assert res["status"] == "PASSED"
        assert res["tamper_frames"] == 3
        assert res["degraded_state_verified"] is True
        assert res["pwm_clamped_pct"] == 50.0
        assert res["auto_recovery_verified"] is True
        # After 10 valid frames, state recovers to NORMAL
        assert sm.state == Iso26262State.STATE_NORMAL
        assert sm.pwm_duty_pct == 100.0


def test_hil_brownout_glitch(temp_db: str) -> None:
    sm = Iso26262SafetyStateMachine()
    with HILStressRunner(
        channel="test_brownout", bustype="virtual", state_machine=sm, db_path=temp_db
    ) as runner:
        res = runner.test_brownout_glitch(
            supply_voltage=4.2, normal_voltage=12.0, sag_duration_ms=20.0
        )
        assert res["status"] == "PASSED"
        assert res["supply_voltage_v"] == 4.2
        assert res["non_volatile_consistent"] is True
        assert any("BROWNOUT_DETECTED" in incident for incident in sm.incident_history)


def test_hil_bus_off_recovery_fast_and_hard_fault(temp_db: str) -> None:
    # 1. Fast restart success
    sm1 = Iso26262SafetyStateMachine()
    with HILStressRunner(
        channel="test_busoff1", bustype="virtual", state_machine=sm1, db_path=temp_db
    ) as runner1:
        res1 = runner1.test_bus_off_recovery(simulate_permanent_failure=False)
        assert res1["status"] == "PASSED"
        assert res1["bus_off_triggered"] is True
        assert sm1.state == Iso26262State.STATE_NORMAL

    # 2. Permanent failure -> hard fault -> UDS $14 clear
    sm2 = Iso26262SafetyStateMachine()
    with HILStressRunner(
        channel="test_busoff2", bustype="virtual", state_machine=sm2, db_path=temp_db
    ) as runner2:
        res2 = runner2.test_bus_off_recovery(simulate_permanent_failure=True)
        assert res2["status"] == "PASSED"
        assert res2["hard_fault_dtc_verified"] is True
        assert sm2.state == Iso26262State.STATE_NORMAL
        assert sm2.active_dtc is None


def test_hil_run_suite_and_sqlite_audit(temp_db: str) -> None:
    sm = Iso26262SafetyStateMachine()
    with HILStressRunner(
        channel="test_suite", bustype="virtual", state_machine=sm, db_path=temp_db
    ) as runner:
        report = runner.run_suite()
        assert report["audit_archived"] is True
        assert "E2E_TAMPER" in report["results"]
        assert "BUS_FLOODING" in report["results"]
        assert "BROWNOUT_GLITCH" in report["results"]
        assert "BUS_OFF_RECOVERY" in report["results"]

        # Verify SQLite audit log entry
        db = GovernanceDB(db_path=temp_db)
        logs = db.query_logs(limit=5)
        hil_logs = [item for item in logs if item["task_id"] == "HIL_STRESS_PHASE3"]
        assert len(hil_logs) == 1
        entry = hil_logs[0]
        assert entry["operator"] == "秘書小米"
        assert entry["status"] == "EXECUTED"
        assert entry["action_type"] == "HIL_STRESS_AUDIT"
        assert "HIL Phase 3" in entry["details"]
        db.close()


def test_hil_phantom_grid_core_exports() -> None:
    assert CoreHILRunner is not None
    assert CoreMockCANBus is not None
    mock_bus = CoreMockCANBus()
    mock_bus.send({"id": 0x123})
    assert mock_bus.recv() == {"id": 0x123}
    mock_bus.shutdown()
