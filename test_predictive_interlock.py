# -*- coding: utf-8 -*-
"""
Test Suite for Automotive Predictive Causal Pre-emption and E-Fuse Hardware Interlock Engine
Conforms to ISO 26262 ASIL-D, ISO 21434, and Model Context Protocol (MCP).
"""

import json
import pytest
from predictive_efuse_interlock import (
    CausalSignalSample,
    PredictiveCausalEFuseEngine,
    PredictiveInterlockResult,
)
from vehicle_mcp_server import VehicleMCPServer


def test_causal_entropy_evaluation():
    """Validates that upstream telemetry correctly classifies nominal vs singularity drift."""
    engine = PredictiveCausalEFuseEngine(vin="TEST-VIN-CAUSAL-01")

    # 1. Nominal sample
    nominal_sample = CausalSignalSample(
        channel="POWERTRAIN_CAN_FD_L1",
        entropy_bits=1.85,
        torque_gradient_pct_per_ms=2.1,
        firmware_divergence=0.01,
        bus_jitter_us=2.5,
    )
    is_singularity, entropy, risk = engine.evaluate_upstream_telemetry(nominal_sample)
    assert not is_singularity
    assert entropy < 3.80
    assert risk < 0.85

    # 2. Anomaly singularity sample
    anomaly_sample = CausalSignalSample(
        channel="POWERTRAIN_CAN_FD_L1",
        entropy_bits=4.25,
        torque_gradient_pct_per_ms=19.2,
        firmware_divergence=0.95,
        bus_jitter_us=18.6,
    )
    is_singularity2, entropy2, risk2 = engine.evaluate_upstream_telemetry(anomaly_sample)
    assert is_singularity2
    assert entropy2 >= 3.80
    assert risk2 >= 0.85


def test_predictive_efuse_hardware_interlock_execution():
    """Validates proactive 100A e-fuse cutoff and physical pin latch isolation."""
    engine = PredictiveCausalEFuseEngine(vin="TEST-VIN-CAUSAL-02")
    captured = []
    engine.register_interlock_listener(lambda r: captured.append(r))

    target = "PREDICTED_MALICIOUS_NODE_0x666"
    res = engine.execute_predictive_interlock(target_node=target)

    assert res.target_node == target
    assert res.cutoff_current_a == 100.0
    assert res.power_rail_state == "CUT_ZERO_LEAKAGE"
    assert res.pin_transceiver_state == "PHYSICALLY_LATCHED_ISOLATED"
    assert res.interlock_latency_us <= 2.0  # Ultra-fast microsecond range
    assert res.interlock_status == "PREDICTIVE_HARDWARE_INTERLOCK_EXECUTED"
    assert len(res.security_hash) == 64     # SHA-256 seal

    # Verify listener callback
    assert len(captured) == 1
    assert captured[0].run_id == res.run_id


def test_predictive_interlock_sqlite_persistence():
    """Validates audit persistence and tamper-proof SQLite ledger storage."""
    engine = PredictiveCausalEFuseEngine(vin="TEST-VIN-CAUSAL-03", db_path=":memory:")

    engine.execute_predictive_interlock(target_node="NODE_TEST_A")
    engine.execute_predictive_interlock(target_node="NODE_TEST_B")

    records = engine.get_recent_interlock_records(limit=10)
    assert len(records) == 2
    assert records[0]["target_node"] in ("NODE_TEST_A", "NODE_TEST_B")
    assert records[0]["cutoff_current_a"] == 100.0
    assert len(records[0]["security_sha256"]) == 64


def test_vehicle_mcp_predictive_interlock_tools():
    """Validates MCP JSON-RPC protocol execution of predictive interlock tools."""
    server = VehicleMCPServer(vin="TEST-MCP-PREDICTIVE")

    # 1. Tools list contains both tools
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    assert "simulate_predictive_efuse_interlock" in tool_names
    assert "get_predictive_interlock_records" in tool_names

    # 2. Execute simulate_predictive_efuse_interlock
    call_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "simulate_predictive_efuse_interlock",
            "arguments": {
                "target_node": "PREDICTED_MALICIOUS_NODE_0x666",
                "entropy_bits": 4.15,
                "torque_gradient_pct_per_ms": 18.0,
                "firmware_divergence": 0.90,
            },
        },
    })
    assert not call_res["result"]["isError"]
    content = json.loads(call_res["result"]["content"][0]["text"])
    assert content["status"] == "PREDICTIVE_INTERLOCK_SUCCESS"
    assert content["target_node"] == "PREDICTED_MALICIOUS_NODE_0x666"
    assert content["cutoff_current_a"] == 100.0
    assert content["power_rail_state"] == "CUT_ZERO_LEAKAGE"
    assert content["pin_transceiver_state"] == "PHYSICALLY_LATCHED_ISOLATED"
    assert content["interlock_latency_us"] <= 2.0
    assert len(content["security_sha256"]) == 64

    # 3. Execute get_predictive_interlock_records
    query_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_predictive_interlock_records",
            "arguments": {"limit": 5},
        },
    })
    assert not query_res["result"]["isError"]
    q_content = json.loads(query_res["result"]["content"][0]["text"])
    assert q_content["total_records"] >= 1
    assert q_content["interlock_records"][0]["cutoff_current_a"] == 100.0
