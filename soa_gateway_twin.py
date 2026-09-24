# -*- coding: utf-8 -*-
"""
SOA Gateway Twin (服務導向架構網關與數位孿生) - Signal-to-Service Engine
Conforms to AUTOSAR SOME/IP Protocol Specification (Ethernet UDP / TCP).

Key Capabilities:
1. Signal-to-Service Translation:
   - Ingests CAN / CAN-FD raw data frames (0x280 Powertrain, 0x380 Sensor).
   - Unpacks E2E protected payload and converts signals into structured service attributes.
   - Encapsulates into AUTOSAR-compliant SOME/IP Notification packets.
2. SOME/IP Event Publishing:
   - Event 0x8001: Actuator speed, torque, limit, and status notification.
   - Event 0x8002: Battery voltage, coolant/sensor temperature, and pressure notification.
   - Standard 16-byte SOME/IP header with UDP transmission (Port 30490) & subscriber callbacks.
3. Digital Twin Synchronization:
   - Real-time in-memory digital twin representation of the physical vehicle state.
   - Thread-safe snapshots and telemetry queries for cloud/edge AI consumers.
"""

from __future__ import annotations

import enum
import socket
import struct
import sys
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from can_l0_l1_matrix import (
    CANFrame,
    E2EFrameCodec,
    CAN_ID_POWERTRAIN_ACT,
    CAN_ID_SENSOR_ACQ,
)
from digital_twin_state import (
    DigitalTwinMirrorEngine,
    DigitalTwinState,
)


# ============================================================================
# 1. AUTOSAR SOME/IP Protocol Definitions
# ============================================================================

DEFAULT_SOMEIP_PORT = 30490
DEFAULT_SERVICE_ID_VEHICLE = 0x1234

# Event IDs (Bit 15 is 1 for Events according to SOME/IP spec)
EVENT_ID_ACTUATOR_STATUS = 0x8001  # Event 0x8001: 致動轉速與狀態
EVENT_ID_SENSOR_TELEMETRY = 0x8002 # Event 0x8002: 電壓與溫度


class SOMEIPMessageType(enum.IntEnum):
    REQUEST = 0x00
    REQUEST_NO_RETURN = 0x01
    NOTIFICATION = 0x02          # Asynchronous Event Notification
    RESPONSE = 0x80
    ERROR = 0x81
    TP_REQUEST = 0x20
    TP_NOTIFICATION = 0x22


class SOMEIPReturnCode(enum.IntEnum):
    E_OK = 0x00
    E_NOT_OK = 0x01
    E_UNKNOWN_SERVICE = 0x02
    E_UNKNOWN_METHOD = 0x03
    E_NOT_READY = 0x04
    E_NOT_REACHABLE = 0x05
    E_TIMEOUT = 0x06
    E_WRONG_PROTOCOL_VERSION = 0x07
    E_WRONG_INTERFACE_VERSION = 0x08
    E_MALFORMED_MESSAGE = 0x09
    E_WRONG_MESSAGE_TYPE = 0x0A


@dataclass
class SOMEIPHeader:
    """
    AUTOSAR SOME/IP 16-byte standard message header.
    Format (Big-Endian '>'):
      - Message ID: Service ID (16-bit) + Method/Event ID (16-bit)  [4 Bytes]
      - Length: Length of payload + 8 bytes (covers Request ID to End) [4 Bytes]
      - Request ID: Client ID (16-bit) + Session ID (16-bit)         [4 Bytes]
      - Protocol Version (8-bit)                                      [1 Byte]
      - Interface Version (8-bit)                                     [1 Byte]
      - Message Type (8-bit)                                          [1 Byte]
      - Return Code (8-bit)                                           [1 Byte]
    """
    service_id: int
    event_or_method_id: int
    length: int
    client_id: int = 0x0001
    session_id: int = 0x0001
    protocol_version: int = 0x01
    interface_version: int = 0x01
    message_type: SOMEIPMessageType = SOMEIPMessageType.NOTIFICATION
    return_code: SOMEIPReturnCode = SOMEIPReturnCode.E_OK

    def pack(self) -> bytes:
        message_id = ((self.service_id & 0xFFFF) << 16) | (self.event_or_method_id & 0xFFFF)
        request_id = ((self.client_id & 0xFFFF) << 16) | (self.session_id & 0xFFFF)
        return struct.pack(
            ">IIIBBBB",
            message_id,
            self.length,
            request_id,
            self.protocol_version,
            self.interface_version,
            int(self.message_type),
            int(self.return_code),
        )

    @classmethod
    def unpack(cls, buffer: bytes) -> Tuple["SOMEIPHeader", bytes]:
        if len(buffer) < 16:
            raise ValueError(f"SOME/IP buffer too short ({len(buffer)} < 16 bytes)")
        header_data = buffer[:16]
        payload = buffer[16:]

        message_id, length, request_id, proto_ver, iface_ver, msg_type, ret_code = struct.unpack(
            ">IIIBBBB", header_data
        )

        service_id = (message_id >> 16) & 0xFFFF
        event_or_method_id = message_id & 0xFFFF
        client_id = (request_id >> 16) & 0xFFFF
        session_id = request_id & 0xFFFF

        header = cls(
            service_id=service_id,
            event_or_method_id=event_or_method_id,
            length=length,
            client_id=client_id,
            session_id=session_id,
            protocol_version=proto_ver,
            interface_version=iface_ver,
            message_type=SOMEIPMessageType(msg_type),
            return_code=SOMEIPReturnCode(ret_code),
        )
        return header, payload


@dataclass
class SOMEIPMessage:
    """Full SOME/IP Message container."""
    header: SOMEIPHeader
    payload: bytes

    def serialize(self) -> bytes:
        # Length in SOME/IP header includes Request ID (4), Interface Version/Proto/Type/Code (4) + Payload
        self.header.length = len(self.payload) + 8
        return self.header.pack() + self.payload

    @classmethod
    def parse(cls, raw_bytes: bytes) -> "SOMEIPMessage":
        header, payload = SOMEIPHeader.unpack(raw_bytes)
        return cls(header=header, payload=payload)


# ============================================================================
# 2. Digital Twin State Models
# ============================================================================

@dataclass
class PowertrainTwinState:
    """Digital Twin view of Powertrain Actuator (CAN ID 0x280)."""
    speed_rpm: float = 0.0
    torque_nm: float = 0.0
    torque_limit_pct: float = 100.0
    alive_counter: int = 0
    status_flags: int = 0
    last_update_ts: float = 0.0


@dataclass
class SensorTelemetryTwinState:
    """Digital Twin view of Vehicle Sensors (CAN ID 0x380)."""
    battery_voltage_v: float = 0.0
    temperature_c: float = 0.0
    pressure_kpa: float = 0.0
    alive_counter: int = 0
    status_flags: int = 0
    last_update_ts: float = 0.0


@dataclass
class VehicleDigitalTwinSnapshot:
    powertrain: PowertrainTwinState
    telemetry: SensorTelemetryTwinState
    total_translated_events: int
    gateway_uptime_sec: float
    timestamp: float = field(default_factory=time.time)


# ============================================================================
# 3. Signal-to-Service Gateway & Digital Twin Engine
# ============================================================================

class SOAGatewayTwin:
    """
    Service-Oriented Architecture Gateway Twin.
    - Bridges Physical CAN L0/L1 signals to Ethernet SOME/IP UDP services.
    - Translates 0x280 -> Event 0x8001 (Speed & Torque & Status)
    - Translates 0x380 -> Event 0x8002 (Voltage & Temperature & Pressure)
    - Publishes over UDP Ethernet socket and dispatches to registered subscribers.
    - Maintains synchronized Digital Twin state.
    """

    def __init__(
        self,
        service_id: int = DEFAULT_SERVICE_ID_VEHICLE,
        udp_host: str = "127.0.0.1",
        udp_port: int = DEFAULT_SOMEIP_PORT,
        enable_udp_broadcast: bool = False,
    ):
        self.service_id = service_id
        self.udp_host = udp_host
        self.udp_port = udp_port
        self.enable_udp_broadcast = enable_udp_broadcast

        # Codecs for CAN frames
        self.actuator_codec = E2EFrameCodec(data_id=0x28)
        self.sensor_codec = E2EFrameCodec(data_id=0x38)

        # Monotonic SOME/IP session counters per event
        self._session_counters: Dict[int, int] = {
            EVENT_ID_ACTUATOR_STATUS: 1,
            EVENT_ID_SENSOR_TELEMETRY: 1,
        }

        # Digital Twin State
        self.digital_twin_engine = DigitalTwinMirrorEngine(vin="PHANTOM-GRID-2026")
        self.twin_powertrain = PowertrainTwinState()
        self.twin_telemetry = SensorTelemetryTwinState()
        self.start_time = time.time()
        self.total_translated_events = 0

        # Concurrency & Event subscribers
        self._lock = threading.Lock()
        self._subscribers: List[Callable[[SOMEIPMessage], None]] = []

        # UDP Socket for Ethernet broadcast
        self._sock: Optional[socket.socket] = None
        if self.enable_udp_broadcast:
            try:
                self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            except Exception as e:
                self._sock = None

    def register_subscriber(self, callback: Callable[[SOMEIPMessage], None]) -> None:
        """Subscribes an observer callback to all emitted SOME/IP messages."""
        with self._lock:
            self._subscribers.append(callback)

    def _next_session_id(self, event_id: int) -> int:
        cur = self._session_counters.get(event_id, 1)
        self._session_counters[event_id] = (cur + 1) & 0xFFFF
        return cur

    # ------------------------------------------------------------------------
    # Signal-to-Service Translators
    # ------------------------------------------------------------------------

    def translate_powertrain_signal(self, frame: CANFrame, now: Optional[float] = None) -> Optional[SOMEIPMessage]:
        """
        Translates CAN 0x280 frame into SOME/IP Event 0x8001 (Actuator Speed, Torque, Status).
        CAN Payload: [Torque: int16 (2B)] + [TorqueLimitPct: uint8 (1B)]
        Calculates estimated motor RPM based on torque/gear dynamic model.
        """
        if now is None:
            now = time.time()

        valid, alive_cnt, payload, err = self.actuator_codec.decode(frame)
        if not valid or len(payload) < 3:
            return None

        # Unpack CAN signals
        actual_torque_nm, torque_limit_pct = struct.unpack(">hB", payload[:3])
        # Estimated speed in rpm: linear drivetrain model (e.g. 24.5 rpm/Nm dynamic response)
        speed_rpm = float(max(0.0, actual_torque_nm * 24.5))

        # Update Digital Twin
        with self._lock:
            self.twin_powertrain.speed_rpm = speed_rpm
            self.twin_powertrain.torque_nm = float(actual_torque_nm)
            self.twin_powertrain.torque_limit_pct = float(torque_limit_pct)
            self.twin_powertrain.alive_counter = alive_cnt
            self.twin_powertrain.status_flags = 0x01 if torque_limit_pct > 50 else 0x02  # 0x01: Optimal, 0x02: Degraded
            self.twin_powertrain.last_update_ts = now
            self.total_translated_events += 1

        self.digital_twin_engine.sync_powertrain_telemetry(
            actual_torque_nm=actual_torque_nm,
            torque_limit_pct=torque_limit_pct,
            alive_counter=alive_cnt,
            now=now,
        )

        # Serialize SOME/IP Event 0x8001 Payload:
        # Format (Big-Endian):
        # [SpeedRPM: float32 (4B)] + [TorqueNM: float32 (4B)] + [LimitPct: float32 (4B)] + [AliveCnt: uint8] + [Status: uint8]
        someip_payload = struct.pack(
            ">fffBB",
            float(speed_rpm),
            float(actual_torque_nm),
            float(torque_limit_pct),
            alive_cnt & 0xFF,
            self.twin_powertrain.status_flags & 0xFF,
        )

        header = SOMEIPHeader(
            service_id=self.service_id,
            event_or_method_id=EVENT_ID_ACTUATOR_STATUS,
            length=len(someip_payload) + 8,
            client_id=0x0001,
            session_id=self._next_session_id(EVENT_ID_ACTUATOR_STATUS),
            message_type=SOMEIPMessageType.NOTIFICATION,
            return_code=SOMEIPReturnCode.E_OK,
        )

        msg = SOMEIPMessage(header=header, payload=someip_payload)
        self._publish(msg)
        return msg

    def translate_sensor_signal(self, frame: CANFrame, now: Optional[float] = None) -> Optional[SOMEIPMessage]:
        """
        Translates CAN 0x380 frame into SOME/IP Event 0x8002 (Voltage, Temperature, Pressure).
        CAN Payload: [TempRaw: uint16 (temp_c * 10)] + [PresRaw: uint16 (kPa)]
        Synthesizes high voltage bus battery telemetry (e.g. 398.5V nominal).
        """
        if now is None:
            now = time.time()

        valid, alive_cnt, payload, err = self.sensor_codec.decode(frame)
        if not valid or len(payload) < 4:
            return None

        # Unpack CAN signals
        temp_raw, pres_raw = struct.unpack(">HH", payload[:4])
        temperature_c = temp_raw / 10.0
        pressure_kpa = float(pres_raw)
        battery_voltage_v = 398.5 - (temperature_c * 0.05)  # Realistic temperature-voltage droop curve

        # Update Digital Twin
        with self._lock:
            self.twin_telemetry.battery_voltage_v = battery_voltage_v
            self.twin_telemetry.temperature_c = temperature_c
            self.twin_telemetry.pressure_kpa = pressure_kpa
            self.twin_telemetry.alive_counter = alive_cnt
            self.twin_telemetry.status_flags = 0x01 if temperature_c < 90.0 else 0x04  # 0x04: Thermal Warning
            self.twin_telemetry.last_update_ts = now
            self.total_translated_events += 1

        self.digital_twin_engine.sync_sensor_telemetry(
            temperature_c=temperature_c,
            pressure_kpa=pressure_kpa,
            alive_counter=alive_cnt,
            now=now,
        )

        # Serialize SOME/IP Event 0x8002 Payload:
        # Format (Big-Endian):
        # [VoltageV: float32 (4B)] + [TempC: float32 (4B)] + [PressureKPa: float32 (4B)] + [AliveCnt: uint8] + [Status: uint8]
        someip_payload = struct.pack(
            ">fffBB",
            float(battery_voltage_v),
            float(temperature_c),
            float(pressure_kpa),
            alive_cnt & 0xFF,
            self.twin_telemetry.status_flags & 0xFF,
        )

        header = SOMEIPHeader(
            service_id=self.service_id,
            event_or_method_id=EVENT_ID_SENSOR_TELEMETRY,
            length=len(someip_payload) + 8,
            client_id=0x0001,
            session_id=self._next_session_id(EVENT_ID_SENSOR_TELEMETRY),
            message_type=SOMEIPMessageType.NOTIFICATION,
            return_code=SOMEIPReturnCode.E_OK,
        )

        msg = SOMEIPMessage(header=header, payload=someip_payload)
        self._publish(msg)
        return msg

    def ingest_can_frame(self, frame: CANFrame, now: Optional[float] = None) -> Optional[SOMEIPMessage]:
        """Unified entry point for CAN frame translation dispatch."""
        if frame.can_id == CAN_ID_POWERTRAIN_ACT:
            return self.translate_powertrain_signal(frame, now=now)
        elif frame.can_id == CAN_ID_SENSOR_ACQ:
            return self.translate_sensor_signal(frame, now=now)
        return None

    # ------------------------------------------------------------------------
    # Event Publishing & Ethernet UDP Broadcaster
    # ------------------------------------------------------------------------

    def _publish(self, msg: SOMEIPMessage) -> None:
        """Dispatches SOME/IP message to subscribers and UDP socket."""
        raw_packet = msg.serialize()

        # Send over UDP Ethernet
        if self._sock and self.enable_udp_broadcast:
            try:
                self._sock.sendto(raw_packet, (self.udp_host, self.udp_port))
            except Exception:
                pass

        # In-memory observer dispatch
        for callback in self._subscribers:
            try:
                callback(msg)
            except Exception:
                pass

    def get_twin_snapshot(self) -> VehicleDigitalTwinSnapshot:
        """Returns a consistent, thread-safe snapshot of the vehicle digital twin."""
        with self._lock:
            pt = PowertrainTwinState(
                speed_rpm=self.twin_powertrain.speed_rpm,
                torque_nm=self.twin_powertrain.torque_nm,
                torque_limit_pct=self.twin_powertrain.torque_limit_pct,
                alive_counter=self.twin_powertrain.alive_counter,
                status_flags=self.twin_powertrain.status_flags,
                last_update_ts=self.twin_powertrain.last_update_ts,
            )
            tl = SensorTelemetryTwinState(
                battery_voltage_v=self.twin_telemetry.battery_voltage_v,
                temperature_c=self.twin_telemetry.temperature_c,
                pressure_kpa=self.twin_telemetry.pressure_kpa,
                alive_counter=self.twin_telemetry.alive_counter,
                status_flags=self.twin_telemetry.status_flags,
                last_update_ts=self.twin_telemetry.last_update_ts,
            )
            return VehicleDigitalTwinSnapshot(
                powertrain=pt,
                telemetry=tl,
                total_translated_events=self.total_translated_events,
                gateway_uptime_sec=time.time() - self.start_time,
            )

    def get_digital_twin_state(self) -> DigitalTwinState:
        """Returns the in-memory DigitalTwinState model."""
        return self.digital_twin_engine.get_snapshot()

    def close(self) -> None:
        """Closes networking resources."""
        if self._sock:
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None


# ============================================================================
# 4. Standalone CLI & Signal-to-Service Demonstration
# ============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("🌐 [PHANTOM GRID] SOA Gateway Twin - Signal-to-Service Engine")
    print("   AUTOSAR SOME/IP UDP Ethernet Event Publisher (Port 30490)")
    print("=" * 70)

    gateway = SOAGatewayTwin(enable_udp_broadcast=False)
    captured_messages: List[SOMEIPMessage] = []
    gateway.register_subscriber(lambda m: captured_messages.append(m))

    # 1. Simulate CAN ID 0x280 (Powertrain Actuator)
    act_codec = E2EFrameCodec(data_id=0x28)
    can_act_payload = struct.pack(">hB", 140, 100)  # 140 Nm torque, 100% limit
    can_act_frame = act_codec.encode(can_id=CAN_ID_POWERTRAIN_ACT, payload=can_act_payload)

    msg_act = gateway.ingest_can_frame(can_act_frame)
    assert msg_act is not None
    print(f"\n[CAN 0x280 -> SOME/IP Event 0x8001 Translation]")
    print(f"   -> Service ID: 0x{msg_act.header.service_id:04X} | Event ID: 0x{msg_act.header.event_or_method_id:04X}")
    print(f"   -> Message Type: {msg_act.header.message_type.name} (0x{int(msg_act.header.message_type):02X})")
    print(f"   -> Total Packet Length: {len(msg_act.serialize())} Bytes")
    speed_rpm, torque_nm, limit_pct, alive_c, status_c = struct.unpack(">fffBB", msg_act.payload)
    print(f"   -> Payload Attributes: Speed={speed_rpm:.1f} RPM, Torque={torque_nm:.1f} Nm, Limit={limit_pct:.0f}%, Alive={alive_c}")

    # 2. Simulate CAN ID 0x380 (Sensor Acquisition)
    sns_codec = E2EFrameCodec(data_id=0x38)
    can_sns_payload = struct.pack(">HH", 650, 230)  # 65.0°C, 230 kPa
    can_sns_frame = sns_codec.encode(can_id=CAN_ID_SENSOR_ACQ, payload=can_sns_payload)

    msg_sns = gateway.ingest_can_frame(can_sns_frame)
    assert msg_sns is not None
    print(f"\n[CAN 0x380 -> SOME/IP Event 0x8002 Translation]")
    print(f"   -> Service ID: 0x{msg_sns.header.service_id:04X} | Event ID: 0x{msg_sns.header.event_or_method_id:04X}")
    print(f"   -> Message Type: {msg_sns.header.message_type.name} (0x{int(msg_sns.header.message_type):02X})")
    v_batt, temp_c, pres_kpa, alive_s, status_s = struct.unpack(">fffBB", msg_sns.payload)
    print(f"   -> Payload Attributes: Voltage={v_batt:.2f}V, Temp={temp_c:.1f}°C, Pressure={pres_kpa:.1f} kPa, Alive={alive_s}")

    # 3. Query Digital Twin State
    snapshot = gateway.get_twin_snapshot()
    print(f"\n[Digital Twin Real-Time State Synchronized]")
    print(f"   -> Powertrain: {snapshot.powertrain.speed_rpm:.1f} RPM | {snapshot.powertrain.torque_nm:.1f} Nm | Limit: {snapshot.powertrain.torque_limit_pct:.0f}%")
    print(f"   -> Telemetry: {snapshot.telemetry.battery_voltage_v:.2f} V | {snapshot.telemetry.temperature_c:.1f} °C | {snapshot.telemetry.pressure_kpa:.1f} kPa")
    print(f"   -> Total Translated Events: {snapshot.total_translated_events}")
    print("=" * 70)
