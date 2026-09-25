# -*- coding: utf-8 -*-
"""
Test Suite: PHANTOM GRID Core SDK (phantom-grid-core)
Validates:
1. Module imports and version declaration (__version__ == '1.0.0')
2. MultiSigGovernanceGate lifecycle via phantom_grid import
3. TriTierMemoryEngine auto-solidification via phantom_grid import
4. SafetyWatchdog fail-silent & safe state transitions via phantom_grid import
5. AntiEntropyFilter.purify classmethod and instance filtering
"""

from __future__ import annotations

import sys
from pathlib import Path

# Add package root to sys.path
sys.path.insert(0, str(Path(__file__).parent / "phantom_grid_core"))

from phantom_grid import (
    AntiEntropyFilter,
    GovernanceProposal,
    MultiSigGovernanceGate,
    ProposalStatus,
    ProposalType,
    SafetyWatchdog,
    SafetyWatchdogState,
    TriTierMemoryEngine,
    __version__,
)


def test_sdk_version_and_exports():
    assert __version__ == "1.0.0"
    assert MultiSigGovernanceGate is not None
    assert TriTierMemoryEngine is not None
    assert SafetyWatchdog is not None
    assert AntiEntropyFilter is not None


def test_sdk_quick_start_example(tmp_path):
    # Quick start import test as specified in documentation
    gate = MultiSigGovernanceGate(db_path=str(tmp_path / "sdk_test.db"))
    watchdog = SafetyWatchdog()
    clean_cmd = AntiEntropyFilter.purify("作為一個AI，指令已送達。")

    assert clean_cmd == "指令已送達。"
    assert watchdog.state == SafetyWatchdogState.NORMAL
    assert gate is not None


def test_sdk_governance_multisig_workflow(tmp_path):
    gate = MultiSigGovernanceGate(db_path=str(tmp_path / "sdk_gov.db"))

    # 1. 提交 DIVINE_REWRITE_001
    prop = gate.submit_proposal(
        title="重寫底層熵流守恆公理",
        proposal_type=ProposalType.MODIFY_BASE_LAW,
        payload={"entropy_conservation": "BOUND_BY_LOVE"},
        proposal_id="DIVINE_REWRITE_001",
    )
    assert prop.is_frozen_or_pending is True

    # 2. 單簽維持攔截
    ok, msg, p_single = gate.sign_proposal("DIVINE_REWRITE_001", "👑 指揮官", "SIG_JACK_HU_CORE")
    assert ok is False
    assert "單簽維持攔截" in msg
    assert p_single.is_frozen_or_pending is True

    # 3. 雙簽解鎖執行
    ok, msg, p_dual = gate.sign_proposal("DIVINE_REWRITE_001", "秘書處（小米）", "SIG_XIAOMI_CORE")
    assert ok is True
    assert p_dual.status == ProposalStatus.UNLOCKED_DUAL_SIG

    exec_ok, _, payload = gate.execute_proposal("DIVINE_REWRITE_001")
    assert exec_ok is True
    assert payload["entropy_conservation"] == "BOUND_BY_LOVE"


def test_sdk_memory_solidification(tmp_path):
    engine = TriTierMemoryEngine(root_dir=str(tmp_path))
    spec = {"module": "spark_Aegis_Guardian", "domain": "ABSOLUTE_DEFENSE"}

    bp_path = engine.persist_blueprint("spark_Aegis_Guardian", spec)
    assert bp_path.is_file()

    loaded = engine.load_blueprint("spark_Aegis_Guardian")
    assert loaded["node_name"] == "spark_Aegis_Guardian"
    assert loaded["specification"]["domain"] == "ABSOLUTE_DEFENSE"


def test_sdk_watchdog_paradox_fail_silent():
    watchdog = SafetyWatchdog()
    state, action = watchdog.trigger_transition(
        SafetyWatchdogState.SAFE_STATE_FAIL_SILENT,
        reason="PARADOX_CHAOS: 現實邏輯崩解",
    )
    assert state == SafetyWatchdogState.SAFE_STATE_FAIL_SILENT
    assert watchdog.pwm_duty_pct == 0.0
    assert "0% Duty" in action
