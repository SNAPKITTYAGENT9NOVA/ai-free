# -*- coding: utf-8 -*-
"""
PHANTOM GRID Core - Multi-Node Cluster Integration & SOME/IP Signal-to-Service Gateway
"""

from __future__ import annotations

import enum
import struct
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

from .e2e import (
    E2ERxState,
    Iso26262SafetyStateMachine,
    Iso26262State,
    build_e2e_frame,
    calculate_crc8_sae_j1850,
)


class SomeIpMessageType(enum.Enum):
    REQUEST = 0x00
    REQUEST_NO_RETURN = 0x01
    NOTIFICATION = 0x02
    RESPONSE = 0x80
    ERROR = 0x81


@dataclass
class SomeIpHeader:
    """Standard AUTOSAR SOME/IP 16-byte Header."""
    service_id: int
    method_or_event_id: int
    length: int
    client_id: int
    session_id: int
    protocol_version: int = 1
    interface_version: int = 1
    message_type: SomeIpMessageType = SomeIpMessageType.NOTIFICATION
    return_code: int = 0x00

    def serialize(self, payload: bytes) -> bytes:
        calc_length = 8 + len(payload)
        header_bytes = struct.pack(
            ">HHIIBBBB",
            self.service_id,
            self.method_or_event_id,
            calc_length,
            (self.client_id << 16) | (self.session_id & 0xFFFF),
            self.protocol_version,
            self.interface_version,
            self.message_type.value,
            self.return_code,
        )
        return header_bytes + payload

    @classmethod
    def deserialize(cls, data: bytes) -> Tuple[SomeIpHeader, bytes]:
        if len(data) < 16:
            raise ValueError(f"SOME/IP 報文長度不足 16 字節: {len(data)}")
        (
            svc_id,
            method_id,
            length,
            req_id,
            proto_ver,
            iface_ver,
            msg_type_val,
            ret_code,
        ) = struct.unpack(">HHIIBBBB", data[:16])

        header = cls(
            service_id=svc_id,
            method_or_event_id=method_id,
            length=length,
            client_id=(req_id >> 16) & 0xFFFF,
            session_id=req_id & 0xFFFF,
            protocol_version=proto_ver,
            interface_version=iface_ver,
            message_type=SomeIpMessageType(msg_type_val),
            return_code=ret_code,
        )
        payload = data[16 : 16 + (length - 8)]
        return header, payload


@dataclass
class MasterGatewayNode:
    can_id: int = 0x120
    cycle_time_ms: int = 10
    alive_counter: int = 0
    system_mode: int = 0x01
    power_limit_pct: float = 100.0

    def step(self) -> bytes:
        self.alive_counter = (self.alive_counter + 1) & 0x0F
        payload_6 = bytes([self.system_mode, int(self.power_limit_pct), 0x00, 0x00, 0x00, 0x00])
        return build_e2e_frame(payload_6, self.alive_counter)


@dataclass
class PowertrainActuatorNode:
    can_id: int = 0x280
    cycle_time_ms: int = 20
    alive_counter: int = 0
    motor_rpm: int = 8000
    torque_nm: int = 150
    pwm_duty_pct: float = 100.0
    state_machine: Iso26262SafetyStateMachine = field(default_factory=Iso26262SafetyStateMachine)

    def step(self) -> bytes:
        self.alive_counter = (self.alive_counter + 1) & 0x0F
        rpm_bytes = self.motor_rpm.to_bytes(2, "big")
        torque_bytes = self.torque_nm.to_bytes(2, "big")
        payload_6 = rpm_bytes + torque_bytes + bytes([int(self.pwm_duty_pct), 0x00])
        return build_e2e_frame(payload_6, self.alive_counter)


@dataclass
class SensorAcquisitionNode:
    can_id: int = 0x380
    cycle_time_ms: int = 50
    alive_counter: int = 0
    battery_mv: int = 12500
    temp_celsius: int = 65

    def step(self) -> bytes:
        self.alive_counter = (self.alive_counter + 1) & 0x0F
        volt_bytes = self.battery_mv.to_bytes(2, "big")
        payload_6 = volt_bytes + bytes([self.temp_celsius, 0x00, 0x00, 0x00])
        return build_e2e_frame(payload_6, self.alive_counter)


class MultiNodeClusterGateway:
    SERVICE_VEHICLE_DYNAMICS = 0x1000
    EVENT_POWERTRAIN = 0x8001
    EVENT_SENSOR = 0x8002

    def __init__(self) -> None:
        self.master_node = MasterGatewayNode()
        self.actuator_node = PowertrainActuatorNode()
        self.sensor_node = SensorAcquisitionNode()

        self.someip_session_counter = 0
        self.event_subscribers: Dict[int, List[Callable[[SomeIpHeader, bytes], None]]] = {
            self.EVENT_POWERTRAIN: [],
            self.EVENT_SENSOR: [],
        }
        self.dispatched_someip_frames: List[bytes] = []

    def subscribe_event(
        self, event_id: int, callback: Callable[[SomeIpHeader, bytes], None]
    ) -> None:
        if event_id in self.event_subscribers:
            self.event_subscribers[event_id].append(callback)

    def route_can_to_someip(self, can_id: int, frame_8bytes: bytes) -> Optional[bytes]:
        self.someip_session_counter = (self.someip_session_counter + 1) & 0xFFFF

        if can_id == 0x280:
            rpm = int.from_bytes(frame_8bytes[1:3], "big")
            torque = int.from_bytes(frame_8bytes[3:5], "big")
            pwm = frame_8bytes[5]
            someip_payload = struct.pack(">HHB", rpm, torque, pwm)
            header = SomeIpHeader(
                service_id=self.SERVICE_VEHICLE_DYNAMICS,
                method_or_event_id=self.EVENT_POWERTRAIN,
                length=8 + len(someip_payload),
                client_id=0x0001,
                session_id=self.someip_session_counter,
                message_type=SomeIpMessageType.NOTIFICATION,
            )
            packet = header.serialize(someip_payload)
            self._notify_subscribers(self.EVENT_POWERTRAIN, header, someip_payload)
            self.dispatched_someip_frames.append(packet)
            return packet

        elif can_id == 0x380:
            voltage = int.from_bytes(frame_8bytes[1:3], "big")
            temp = frame_8bytes[3]
            someip_payload = struct.pack(">HB", voltage, temp)
            header = SomeIpHeader(
                service_id=self.SERVICE_VEHICLE_DYNAMICS,
                method_or_event_id=self.EVENT_SENSOR,
                length=8 + len(someip_payload),
                client_id=0x0001,
                session_id=self.someip_session_counter,
                message_type=SomeIpMessageType.NOTIFICATION,
            )
            packet = header.serialize(someip_payload)
            self._notify_subscribers(self.EVENT_SENSOR, header, someip_payload)
            self.dispatched_someip_frames.append(packet)
            return packet

        return None

    def _notify_subscribers(self, event_id: int, header: SomeIpHeader, payload: bytes) -> None:
        for cb in self.event_subscribers.get(event_id, []):
            try:
                cb(header, payload)
            except Exception:
                pass

    def run_cluster_cycle(self) -> Dict[str, Any]:
        frame_master = self.master_node.step()
        frame_actuator = self.actuator_node.step()
        frame_sensor = self.sensor_node.step()

        someip_actuator = self.route_can_to_someip(0x280, frame_actuator)
        someip_sensor = self.route_can_to_someip(0x380, frame_sensor)

        return {
            "master_frame_len": len(frame_master),
            "actuator_someip_len": len(someip_actuator) if someip_actuator else 0,
            "sensor_someip_len": len(someip_sensor) if someip_sensor else 0,
            "total_dispatched_events": len(self.dispatched_someip_frames),
        }
