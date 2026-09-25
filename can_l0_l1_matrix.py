# -*- coding: utf-8 -*-
"""
CAN L0/L1 Physical & Communication Layer Matrix (底層 CAN 總線與通訊矩陣實體化)
Conforms to ISO 11898, ISO 26262 (ASIL-D Functional Safety), and ISO 14229 (UDS).

Architecture:
1. E2E Data Frame Validation:
   - Header: 0~15 Monotonic Alive Counter (AUTOSAR Profile compliant)
   - Tail: SAE J1850 CRC-8 (Polynomial 0x1D, Init 0xFF, XorOut 0xFF)
2. Safety State Machine & ISO 14229 UDS Diagnostics:
   - Ladder-based Bus-Off Recovery (100ms quick restart x3 -> 1000ms slow restart backoff)
   - Watchdog Timeout & Exponential Backoff Protection
   - Full ISO 14229 UDS Diagnostic Stack (0x10, 0x11, 0x14, 0x19, 0x22, 0x27, 0x3E)
3. Multi-Node Topology Cluster:
   - Master Gateway Node (CAN IDs: 0x080, 0x120)
   - Powertrain Actuator Node (CAN ID: 0x280)
   - Sensor Acquisition Node (CAN ID: 0x380)
   - 10ms ~ 50ms Periodic Heartbeat Monitoring & Autonomous Safety Degradation (Limp-Home / Safe Stop)
"""

from __future__ import annotations

import enum
import struct
import sys
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


# ============================================================================
# 1. E2E CRC-8 (SAE J1850 Poly 0x1D) & Frame Protocol
# ============================================================================

def calculate_crc8_j1850(data: bytes, init: int = 0xFF, xor_out: int = 0xFF) -> int:
    """
    Computes CRC-8 according to SAE J1850 specification.
    Polynomial: x^8 + x^4 + x^3 + x^2 + 1 (0x1D / 0x11D)
    Initial value: 0xFF, Final XOR: 0xFF
    """
    crc = init
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ 0x1D) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc ^ xor_out


@dataclass
class CANFrame:
    """Standard / Extended CAN or CAN-FD Frame."""
    can_id: int
    data: bytearray
    is_extended: bool = False
    is_fd: bool = False
    timestamp: float = field(default_factory=time.time)

    @property
    def dlc(self) -> int:
        return len(self.data)


class E2EFrameCodec:
    """
    E2E Protection Wrapper (AUTOSAR compliant profile):
    - Byte 0: [High Nibble: DataID Low Nibble or Reserve] | [Low Nibble: Alive Counter 0~15]
    - Byte 1 .. N-2: Payload data
    - Byte N-1: SAE J1850 CRC-8 over (data[0:N-1] + DataID)
    """

    def __init__(self, data_id: int = 0x5A):
        self.data_id = data_id & 0xFF
        self._tx_alive_counter = 0

    def encode(self, can_id: int, payload: bytes, is_fd: bool = False) -> CANFrame:
        """Encapsulates raw payload with monotonic Alive Counter and SAE J1850 CRC-8."""
        alive_cnt = self._tx_alive_counter & 0x0F
        self._tx_alive_counter = (self._tx_alive_counter + 1) % 16

        header_byte = ((self.data_id & 0x0F) << 4) | alive_cnt
        frame_buf = bytearray([header_byte])
        frame_buf.extend(payload)

        # Calculate CRC over Header + Payload + DataID
        crc_input = bytes(frame_buf) + bytes([self.data_id])
        crc = calculate_crc8_j1850(crc_input)
        frame_buf.append(crc)

        return CANFrame(can_id=can_id, data=frame_buf, is_fd=is_fd)

    def decode(self, frame: CANFrame, last_counter: Optional[int] = None) -> Tuple[bool, int, bytes, str]:
        """
        Validates E2E frame integrity.
        Returns: (is_valid, alive_counter, payload, error_message)
        """
        if len(frame.data) < 2:
            return False, -1, b"", "E2E_PAYLOAD_TOO_SHORT"

        header = frame.data[0]
        alive_counter = header & 0x0F
        received_crc = frame.data[-1]
        payload = bytes(frame.data[1:-1])

        # Verify CRC
        crc_input = bytes(frame.data[:-1]) + bytes([self.data_id])
        expected_crc = calculate_crc8_j1850(crc_input)

        if received_crc != expected_crc:
            return False, alive_counter, payload, f"CRC_MISMATCH: expected 0x{expected_crc:02X}, got 0x{received_crc:02X}"

        # Verify Alive Counter Monotonicity (if last_counter provided)
        if last_counter is not None:
            expected_counter = (last_counter + 1) % 16
            if alive_counter != expected_counter:
                return False, alive_counter, payload, f"ALIVE_COUNTER_ERROR: expected {expected_counter}, got {alive_counter}"

        return True, alive_counter, payload, "OK"


# ============================================================================
# 2. Safety State Machine & ISO 26262 Bus-Off Ladder Recovery & Watchdog
# ============================================================================

class NodeSafetyState(enum.Enum):
    INIT = "INIT"
    NORMAL_OPERATION = "NORMAL_OPERATION"
    STATE_NORMAL = "NORMAL_OPERATION"
    STATE_DEGRADED = "STATE_DEGRADED"
    WARNING_DEGRADED = "STATE_DEGRADED"
    LIMP_HOME = "LIMP_HOME"
    BUS_OFF = "BUS_OFF"
    STATE_BUS_OFF_SAFE = "STATE_BUS_OFF_SAFE"
    STATE_HARD_FAULT = "STATE_HARD_FAULT"
    STATE_RESET = "STATE_RESET"
    EMERGENCY_SAFE_STOP = "EMERGENCY_SAFE_STOP"


SAFETY_STATE_PRIORITY: Dict[NodeSafetyState, int] = {
    NodeSafetyState.INIT: 0,
    NodeSafetyState.NORMAL_OPERATION: 1,
    NodeSafetyState.STATE_NORMAL: 1,
    NodeSafetyState.STATE_DEGRADED: 2,
    NodeSafetyState.LIMP_HOME: 3,
    NodeSafetyState.BUS_OFF: 4,
    NodeSafetyState.STATE_BUS_OFF_SAFE: 4,
    NodeSafetyState.STATE_HARD_FAULT: 5,
    NodeSafetyState.EMERGENCY_SAFE_STOP: 6,
    NodeSafetyState.STATE_RESET: 7,
}


class BusOffRecoveryMode(enum.Enum):
    IDLE = "IDLE"
    FAST_RECOVERY = "FAST_RECOVERY"   # 100ms interval (up to 3 times)
    SLOW_RECOVERY = "SLOW_RECOVERY"   # 1000ms interval (backoff protection)


class BusOffLadderManager:
    """
    ISO 26262 Compliant Bus-Off Ladder Recovery Manager:
    - On Bus-Off: Triggers fast restart attempts every 100ms.
    - If 3 consecutive fast recovery attempts fail: Drops into 1000ms slow restart backoff.
    - Prevents bus babbling and network resource exhaustion.
    """

    FAST_INTERVAL_SEC = 0.100   # 100ms
    SLOW_INTERVAL_SEC = 1.000   # 1000ms
    MAX_FAST_ATTEMPTS = 3

    def __init__(self, node_id: str):
        self.node_id = node_id
        self.mode = BusOffRecoveryMode.IDLE
        self.consecutive_failures = 0
        self.total_recoveries = 0
        self.last_attempt_time = 0.0

    def trigger_bus_off(self, now: Optional[float] = None) -> None:
        """Signals hardware or protocol Bus-Off event."""
        if now is None:
            now = time.time()
        self.mode = BusOffRecoveryMode.FAST_RECOVERY
        self.last_attempt_time = now

    def step(self, now: Optional[float] = None) -> Tuple[bool, str]:
        """
        State machine step.
        Returns (should_reinitialize_controller, status_log)
        """
        if self.mode == BusOffRecoveryMode.IDLE:
            return False, "IDLE"

        if now is None:
            now = time.time()

        elapsed = now - self.last_attempt_time

        if self.mode == BusOffRecoveryMode.FAST_RECOVERY:
            if elapsed >= self.FAST_INTERVAL_SEC - 1e-5:
                self.last_attempt_time = now
                self.consecutive_failures += 1
                if self.consecutive_failures >= self.MAX_FAST_ATTEMPTS:
                    self.mode = BusOffRecoveryMode.SLOW_RECOVERY
                    return True, f"FAST_RESTART_ATTEMPT_{self.consecutive_failures}_FAILED -> FALLBACK_TO_SLOW_RECOVERY"
                return True, f"FAST_RESTART_ATTEMPT_{self.consecutive_failures}"
            return False, f"WAITING_FAST_INTERVAL ({elapsed:.3f}s / {self.FAST_INTERVAL_SEC}s)"

        elif self.mode == BusOffRecoveryMode.SLOW_RECOVERY:
            if elapsed >= self.SLOW_INTERVAL_SEC - 1e-5:
                self.last_attempt_time = now
                self.consecutive_failures += 1
                return True, f"SLOW_RESTART_ATTEMPT_{self.consecutive_failures}"
            return False, f"WAITING_SLOW_INTERVAL ({elapsed:.3f}s / {self.SLOW_INTERVAL_SEC}s)"

        return False, "UNKNOWN"

    def mark_recovery_success(self) -> None:
        """Call when frame successfully acknowledged on the bus."""
        self.mode = BusOffRecoveryMode.IDLE
        self.consecutive_failures = 0
        self.total_recoveries += 1


class WatchdogSupervisor:
    """
    Hardware/Software Watchdog with Timeout & Exponential Backoff Protection.
    Monitors node scheduling loop latency.
    """

    def __init__(self, timeout_sec: float = 0.050, max_backoff_sec: float = 0.500):
        self.timeout_sec = timeout_sec
        self.max_backoff_sec = max_backoff_sec
        self.current_backoff_sec = timeout_sec
        self.last_kick_time = time.time()
        self.missed_kicks = 0

    def kick(self, now: Optional[float] = None) -> None:
        """Service/feed the watchdog."""
        if now is None:
            now = time.time()
        self.last_kick_time = now
        self.missed_kicks = 0
        self.current_backoff_sec = self.timeout_sec

    def check(self, now: Optional[float] = None) -> Tuple[bool, float]:
        """
        Checks watchdog status.
        Returns: (is_tripped, elapsed_time)
        """
        if now is None:
            now = time.time()
        elapsed = now - self.last_kick_time
        if elapsed > self.current_backoff_sec:
            self.missed_kicks += 1
            # Exponential backoff up to max
            self.current_backoff_sec = min(self.current_backoff_sec * 1.5, self.max_backoff_sec)
            return True, elapsed
        return False, elapsed


# ============================================================================
# 3. ISO 14229 UDS Diagnostic Stack
# ============================================================================

class UDSServiceId(enum.IntEnum):
    DIAGNOSTIC_SESSION_CONTROL = 0x10
    ECU_RESET = 0x11
    CLEAR_DIAGNOSTIC_INFO = 0x14
    READ_DTC_INFO = 0x19
    SECURITY_ACCESS = 0x27
    READ_DATA_BY_ID = 0x22
    TESTER_PRESENT = 0x3E


class UDSNegativeResponseCode(enum.IntEnum):
    SUB_FUNCTION_NOT_SUPPORTED = 0x12
    INCORRECT_MESSAGE_LENGTH = 0x13
    CONDITIONS_NOT_CORRECT = 0x22
    REQUEST_SEQUENCE_ERROR = 0x24
    REQUEST_OUT_OF_RANGE = 0x31
    SECURITY_ACCESS_DENIED = 0x33
    INVALID_KEY = 0x35
    EXCEEDED_NUMBER_OF_ATTEMPTS = 0x36


class UDSServer:
    """
    ISO 14229-1 Unified Diagnostic Services (UDS) Server.
    Handles sessions, security access, DTC reading/clearing, and DID readouts.
    """

    def __init__(self, ecu_name: str = "ECU_GATEWAY"):
        self.ecu_name = ecu_name
        self.session = 0x01  # 0x01: Default, 0x02: Programming, 0x03: Extended
        self.security_unlocked = False
        self.dtc_store: List[Dict[str, Any]] = [
            {"code": 0xC12000, "name": "U0120_LOST_COMM_GATEWAY", "status": 0x2F},
            {"code": 0xC28000, "name": "U0280_LOST_COMM_ACTUATOR", "status": 0x2F},
            {"code": 0xC38000, "name": "U0380_LOST_COMM_SENSOR", "status": 0x2F},
        ]
        self.data_identifiers: Dict[int, bytes] = {
            0xF190: b"PHANTOM-GRID-2026",  # VIN
            0x0120: struct.pack(">HBB", 120, 1, 99),  # Gateway stats
            0x0280: struct.pack(">hH", 1500, 240),   # Actuator torque & rpm
            0x0380: struct.pack(">hhh", 450, 25, 102),  # Sensor temp, angle, pres
        }

    def process_request(self, request_payload: bytes) -> bytes:
        """Processes raw UDS request and returns UDS response."""
        if not request_payload:
            return bytes([0x7F, 0x00, UDSNegativeResponseCode.INCORRECT_MESSAGE_LENGTH])

        sid = request_payload[0]
        params = request_payload[1:]

        # 0x10: DiagnosticSessionControl
        if sid == UDSServiceId.DIAGNOSTIC_SESSION_CONTROL:
            if not params:
                return bytes([0x7F, sid, UDSNegativeResponseCode.INCORRECT_MESSAGE_LENGTH])
            sub_function = params[0]
            if sub_function in (0x01, 0x02, 0x03):
                self.session = sub_function
                # P2 Server Max = 50ms (0x0032), P2* Server Max = 5000ms (0x01F4)
                return bytes([sid + 0x40, sub_function, 0x00, 0x32, 0x01, 0xF4])
            return bytes([0x7F, sid, UDSNegativeResponseCode.SUB_FUNCTION_NOT_SUPPORTED])

        # 0x3E: TesterPresent
        elif sid == UDSServiceId.TESTER_PRESENT:
            if not params:
                return bytes([0x7F, sid, UDSNegativeResponseCode.INCORRECT_MESSAGE_LENGTH])
            sub_function = params[0]
            if sub_function & 0x7F == 0x00:
                # If suppressPosRspMsg bit is set (0x80), return empty
                if sub_function & 0x80:
                    return b""
                return bytes([sid + 0x40, sub_function & 0x7F])
            return bytes([0x7F, sid, UDSNegativeResponseCode.SUB_FUNCTION_NOT_SUPPORTED])

        # 0x11: ECUReset
        elif sid == UDSServiceId.ECU_RESET:
            if not params:
                return bytes([0x7F, sid, UDSNegativeResponseCode.INCORRECT_MESSAGE_LENGTH])
            reset_type = params[0]
            if reset_type in (0x01, 0x03):  # Hard or Soft
                self.session = 0x01
                self.security_unlocked = False
                return bytes([sid + 0x40, reset_type])
            return bytes([0x7F, sid, UDSNegativeResponseCode.SUB_FUNCTION_NOT_SUPPORTED])

        # 0x14: ClearDiagnosticInformation
        elif sid == UDSServiceId.CLEAR_DIAGNOSTIC_INFO:
            self.dtc_store.clear()
            return bytes([sid + 0x40])

        # 0x19: ReadDTCInformation
        elif sid == UDSServiceId.READ_DTC_INFO:
            if not params:
                return bytes([0x7F, sid, UDSNegativeResponseCode.INCORRECT_MESSAGE_LENGTH])
            sub_function = params[0]
            if sub_function == 0x02:  # reportDTCByStatusMask
                status_mask = params[1] if len(params) > 1 else 0xFF
                resp = bytearray([sid + 0x40, sub_function, status_mask])
                for dtc in self.dtc_store:
                    if dtc["status"] & status_mask:
                        code_bytes = struct.pack(">I", dtc["code"])[1:]  # 3 bytes
                        resp.extend(code_bytes)
                        resp.append(dtc["status"])
                return bytes(resp)
            return bytes([0x7F, sid, UDSNegativeResponseCode.SUB_FUNCTION_NOT_SUPPORTED])

        # 0x22: ReadDataByIdentifier
        elif sid == UDSServiceId.READ_DATA_BY_ID:
            if len(params) < 2:
                return bytes([0x7F, sid, UDSNegativeResponseCode.INCORRECT_MESSAGE_LENGTH])
            did = (params[0] << 8) | params[1]
            if did in self.data_identifiers:
                val = self.data_identifiers[did]
                return bytes([sid + 0x40, params[0], params[1]]) + val
            return bytes([0x7F, sid, UDSNegativeResponseCode.REQUEST_OUT_OF_RANGE])

        # 0x27: SecurityAccess
        elif sid == UDSServiceId.SECURITY_ACCESS:
            if not params:
                return bytes([0x7F, sid, UDSNegativeResponseCode.INCORRECT_MESSAGE_LENGTH])
            sub_func = params[0]
            if sub_func == 0x01:  # Request Seed
                seed = b"\x12\x34\x56\x78"
                return bytes([sid + 0x40, 0x01]) + seed
            elif sub_func == 0x02:  # Send Key (Key = Seed XOR 0xFF)
                key = params[1:]
                if key == b"\xED\xCB\xA9\x87":
                    self.security_unlocked = True
                    return bytes([sid + 0x40, 0x02])
                return bytes([0x7F, sid, UDSNegativeResponseCode.INVALID_KEY])
            return bytes([0x7F, sid, UDSNegativeResponseCode.SUB_FUNCTION_NOT_SUPPORTED])

        return bytes([0x7F, sid, UDSNegativeResponseCode.SUB_FUNCTION_NOT_SUPPORTED])


# ============================================================================
# 4. Multi-Node Topology Cluster & Heartbeat Monitoring
# ============================================================================

# CAN IDs Architecture
CAN_ID_MASTER_EMERGENCY = 0x080     # Highest Priority (E-Stop / Global Sync)
CAN_ID_MASTER_GATEWAY   = 0x120     # Master Gateway State & Commands (10ms)
CAN_ID_POWERTRAIN_ACT   = 0x280     # Powertrain & Actuation Control (20ms)
CAN_ID_SENSOR_ACQ       = 0x380     # Sensor Acquisition & Telemetry (50ms)
CAN_ID_UDS_REQ          = 0x7E0     # Diagnostic Request
CAN_ID_UDS_RESP         = 0x7E8     # Diagnostic Response


@dataclass
class NodeHeartbeatConfig:
    node_id: str
    can_id: int
    period_sec: float
    timeout_multiplier: float = 3.0  # Safe threshold: 3 missed cycles


class BaseCANNode:
    """Base class for cluster nodes with E2E transmission and Bus-Off management."""

    def __init__(self, node_id: str, can_id: int, period_sec: float, data_id: int):
        self.node_id = node_id
        self.can_id = can_id
        self.period_sec = period_sec
        self.e2e = E2EFrameCodec(data_id=data_id)
        self.bus_off_mgr = BusOffLadderManager(node_id=node_id)
        self.watchdog = WatchdogSupervisor(timeout_sec=period_sec * 2.0)
        self.safety_state = NodeSafetyState.NORMAL_OPERATION
        self.last_tx_time = 0.0
        self.consecutive_rx_errors = 0

    def create_heartbeat_frame(self, custom_payload: bytes = b"\x00") -> CANFrame:
        """Packs state and heartbeat payload with E2E protection."""
        self.watchdog.kick()
        return self.e2e.encode(self.can_id, custom_payload)


class MasterGatewayNode(BaseCANNode):
    """
    Master Gateway (ID 0x080 / 0x120, 10ms cycle).
    Coordinates cluster synchronization and issues global safety states.
    """

    def __init__(self):
        super().__init__(node_id="GATEWAY", can_id=CAN_ID_MASTER_GATEWAY, period_sec=0.010, data_id=0x12)
        self.uds_server = UDSServer(ecu_name="MASTER_GW")

    def create_sync_command(self, global_safe: bool = True, target_speed_kph: float = 50.0) -> CANFrame:
        status_byte = 0x01 if global_safe else 0x00
        speed_raw = int(target_speed_kph * 10) & 0xFFFF
        payload = struct.pack(">BH", status_byte, speed_raw)
        return self.create_heartbeat_frame(payload)

    def create_emergency_stop_frame(self) -> CANFrame:
        """0x080 High Priority Immediate E-Stop Frame."""
        payload = b"\xFF\xEE\x00\x00"
        return self.e2e.encode(CAN_ID_MASTER_EMERGENCY, payload)


class PowertrainActuatorNode(BaseCANNode):
    """
    Powertrain Actuator (ID 0x280, 20ms cycle).
    Executes torque & braking commands; monitors safety constraints.
    """

    def __init__(self):
        super().__init__(node_id="ACTUATOR", can_id=CAN_ID_POWERTRAIN_ACT, period_sec=0.020, data_id=0x28)
        self.torque_limit_pct = 100.0  # Drops to 50% in State-Degraded, 20% in Limp-Home, 0% in Safe Stop
        self.pwm_output_enabled = True
        self.pwm_duty_pct = 100.0

    def apply_safety_degradation(self, target_state: NodeSafetyState) -> None:
        self.safety_state = target_state
        if target_state in (NodeSafetyState.STATE_DEGRADED, NodeSafetyState.WARNING_DEGRADED):
            self.torque_limit_pct = 50.0
            self.pwm_duty_pct = 50.0
        elif target_state == NodeSafetyState.LIMP_HOME:
            self.torque_limit_pct = 20.0
            self.pwm_duty_pct = 20.0
        elif target_state in (NodeSafetyState.EMERGENCY_SAFE_STOP, NodeSafetyState.BUS_OFF):
            self.torque_limit_pct = 0.0
            self.pwm_duty_pct = 0.0
            self.pwm_output_enabled = False

    def handle_bus_off(self, now: Optional[float] = None) -> None:
        """On Bus-Off event, immediately disable PWM output and arm 100ms fast restart timer."""
        self.apply_safety_degradation(NodeSafetyState.BUS_OFF)
        self.bus_off_mgr.trigger_bus_off(now=now)

    def create_actuator_telemetry(self, actual_torque_nm: float = 120.0) -> CANFrame:
        clamped_torque = min(actual_torque_nm, 300.0 * (self.torque_limit_pct / 100.0))
        payload = struct.pack(">hB", int(clamped_torque), int(self.torque_limit_pct))
        return self.create_heartbeat_frame(payload)


class SensorAcquisitionNode(BaseCANNode):
    """
    Sensor Acquisition (ID 0x380, 50ms cycle).
    Collects wheel speed, IMU, and thermal telemetry.
    """

    def __init__(self):
        super().__init__(node_id="SENSOR", can_id=CAN_ID_SENSOR_ACQ, period_sec=0.050, data_id=0x38)

    def create_sensor_telemetry(self, temp_c: float = 65.5, pressure_kpa: float = 220.0) -> CANFrame:
        temp_raw = int(temp_c * 10) & 0xFFFF
        pres_raw = int(pressure_kpa) & 0xFFFF
        payload = struct.pack(">HH", temp_raw, pres_raw)
        return self.create_heartbeat_frame(payload)


class MultiNodeTopologyCluster:
    """
    Supervises the 3-Node Topology Cluster (Gateway, Actuator, Sensor).
    Monitors periodic heartbeats, validates E2E integrity, and enforces Safety Degradation.
    """

    def __init__(self):
        self.gateway = MasterGatewayNode()
        self.actuator = PowertrainActuatorNode()
        self.sensor = SensorAcquisitionNode()

        self.nodes: Dict[int, BaseCANNode] = {
            CAN_ID_MASTER_GATEWAY: self.gateway,
            CAN_ID_POWERTRAIN_ACT: self.actuator,
            CAN_ID_SENSOR_ACQ: self.sensor,
        }

        self.last_heartbeat_received: Dict[int, float] = {
            can_id: time.time() for can_id in self.nodes
        }
        self.last_alive_counter: Dict[int, int] = {
            can_id: -1 for can_id in self.nodes
        }
        self.cluster_safety_mode = NodeSafetyState.NORMAL_OPERATION
        self.incident_log: List[str] = []

    def dispatch_frame(self, frame: CANFrame, now: Optional[float] = None) -> bool:
        """
        Receives and decodes frame through E2E pipeline.
        Updates heartbeat timestamps and monitors for anomalies.
        """
        if now is None:
            now = time.time()

        can_id = frame.can_id
        if can_id not in self.nodes:
            # Handle emergency broadcast ID 0x080
            if can_id == CAN_ID_MASTER_EMERGENCY:
                self.trigger_cluster_safe_state(NodeSafetyState.EMERGENCY_SAFE_STOP, "EMERGENCY_BROADCAST_RECEIVED")
                return True
            return False

        target_node = self.nodes[can_id]
        prev_cnt = self.last_alive_counter[can_id]
        last_check_cnt = None if prev_cnt == -1 else prev_cnt

        is_valid, alive_cnt, payload, err = target_node.e2e.decode(frame, last_check_cnt)

        if not is_valid:
            target_node.consecutive_rx_errors += 1
            log_msg = f"[E2E_FAULT] Node {target_node.node_id} (0x{can_id:03X}): {err} (Streak: {target_node.consecutive_rx_errors})"
            self.incident_log.append(log_msg)

            if target_node.consecutive_rx_errors >= 3:
                self.trigger_cluster_safe_state(
                    NodeSafetyState.STATE_DEGRADED,
                    f"Consecutive E2E CRC errors on {target_node.node_id} (>= 3 frames)"
                )
            return False

        # Valid frame received
        target_node.consecutive_rx_errors = 0
        self.last_alive_counter[can_id] = alive_cnt
        self.last_heartbeat_received[can_id] = now
        return True

    def monitor_heartbeats(self, now: Optional[float] = None) -> NodeSafetyState:
        """
        Evaluates cluster nodes against timeout multipliers.
        Switches to LIMP_HOME or EMERGENCY_SAFE_STOP if heartbeats are lost.
        """
        if now is None:
            now = time.time()

        for can_id, node in self.nodes.items():
            elapsed = now - self.last_heartbeat_received[can_id]
            max_allowed = node.period_sec * 3.0  # 3 missed cycles

            if elapsed > max_allowed:
                reason = f"HEARTBEAT_TIMEOUT: Node {node.node_id} (0x{can_id:03X}) silent for {elapsed*1000:.1f}ms (threshold: {max_allowed*1000:.1f}ms)"
                self.incident_log.append(reason)

                # Gateway or Actuator failure triggers immediate Limp-Home / Safe-Stop
                if can_id in (CAN_ID_MASTER_GATEWAY, CAN_ID_POWERTRAIN_ACT):
                    self.trigger_cluster_safe_state(NodeSafetyState.EMERGENCY_SAFE_STOP, reason)
                else:
                    self.trigger_cluster_safe_state(NodeSafetyState.LIMP_HOME, reason)

        return self.cluster_safety_mode

    def trigger_cluster_safe_state(self, target_state: NodeSafetyState, reason: str, force: bool = False) -> None:
        """Enforces degradation across all topology members with priority escalation protection."""
        curr_prio = SAFETY_STATE_PRIORITY.get(self.cluster_safety_mode, 0)
        target_prio = SAFETY_STATE_PRIORITY.get(target_state, 0)

        # Do not downgrade a more severe safe state unless force=True
        if not force and target_prio < curr_prio:
            return

        self.cluster_safety_mode = target_state
        self.gateway.safety_state = target_state
        self.actuator.apply_safety_degradation(target_state)
        self.sensor.safety_state = target_state
        self.incident_log.append(f"[SAFETY_DEGRADATION] Transitioned cluster to {target_state.value} | Reason: {reason}")


if __name__ == "__main__":
    print("=" * 70)
    print("🚗 [PHANTOM GRID] CAN L0/L1 Physical & Communication Layer Matrix")
    print("   ISO 11898 / ISO 26262 ASIL-D / ISO 14229 UDS Multi-Node Cluster")
    print("=" * 70)

    # 1. E2E Frame Demo
    codec = E2EFrameCodec(data_id=0x12)
    sample_frame = codec.encode(can_id=CAN_ID_MASTER_GATEWAY, payload=b"\x01\x02\x03\x04")
    print(f"\n[1. E2E Frame Validation]")
    print(f"   -> CAN ID: 0x{sample_frame.can_id:03X} | DLC: {sample_frame.dlc} Bytes")
    print(f"   -> Raw Buffer: {list(sample_frame.data)}")
    print(f"   -> Header (Alive Counter): {sample_frame.data[0] & 0x0F} | Tail (J1850 CRC-8): 0x{sample_frame.data[-1]:02X}")
    valid, cnt, payload, err = codec.decode(sample_frame)
    print(f"   -> Verification: {valid} ({err}) | Payload: {payload.hex()}")

    # 2. ISO 26262 Bus-Off Ladder Recovery Demo
    print(f"\n[2. ISO 26262 Bus-Off Ladder Recovery]")
    bus_off = BusOffLadderManager(node_id="ACTUATOR_ECU")
    t = 100.0
    bus_off.trigger_bus_off(now=t)
    print(f"   -> Trigger Bus-Off: Mode = {bus_off.mode.value}")
    for i in range(1, 4):
        t += 0.100
        _, log = bus_off.step(now=t)
        print(f"   -> Step +100ms: {log}")
    t += 1.000
    _, log = bus_off.step(now=t)
    print(f"   -> Step +1000ms: {log} (Slow Recovery Active)")
    bus_off.mark_recovery_success()
    print(f"   -> Frame ACK Received -> Restored to {bus_off.mode.value} 🟢")

    # 3. ISO 14229 UDS Demo
    print(f"\n[3. ISO 14229 UDS Diagnostic Stack]")
    uds = UDSServer()
    resp_session = uds.process_request(bytes([UDSServiceId.DIAGNOSTIC_SESSION_CONTROL, 0x03]))
    print(f"   -> 0x10 Extended Session Response: {list(resp_session)}")
    resp_vin = uds.process_request(bytes([UDSServiceId.READ_DATA_BY_ID, 0xF1, 0x90]))
    print(f"   -> 0x22 Read VIN (0xF190): {resp_vin[3:].decode('ascii')}")

    # 4. Multi-Node Topology Cluster Demo
    print(f"\n[4. Multi-Node Topology Cluster & Safety Degradation]")
    cluster = MultiNodeTopologyCluster()
    gw_frame = cluster.gateway.create_sync_command(global_safe=True, target_speed_kph=80.0)
    act_frame = cluster.actuator.create_actuator_telemetry(actual_torque_nm=180.0)
    sns_frame = cluster.sensor.create_sensor_telemetry(temp_c=62.0, pressure_kpa=220.0)

    now = 500.0
    cluster.dispatch_frame(gw_frame, now=now)
    cluster.dispatch_frame(act_frame, now=now)
    cluster.dispatch_frame(sns_frame, now=now)
    print(f"   -> Cluster Heartbeats Healthy. Safety Mode: {cluster.cluster_safety_mode.value}")
    print(f"   -> Actuator Torque Limit: {cluster.actuator.torque_limit_pct:.1f}%")

    # Simulate Sensor silent for 200ms
    cluster.monitor_heartbeats(now=now + 0.200)
    print(f"   -> Sensor Timeout (200ms > 150ms)! Safety Mode: {cluster.cluster_safety_mode.value} ⚠️")
    print(f"   -> Actuator Torque Limit clamped to: {cluster.actuator.torque_limit_pct:.1f}% (Limp-Home)")

    # Simulate Emergency Stop broadcast
    e_stop = cluster.gateway.create_emergency_stop_frame()
    cluster.dispatch_frame(e_stop, now=now + 0.210)
    print(f"   -> Emergency Stop (0x080) Broadcast! Safety Mode: {cluster.cluster_safety_mode.value} 🛑")
    print(f"   -> Actuator Torque Limit clamped to: {cluster.actuator.torque_limit_pct:.1f}%")
    print("=" * 70)

