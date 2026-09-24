# -*- coding: utf-8 -*-
"""
Test Suite for L3-L5 Edge Autonomous Healing & In-Vehicle MCP Server
Conforms to ISO 26262 ASIL-D, Model Context Protocol, and AUTOSAR Adaptive Verification Standards.
"""

import json
import pytest
import time
from autonomous_healer import AutonomousHealer, HealingDecision, HealingLevel
from can_l0_l1_matrix import (
    CANFrame,
    CAN_ID_SENSOR_ACQ,
    CAN_ID_POWERTRAIN_ACT,
    E2EFrameCodec,
)
from digital_twin_state import DigitalTwinMirrorEngine, DigitalTwinState
from fleet_nostr_mesh_node import (
    FleetNostrMeshNode,
    NOSTR_KIND_VEHICLE_TELEMETRY,
    NOSTR_KIND_HEALING_ALERT,
)
from hybrid_model_router import ExecutionTier, HybridModelRouter
from soa_gateway_twin import SOAGatewayTwin
from vehicle_mcp_server import VehicleMCPServer


# ============================================================================
# 1. L3 Edge Autonomous Healer Unit Tests
# ============================================================================

def test_healer_level_transitions():
    """Validates graduated dynamic derating thresholds (75°C, 85°C, 105°C, <320V)."""
    twin = DigitalTwinMirrorEngine(vin="TEST-VIN-01")
    healer = AutonomousHealer(twin_engine=twin, db_path=":memory:", vin="TEST-VIN-01")

    # 1. Level 0 Nominal
    d0 = healer.evaluate_and_heal(temperature_c=60.0, battery_voltage_mv=398000)
    assert d0.level == HealingLevel.LEVEL_0_NORMAL
    assert d0.torque_limit_pct == 100.0
    assert not d0.motor_degraded
    assert d0.safety_mode == "NORMAL_OPERATION"

    # 2. Level 1 Dynamic Thermal Derating (> 75°C)
    d1 = healer.evaluate_and_heal(temperature_c=78.0, battery_voltage_mv=395000)
    assert d1.level == HealingLevel.LEVEL_1_DYNAMIC_DERATING
    assert d1.torque_limit_pct == 70.0
    assert d1.motor_degraded
    assert d1.safety_mode == "DERATED_LEVEL_1"
    assert twin.get_snapshot().torque_limit_pct == 70.0

    # 3. Level 2 Limp-Home Derating (> 85°C)
    d2 = healer.evaluate_and_heal(temperature_c=88.5, battery_voltage_mv=390000)
    assert d2.level == HealingLevel.LEVEL_2_LIMP_HOME
    assert d2.torque_limit_pct == 30.0
    assert d2.motor_degraded
    assert d2.safety_mode == "LIMP_HOME"
    assert twin.get_snapshot().torque_limit_pct == 30.0

    # 4. Level 2 Under-Voltage Derating (< 320V)
    d2_volt = healer.evaluate_and_heal(temperature_c=65.0, battery_voltage_mv=315000)
    assert d2_volt.level == HealingLevel.LEVEL_2_LIMP_HOME
    assert d2_volt.torque_limit_pct == 30.0

    # 5. Level 3 Emergency Safe Stop (> 105°C)
    d3 = healer.evaluate_and_heal(temperature_c=108.0, battery_voltage_mv=380000)
    assert d3.level == HealingLevel.LEVEL_3_EMERGENCY_STOP
    assert d3.torque_limit_pct == 0.0
    assert d3.safety_mode == "EMERGENCY_SAFE_STOP"

    # 6. Thermal Recovery
    d_rec = healer.evaluate_and_heal(temperature_c=55.0, battery_voltage_mv=398000)
    assert d_rec.level == HealingLevel.LEVEL_0_NORMAL
    assert d_rec.torque_limit_pct == 100.0
    assert not d_rec.motor_degraded
    assert d_rec.safety_mode == "NORMAL_OPERATION"


def test_healer_sqlite_audit_integrity():
    """Validates immutable SQLite audit logging and cryptographic signatures."""
    healer = AutonomousHealer(db_path=":memory:", vin="TEST-AUDIT-VIN")

    # Trigger multiple transitions
    healer.evaluate_and_heal(temperature_c=79.0, battery_voltage_mv=390000)
    healer.evaluate_and_heal(temperature_c=89.0, battery_voltage_mv=380000)
    healer.evaluate_and_heal(temperature_c=50.0, battery_voltage_mv=398000)

    audits = healer.get_recent_audits(10)
    assert len(audits) >= 3

    for row in audits:
        assert row["vin"] == "TEST-AUDIT-VIN"
        assert len(row["audit_hash"]) == 64  # SHA-256
        assert row["action_taken"] != ""
        assert row["status"] != ""

    summary = healer.get_audit_summary()
    assert summary["total_records"] >= 3
    assert summary["vin"] == "TEST-AUDIT-VIN"


def test_healer_manual_override_and_listeners():
    """Tests manual commander override and asynchronous decision listener dispatch."""
    healer = AutonomousHealer(db_path=":memory:", vin="TEST-OVERRIDE")
    dispatched_decisions = []

    healer.register_decision_listener(lambda d: dispatched_decisions.append(d))

    override_d = healer.manual_override_healing(
        target_level=2,
        reason="HIL Hardware-In-the-Loop Fault Injection Test",
        operator="Commander Jack Hu",
    )
    assert override_d.level == HealingLevel.LEVEL_2_LIMP_HOME
    assert override_d.torque_limit_pct == 30.0
    assert "HIL Hardware-In-the-Loop" in override_d.action_taken

    # Evaluate another event and ensure listener caught it
    healer.evaluate_and_heal(temperature_c=80.0, battery_voltage_mv=380000)
    assert len(dispatched_decisions) >= 1


# ============================================================================
# 2. Closed-Loop SOME/IP to Healer Integration Tests
# ============================================================================

def test_closed_loop_soa_someip_to_healer():
    """Tests CAN frame -> SOA SOME/IP Event 0x8002 -> Healer dynamic derating."""
    gateway = SOAGatewayTwin(enable_udp_broadcast=False)
    healer = AutonomousHealer(
        twin_engine=gateway.digital_twin_engine,
        db_path=":memory:",
        vin="PHANTOM-GRID-2026",
    )
    healer.attach_to_soa_gateway(gateway)

    # Encode a CAN frame with high temperature (88.0°C -> raw 880)
    codec = E2EFrameCodec(data_id=0x38)
    sensor_payload = (880).to_bytes(2, "big") + (220).to_bytes(2, "big")
    frame = codec.encode(CAN_ID_SENSOR_ACQ, sensor_payload)

    # Translate CAN frame
    someip_msg = gateway.translate_sensor_signal(frame)
    assert someip_msg is not None

    # Verify healer triggered Level 2 Limp-Home automatically!
    assert healer.current_level == HealingLevel.LEVEL_2_LIMP_HOME
    snap = gateway.digital_twin_engine.get_snapshot()
    assert snap.torque_limit_pct == 30.0
    assert snap.motor_degraded is True
    assert snap.safety_mode == "LIMP_HOME"


# ============================================================================
# 3. Fleet Nostr Mesh Node Tests
# ============================================================================

def test_nostr_mesh_event_signing_and_verification():
    """Tests NIP-01 / NIP-78 Nostr event generation, HMAC-SHA512 signing, and verification."""
    node = FleetNostrMeshNode(vin="PHANTOM-NOSTR-01")
    telemetry = {
        "motor_rpm": 2450.0,
        "temperature_c": 72.0,
        "battery_voltage_mv": 396000,
        "health_score_pct": 100.0,
    }

    event = node.broadcast_telemetry(telemetry, healing_level=0, note="Mesh nominal")
    assert event.kind == NOSTR_KIND_VEHICLE_TELEMETRY
    assert len(event.id) == 64
    assert len(event.pubkey) == 64
    assert len(event.sig) == 128
    assert event.verify() is True

    # Test query
    recent = node.query_recent_events(limit=5)
    assert len(recent) >= 1
    assert recent[0]["id"] == event.id

    # Test status
    status = node.get_mesh_status()
    assert status["vin"] == "PHANTOM-NOSTR-01"
    assert status["total_events_in_pool"] >= 1


# ============================================================================
# 4. Hybrid Cloud-Edge Router Tests
# ============================================================================

def test_hybrid_cloud_edge_routing():
    """Tests dynamic tier classification between Edge Critical, Edge Local Agent, and Cloud Fleet."""
    router = HybridModelRouter(vin="PHANTOM-ROUTER-01")

    # Safety critical thermal overload
    r1 = router.route_request("thermal_overload_protection", urgency="SAFETY_CRITICAL")
    assert r1.target_tier == ExecutionTier.EDGE_CRITICAL
    assert r1.token_cost == 0
    assert r1.estimated_latency_ms < 1.0

    # Local Agent diagnostic
    r2 = router.route_request("mcp_digital_twin_query", urgency="DIAGNOSTIC_QUERY")
    assert r2.target_tier == ExecutionTier.EDGE_LOCAL_AGENT
    assert r2.token_cost == 0

    # Global cloud fleet aggregation
    r3 = router.route_request("fleet_swarm_telemetry", urgency="NORMAL")
    assert r3.target_tier == ExecutionTier.CLOUD_FLEET_GLOBAL

    stats = router.get_router_stats()
    assert stats["total_routed_tasks"] == 3
    assert stats["tier_distribution"]["EDGE_CRITICAL"] == 1
    assert stats["tier_distribution"]["EDGE_LOCAL_AGENT"] == 1
    assert stats["tier_distribution"]["CLOUD_FLEET_GLOBAL"] == 1


# ============================================================================
# 5. In-Vehicle MCP Server JSON-RPC Tests
# ============================================================================

def test_vehicle_mcp_server_protocol_lifecycle():
    """Tests MCP JSON-RPC 2.0 initialize, ping, and tools/list."""
    server = VehicleMCPServer(vin="PHANTOM-MCP-01")

    # 1. Initialize
    init_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 101, "method": "initialize"})
    assert init_res["result"]["serverInfo"]["name"] == "phantom-grid-vehicle-mcp"
    assert "tools" in init_res["result"]["capabilities"]

    # 2. Ping
    ping_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 102, "method": "ping"})
    assert ping_res["result"] == {}

    # 3. Tools List
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 103, "method": "tools/list"})
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    expected_tools = [
        "get_digital_twin_telemetry",
        "trigger_autonomous_healing",
        "query_uds_dtc_diagnostics",
        "broadcast_nostr_mesh_telemetry",
        "route_hybrid_cloud_edge",
        "get_healing_audit_history",
    ]
    for exp in expected_tools:
        assert exp in tool_names


def test_vehicle_mcp_server_tool_executions():
    """Tests full execution of all exposed MCP tools via JSON-RPC tools/call."""
    server = VehicleMCPServer(vin="PHANTOM-MCP-02")

    # 1. Call get_digital_twin_telemetry
    res_tel = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 201,
        "method": "tools/call",
        "params": {
            "name": "get_digital_twin_telemetry",
            "arguments": {"detailed": True},
        },
    })
    assert not res_tel["result"]["isError"]
    tel_content = json.loads(res_tel["result"]["content"][0]["text"])
    assert tel_content["vin"] == "PHANTOM-MCP-02"
    assert "telemetry" in tel_content
    assert "cockpit_display" in tel_content

    # 2. Call trigger_autonomous_healing (force level 1)
    res_heal = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 202,
        "method": "tools/call",
        "params": {
            "name": "trigger_autonomous_healing",
            "arguments": {"force_level": 1, "reason": "Autonomous Diagnostic Test"},
        },
    })
    heal_content = json.loads(res_heal["result"]["content"][0]["text"])
    assert heal_content["status"] == "SUCCESS"
    assert heal_content["torque_limit_pct"] == 70.0
    assert heal_content["commanded_level"] == "LEVEL_1_DYNAMIC_DERATING"

    # 3. Call query_uds_dtc_diagnostics (now degraded, should see P0A80)
    res_dtc = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 203,
        "method": "tools/call",
        "params": {"name": "query_uds_dtc_diagnostics", "arguments": {}},
    })
    dtc_content = json.loads(res_dtc["result"]["content"][0]["text"])
    assert dtc_content["total_active_dtcs"] >= 1
    dtc_codes = [d["dtc"] for d in dtc_content["dtc_list"]]
    assert "P0A80" in dtc_codes

    # 4. Call broadcast_nostr_mesh_telemetry
    res_nostr = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 204,
        "method": "tools/call",
        "params": {
            "name": "broadcast_nostr_mesh_telemetry",
            "arguments": {"note": "Test broadcast"},
        },
    })
    nostr_content = json.loads(res_nostr["result"]["content"][0]["text"])
    assert nostr_content["status"] == "BROADCAST_SUCCESS"
    assert nostr_content["verified"] is True

    # 5. Call route_hybrid_cloud_edge
    res_route = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 205,
        "method": "tools/call",
        "params": {
            "name": "route_hybrid_cloud_edge",
            "arguments": {"task_type": "critical_derating", "urgency": "SAFETY_CRITICAL"},
        },
    })
    route_content = json.loads(res_route["result"]["content"][0]["text"])
    assert route_content["target_tier"] == "EDGE_CRITICAL"

    # 6. Call get_healing_audit_history
    res_audit = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 206,
        "method": "tools/call",
        "params": {"name": "get_healing_audit_history", "arguments": {"limit": 5}},
    })
    audit_content = json.loads(res_audit["result"]["content"][0]["text"])
    assert audit_content["total_audit_records"] >= 1

    # 7. Error handling: Unknown tool
    res_err = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 207,
        "method": "tools/call",
        "params": {"name": "non_existent_tool", "arguments": {}},
    })
    assert res_err["result"]["isError"] is True
