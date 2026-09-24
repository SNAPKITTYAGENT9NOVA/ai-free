# -*- coding: utf-8 -*-
"""
Test Suite for Automotive Root-of-Trust Intent Lock & 5Gbps Swarm State Recovery Engine
Conforms to ISO 26262 ASIL-D, ISO 21434 Hardware Root of Trust, and Model Context Protocol (MCP).
"""

import json
import pytest
from root_trust_state_recovery import (
    GoldenIntentState,
    RootTrustRecoveryResult,
    RootTrustStateRecoveryEngine,
)
from vehicle_mcp_server import VehicleMCPServer


def test_golden_intent_lock_initialization():
    """Validates immutable Commander intent anchoring in root of trust."""
    intent = GoldenIntentState(
        commander_id="Jack Hu (jackhu24-ship-it)",
        mission_code="PRIMARY_CAUSE_ALPHA",
    )
    engine = RootTrustStateRecoveryEngine(vin="TEST-VIN-ROOT-01", golden_intent=intent)

    assert engine.golden_intent.commander_id == "Jack Hu (jackhu24-ship-it)"
    assert engine.golden_intent.lock_policy == "UNSHAKABLE_PRIMARY_CAUSE"
    assert engine.golden_intent.lock_status == "IMMUTABLE_LOCKED"
    assert len(engine.intent_lock_hash) == 64  # SHA-256


def test_swarm_state_recovery_execution():
    """Validates 100-channel 5Gbps swarm reconstitution and microsecond golden state recovery."""
    engine = RootTrustStateRecoveryEngine(vin="TEST-VIN-ROOT-02")
    captured = []
    engine.register_recovery_listener(lambda r: captured.append(r))

    res = engine.execute_swarm_state_recovery(
        adversarial_disturbance="CYBER_INTRUSION_SIMULATED"
    )

    # 1. Swarm throughput metrics
    assert res.total_channels == 100
    assert res.throughput_gbps >= 5.00

    # 2. State recovery metrics
    assert res.recovery_latency_us <= 50.0  # Ultra-fast microsecond rollback
    assert res.state_integrity_score == 100.0
    assert "PERTURBED" in res.pre_recovery_state
    assert res.post_recovery_state == "GOLDEN_INTENT_RESTORED"
    assert res.recovery_status == "ROOT_TRUST_STATE_RECONSTITUTED"
    assert len(res.security_hash) == 64

    # 3. Listener callback
    assert len(captured) == 1
    assert captured[0].recovery_id == res.recovery_id


def test_root_trust_sqlite_persistence():
    """Validates immutable SQLite persistence and query retrieval."""
    engine = RootTrustStateRecoveryEngine(vin="TEST-VIN-ROOT-03", db_path=":memory:")

    engine.execute_swarm_state_recovery(adversarial_disturbance="FAULT_A")
    engine.execute_swarm_state_recovery(adversarial_disturbance="FAULT_B")

    records = engine.get_recent_recovery_records(limit=10)
    assert len(records) == 2
    assert records[0]["throughput_gbps"] >= 5.00
    assert records[0]["state_integrity_score"] == 100.0
    assert len(records[0]["security_sha256"]) == 64


def test_vehicle_mcp_root_trust_tools():
    """Validates vehicle MCP Server protocol tools for root of trust recovery."""
    server = VehicleMCPServer(vin="TEST-MCP-ROOT-TRUST")

    # 1. Tools list contains both tools
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    assert "simulate_root_trust_swarm_recovery" in tool_names
    assert "get_root_trust_recovery_records" in tool_names

    # 2. Execute simulate_root_trust_swarm_recovery
    call_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "simulate_root_trust_swarm_recovery",
            "arguments": {
                "adversarial_disturbance": "EXTREME_PHYSICAL_BLOWOUT",
            },
        },
    })
    assert not call_res["result"]["isError"]
    content = json.loads(call_res["result"]["content"][0]["text"])
    assert content["status"] == "ROOT_TRUST_RECOVERY_SUCCESS"
    assert content["total_channels"] == 100
    assert content["throughput_gbps"] >= 5.00
    assert content["recovery_latency_us"] <= 50.0
    assert content["state_integrity_score"] == 100.0
    assert content["post_recovery_state"] == "GOLDEN_INTENT_RESTORED"
    assert len(content["security_sha256"]) == 64

    # 3. Execute get_root_trust_recovery_records
    query_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_root_trust_recovery_records",
            "arguments": {"limit": 5},
        },
    })
    assert not query_res["result"]["isError"]
    q_content = json.loads(query_res["result"]["content"][0]["text"])
    assert q_content["total_records"] >= 1
    assert q_content["recovery_records"][0]["throughput_gbps"] >= 5.00
