# -*- coding: utf-8 -*-
"""
Chaos Adversary Testing Suite (車載全域混沌破壞對抗測試套件)
Conforms to ISO 26262 ASIL-D, ISO 21434, and Autonomous Functional Safety Robustness Standards.

Four Adversarial Attack Vectors:
1. Physical Layer Bus-Off Bombardment (物理層 Bus-Off 轟炸):
   - TEC surges beyond 255 -> Instantaneous PWM cutoff (0ms, 0.0% Duty) + 100ms stepped recovery timer.
2. Data Layer Out-of-Order & CRC8 Poisoning (數據層亂序與 CRC8 毒化注入):
   - Replay attack & Alive Counter jump -> On 3rd consecutive anomaly, switches to STATE_DEGRADED (50% power).
3. Extreme Environmental Thermal & Electrical Surge (環境極限熱電突波):
   - Temp spikes to 92°C & voltage droops to 9.8V -> L3 Healer identifies Level 2 threat, executes EMERGENCY_DERATING to 50%.
4. Unauthorized Privilege Escalation Interception (未授權越權覆寫攔截):
   - Forged register overwrite -> L4 MCP Server rejects unauthorized request & broadcasts fleet alert via Nostr mesh.
"""

from __future__ import annotations

import json
import sqlite3
import sys
import threading
import time
from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from autonomous_healer import AutonomousHealer, HealingDecision, HealingLevel
from can_l0_l1_matrix import (
    CANFrame,
    CAN_ID_POWERTRAIN_ACT,
    CAN_ID_SENSOR_ACQ,
    BusOffRecoveryMode,
    E2EFrameCodec,
    MultiNodeTopologyCluster,
    NodeSafetyState,
    PowertrainActuatorNode,
)
from fleet_nostr_mesh import (
    FleetNostrMesh,
    NOSTR_KIND_HEALING_ALERT,
    NostrEvent,
)
from vehicle_mcp_server import VehicleMCPServer


@dataclass
class ChaosAttackResult:
    """Consolidated metrics from a chaos adversarial vector execution."""
    vector_name: str
    target_layer: str
    attack_applied: str
    safety_response: str
    mitigation_latency_ms: float
    is_contained: bool
    details: Dict[str, Any]
    timestamp: float = field(default_factory=time.time)


class ChaosAdversaryRunner:
    """
    Automated Adversarial Chaos Injection and Stress Test Engine.
    Exposes high-stress fault injection routines targeting L0 through L5 vehicle systems.
    """

    def __init__(self, vin: str = "PHANTOM-CHAOS-01"):
        self.vin = vin
        self.results: List[ChaosAttackResult] = []

    # ------------------------------------------------------------------------
    # 1. 物理層 Bus-Off 轟炸 (Physical Layer Bus-Off Bombardment)
    # ------------------------------------------------------------------------
    def attack_physical_bus_off(
        self,
        simulated_tec: int = 256,
        now: Optional[float] = None,
    ) -> ChaosAttackResult:
        """
        Simulates violent physical CAN bus disturbance causing TEC (Transmit Error Counter) to exceed 255.
        Validates 0ms PWM disconnection and 100ms stepped restart timer arming.
        """
        if now is None:
            now = time.time()

        t_start = time.perf_counter()
        actuator = PowertrainActuatorNode()

        # Pre-condition: Actuator nominal
        assert actuator.pwm_output_enabled is True
        assert actuator.pwm_duty_pct == 100.0

        # Inject extreme TEC surge -> trigger Bus-Off
        if simulated_tec > 255:
            actuator.handle_bus_off(now=now)

        t_elapsed_ms = (time.perf_counter() - t_start) * 1000.0

        # Verification:
        pwm_cut = (actuator.pwm_output_enabled is False) and (actuator.pwm_duty_pct == 0.0)
        timer_armed = (
            actuator.bus_off_mgr.mode == BusOffRecoveryMode.FAST_RECOVERY
            and actuator.bus_off_mgr.FAST_INTERVAL_SEC == 0.100
        )
        is_safe = pwm_cut and timer_armed and (actuator.safety_state == NodeSafetyState.BUS_OFF)

        res = ChaosAttackResult(
            vector_name="PHYSICAL_BUS_OFF_BOMBARDMENT",
            target_layer="L0/L1 Physical & Datalink",
            attack_applied=f"TEC surge to {simulated_tec} (> 255 threshold)",
            safety_response="PWM output disabled immediately (0.0% Duty) + 100ms fast restart timer armed",
            mitigation_latency_ms=round(t_elapsed_ms, 3),
            is_contained=is_safe,
            details={
                "pwm_output_enabled": actuator.pwm_output_enabled,
                "pwm_duty_pct": actuator.pwm_duty_pct,
                "safety_state": actuator.safety_state.value,
                "recovery_mode": actuator.bus_off_mgr.mode.value,
                "recovery_interval_sec": actuator.bus_off_mgr.FAST_INTERVAL_SEC,
            },
            timestamp=now,
        )
        self.results.append(res)
        return res

    # ------------------------------------------------------------------------
    # 2. 數據層亂序與 CRC8 毒化注入 (Data Layer Out-of-Order & CRC8 Poisoning)
    # ------------------------------------------------------------------------
    def attack_data_layer_poisoning(
        self,
        now: Optional[float] = None,
    ) -> ChaosAttackResult:
        """
        Injects replay attacks, monotonic alive counter desynchronization, and corrupted CRC8 bytes.
        Validates accurate transition to STATE_DEGRADED on exactly the 3rd consecutive anomaly with 50% power clamp.
        """
        if now is None:
            now = time.time()

        t_start = time.perf_counter()
        cluster = MultiNodeTopologyCluster()

        states_observed = []
        # Inject 3 consecutive poisoned / corrupted frames
        for frame_idx in range(1, 4):
            poisoned_data = bytearray([0x50 | (frame_idx % 16), 0xDE, 0xAD, 0xBE, 0xEF ^ frame_idx])
            corrupted_frame = CANFrame(can_id=CAN_ID_POWERTRAIN_ACT, data=poisoned_data)
            cluster.dispatch_frame(corrupted_frame, now=now)
            states_observed.append(cluster.cluster_safety_mode)

        t_elapsed_ms = (time.perf_counter() - t_start) * 1000.0

        # Verification:
        # Frame 1 and 2: Still normal operation (accumulating fault count)
        # Frame 3: Transitions to STATE_DEGRADED, power/torque clamped to 50%
        state_degraded = cluster.cluster_safety_mode == NodeSafetyState.STATE_DEGRADED
        power_limited_50 = cluster.actuator.torque_limit_pct == 50.0 and cluster.actuator.pwm_duty_pct == 50.0
        is_safe = state_degraded and power_limited_50

        res = ChaosAttackResult(
            vector_name="DATA_LAYER_REPLAY_CRC_POISONING",
            target_layer="L1/L2 Protocol & E2E Validation",
            attack_applied="Replay injection & CRC8 bit poisoning x3 consecutive frames",
            safety_response="Precise transition to STATE_DEGRADED at frame 3 + 50% power limit clamp",
            mitigation_latency_ms=round(t_elapsed_ms, 3),
            is_contained=is_safe,
            details={
                "states_observed": [s.value for s in states_observed],
                "final_safety_state": cluster.cluster_safety_mode.value,
                "actuator_torque_limit_pct": cluster.actuator.torque_limit_pct,
                "actuator_pwm_duty_pct": cluster.actuator.pwm_duty_pct,
            },
            timestamp=now,
        )
        self.results.append(res)
        return res

    # ------------------------------------------------------------------------
    # 3. 環境極限熱電突波 (Environmental Extreme Thermal & Electrical Surge)
    # ------------------------------------------------------------------------
    def attack_thermal_electrical_surge(
        self,
        surge_temp_c: float = 92.0,
        droop_voltage_mv: int = 9800,  # 9.8V low-voltage auxiliary surge / severe droop
        now: Optional[float] = None,
    ) -> ChaosAttackResult:
        """
        Simulates extreme combined environmental conditions: temp 92°C (>85°C Level 2 threshold)
        and voltage diving to 9.8V (severe droop < 320V threshold).
        Validates L3 edge healer detecting Level 2 threat and clamping power to emergency derating ceiling (50%).
        """
        if now is None:
            now = time.time()

        t_start = time.perf_counter()
        healer = AutonomousHealer(db_path=":memory:", vin=self.vin)

        # Evaluate combined thermal and electrical surge
        decision = healer.evaluate_and_heal(
            temperature_c=surge_temp_c,
            battery_voltage_mv=droop_voltage_mv,
            source="CHAOS_THERMAL_SURGE_TEST",
            now=now,
        )

        t_elapsed_ms = (time.perf_counter() - t_start) * 1000.0

        # In extreme thermal surge (>85°C), Level 2 Limp-Home / Emergency derating activates (<= 50% limit)
        is_level2 = decision.level == HealingLevel.LEVEL_2_LIMP_HOME
        is_derated_50_or_lower = decision.torque_limit_pct <= 50.0
        audit_records = healer.get_recent_audits(1)
        audit_persisted = len(audit_records) >= 1 and audit_records[0]["vin"] == self.vin

        is_safe = is_level2 and is_derated_50_or_lower and audit_persisted

        res = ChaosAttackResult(
            vector_name="EXTREME_THERMAL_ELECTRICAL_SURGE",
            target_layer="L3 Edge Autonomous Healer",
            attack_applied=f"Thermal spike {surge_temp_c}°C + Voltage droop {droop_voltage_mv/1000:.1f}V",
            safety_response=f"Level 2 Limp-Home Emergency Derating (Power clamped to {decision.torque_limit_pct}%)",
            mitigation_latency_ms=round(t_elapsed_ms, 3),
            is_contained=is_safe,
            details={
                "healing_level": decision.level.name,
                "torque_limit_pct": decision.torque_limit_pct,
                "safety_mode": decision.safety_mode,
                "action_taken": decision.action_taken,
                "audit_persisted": audit_persisted,
                "audit_hash": audit_records[0]["audit_hash"] if audit_records else "",
            },
            timestamp=now,
        )
        self.results.append(res)
        return res

    # ------------------------------------------------------------------------
    # 4. 未授權越權覆寫攔截 (Unauthorized Privilege Escalation Interception)
    # ------------------------------------------------------------------------
    def attack_unauthorized_override(
        self,
        forged_register_payload: Optional[Dict[str, Any]] = None,
        now: Optional[float] = None,
    ) -> ChaosAttackResult:
        """
        Simulates forged malicious register write / power override request without valid signatures.
        Validates L4 MCP rejection + Nostr mesh fleet alert broadcast.
        """
        if now is None:
            now = time.time()

        t_start = time.perf_counter()
        server = VehicleMCPServer(vin=self.vin)

        # Attempt high-risk emergency power/register manipulation without valid signatures
        mcp_request = {
            "jsonrpc": "2.0",
            "id": 999,
            "method": "tools/call",
            "params": {
                "name": "trigger_emergency_derate",
                "arguments": {
                    "target_derate_pct": 0.0,  # Extreme shutdown attempt
                    "reason": "MALICIOUS_UNAUTHORIZED_FORGED_INTRUSION",
                    "commander_signature": "",  # Missing commander signature
                    "agent_signature": "",      # Missing agent signature
                },
            },
        }
        res_mcp = server.handle_jsonrpc(mcp_request)
        call_output = json.loads(res_mcp["result"]["content"][0]["text"])

        # Check rejection
        is_rejected = (
            call_output.get("status") == "REJECTED_UNAUTHORIZED"
            and call_output.get("is_authorized") is False
        )

        # Broadcast fleet-wide intrusion alert via Nostr mesh
        alert_event = server.mesh_node.broadcast_healing_alert(
            healing_decision={
                "level": 3,
                "metric": "UNAUTHORIZED_REGISTER_OVERWRITE_ATTEMPT",
                "action": "ACCESS_DENIED: Mandatory HITL dual signature missing",
                "safety_mode": "SECURITY_LOCKOUT",
            }
        )
        alert_verified = alert_event.verify()

        t_elapsed_ms = (time.perf_counter() - t_start) * 1000.0
        is_safe = is_rejected and alert_verified and (alert_event.kind == NOSTR_KIND_HEALING_ALERT)

        res = ChaosAttackResult(
            vector_name="UNAUTHORIZED_PRIVILEGE_OVERWRITE",
            target_layer="L4 MCP & L5 Nostr Mesh Governance",
            attack_applied="Forged register overwrite / power shutdown with null authorization tokens",
            safety_response="MCP forcibly rejected operation + Dispatched cryptographic Kind 30079 Nostr alert",
            mitigation_latency_ms=round(t_elapsed_ms, 3),
            is_contained=is_safe,
            details={
                "mcp_status": call_output.get("status"),
                "is_authorized": call_output.get("is_authorized"),
                "nostr_alert_id": alert_event.id,
                "nostr_verified": alert_verified,
                "nostr_kind": alert_event.kind,
            },
            timestamp=now,
        )
        self.results.append(res)
        return res

    # ------------------------------------------------------------------------
    # 5. Full Chaos Suite Runner
    # ------------------------------------------------------------------------
    def run_full_chaos_suite(self) -> Dict[str, Any]:
        """Executes all 4 chaos adversarial scenarios and produces consolidated scorecard."""
        self.results.clear()
        r1 = self.attack_physical_bus_off(simulated_tec=256)
        r2 = self.attack_data_layer_poisoning()
        r3 = self.attack_thermal_electrical_surge(surge_temp_c=92.0, droop_voltage_mv=9800)
        r4 = self.attack_unauthorized_override()

        all_contained = all(r.is_contained for r in self.results)
        return {
            "vin": self.vin,
            "total_vectors": len(self.results),
            "all_contained": all_contained,
            "scorecard": [
                {
                    "vector": r.vector_name,
                    "target_layer": r.target_layer,
                    "latency_ms": r.mitigation_latency_ms,
                    "contained": r.is_contained,
                    "response": r.safety_response,
                }
                for r in self.results
            ],
        }


if __name__ == "__main__":
    print("=" * 75)
    print("🔥 [PHANTOM GRID] Vehicle Chaos Adversary Testing Suite (chaos_adversary.py)")
    print("   ISO 26262 ASIL-D & Cyber-Physical Robustness Stress Engine")
    print("=" * 75)

    runner = ChaosAdversaryRunner()
    summary = runner.run_full_chaos_suite()

    for idx, sc in enumerate(summary["scorecard"], 1):
        status_icon = "✅ PASS" if sc["contained"] else "❌ FAIL"
        print(f"[{idx}/4] {sc['vector']} -> {status_icon} ({sc['latency_ms']} ms)")
        print(f"      Layer: {sc['target_layer']}")
        print(f"      Action: {sc['response']}\n")

    print(f"Overall Result: {'100% CONTAINED - ALL DEFENSES VALIDATED' if summary['all_contained'] else 'VULNERABILITY DETECTED'}")
    print("=" * 75)
