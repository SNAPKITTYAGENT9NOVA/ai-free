# -*- coding: utf-8 -*-
"""
Tests for SOA Gateway Twin & Digital Twin Integration with AsyncMultiNodeCluster.
"""

from __future__ import annotations

import struct
from typing import Any, List

import pytest

from multi_node_cluster import AsyncMultiNodeCluster
from soa_gateway_twin import (
    SOMEIP_HEADER_FORMAT,
    SOAGateway,
    SOMEIPMessage,
)


class MockCANBusWithRecv:
    """In-memory mock bus queue supporting send() and recv() for asyncio cluster."""

    def __init__(self) -> None:
        self.queue: List[Any] = []
        self.sent_messages: List[Any] = []

    def send(self, msg: Any) -> None:
        self.sent_messages.append(msg)
        self.queue.append(msg)

    def recv(self, timeout: float = 0.01) -> Any:
        if self.queue:
            return self.queue.pop(0)
        return None


def test_soa_gateway_facade_pack_someip_event() -> None:
    gateway = SOAGateway(enable_udp_broadcast=False)
    payload = struct.pack("!HB", 6000, 0)
    pkt = gateway.pack_someip_event(0x1001, 0x8001, payload)

    assert len(pkt) == 16 + len(payload)
    msg_id, length, req_id, p_ver, if_ver, m_type, ret_code = struct.unpack(
        SOMEIP_HEADER_FORMAT, pkt[:16]
    )
    assert msg_id == 0x10018001
    assert length == 8 + len(payload)
    assert req_id == 0
    assert p_ver == 1
    assert if_ver == 1
    assert m_type == 0x02  # NOTIFICATION
    assert ret_code == 0x00  # E_OK


def test_soa_gateway_ingest_raw_powertrain_can() -> None:
    gateway = SOAGateway(enable_udp_broadcast=False)

    # Frame with status=0, RPM=8000 (0x1F40)
    data = bytes([0x01, 0x00, 0x1F, 0x40, 0x00, 0x00, 0x00, 0x55])
    msg = gateway.ingest_can_frame(0x280, data)

    assert msg is not None
    assert gateway.twin.motor_rpm == 8000.0
    assert not gateway.twin.motor_degraded
    assert gateway.twin.last_updated > 0

    # Frame with status=1 (degraded)
    data_deg = bytes([0x02, 0x01, 0x13, 0x88, 0x00, 0x00, 0x00, 0x55])  # 5000 RPM
    msg_deg = gateway.ingest_can_frame(0x280, data_deg)
    assert msg_deg is not None
    assert gateway.twin.motor_rpm == 5000.0
    assert gateway.twin.motor_degraded


def test_soa_gateway_ingest_raw_telemetry_can() -> None:
    gateway = SOAGateway(enable_udp_broadcast=False)

    # Voltage = 1260 (12.6V -> 12600 mV), Temp = 45°C
    v_val = 1260
    data = bytes([0x01, (v_val >> 8) & 0xFF, v_val & 0xFF, 45, 0x00, 0x00, 0x00, 0x99])
    msg = gateway.ingest_can_frame(0x380, data)

    assert msg is not None
    assert gateway.twin.battery_voltage_mv == 12600
    assert gateway.twin.temp_celsius == 45.0
    assert gateway.twin.last_updated > 0


def test_soa_gateway_print_twin_telemetry(capsys: Any) -> None:
    gateway = SOAGateway(enable_udp_broadcast=False)
    gateway.twin.motor_rpm = 7500.0
    gateway.twin.motor_degraded = False
    gateway.twin.battery_voltage_mv = 12400
    gateway.twin.temp_celsius = 42.0

    gateway.print_twin_telemetry()
    captured = capsys.readouterr()
    assert "7500 RPM" in captured.out
    assert "12.40 V" in captured.out
    assert "42°C" in captured.out


@pytest.mark.asyncio
async def test_async_multi_node_cluster_integrated_with_soa_gateway() -> None:
    bus = MockCANBusWithRecv()
    gateway = SOAGateway(enable_udp_broadcast=False)
    cluster = AsyncMultiNodeCluster(bus=bus, soa_gateway=gateway)

    captured_events: List[SOMEIPMessage] = []
    gateway.register_subscriber(lambda m: captured_events.append(m))

    res = await cluster.run_cluster(duration_sec=0.15)

    assert res["gw_frames"] >= 6
    assert res["act_frames"] >= 6
    assert res["telem_frames"] >= 3
    assert res["soa_translated_events"] > 0
    assert len(captured_events) > 0

    # Ensure digital twin is synchronized with real cluster values
    assert gateway.twin.motor_rpm == 8000.0
    assert gateway.twin.battery_voltage_mv == 12600
    assert gateway.twin.temp_celsius == 45.0
