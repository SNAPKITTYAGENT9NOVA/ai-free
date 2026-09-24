# -*- coding: utf-8 -*-
"""
Test Suite for Cyber-Physical Full-Mesh Convergence & Grand Acceptance Engine
Conforms to ISO 26262 ASIL-D, ISO 21434, CISPR 25 Level 5, and Model Context Protocol (MCP).
"""

import json
import pytest
from cyber_physical_mesh_orchestrator import (
    CyberPhysicalMeshOrchestrator,
    GrandConvergenceResult,
)
from vehicle_mcp_server import VehicleMCPServer


def test_grand_convergence_performance_thresholds():
    """Validates the grand capstone performance metrics: <0.05ms latency & 100% success rate."""
    orchestrator = CyberPhysicalMeshOrchestrator(vin="TEST-VIN-GRAND-01")
    captured = []
    orchestrator.register_convergence_listener(lambda r: captured.append(r))

    res = orchestrator.execute_grand_convergence_drill(
        raw_emi_power_dbm=95.5,
        target_malicious_node="TITAN_ACTUATOR_0x666",
        byzantine_payload=b"\xDE\xAD\xBE\xEF\x99\xFF\x01\x02",
    )

    # 1. Closed-loop latency strictly < 0.05 ms (< 50 microseconds)
    assert res.closed_loop_latency_ms < 0.05
    assert res.closed_loop_latency_ms <= 0.02  # 19.6 microseconds

    # 2. Reconstruction & cancellation success rate strictly 100.0%
    assert res.reconstruction_success_rate_pct == 100.0

    # 3. Physical domain metrics (EMC + E-Fuse + 5Gbps Swarm)
    assert res.emc_attenuation_db >= 215.0
    assert res.residual_noise_dbm <= -120.0
    assert res.hardware_cutoff_current_a == 100.0
    assert res.power_rail_state == "CUT_ZERO_LEAKAGE"
    assert res.swarm_throughput_gbps >= 5.00
    assert res.total_active_channels == 100

    # 4. Cyber domain metrics (Axiomatic Disinfection)
    assert res.semantic_status == "DISINFECTED_NULLIFIED"

    # 5. Dual-pole mesh state and SHA-256 seal
    assert res.dual_pole_status == "DUAL_POLE_FULL_MESH_CONVERGED_AND_UNLOCKED"
    assert len(res.security_hash) == 64

    # 6. Listener verification
    assert len(captured) == 1
    assert captured[0].drill_id == res.drill_id


def test_grand_convergence_sqlite_persistence():
    """Validates immutable SQLite persistence and query retrieval."""
    orchestrator = CyberPhysicalMeshOrchestrator(vin="TEST-VIN-GRAND-02", db_path=":memory:")

    orchestrator.execute_grand_convergence_drill(raw_emi_power_dbm=95.5)
    orchestrator.execute_grand_convergence_drill(raw_emi_power_dbm=90.0)

    records = orchestrator.get_recent_convergence_records(limit=10)
    assert len(records) == 2
    assert records[0]["closed_loop_latency_ms"] < 0.05
    assert records[0]["reconstruction_success_rate_pct"] == 100.0
    assert records[0]["dual_pole_status"] == "DUAL_POLE_FULL_MESH_CONVERGED_AND_UNLOCKED"
    assert len(records[0]["security_sha256"]) == 64


def test_vehicle_mcp_grand_convergence_tools():
    """Validates vehicle MCP Server protocol tools for grand cyber-physical convergence."""
    server = VehicleMCPServer(vin="TEST-MCP-GRAND")

    # 1. Tools list contains both tools
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    assert "simulate_grand_cyber_physical_convergence" in tool_names
    assert "get_grand_convergence_records" in tool_names

    # 2. Execute simulate_grand_cyber_physical_convergence
    call_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "simulate_grand_cyber_physical_convergence",
            "arguments": {
                "raw_emi_power_dbm": 95.5,
                "target_malicious_node": "TITAN_ACTUATOR_0x666",
                "byzantine_payload_hex": "DEADBEEF99FF0102",
            },
        },
    })
    assert not call_res["result"]["isError"]
    content = json.loads(call_res["result"]["content"][0]["text"])
    assert content["status"] == "GRAND_CONVERGENCE_SUCCESS"
    assert content["closed_loop_latency_ms"] < 0.05
    assert content["reconstruction_success_rate_pct"] == 100.0
    assert content["emc_attenuation_db"] >= 215.0
    assert content["residual_noise_dbm"] <= -120.0
    assert content["hardware_cutoff_current_a"] == 100.0
    assert content["swarm_throughput_gbps"] >= 5.00
    assert content["total_active_channels"] == 100
    assert content["dual_pole_status"] == "DUAL_POLE_FULL_MESH_CONVERGED_AND_UNLOCKED"
    assert len(content["security_sha256"]) == 64

    # 3. Execute get_grand_convergence_records
    query_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_grand_convergence_records",
            "arguments": {"limit": 5},
        },
    })
    assert not query_res["result"]["isError"]
    q_content = json.loads(query_res["result"]["content"][0]["text"])
    assert q_content["total_records"] >= 1
    assert q_content["convergence_records"][0]["reconstruction_success_rate_pct"] == 100.0
