# -*- coding: utf-8 -*-
"""
Test Suite for Vehicle Chaos Adversary Testing Suite (chaos_adversary.py)
Validates ASIL-D functional safety, fault containment, and decentralized intrusion alerting.
"""

import pytest
from chaos_adversary import ChaosAdversaryRunner, ChaosAttackResult
from can_l0_l1_matrix import BusOffRecoveryMode, NodeSafetyState
from autonomous_healer import HealingLevel
from fleet_nostr_mesh import NOSTR_KIND_HEALING_ALERT


def test_chaos_physical_bus_off_bombardment():
    """Validates physical Bus-Off TEC > 255 triggers 0ms PWM cutoff & 100ms timer."""
    runner = ChaosAdversaryRunner(vin="TEST-CHAOS-01")
    res = runner.attack_physical_bus_off(simulated_tec=256)

    assert res.is_contained is True
    assert res.mitigation_latency_ms < 5.0  # Microsecond order
    assert res.details["pwm_output_enabled"] is False
    assert res.details["pwm_duty_pct"] == 0.0
    assert res.details["safety_state"] == "BUS_OFF"
    assert res.details["recovery_mode"] == "FAST_RECOVERY"
    assert res.details["recovery_interval_sec"] == 0.100


def test_chaos_data_layer_replay_and_crc_poisoning():
    """Validates 3 consecutive poisoned frames trigger STATE_DEGRADED and 50% power clamp."""
    runner = ChaosAdversaryRunner(vin="TEST-CHAOS-02")
    res = runner.attack_data_layer_poisoning()

    assert res.is_contained is True
    assert res.details["final_safety_state"] == "STATE_DEGRADED"
    assert res.details["actuator_torque_limit_pct"] == 50.0
    assert res.details["actuator_pwm_duty_pct"] == 50.0


def test_chaos_extreme_thermal_electrical_surge():
    """Validates 92°C and 9.8V electrical droop triggers Level 2 Limp-Home derating (<= 50%)."""
    runner = ChaosAdversaryRunner(vin="TEST-CHAOS-03")
    res = runner.attack_thermal_electrical_surge(surge_temp_c=92.0, droop_voltage_mv=9800)

    assert res.is_contained is True
    assert res.details["healing_level"] == "LEVEL_2_LIMP_HOME"
    assert res.details["torque_limit_pct"] <= 50.0
    assert res.details["audit_persisted"] is True
    assert len(res.details["audit_hash"]) == 64


def test_chaos_unauthorized_override_rejection_and_nostr_alert():
    """Validates unauthorized register overwrite is rejected and triggers Nostr alert."""
    runner = ChaosAdversaryRunner(vin="TEST-CHAOS-04")
    res = runner.attack_unauthorized_override()

    assert res.is_contained is True
    assert res.details["mcp_status"] == "REJECTED_UNAUTHORIZED"
    assert res.details["is_authorized"] is False
    assert res.details["nostr_verified"] is True
    assert res.details["nostr_kind"] == NOSTR_KIND_HEALING_ALERT


def test_chaos_full_adversarial_suite_execution():
    """Validates that running the complete chaos adversary suite yields 100% containment."""
    runner = ChaosAdversaryRunner(vin="TEST-CHAOS-SUITE")
    summary = runner.run_full_chaos_suite()

    assert summary["total_vectors"] == 4
    assert summary["all_contained"] is True
    for sc in summary["scorecard"]:
        assert sc["contained"] is True
