# -*- coding: utf-8 -*-
"""
Tests for Axis 3: Multi-Node Cluster Integration & SOME/IP Signal-to-Service Gateway.
"""

from __future__ import annotations

import struct
from typing import List, Tuple

from multi_node_cluster import (
    MasterGatewayNode,
    MultiNodeClusterGateway,
    PowertrainActuatorNode,
    SensorAcquisitionNode,
    SomeIpHeader,
    SomeIpMessageType,
)


def test_someip_header_serialization_and_deserialization() -> None:
    payload = b"\x01\x02\x03\x04\x05"
    hdr = SomeIpHeader(
        service_id=0x1000,
        method_or_event_id=0x8001,
        length=8 + len(payload),
        client_id=0x0042,
        session_id=0x0007,
        protocol_version=1,
        interface_version=1,
        message_type=SomeIpMessageType.NOTIFICATION,
        return_code=0x00,
    )

    serialized = hdr.serialize(payload)
    assert len(serialized) == 16 + len(payload)

    parsed_hdr, parsed_payload = SomeIpHeader.deserialize(serialized)
    assert parsed_hdr.service_id == 0x1000
    assert parsed_hdr.method_or_event_id == 0x8001
    assert parsed_hdr.client_id == 0x0042
    assert parsed_hdr.session_id == 0x0007
    assert parsed_hdr.message_type == SomeIpMessageType.NOTIFICATION
    assert parsed_payload == payload


def test_three_node_e2e_frame_generation() -> None:
    master = MasterGatewayNode()
    actuator = PowertrainActuatorNode()
    sensor = SensorAcquisitionNode()

    f_master = master.step()
    f_actuator = actuator.step()
    f_sensor = sensor.step()

    assert len(f_master) == 8
    assert len(f_actuator) == 8
    assert len(f_sensor) == 8

    # Check Alive Counter increments monotonically
    assert (f_master[0] & 0x0F) == master.alive_counter
    assert (f_actuator[0] & 0x0F) == actuator.alive_counter
    assert (f_sensor[0] & 0x0F) == sensor.alive_counter


def test_signal_to_service_gateway_and_subscribers() -> None:
    gateway = MultiNodeClusterGateway()
    received_powertrain: list[tuple[int, int, int]] = []
    received_sensor: list[tuple[int, int]] = []

    def on_powertrain(header: SomeIpHeader, payload: bytes) -> None:
        rpm, torque, pwm = struct.unpack(">HHB", payload)
        received_powertrain.append((rpm, torque, pwm))

    def on_sensor(header: SomeIpHeader, payload: bytes) -> None:
        voltage, temp = struct.unpack(">HB", payload)
        received_sensor.append((voltage, temp))

    gateway.subscribe_event(MultiNodeClusterGateway.EVENT_POWERTRAIN, on_powertrain)
    gateway.subscribe_event(MultiNodeClusterGateway.EVENT_SENSOR, on_sensor)

    # Run cluster cycle
    cycle_res = gateway.run_cluster_cycle()
    assert cycle_res["master_frame_len"] == 8
    assert cycle_res["actuator_someip_len"] == 16 + 5  # 16 header + 5 payload
    assert cycle_res["sensor_someip_len"] == 16 + 3  # 16 header + 3 payload
    assert cycle_res["total_dispatched_events"] == 2

    # Verify subscriber callbacks triggered with accurate values
    assert len(received_powertrain) == 1
    assert received_powertrain[0][0] == 8000  # RPM
    assert received_powertrain[0][1] == 150  # Torque
    assert received_powertrain[0][2] == 100  # PWM

    assert len(received_sensor) == 1
    assert received_sensor[0][0] == 12500  # Voltage (mV)
    assert received_sensor[0][1] == 65  # Temp (°C)


def test_sdk_exports_cluster_and_bootloader() -> None:
    from phantom_grid import (
        CalibrationMemoryMap as SDKCalMap,
    )
    from phantom_grid import (
        MultiNodeClusterGateway as SDKGateway,
    )
    from phantom_grid import (
        PartitionSlot as SDKSlot,
    )
    from phantom_grid import (
        UdsBootloaderPipeline as SDKBootloader,
    )
    from phantom_grid import (
        XcpCalibrationEngine as SDKXcp,
    )

    assert SDKBootloader is not None
    assert SDKSlot.SLOT_A.value == "SLOT_A"
    assert SDKXcp is not None
    assert SDKCalMap is not None
    assert SDKGateway is not None


def test_uds_someip_event_routing() -> None:
    gateway = MultiNodeClusterGateway()
    dispatched_events: List[Tuple[SomeIpHeader, bytes]] = []

    def on_uds_event(header: SomeIpHeader, payload: bytes) -> None:
        dispatched_events.append((header, payload))

    gateway.subscribe_event(MultiNodeClusterGateway.EVENT_UDS_BOOTLOADER, on_uds_event)

    packet = gateway.route_uds_to_someip(
        session=0x02,
        bl_state=0x03,
        active_partition=0x00,
        block_seq=0x05,
        received_bytes=2048,
        total_expected_bytes=4096,
    )

    assert len(packet) == 16 + 13  # 16-byte header + 13-byte payload
    header, payload = SomeIpHeader.deserialize(packet)
    assert header.service_id == 0x1000
    assert header.method_or_event_id == 0x8003
    assert len(dispatched_events) == 1

    (
        session,
        bl_state,
        active_part,
        block_seq,
        rx_bytes,
        total_bytes,
        progress,
    ) = struct.unpack(">BBBBI I B", payload)

    assert session == 0x02
    assert bl_state == 0x03
    assert active_part == 0x00
    assert block_seq == 0x05
    assert rx_bytes == 2048
    assert total_bytes == 4096
    assert progress == 50


def test_fleet_nostr_broadcast_integration() -> None:
    gateway = MultiNodeClusterGateway()
    event = gateway.route_and_broadcast_safety_event(
        node_id="ACTUATOR_0x280",
        old_state="NORMAL",
        new_state="DEGRADED",
        details="E2E CRC Error limit exceeded",
    )

    assert event["kind"] == 30079
    assert len(event["id"]) == 64
    assert len(event["sig"]) == 128
    assert ["t", "EMERGENCY_ALARM"] in event["tags"]
    assert ["node", "ACTUATOR_0x280"] in event["tags"]
    assert len(gateway.dispatched_nostr_events) == 1
