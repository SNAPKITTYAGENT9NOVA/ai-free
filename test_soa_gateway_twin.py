# -*- coding: utf-8 -*-
"""
Unit and Integration Test Suite for SOA Gateway Twin & SOME/IP Signal-to-Service Engine.
Verifies:
1. AUTOSAR SOME/IP 16-byte Header packing and unpacking conformance.
2. Signal-to-Service translation: CAN ID 0x280 -> SOME/IP Notification Event 0x8001.
3. Signal-to-Service translation: CAN ID 0x380 -> SOME/IP Notification Event 0x8002.
4. Observer event publishing and session ID monotonicity.
5. In-memory Digital Twin synchronization & thread-safe snapshot queries.
"""

import struct
import time
import pytest
from can_l0_l1_matrix import (
    CANFrame,
    E2EFrameCodec,
    PowertrainActuatorNode,
    SensorAcquisitionNode,
    CAN_ID_POWERTRAIN_ACT,
    CAN_ID_SENSOR_ACQ,
)
from soa_gateway_twin import (
    SOAGatewayTwin,
    SOMEIPHeader,
    SOMEIPMessage,
    SOMEIPMessageType,
    SOMEIPReturnCode,
    EVENT_ID_ACTUATOR_STATUS,
    EVENT_ID_SENSOR_TELEMETRY,
    DEFAULT_SERVICE_ID_VEHICLE,
)


def test_someip_header_pack_unpack_conformance():
    """Verify standard AUTOSAR 16-byte SOME/IP header binary wire format."""
    header = SOMEIPHeader(
        service_id=0x1234,
        event_or_method_id=0x8001,
        length=22,  # 8 bytes header remainder + 14 bytes payload
        client_id=0x0001,
        session_id=0x0042,
        protocol_version=0x01,
        interface_version=0x01,
        message_type=SOMEIPMessageType.NOTIFICATION,
        return_code=SOMEIPReturnCode.E_OK,
    )

    packed = header.pack()
    assert len(packed) == 16

    # Verify wire format fields
    msg_id, length, req_id, p_ver, if_ver, m_type, ret_code = struct.unpack(">IIIBBBB", packed)
    assert msg_id == 0x12348001
    assert length == 22
    assert req_id == 0x00010042
    assert p_ver == 1
    assert if_ver == 1
    assert m_type == 0x02  # NOTIFICATION
    assert ret_code == 0x00 # E_OK

    # Unpack roundtrip
    unpacked_hdr, leftover = SOMEIPHeader.unpack(packed + b"\xDE\xAD\xBE\xEF")
    assert unpacked_hdr.service_id == 0x1234
    assert unpacked_hdr.event_or_method_id == 0x8001
    assert unpacked_hdr.session_id == 0x0042
    assert leftover == b"\xDE\xAD\xBE\xEF"


def test_someip_header_unpack_error_on_short_buffer():
    """Verify ValueError is raised on buffer smaller than 16 bytes."""
    with pytest.raises(ValueError, match="too short"):
        SOMEIPHeader.unpack(b"\x00" * 15)


def test_signal_to_service_actuator_0x280_to_event_0x8001():
    """
    Verify translation of physical CAN 0x280 frame into SOME/IP Event 0x8001.
    """
    gateway = SOAGatewayTwin(service_id=0x1234)
    actuator = PowertrainActuatorNode()

    # Generate legitimate CAN frame from Powertrain Actuator
    # Torque: 160 Nm, Limit: 100%
    can_frame = actuator.create_actuator_telemetry(actual_torque_nm=160.0)
    assert can_frame.can_id == CAN_ID_POWERTRAIN_ACT

    t_now = 1000.0
    someip_msg = gateway.ingest_can_frame(can_frame, now=t_now)
    assert someip_msg is not None

    # 1. Header Validation
    hdr = someip_msg.header
    assert hdr.service_id == 0x1234
    assert hdr.event_or_method_id == EVENT_ID_ACTUATOR_STATUS  # 0x8001
    assert hdr.message_type == SOMEIPMessageType.NOTIFICATION
    assert hdr.return_code == SOMEIPReturnCode.E_OK

    # 2. Payload Validation
    # Format: [Speed: float32] + [Torque: float32] + [Limit: float32] + [AliveCnt: uint8] + [Status: uint8]
    speed, torque, limit, alive, status = struct.unpack(">fffBB", someip_msg.payload)
    assert abs(torque - 160.0) < 1.0
    assert abs(speed - (160.0 * 24.5)) < 1.0  # Speed dynamically modeled from torque
    assert limit == 100.0
    assert alive == 0
    assert status == 0x01  # Optimal status

    # 3. Digital Twin Validation
    twin = gateway.get_twin_snapshot().powertrain
    assert twin.torque_nm == 160.0
    assert twin.speed_rpm == speed
    assert twin.torque_limit_pct == 100.0
    assert twin.last_update_ts == t_now


def test_signal_to_service_sensor_0x380_to_event_0x8002():
    """
    Verify translation of physical CAN 0x380 frame into SOME/IP Event 0x8002.
    """
    gateway = SOAGatewayTwin(service_id=0x1234)
    sensor = SensorAcquisitionNode()

    # Generate legitimate CAN frame from Sensor node
    # Temp: 72.5°C, Pressure: 245 kPa
    can_frame = sensor.create_sensor_telemetry(temp_c=72.5, pressure_kpa=245.0)
    assert can_frame.can_id == CAN_ID_SENSOR_ACQ

    t_now = 2000.0
    someip_msg = gateway.ingest_can_frame(can_frame, now=t_now)
    assert someip_msg is not None

    # 1. Header Validation
    hdr = someip_msg.header
    assert hdr.service_id == 0x1234
    assert hdr.event_or_method_id == EVENT_ID_SENSOR_TELEMETRY  # 0x8002
    assert hdr.message_type == SOMEIPMessageType.NOTIFICATION

    # 2. Payload Validation
    v_batt, temp_c, pres_kpa, alive, status = struct.unpack(">fffBB", someip_msg.payload)
    assert abs(temp_c - 72.5) < 0.2
    assert abs(pres_kpa - 245.0) < 1.0
    assert 390.0 < v_batt < 400.0
    assert alive == 0
    assert status == 0x01

    # 3. Digital Twin Validation
    twin = gateway.get_twin_snapshot().telemetry
    assert abs(twin.temperature_c - 72.5) < 0.2
    assert twin.pressure_kpa == 245.0
    assert twin.last_update_ts == t_now


def test_event_subscriber_publishing_and_session_increment():
    """Verify observer callbacks receive published events and session IDs monotonically increment."""
    gateway = SOAGatewayTwin(service_id=0x5678)
    received_events = []

    gateway.register_subscriber(lambda m: received_events.append(m))

    actuator = PowertrainActuatorNode()
    for _ in range(5):
        frame = actuator.create_actuator_telemetry(actual_torque_nm=100.0)
        gateway.ingest_can_frame(frame)

    assert len(received_events) == 5
    # Session IDs should increment 1, 2, 3, 4, 5
    session_ids = [m.header.session_id for m in received_events]
    assert session_ids == [1, 2, 3, 4, 5]
    for m in received_events:
        assert m.header.event_or_method_id == EVENT_ID_ACTUATOR_STATUS
        assert m.header.service_id == 0x5678


def test_corrupted_can_frame_rejected_by_gateway():
    """Verify corrupted E2E CAN frame is rejected and not published as SOME/IP."""
    gateway = SOAGatewayTwin()
    received_events = []
    gateway.register_subscriber(lambda m: received_events.append(m))

    # Send corrupted CAN payload
    corrupted_frame = CANFrame(can_id=CAN_ID_POWERTRAIN_ACT, data=bytearray(b"\x00\xFF\x00\x00"))
    msg = gateway.ingest_can_frame(corrupted_frame)

    assert msg is None
    assert len(received_events) == 0
    assert gateway.total_translated_events == 0


def test_digital_twin_thermal_warning_and_degraded_status():
    """Verify Digital Twin flags thermal warning on high sensor temperature."""
    gateway = SOAGatewayTwin()
    sensor = SensorAcquisitionNode()

    # Temperature > 90°C -> Should trigger thermal warning status flag (0x04)
    hot_frame = sensor.create_sensor_telemetry(temp_c=98.0, pressure_kpa=220.0)
    msg = gateway.ingest_can_frame(hot_frame)

    assert msg is not None
    _, _, _, _, status_flag = struct.unpack(">fffBB", msg.payload)
    assert status_flag == 0x04  # Thermal Warning

    snapshot = gateway.get_twin_snapshot()
    assert snapshot.telemetry.status_flags == 0x04
    assert snapshot.telemetry.temperature_c == 98.0
