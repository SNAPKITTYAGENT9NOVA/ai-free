# -*- coding: utf-8 -*-
"""
Test Suite for L3 Autonomous Healer and L4 Vehicle MCP Server Stdio JSON-RPC
Conforms to ISO 26262 ASIL-D, SOME/IP Service 0x1002 Event 0x8002, and Model Context Protocol.
"""

import json
import os
import struct
import tempfile
import pytest

from audit_governance import GovernanceDB
from autonomous_healer import AutonomousHealer, SOMEIP_HEADER_LEN
from vehicle_mcp_server import (
    handle_get_digital_twin_telemetry,
    handle_trigger_emergency_derate,
    handle_query_audit_trail,
    TOOLS,
    DB_PATH,
)


def build_someip_packet(service_id: int, event_id: int, voltage_mv: int, temp_c: int) -> bytes:
    """Constructs a 16-byte SOME/IP header + 5-byte payload (!IB)."""
    msg_id = (service_id << 16) | event_id
    length = 8 + 5
    req_id = 0x00010001
    proto_ver = 1
    if_ver = 1
    msg_type = 0x02
    ret_code = 0x00

    header = struct.pack("!IIIBBBB", msg_id, length, req_id, proto_ver, if_ver, msg_type, ret_code)
    payload = struct.pack("!IB", voltage_mv, temp_c)
    return header + payload


def test_autonomous_healer_someip_dynamic_derating():
    """Tests Level 1, Level 2, and Auto Recovery dynamic derating thresholds via SOME/IP."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_db = os.path.join(tmpdir, "test_audit.db")
        healer = AutonomousHealer(db_path=test_db, bind_socket=False)
        assert healer.power_limit_pct == 100

        # 1. Level 1 防線 (75°C -> 70% power)
        pkt_75 = build_someip_packet(0x1002, 0x8002, 12600, 78)
        healer.process_incoming_event(pkt_75)
        assert healer.power_limit_pct == 70

        # 2. Level 2 防線 (85°C -> 50% power)
        pkt_85 = build_someip_packet(0x1002, 0x8002, 12400, 89)
        healer.process_incoming_event(pkt_85)
        assert healer.power_limit_pct == 50

        # 3. 自動回正 (Auto Recovery < 60°C -> 100% power)
        pkt_rec = build_someip_packet(0x1002, 0x8002, 12800, 52)
        healer.process_incoming_event(pkt_rec)
        assert healer.power_limit_pct == 100

        # 4. Verify audit_logs table written in SQLite
        logs = healer.db.query_logs(limit=10)
        assert len(logs) >= 3
        actions = [log["action_type"] for log in logs]
        assert "THERMAL_TRIMMING" in actions
        assert "EMERGENCY_DERATING" in actions
        assert "AUTO_RECOVERY" in actions
        healer.close()


def test_vehicle_mcp_standalone_tools():
    """Tests handle_get_digital_twin_telemetry, handle_trigger_emergency_derate, and handle_query_audit_trail."""
    # 1. Telemetry query
    raw_telemetry = handle_get_digital_twin_telemetry({})
    telemetry = json.loads(raw_telemetry)
    assert "motor_rpm" in telemetry
    assert "battery_voltage_mv" in telemetry
    assert "temperature_c" in telemetry
    assert "power_limit_pct" in telemetry
    assert telemetry["e2e_valid"] is True

    # 2. Emergency derate execution
    derate_raw = handle_trigger_emergency_derate({"target_power_pct": 45, "reason": "Track temperature surge"})
    derate_res = json.loads(derate_raw)
    assert derate_res["status"] == "SUCCESS"
    assert derate_res["applied_power_limit"] == 45
    assert derate_res["audit_logged"] is True

    # 3. Query audit trail
    trail_raw = handle_query_audit_trail({"limit": 5})
    trail = json.loads(trail_raw)
    assert isinstance(trail, list)
    assert len(trail) >= 1
    latest = trail[0]
    assert latest["status"] == "EXECUTED"
    assert latest["action"] == "EMERGENCY_DERATE"
    assert "45%" in latest["details"]


def test_vehicle_mcp_tools_list_spec():
    """Validates that TOOLS contains standard tool names and input schemas."""
    tool_names = [t["name"] for t in TOOLS]
    assert "get_digital_twin_telemetry" in tool_names
    assert "trigger_emergency_derate" in tool_names
    assert "query_audit_trail" in tool_names


def test_vehicle_mcp_stdio_jsonrpc_pipeline():
    """Tests stdio JSON-RPC loop handling tools/list and tools/call requests."""
    import subprocess
    import sys

    # Send tools/list and tools/call commands over stdin
    req1 = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
    req2 = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "trigger_emergency_derate",
            "arguments": {"target_power_pct": 50, "reason": "Stdio pipe emergency test"}
        }
    }
    req3 = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "query_audit_trail",
            "arguments": {"limit": 3}
        }
    }
    input_str = f"{json.dumps(req1)}\n{json.dumps(req2)}\n{json.dumps(req3)}\n"

    proc = subprocess.run(
        [sys.executable, "-X", "utf8", "vehicle_mcp_server.py", "--stdio"],
        input=input_str,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=5,
    )
    assert proc.returncode == 0
    lines = [line.strip() for line in proc.stdout.strip().split("\n") if line.strip()]
    assert len(lines) >= 3

    resp1 = json.loads(lines[0])
    assert resp1["id"] == 1
    assert "tools" in resp1["result"]

    resp2 = json.loads(lines[1])
    assert resp2["id"] == 2
    content2 = json.loads(resp2["result"]["content"][0]["text"])
    assert content2["status"] == "SUCCESS"
    assert content2["applied_power_limit"] == 50

    resp3 = json.loads(lines[2])
    assert resp3["id"] == 3
    content3 = json.loads(resp3["result"]["content"][0]["text"])
    assert isinstance(content3, list)
    assert len(content3) >= 1


