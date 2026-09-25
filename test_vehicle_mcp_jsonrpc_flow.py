# -*- coding: utf-8 -*-
"""
Test Suite: Vehicle MCP Server JSON-RPC Stdio Simulation Workflow
Simulates Commander Agent resolving high-temperature anomalies via MCP JSON-RPC:
1. Step 1: get_digital_twin_telemetry -> Detect 78°C / 8250 RPM / WARNING_HIGH_TEMP.
2. Step 2: trigger_emergency_derate -> Command 50% power ceiling clamping.
3. Step 3: query_audit_trail -> Verify tamper-evident SQLite audit logs.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def test_vehicle_mcp_jsonrpc_three_step_flow():
    requests = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {
                "name": "get_digital_twin_telemetry",
                "arguments": {
                    "temperature_c": 78,
                    "motor_rpm": 8250,
                    "battery_voltage_mv": 12450,
                    "system_status": "WARNING_HIGH_TEMP",
                    "power_limit_pct": 100,
                    "e2e_valid": True,
                },
            },
        },
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": "trigger_emergency_derate",
                "arguments": {
                    "target_power_pct": 50,
                    "reason": "極限高溫告警 (78°C) 觸發 Level 2 主動功率降額",
                },
            },
        },
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "query_audit_trail",
                "arguments": {
                    "limit": 2,
                },
            },
        },
    ]

    input_payload = "\n".join(json.dumps(r) for r in requests) + "\n"

    proc = subprocess.Popen(
        [sys.executable, "vehicle_mcp_server.py", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )

    out, err = proc.communicate(input=input_payload)
    assert proc.returncode == 0

    responses = {}
    for line in out.strip().split("\n"):
        if line.strip():
            resp = json.loads(line)
            responses[resp["id"]] = resp

    # Validate Step 1
    assert 1 in responses
    telemetry = json.loads(responses[1]["result"]["content"][0]["text"])
    assert telemetry["motor_rpm"] == 8250
    assert telemetry["battery_voltage_mv"] == 12450
    assert telemetry["temperature_c"] == 78
    assert telemetry["system_status"] == "WARNING_HIGH_TEMP"
    assert telemetry["power_limit_pct"] == 100
    assert telemetry["e2e_valid"] is True

    # Validate Step 2
    assert 2 in responses
    derate_res = json.loads(responses[2]["result"]["content"][0]["text"])
    assert derate_res["status"] == "SUCCESS"
    assert derate_res["applied_power_limit"] == 50
    assert derate_res["audit_logged"] is True
    assert "50%" in derate_res["message"]

    # Validate Step 3
    assert 3 in responses
    audits = json.loads(responses[3]["result"]["content"][0]["text"])
    assert isinstance(audits, list)
    assert len(audits) >= 1
    top_audit = audits[0]
    assert top_audit["task_id"] == "MCP_DERATE"
    assert "👑 指揮官" in top_audit["operator"]
    assert top_audit["status"] == "EXECUTED"
    assert top_audit["action"] == "EMERGENCY_DERATE"
    assert "78°C" in top_audit["details"]
