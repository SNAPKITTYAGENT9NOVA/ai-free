# -*- coding: utf-8 -*-
"""
Test Suite for Automotive Central HPC Swarm & 5Gbps Throughput Engine
Conforms to AUTOSAR Adaptive Platform, IEEE 802.1Q TSN, and Model Context Protocol.
"""

import json
import pytest
from hpc_swarm_throughput_engine import (
    HPCBenchmarkResult,
    HPCSwarmThroughputEngine,
)
from vehicle_mcp_server import VehicleMCPServer


def test_hpc_100_channel_5gbps_line_rate():
    """Validates that 100 concurrent channels achieve >= 5.00 Gbps with zero packet loss."""
    engine = HPCSwarmThroughputEngine(vin="TEST-VIN-HPC-01")

    res = engine.run_hpc_swarm_benchmark(num_channels=100, burst_duration_sec=0.1)
    assert res.total_channels == 100
    assert res.can_fd_channels == 50
    assert res.someip_channels == 50
    assert res.effective_throughput_gbps >= 5.00
    assert res.packet_loss_rate_pct == 0.0  # Zero-Drop
    assert res.avg_latency_us <= 15.0       # <= 15 microseconds
    assert res.hpc_status == "5GBPS_LINE_RATE_VERIFIED"
    assert len(res.security_hash) == 64     # SHA-256


def test_hpc_sqlite_persistence():
    """Validates immutable SQLite persistence of benchmark runs."""
    engine = HPCSwarmThroughputEngine(vin="TEST-VIN-HPC-02", db_path=":memory:")

    engine.run_hpc_swarm_benchmark(num_channels=100, burst_duration_sec=0.05)
    engine.run_hpc_swarm_benchmark(num_channels=60, burst_duration_sec=0.05)

    records = engine.get_recent_benchmarks(limit=10)
    assert len(records) == 2
    assert records[0]["throughput_gbps"] >= 5.00
    assert records[0]["loss_rate_pct"] == 0.0
    assert len(records[0]["security_sha256"]) == 64


def test_hpc_listener_callback():
    """Validates real-time listener callback invocation upon benchmark completion."""
    engine = HPCSwarmThroughputEngine(vin="TEST-VIN-HPC-03")
    captured = []

    engine.register_benchmark_listener(lambda r: captured.append(r))
    engine.run_hpc_swarm_benchmark(num_channels=100, burst_duration_sec=0.05)

    assert len(captured) == 1
    assert captured[0].total_channels == 100
    assert captured[0].effective_throughput_gbps >= 5.00


def test_vehicle_mcp_hpc_tools():
    """Validates that VehicleMCPServer can run HPC throughput drills via MCP JSON-RPC."""
    server = VehicleMCPServer(vin="TEST-MCP-HPC")

    # 1. Tools listed
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    assert "run_hpc_swarm_throughput_drill" in tool_names
    assert "get_hpc_swarm_benchmarks" in tool_names

    # 2. Call run_hpc_swarm_throughput_drill
    call_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "run_hpc_swarm_throughput_drill",
            "arguments": {"num_channels": 100, "burst_duration_sec": 0.1},
        },
    })
    assert not call_res["result"]["isError"]
    content = json.loads(call_res["result"]["content"][0]["text"])
    assert content["status"] == "BENCHMARK_SUCCESS"
    assert content["total_channels"] == 100
    assert content["effective_throughput_gbps"] >= 5.00
    assert content["packet_loss_rate_pct"] == 0.0
    assert content["hpc_status"] == "5GBPS_LINE_RATE_VERIFIED"
    assert len(content["security_sha256"]) == 64

    # 3. Call get_hpc_swarm_benchmarks
    list_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_hpc_swarm_benchmarks",
            "arguments": {"limit": 5},
        },
    })
    assert not list_res["result"]["isError"]
    list_content = json.loads(list_res["result"]["content"][0]["text"])
    assert list_content["total_benchmarks"] >= 1
    assert list_content["benchmark_records"][0]["throughput_gbps"] >= 5.00
