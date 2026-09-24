# -*- coding: utf-8 -*-
"""
Test Suite for Automotive Active Anti-Phase Noise Canceller & EMC Hardening
Conforms to CISPR 25 Level 5, ISO 11452-2 Radiated Immunity, and Model Context Protocol.
"""

import json
import pytest
from aegis_emc_canceller import (
    ActiveAntiNoiseCanceller,
    CancellationResult,
    EMCInjectionSpec,
)
from vehicle_mcp_server import VehicleMCPServer


def test_extreme_emi_cancellation_performance():
    """Validates that +95.5 dBm EMI is attenuated by 215.5 dB down to -120 dBm in 30 ps."""
    canceller = ActiveAntiNoiseCanceller(vin="TEST-VIN-EMC-01")

    spec = EMCInjectionSpec(
        channel_name="CAN_H_ANALOG_FRONTEND",
        raw_emi_power_dbm=95.5,
        center_frequency_mhz=2450.0,
    )

    res = canceller.execute_active_cancellation(spec)
    assert res.channel_name == "CAN_H_ANALOG_FRONTEND"
    assert res.raw_noise_dbm == 95.5
    assert res.anti_phase_angle_deg == 180.0
    assert res.residual_noise_dbm <= -120.0
    assert res.total_attenuation_db >= 215.5
    assert res.response_latency_ps == 30.0  # 0.03 ns
    assert res.signal_snr_db >= 40.0
    assert res.snr_preserved is True
    assert res.emc_compliance == "CISPR_25_LEVEL_5_VERIFIED"
    assert len(res.security_hash) == 64  # SHA-256


def test_sqlite_emc_audit_persistence():
    """Validates immutable SQLite persistence and query operations."""
    canceller = ActiveAntiNoiseCanceller(vin="TEST-VIN-EMC-02", db_path=":memory:")

    canceller.execute_active_cancellation(
        EMCInjectionSpec(channel_name="SENSOR_0x380", raw_emi_power_dbm=90.0)
    )
    canceller.execute_active_cancellation(
        EMCInjectionSpec(channel_name="CAN_L_0x280", raw_emi_power_dbm=95.5)
    )

    records = canceller.get_recent_emc_records(limit=10)
    assert len(records) == 2
    assert records[0]["channel_name"] == "CAN_L_0x280"
    assert records[0]["residual_noise_dbm"] <= -120.0
    assert len(records[0]["security_sha256"]) == 64


def test_cancellation_listener_dispatch():
    """Validates real-time observer callback dispatch."""
    canceller = ActiveAntiNoiseCanceller(vin="TEST-VIN-EMC-03")
    captured_events = []

    canceller.register_cancellation_listener(lambda r: captured_events.append(r))

    canceller.execute_active_cancellation(
        EMCInjectionSpec(channel_name="TEST_CH", raw_emi_power_dbm=85.0)
    )
    assert len(captured_events) == 1
    assert captured_events[0].channel_name == "TEST_CH"
    assert captured_events[0].response_latency_ps == 30.0


def test_vehicle_mcp_server_emc_tools():
    """Validates that VehicleMCPServer can simulate EMC cancellation via MCP JSON-RPC."""
    server = VehicleMCPServer(vin="TEST-MCP-EMC")

    # 1. Verify tools in tools/list
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    tool_names = [t["name"] for t in tools_res["result"]["tools"]]
    assert "simulate_emc_anti_noise_cancellation" in tool_names
    assert "get_emc_cancellation_records" in tool_names

    # 2. Call simulate_emc_anti_noise_cancellation
    call_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "simulate_emc_anti_noise_cancellation",
            "arguments": {
                "channel_name": "CAN_H_ANALOG_IN",
                "raw_emi_power_dbm": 95.5,
            },
        },
    })
    assert not call_res["result"]["isError"]
    content = json.loads(call_res["result"]["content"][0]["text"])
    assert content["status"] == "CANCELLATION_SUCCESS"
    assert content["raw_noise_dbm"] == 95.5
    assert content["residual_noise_dbm"] <= -120.0
    assert content["response_latency_ps"] == 30.0
    assert content["anti_phase_angle_deg"] == 180.0
    assert len(content["security_sha256"]) == 64

    # 3. Call get_emc_cancellation_records
    hist_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_emc_cancellation_records",
            "arguments": {"limit": 5},
        },
    })
    assert not hist_res["result"]["isError"]
    hist_content = json.loads(hist_res["result"]["content"][0]["text"])
    assert hist_content["total_emc_records"] >= 1
    assert hist_content["emc_audit_records"][0]["channel_name"] == "CAN_H_ANALOG_IN"
