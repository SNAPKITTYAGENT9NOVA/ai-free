# -*- coding: utf-8 -*-
"""
Test Suite for Axiomatic Semantic Disinfection and Active Anti-Phase Dual Shielding Engine
Conforms to CISPR 25 Level 5, ISO 11452, ISO 26262 ASIL-D, and Model Context Protocol (MCP).
"""

import json
import pytest
from axiomatic_dual_shielding import (
    AxiomaticDualShieldingEngine,
    AxiomaticDualShieldResult,
    AxiomaticSemanticDisinfector,
    AxiomaticValidationStatus,
)
from vehicle_mcp_server import VehicleMCPServer


def test_axiomatic_semantic_disinfector():
    """Validates formal axiomatic verification and semantic nullification rules."""
    # 1. Canonical payload
    canonical_payload = bytes([0x28, 0x01, 0x01, 0xF4, 0x00, 0x00, 0x00, 0x00])  # 50.0% torque
    status, rule, disinfected = AxiomaticSemanticDisinfector.evaluate_and_disinfect(canonical_payload)
    assert status == AxiomaticValidationStatus.VALID_CANONICAL
    assert disinfected == canonical_payload

    # 2. Byzantine / malformed opcode injection
    byzantine_payload = b"\xDE\xAD\xBE\xEF\x99\xFF\x01\x02"
    status2, rule2, disinfected2 = AxiomaticSemanticDisinfector.evaluate_and_disinfect(byzantine_payload)
    assert status2 == AxiomaticValidationStatus.DISINFECTED_NULLIFIED
    assert "BYZANTINE" in rule2
    assert disinfected2 == b"\x00" * 8

    # 3. Torque boundary violation (> 100.0%)
    invalid_torque_payload = bytes([0x28, 0x01, 0x05, 0x00])  # 128.0% torque (> 1000)
    status3, rule3, disinfected3 = AxiomaticSemanticDisinfector.evaluate_and_disinfect(invalid_torque_payload)
    assert status3 == AxiomaticValidationStatus.DISINFECTED_NULLIFIED
    assert "TORQUE_BOUNDARY" in rule3
    assert int.from_bytes(disinfected3[2:4], "big") == 0


def test_dual_shield_orchestration():
    """Validates simultaneous 30ps physical EMC cancellation and logic semantic disinfection."""
    engine = AxiomaticDualShieldingEngine(vin="TEST-VIN-AXIOM-01")
    captured = []
    engine.register_shield_listener(lambda r: captured.append(r))

    res = engine.execute_dual_shield(
        channel_name="CAN_H_ANALOG_IN",
        raw_emi_power_dbm=95.5,
        payload=b"\xFF\xDE\xAD\x00\x00\x00\x00\x00",
    )

    # Physical layer validations
    assert res.raw_emi_power_dbm == 95.5
    assert res.anti_phase_angle_deg == 180.0
    assert res.residual_noise_dbm == -120.0
    assert res.total_attenuation_db == 215.5
    assert res.response_latency_ps == 30.0
    assert res.signal_snr_db >= 45.0

    # Semantic layer validations
    assert res.semantic_status == "DISINFECTED_NULLIFIED"
    assert "BYZANTINE" in res.nullification_rule
    assert res.dual_shield_compliance == "LOGICAL_INCOMPATIBLE_PHYSICAL_IMMUNE"
    assert len(res.security_hash) == 64

    # Listener validation
    assert len(captured) == 1
    assert captured[0].drill_id == res.drill_id


def test_axiomatic_dual_shield_sqlite_persistence():
    """Validates immutable SQLite persistence and query retrieval."""
    engine = AxiomaticDualShieldingEngine(vin="TEST-VIN-AXIOM-02", db_path=":memory:")

    engine.execute_dual_shield(channel_name="CH_A", raw_emi_power_dbm=95.5)
    engine.execute_dual_shield(channel_name="CH_B", raw_emi_power_dbm=90.0)

    records = engine.get_recent_shield_records(limit=10)
    assert len(records) == 2
    assert records[0]["channel_name"] in ("CH_A", "CH_B")
    assert records[0]["residual_noise_dbm"] == -120.0
    assert records[0]["response_latency_ps"] == 30.0
    assert len(records[0]["security_sha256"]) == 64


def test_vehicle_mcp_axiomatic_dual_shield_tools():
    """Validates vehicle MCP Server protocol tools for dual-layer shielding."""
    server = VehicleMCPServer(vin="TEST-MCP-AXIOM")

    # 1. Tools list contains both tools
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    assert "simulate_axiomatic_dual_shield" in tool_names
    assert "get_axiomatic_dual_shield_records" in tool_names

    # 2. Execute simulate_axiomatic_dual_shield
    call_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "simulate_axiomatic_dual_shield",
            "arguments": {
                "channel_name": "CAN_H_ANALOG_IN",
                "raw_emi_power_dbm": 95.5,
                "payload_hex": "DEADBEEF99FF0102",
            },
        },
    })
    assert not call_res["result"]["isError"]
    content = json.loads(call_res["result"]["content"][0]["text"])
    assert content["status"] == "DUAL_SHIELD_SUCCESS"
    assert content["raw_emi_power_dbm"] == 95.5
    assert content["anti_phase_angle_deg"] == 180.0
    assert content["residual_noise_dbm"] == -120.0
    assert content["response_latency_ps"] == 30.0
    assert content["semantic_status"] == "DISINFECTED_NULLIFIED"
    assert content["dual_shield_compliance"] == "LOGICAL_INCOMPATIBLE_PHYSICAL_IMMUNE"
    assert len(content["security_sha256"]) == 64

    # 3. Execute get_axiomatic_dual_shield_records
    query_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_axiomatic_dual_shield_records",
            "arguments": {"limit": 5},
        },
    })
    assert not query_res["result"]["isError"]
    q_content = json.loads(query_res["result"]["content"][0]["text"])
    assert q_content["total_records"] >= 1
    assert q_content["shield_records"][0]["residual_noise_dbm"] == -120.0
