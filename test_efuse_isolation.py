# -*- coding: utf-8 -*-
"""
Test Suite for Automotive Hardware Isolation & E-Fuse Protection Engine
Conforms to ISO 26262 ASIL-D, ISO 21434 Cybersecurity, and Model Context Protocol.
"""

import hashlib
import json
import pytest
from efuse_isolation_engine import (
    AttackType,
    EFuseIsolationEvent,
    EFuseProtectionEngine,
    EFuseState,
)
from vehicle_mcp_server import VehicleMCPServer


def test_nominal_node_activity_no_trip():
    """Validates that authorized CAN IDs operate with closed nominal switches."""
    engine = EFuseProtectionEngine(vin="TEST-VIN-NOMINAL")

    event = engine.evaluate_node_activity(
        node_id="POWERTRAIN_0x280",
        can_id=0x280,
        raw_payload=b"\x00\x10\x64",
        claimed_torque_pct=85.0,
    )
    assert event is None
    status = engine.get_node_status("POWERTRAIN_0x280")
    assert status["efuse_state"] == "CLOSED_NOMINAL"
    assert status["pin_isolated"] is False
    assert status["blacklisted"] is False
    assert status["power_rail"] == "ONLINE_POWERED"


def test_unauthorized_node_0x666_efuse_trip():
    """Validates that unauthorized node 0x666 triggers 100A trip, pin isolation, and burnout."""
    engine = EFuseProtectionEngine(vin="TEST-VIN-MALICIOUS")

    event = engine.evaluate_node_activity(
        node_id="UNAUTHORIZED_NODE_0x666",
        can_id=0x666,
        raw_payload=b"\xDE\xAD\xBE\xEF",
        claimed_torque_pct=100.0,
    )
    assert event is not None
    assert event.target_node_id == "UNAUTHORIZED_NODE_0x666"
    assert event.target_can_id == 0x666
    assert event.attack_type == AttackType.UNAUTHORIZED_NODE_INJECTION
    assert event.peak_trip_current_a == 100.0
    assert event.efuse_state == EFuseState.PERMANENT_BURNOUT
    assert event.pin_isolated is True
    assert event.blacklisted is True
    assert len(event.security_hash) == 64  # SHA-256

    # Node status reflects hardware cutoff
    status = engine.get_node_status("UNAUTHORIZED_NODE_0x666")
    assert status["efuse_state"] == "PERMANENT_BURNOUT"
    assert status["pin_isolated"] is True
    assert status["power_rail"] == "OFFLINE_LATCHED"


def test_firmware_tampering_and_torque_spoofing():
    """Validates detection and trip on firmware tampering and illegal torque ceilings."""
    engine = EFuseProtectionEngine(vin="TEST-VIN-SPOOF")

    # 1. Firmware tampering
    fake_fw_hash = hashlib.sha256(b"MALICIOUS_ROOTKIT_FIRMWARE").hexdigest()
    ev_fw = engine.evaluate_node_activity(
        node_id="TAMPERED_NODE_0x080",
        can_id=0x080,
        raw_payload=b"\x01\x02",
        firmware_hash=fake_fw_hash,
    )
    assert ev_fw is not None
    assert ev_fw.attack_type == AttackType.FIRMWARE_TAMPER_ATTEMPT
    assert ev_fw.efuse_state == EFuseState.PERMANENT_BURNOUT

    # 2. Out-of-envelope torque spoofing (250% torque)
    ev_tq = engine.evaluate_node_activity(
        node_id="ROGUE_ACTUATOR_0x120",
        can_id=0x120,
        raw_payload=b"\x03\x04",
        claimed_torque_pct=250.0,
    )
    assert ev_tq is not None
    assert ev_tq.attack_type == AttackType.TORQUE_LIMIT_SPOOFING
    assert ev_tq.efuse_state == EFuseState.PERMANENT_BURNOUT


def test_sqlite_blacklist_persistence_and_queries():
    """Validates immutable SQLite persistence and query operations."""
    engine = EFuseProtectionEngine(vin="TEST-VIN-SQLITE", db_path=":memory:")

    engine.evaluate_node_activity(
        node_id="ROGUE_0x666",
        can_id=0x666,
        raw_payload=b"\x13\x37",
    )
    assert engine.is_node_blacklisted("ROGUE_0x666") is True

    records = engine.get_blacklist_records(limit=10)
    assert len(records) == 1
    rec = records[0]
    assert rec["target_node_id"] == "ROGUE_0x666"
    assert rec["target_can_id"] == 0x666
    assert rec["peak_trip_current_a"] == 100.0
    assert rec["pin_isolated"] == 1
    assert len(rec["security_sha256"]) == 64


def test_vehicle_mcp_server_efuse_tool_integration():
    """Validates that VehicleMCPServer can trigger E-Fuse isolation and query blacklist via MCP."""
    server = VehicleMCPServer(vin="TEST-MCP-EFUSE")

    # 1. Verify tools listed
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    assert "trigger_efuse_hardware_isolation" in tool_names
    assert "get_efuse_blacklist" in tool_names

    # 2. Call trigger_efuse_hardware_isolation
    call_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "trigger_efuse_hardware_isolation",
            "arguments": {
                "node_id": "UNAUTHORIZED_NODE_0x666",
                "can_id": 0x666,
                "reason": "Tamper attack detected by AI Sentinel",
            },
        },
    })
    assert not call_res["result"]["isError"]
    content = json.loads(call_res["result"]["content"][0]["text"])
    assert content["status"] == "HARDWARE_ISOLATED"
    assert content["target_node_id"] == "UNAUTHORIZED_NODE_0x666"
    assert content["trip_current_a"] == 100.0
    assert content["pin_isolated"] is True
    assert len(content["security_sha256"]) == 64

    # 3. Call get_efuse_blacklist
    list_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_efuse_blacklist",
            "arguments": {"limit": 5},
        },
    })
    assert not list_res["result"]["isError"]
    list_content = json.loads(list_res["result"]["content"][0]["text"])
    assert list_content["total_isolated_nodes"] >= 1
    assert list_content["blacklist_records"][0]["target_node_id"] == "UNAUTHORIZED_NODE_0x666"
