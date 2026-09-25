# -*- coding: utf-8 -*-
"""
End-to-End Closed-Loop Test Suite:
Multi-Node CAN Cluster -> SOA Gateway SOME/IP -> AutonomousHealer -> SQLite.
"""

from __future__ import annotations

import struct
from typing import Any, List

import pytest

from autonomous_healer import AutonomousHealer, HealingLevel
from multi_node_cluster import AsyncMultiNodeCluster
from soa_gateway_twin import SOAGateway


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


def test_healer_thermal_defense_tiers() -> None:
    gateway = SOAGateway(enable_udp_broadcast=False)
    healer = AutonomousHealer(bind_socket=False)

    # 1. Nominal state: 12.6V, 45°C
    pkt_norm = gateway.pack_someip_event(0x1002, 0x8002, struct.pack("!IB", 12600, 45))
    healer.process_incoming_event(pkt_norm)
    assert healer.power_limit_pct == 100
    assert not healer.cooling_boost_active

    # 2. Level 1 Over-temperature (78°C >= 75°C) -> 70% derating + cooling boost
    pkt_lvl1 = gateway.pack_someip_event(0x1002, 0x8002, struct.pack("!IB", 12600, 78))
    healer.process_incoming_event(pkt_lvl1)
    assert healer.power_limit_pct == 70
    assert healer.cooling_boost_active is True

    # 3. Level 2 Severe Heat (88°C >= 85°C) -> 50% emergency derating
    pkt_lvl2 = gateway.pack_someip_event(0x1002, 0x8002, struct.pack("!IB", 12600, 88))
    healer.process_incoming_event(pkt_lvl2)
    assert healer.power_limit_pct == 50
    assert healer.cooling_boost_active is True

    # 4. Thermal Recovery (< 60°C) -> 100% full power + cooling boost off
    pkt_recov = gateway.pack_someip_event(0x1002, 0x8002, struct.pack("!IB", 12600, 52))
    healer.process_incoming_event(pkt_recov)
    assert healer.power_limit_pct == 100
    assert healer.cooling_boost_active is False


def test_healer_low_voltage_defense_tiers() -> None:
    gateway = SOAGateway(enable_udp_broadcast=False)
    healer = AutonomousHealer(bind_socket=False)

    # 1. Level 1 Low Voltage (10.8V = 10800 mV < 11.2V)
    pkt_low = gateway.pack_someip_event(0x1002, 0x8002, struct.pack("!IB", 10800, 40))
    healer.process_incoming_event(pkt_low)
    assert healer.power_limit_pct == 70
    assert healer.cooling_boost_active is True

    # 2. Level 3 Undervoltage Safe Stop (9.5V = 9500 mV < 10.0V)
    pkt_crit = gateway.pack_someip_event(0x1002, 0x8002, struct.pack("!IB", 9500, 40))
    healer.process_incoming_event(pkt_crit)
    assert healer.power_limit_pct == 0
    assert healer.current_level == HealingLevel.LEVEL_3_EMERGENCY_STOP
    assert healer.cooling_boost_active is False


@pytest.mark.asyncio
async def test_full_multinode_to_soa_to_healer_closed_loop() -> None:
    bus = MockCANBusWithRecv()
    gateway = SOAGateway(enable_udp_broadcast=False)
    healer = AutonomousHealer(bind_socket=False)

    def _on_event(m: Any) -> None:
        healer.process_incoming_event(m.serialize())

    # Wire SOA Gateway SOME/IP output directly to AutonomousHealer
    gateway.register_subscriber(_on_event)

    cluster = AsyncMultiNodeCluster(bus=bus, soa_gateway=gateway)
    # Set telemetry node to broadcast over-temperature (88°C)
    cluster.telem.temp_c = 88

    res = await cluster.run_cluster(duration_sec=0.15)
    assert res["telem_frames"] >= 3
    assert res["soa_translated_events"] > 0

    # Verify healer detected SOME/IP event from cluster and engaged Level 2 emergency derating
    assert healer.power_limit_pct == 50
    assert healer.cooling_boost_active is True

    # Verify audit database records
    audits = healer.get_recent_audits(limit=5)
    assert len(audits) > 0
