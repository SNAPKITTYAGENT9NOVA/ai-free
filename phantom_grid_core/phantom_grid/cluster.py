# -*- coding: utf-8 -*-
"""
Multi-Node Cluster Integration & SOME/IP Signal-to-Service Gateway
Axis 3: Distributed three-node EE architecture and SOME/IP UDP 30490 service routing.
Nodes:
1. Master Gateway ECU (0x120, 10ms)
2. Powertrain Actuator ECU (0x280, 20ms)
3. Sensor Acquisition Gateway (0x380, 50ms)
4. UDS Bootloader Flashing Telemetry (Service 0x1000, Event 0x8003)
5. Nostr Fleet Mesh V2V / V2C Broadcast Gateway (Kind 30078 / 30079)
6. Asynchronous Concurrent Coroutine Cluster (BaseNode, GatewayNode, ActuatorNode, TelemetryNode)
"""

from __future__ import annotations

import asyncio
import enum
import hashlib
import json
import struct
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

try:
    import can
    CAN_AVAILABLE = True
except ImportError:
    can = None  # type: ignore[assignment]
    CAN_AVAILABLE = False

from e2e_state_matrix import (
    Iso26262SafetyStateMachine,
    build_e2e_frame,
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

    service_id: int  # 16-bit
    method_or_event_id: int  # 16-bit (Bit 15=1 for Events)
    length: int  # 32-bit (8 + payload length)
    client_id: int  # 16-bit
    session_id: int  # 16-bit
    protocol_version: int = 1
    interface_version: int = 1
    message_type: SomeIpMessageType = SomeIpMessageType.NOTIFICATION
    return_code: int = 0x00  # 0x00 = E_OK

    def serialize(self, payload: bytes) -> bytes:
        """Serializes 16-byte SOME/IP header + payload."""
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
        """Deserializes SOME/IP frame into Header and Payload."""
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


# =============================================================================
# Distributed CAN Nodes (Synchronous Models)
# =============================================================================


@dataclass
class MasterGatewayNode:
    """Master Gateway ECU (CAN ID 0x120, 10ms cycle)."""

    can_id: int = 0x120
    cycle_time_ms: int = 10
    alive_counter: int = 0
    system_mode: int = 0x01  # 0x01=NORMAL, 0x02=DEGRADED, 0x03=SAFE_STOP
    power_limit_pct: float = 100.0

    def step(self) -> bytes:
        self.alive_counter = (self.alive_counter + 1) & 0x0F
        # 6-byte functional payload: [system_mode, power_limit, timestamp, reserved...]
        payload_6 = bytes([self.system_mode, int(self.power_limit_pct), 0x00, 0x00, 0x00, 0x00])
        return build_e2e_frame(payload_6, self.alive_counter)


@dataclass
class PowertrainActuatorNode:
    """Powertrain Actuator ECU (CAN ID 0x280, 20ms cycle)."""

    can_id: int = 0x280
    cycle_time_ms: int = 20
    alive_counter: int = 0
    motor_rpm: int = 8000
    torque_nm: int = 150
    pwm_duty_pct: float = 100.0
    state_machine: Iso26262SafetyStateMachine = field(default_factory=Iso26262SafetyStateMachine)

    def step(self) -> bytes:
        self.alive_counter = (self.alive_counter + 1) & 0x0F
        # 6-byte functional payload: [motor_rpm (2B), torque_nm (2B), pwm_duty, reserved]
        rpm_bytes = self.motor_rpm.to_bytes(2, "big")
        torque_bytes = self.torque_nm.to_bytes(2, "big")
        payload_6 = rpm_bytes + torque_bytes + bytes([int(self.pwm_duty_pct), 0x00])
        return build_e2e_frame(payload_6, self.alive_counter)


@dataclass
class SensorAcquisitionNode:
    """Sensor Acquisition Gateway (CAN ID 0x380, 50ms cycle)."""

    can_id: int = 0x380
    cycle_time_ms: int = 50
    alive_counter: int = 0
    battery_mv: int = 12500
    temp_celsius: int = 65

    def step(self) -> bytes:
        self.alive_counter = (self.alive_counter + 1) & 0x0F
        # 6-byte functional payload: [battery_mv (2B), temp_celsius (1B), reserved (3B)]
        volt_bytes = self.battery_mv.to_bytes(2, "big")
        payload_6 = volt_bytes + bytes([self.temp_celsius, 0x00, 0x00, 0x00])
        return build_e2e_frame(payload_6, self.alive_counter)


# =============================================================================
# Multi-Node Cluster Orchestrator & SOME/IP Gateway
# =============================================================================


class MultiNodeClusterGateway:
    """
    Coordinates 3-node CAN topology and routes signals into SOME/IP UDP 30490 services:
    - Service ID 0x1000: Vehicle Dynamics Service
      - Event ID 0x8001: Powertrain Actuator Telemetry (RPM, Torque, PWM)
      - Event ID 0x8002: Battery & Thermal Health Telemetry (Voltage, Temp)
      - Event ID 0x8003: UDS Bootloader Flashing Telemetry (Session, State, Progress)
    - Fleet Nostr Mesh Broadcast Gateway (Kind 30078 / 30079)
    """

    SERVICE_VEHICLE_DYNAMICS = 0x1000
    EVENT_POWERTRAIN = 0x8001
    EVENT_SENSOR = 0x8002
    EVENT_UDS_BOOTLOADER = 0x8003

    def __init__(self) -> None:
        self.master_node = MasterGatewayNode()
        self.actuator_node = PowertrainActuatorNode()
        self.sensor_node = SensorAcquisitionNode()

        self.someip_session_counter = 0
        self.event_subscribers: Dict[int, List[Callable[[SomeIpHeader, bytes], None]]] = {
            self.EVENT_POWERTRAIN: [],
            self.EVENT_SENSOR: [],
            self.EVENT_UDS_BOOTLOADER: [],
        }
        self.dispatched_someip_frames: List[bytes] = []
        self.dispatched_nostr_events: List[Dict[str, Any]] = []

    def subscribe_event(
        self, event_id: int, callback: Callable[[SomeIpHeader, bytes], None]
    ) -> None:
        """Subscribes to a SOME/IP event notification."""
        if event_id not in self.event_subscribers:
            self.event_subscribers[event_id] = []
        self.event_subscribers[event_id].append(callback)

    def route_can_to_someip(self, can_id: int, frame_8bytes: bytes) -> Optional[bytes]:
        """
        Signal-to-Service Funnel:
        Translates raw E2E CAN frames into standardized SOME/IP Event packets.
        """
        self.someip_session_counter = (self.someip_session_counter + 1) & 0xFFFF

        if can_id == 0x280:  # Powertrain Node
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

        elif can_id == 0x380:  # Sensor Node
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

    def route_uds_to_someip(
        self,
        session: int,
        bl_state: int,
        active_partition: int,
        block_seq: int,
        received_bytes: int,
        total_expected_bytes: int,
    ) -> bytes:
        """
        Translates low-level UDS Bootloader flashing state into SOME/IP Event 0x8003.
        Payload format:
        [session (1B), bl_state (1B), active_partition (1B), block_seq (1B),
         received_bytes (4B), total_expected_bytes (4B), progress_pct (1B)] = 13 Bytes
        """
        self.someip_session_counter = (self.someip_session_counter + 1) & 0xFFFF
        progress_pct = (
            min(100, int((received_bytes / total_expected_bytes) * 100))
            if total_expected_bytes > 0
            else 0
        )

        someip_payload = struct.pack(
            ">BBBBI I B",
            session & 0xFF,
            bl_state & 0xFF,
            active_partition & 0xFF,
            block_seq & 0xFF,
            received_bytes,
            total_expected_bytes,
            progress_pct,
        )

        header = SomeIpHeader(
            service_id=self.SERVICE_VEHICLE_DYNAMICS,
            method_or_event_id=self.EVENT_UDS_BOOTLOADER,
            length=8 + len(someip_payload),
            client_id=0x0001,
            session_id=self.someip_session_counter,
            message_type=SomeIpMessageType.NOTIFICATION,
        )
        packet = header.serialize(someip_payload)
        self._notify_subscribers(self.EVENT_UDS_BOOTLOADER, header, someip_payload)
        self.dispatched_someip_frames.append(packet)
        return packet

    def broadcast_to_fleet_nostr(
        self,
        event_kind: int,
        tags: List[List[str]],
        payload_dict: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Broadcasts vehicle telemetry / healing alert to decentralized fleet peers
        conforming to Nostr NIP-01 / NIP-78.
        """
        now = int(time.time())
        pubkey = "a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0"
        content_str = json.dumps(payload_dict, separators=(",", ":"), ensure_ascii=False)

        serialized = json.dumps(
            [0, pubkey, now, event_kind, tags, content_str],
            separators=(",", ":"),
            ensure_ascii=False,
        )
        event_id = hashlib.sha256(serialized.encode("utf-8")).hexdigest()
        # 128-hex simulated ECDSA/Schnorr signature
        sig = hashlib.sha256((event_id + "PHANTOM_KEY").encode("utf-8")).hexdigest() * 2

        event = {
            "id": event_id,
            "pubkey": pubkey,
            "created_at": now,
            "kind": event_kind,
            "tags": tags,
            "content": content_str,
            "sig": sig,
        }
        self.dispatched_nostr_events.append(event)
        return event

    def route_and_broadcast_safety_event(
        self,
        node_id: str,
        old_state: str,
        new_state: str,
        details: str = "",
    ) -> Dict[str, Any]:
        """Dispatches SOME/IP and simultaneously broadcasts Nostr Kind 30079 to fleet peers."""
        tags = [
            ["p", "fleet_broadcast"],
            ["t", "EMERGENCY_ALARM"],
            ["node", node_id],
        ]
        payload = {
            "node_id": node_id,
            "transition": f"{old_state} -> {new_state}",
            "details": details,
            "timestamp": time.time(),
        }
        return self.broadcast_to_fleet_nostr(
            event_kind=30079,
            tags=tags,
            payload_dict=payload,
        )

    def _notify_subscribers(self, event_id: int, header: SomeIpHeader, payload: bytes) -> None:
        for cb in self.event_subscribers.get(event_id, []):
            try:
                cb(header, payload)
            except Exception:
                pass

    def run_cluster_cycle(self) -> Dict[str, Any]:
        """Runs one full coordinated multi-node broadcast & gateway conversion cycle."""
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


# =============================================================================
# Asynchronous Concurrent Multi-Node Cluster Engine (Xiaomi Distributed Matrix)
# =============================================================================


class BaseNode:
    """Base class for asynchronous concurrent CAN cluster nodes."""

    def __init__(self, name: str, node_id: int, bus: Any) -> None:
        self.name = name
        self.node_id = node_id
        self.bus = bus
        self.alive_counter = 0

    def next_counter(self) -> int:
        c = self.alive_counter
        self.alive_counter = (self.alive_counter + 1) & 0x0F
        return c

    def _send_can_message(self, can_id: int, data: bytes) -> None:
        if not self.bus:
            return
        try:
            if CAN_AVAILABLE and can is not None and hasattr(can, "Message"):
                msg = can.Message(arbitration_id=can_id, data=data, is_extended_id=False)
            else:
                msg = type(
                    "CANMessage",
                    (),
                    {
                        "arbitration_id": can_id,
                        "data": data,
                        "dlc": len(data),
                        "timestamp": time.time(),
                        "is_extended_id": False,
                    },
                )()
            self.bus.send(msg)
        except Exception:
            pass


class GatewayNode(BaseNode):
    """主控節點：發送心跳 (0x080, 50ms) 與控制指令 (0x120, 10ms)。"""

    def __init__(
        self,
        name: str,
        node_id: int,
        bus: Any,
        target_power_pct: int = 75,
    ) -> None:
        super().__init__(name, node_id, bus)
        self.target_power_pct = target_power_pct
        self.is_running = True
        self.frames_sent = 0

    async def run(self, stop_event: Optional[asyncio.Event] = None) -> None:
        heartbeat_ticks = 0
        while self.is_running and (stop_event is None or not stop_event.is_set()):
            cnt = self.next_counter()
            # 構造控制幀: ID 0x120, Byte 0 為 Counter, Byte 1 為目標功率 (75%)
            data = bytes([cnt, self.target_power_pct, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAA])
            self._send_can_message(0x120, data)
            self.frames_sent += 1

            # 每 50ms (每 5 次 10ms 循環) 發送一次 0x080 心跳廣播幀
            heartbeat_ticks += 1
            if heartbeat_ticks >= 5:
                heartbeat_ticks = 0
                hb_data = bytes([cnt, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
                self._send_can_message(0x080, hb_data)

            await asyncio.sleep(0.01)  # 10ms 週期


class ActuatorNode(BaseNode):
    """致動節點：接收控制指令，定時上報轉速 (0x280, 10ms)，監聽心跳超時 (>50ms 降級)。"""

    def __init__(self, name: str, node_id: int, bus: Any) -> None:
        super().__init__(name, node_id, bus)
        self.last_cmd_time = time.time()
        self.degraded = False
        self.is_running = True
        self.rpm = 8000
        self.frames_sent = 0
        self.degraded_transitions = 0
        self.recovery_transitions = 0

    async def run(self, stop_event: Optional[asyncio.Event] = None) -> None:
        while self.is_running and (stop_event is None or not stop_event.is_set()):
            # 檢查主控指令超時 (超過 50ms 視為失聯，強制切入安全降級模式)
            if time.time() - self.last_cmd_time > 0.05:
                if not self.degraded:
                    self.degraded = True
                    self.degraded_transitions += 1

            # 回饋當前執行狀態
            cnt = self.next_counter()
            status_flag = 0x01 if self.degraded else 0x00
            # 0x1F40 = 8000 RPM
            data = bytes([cnt, status_flag, 0x1F, 0x40, 0x00, 0x00, 0x00, 0x55])
            self._send_can_message(0x280, data)
            self.frames_sent += 1
            await asyncio.sleep(0.01)  # 10ms 週期

    def on_message_received(self, msg: Any) -> None:
        arb_id = getattr(msg, "arbitration_id", 0)
        if arb_id == 0x120:
            self.last_cmd_time = time.time()
            if self.degraded:
                self.degraded = False
                self.recovery_transitions += 1


class TelemetryNode(BaseNode):
    """感測網關：上報電壓與溫度 (0x380, 20ms)。"""

    def __init__(
        self,
        name: str,
        node_id: int,
        bus: Any,
        battery_mv: int = 12600,
        temp_c: int = 45,
    ) -> None:
        super().__init__(name, node_id, bus)
        self.battery_mv = battery_mv
        self.temp_c = temp_c
        self.is_running = True
        self.frames_sent = 0

    async def run(self, stop_event: Optional[asyncio.Event] = None) -> None:
        while self.is_running and (stop_event is None or not stop_event.is_set()):
            cnt = self.next_counter()
            # 模擬 12.6V 電壓 (1260 -> 0x04EC) 與 45°C
            v_val = self.battery_mv // 10
            data = bytes(
                [
                    cnt,
                    (v_val >> 8) & 0xFF,
                    v_val & 0xFF,
                    self.temp_c & 0xFF,
                    0x00,
                    0x00,
                    0x00,
                    0x99,
                ]
            )
            self._send_can_message(0x380, data)
            self.frames_sent += 1
            await asyncio.sleep(0.02)  # 20ms 週期


class AsyncMultiNodeCluster:
    """
    非同步多節點集群控制器：
    管理 GatewayNode, ActuatorNode, TelemetryNode，
    並透過協程讀取分發循環 (rx_loop) 自動串接致動節點消息接收回呼。
    """

    def __init__(self, bus: Any, channel: str = "vcan0") -> None:
        self.bus = bus
        self.channel = channel
        self.gw = GatewayNode("GW_NODE", 0x01, self.bus)
        self.act = ActuatorNode("ACTUATOR_NODE", 0x02, self.bus)
        self.telem = TelemetryNode("TELEM_NODE", 0x03, self.bus)
        self.stop_event = asyncio.Event()

    async def rx_loop(self) -> None:
        """非同步輪詢或讀取總線消息並派發至節點。"""
        while not self.stop_event.is_set():
            try:
                # 兼容同步/非同步 bus.recv
                if hasattr(self.bus, "recv"):
                    msg = self.bus.recv(timeout=0.01)
                    if msg:
                        self.act.on_message_received(msg)
                await asyncio.sleep(0.005)
            except Exception:
                await asyncio.sleep(0.01)

    async def run_cluster(self, duration_sec: float = 0.5) -> Dict[str, Any]:
        """啟動三節點並行執行預定時長。"""
        task_gw = asyncio.create_task(self.gw.run(self.stop_event))
        task_act = asyncio.create_task(self.act.run(self.stop_event))
        task_telem = asyncio.create_task(self.telem.run(self.stop_event))
        task_rx = asyncio.create_task(self.rx_loop())

        await asyncio.sleep(duration_sec)
        self.stop_event.set()

        await asyncio.gather(task_gw, task_act, task_telem, task_rx, return_exceptions=True)

        return {
            "gw_frames": self.gw.frames_sent,
            "act_frames": self.act.frames_sent,
            "telem_frames": self.telem.frames_sent,
            "act_degraded": self.act.degraded,
            "degraded_transitions": self.act.degraded_transitions,
            "recovery_transitions": self.act.recovery_transitions,
        }
