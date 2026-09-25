# -*- coding: utf-8 -*-
"""
Real-Time SocketCAN Telemetry Streaming Engine & Metrics Backend
Axis 2 Component: Low-latency CAN bus frame ingestion, sliding-window load & jitter calculation,
and thread-safe vehicle telemetry snapshot provider.
"""

from __future__ import annotations

import collections
import logging
import struct
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Deque, Dict, List, Optional, Tuple

from audit_governance import GovernanceDB

logger = logging.getLogger("can_telemetry_backend")

try:
    import can
    CAN_AVAILABLE = True
except ImportError:
    can = None  # type: ignore
    CAN_AVAILABLE = False


@dataclass
class CANFrameMetrics:
    total_frames_received: int = 0
    bus_load_pct: float = 0.0
    average_jitter_us: float = 0.0
    max_jitter_us: float = 0.0
    crc_error_count: int = 0
    alive_counter_drop_count: int = 0
    active_can_ids: List[int] = field(default_factory=list)


@dataclass
class VehicleTelemetrySnapshot:
    timestamp: float = 0.0
    bus_load_pct: float = 0.0
    frame_jitter_us: float = 0.0
    alive_counter: int = 0
    motor_rpm: int = 0
    battery_mv: int = 0
    motor_temp_c: float = 0.0
    safety_state: str = "NORMAL"
    pwm_limit_pct: float = 100.0
    active_dtc: Optional[str] = None
    last_arbitration_id: int = 0


class MockCANBusAdapter:
    """Thread-safe in-memory virtual CAN adapter when python-can / vcan is unavailable."""

    def __init__(self, channel: str = "vcan0") -> None:
        self.channel = channel
        self._queue: collections.deque[Any] = collections.deque(maxlen=1024)
        self._lock = threading.Lock()
        self._closed = False

    def send(self, msg: Any) -> None:
        if self._closed:
            raise RuntimeError("Bus is closed")
        with self._lock:
            self._queue.append(msg)

    def recv(self, timeout: float = 0.1) -> Optional[Any]:
        start = time.time()
        while time.time() - start < timeout:
            if self._closed:
                return None
            with self._lock:
                if self._queue:
                    return self._queue.popleft()
            time.sleep(0.005)
        return None

    def shutdown(self) -> None:
        self._closed = True


class SocketCANTelemetryBackend:
    """
    High-performance real-time telemetry streaming backend.
    Connects to SocketCAN interface (or falls back to mock/virtual),
    computes rolling bus load % and frame jitter μs over a sliding window,
    and provides thread-safe telemetry snapshots for UI dashboards and controllers.
    """

    def __init__(
        self,
        channel: str = "vcan0",
        bustype: str = "socketcan",
        bitrate: int = 500000,
        window_ms: float = 100.0,
        db_path: str = "audit_log.db",
    ) -> None:
        self.channel = channel
        self.bustype = bustype
        self.bitrate = bitrate
        self.window_sec = window_ms / 1000.0
        self.db = GovernanceDB(db_path=db_path)

        self.bus: Any = None
        self._is_mock = False
        self._init_can_interface()

        # Thread synchronization
        self._lock = threading.Lock()
        self._running = False
        self._worker_thread: Optional[threading.Thread] = None

        # Metrics & sliding window
        self._frame_sliding_window: Deque[Tuple[float, int]] = collections.deque()
        self._last_timestamps_by_id: Dict[int, float] = {}
        self._jitter_samples_us: Deque[float] = collections.deque(maxlen=50)

        # Telemetry state
        self._metrics = CANFrameMetrics()
        self._snapshot = VehicleTelemetrySnapshot()

        # Event callbacks
        self._subscribers: List[Callable[[VehicleTelemetrySnapshot], None]] = []

    def _init_can_interface(self) -> None:
        """Initializes CAN interface with graceful fallback."""
        if CAN_AVAILABLE and can is not None:
            try:
                self.bus = can.interface.Bus(
                    channel=self.channel,
                    interface=self.bustype,
                    bitrate=self.bitrate,
                    receive_own_messages=True,
                )
                self._is_mock = False
                logger.info("Connected to native CAN bus on %s", self.channel)
                return
            except Exception as e:
                logger.warning(
                    "Native CAN init failed (%s). Attempting virtual fallback.",
                    e,
                )
                try:
                    self.bus = can.interface.Bus(
                        channel=self.channel,
                        interface="virtual",
                        receive_own_messages=True,
                    )
                    self._is_mock = False
                    logger.info("Connected to virtual python-can bus on %s", self.channel)
                    return
                except Exception as e2:
                    logger.warning("Virtual CAN init failed (%s). Using mock bus.", e2)

        self.bus = MockCANBusAdapter(channel=self.channel)
        self._is_mock = True
        logger.info("MockCANBusAdapter initialized for %s", self.channel)

    def start(self) -> None:
        """Starts background listener worker thread."""
        with self._lock:
            if self._running:
                return
            self._running = True
            self._worker_thread = threading.Thread(
                target=self._worker_loop,
                name="SocketCANTelemetryWorker",
                daemon=True,
            )
            self._worker_thread.start()
            logger.info("SocketCAN telemetry worker thread started")

    def stop(self) -> None:
        """Stops background listener worker thread cleanly."""
        with self._lock:
            if not self._running:
                return
            self._running = False

        if self._worker_thread and self._worker_thread.is_alive():
            self._worker_thread.join(timeout=1.0)
            self._worker_thread = None

        if hasattr(self.bus, "shutdown"):
            try:
                self.bus.shutdown()
            except Exception:
                pass
        logger.info("SocketCAN telemetry backend stopped")

    def send_frame(
        self,
        arbitration_id: int,
        data: bytes,
        is_extended_id: bool = False,
    ) -> bool:
        """Sends a raw CAN frame over the bus."""
        if not self.bus:
            return False
        try:
            if CAN_AVAILABLE and can is not None and not self._is_mock:
                msg = can.Message(
                    arbitration_id=arbitration_id,
                    data=data,
                    is_extended_id=is_extended_id,
                )
            else:
                msg = type(
                    "CANMessage",
                    (),
                    {
                        "arbitration_id": arbitration_id,
                        "data": data,
                        "dlc": len(data),
                        "timestamp": time.time(),
                        "is_extended_id": is_extended_id,
                    },
                )()
            self.bus.send(msg)
            return True
        except Exception as e:
            logger.error("Failed to send CAN frame 0x%03X: %s", arbitration_id, e)
            return False

    def get_snapshot(self) -> VehicleTelemetrySnapshot:
        """Returns a thread-safe copy of the latest telemetry snapshot."""
        with self._lock:
            return VehicleTelemetrySnapshot(
                timestamp=self._snapshot.timestamp,
                bus_load_pct=self._metrics.bus_load_pct,
                frame_jitter_us=self._metrics.average_jitter_us,
                alive_counter=self._snapshot.alive_counter,
                motor_rpm=self._snapshot.motor_rpm,
                battery_mv=self._snapshot.battery_mv,
                motor_temp_c=self._snapshot.motor_temp_c,
                safety_state=self._snapshot.safety_state,
                pwm_limit_pct=self._snapshot.pwm_limit_pct,
                active_dtc=self._snapshot.active_dtc,
                last_arbitration_id=self._snapshot.last_arbitration_id,
            )

    def get_metrics(self) -> CANFrameMetrics:
        """Returns a thread-safe copy of current bus performance metrics."""
        with self._lock:
            return CANFrameMetrics(
                total_frames_received=self._metrics.total_frames_received,
                bus_load_pct=self._metrics.bus_load_pct,
                average_jitter_us=self._metrics.average_jitter_us,
                max_jitter_us=self._metrics.max_jitter_us,
                crc_error_count=self._metrics.crc_error_count,
                alive_counter_drop_count=self._metrics.alive_counter_drop_count,
                active_can_ids=list(self._metrics.active_can_ids),
            )

    def subscribe(self, callback: Callable[[VehicleTelemetrySnapshot], None]) -> None:
        """Subscribes an external listener to real-time snapshot updates."""
        with self._lock:
            self._subscribers.append(callback)

    def _worker_loop(self) -> None:
        """Continuous frame ingestion loop."""
        while self._running:
            try:
                msg = self.bus.recv(timeout=0.05)
                if msg is None:
                    continue
                self._process_incoming_frame(msg)
            except Exception as e:
                if self._running:
                    logger.debug("Exception in CAN worker loop: %s", e)
                time.sleep(0.01)

    def _process_incoming_frame(self, msg: Any) -> None:
        """Decodes frame, updates sliding window metrics, and refreshes snapshot."""
        now = getattr(msg, "timestamp", None) or time.time()
        can_id = getattr(msg, "arbitration_id", 0)
        data = bytes(getattr(msg, "data", b""))
        dlc = len(data)

        with self._lock:
            self._metrics.total_frames_received += 1
            if can_id not in self._metrics.active_can_ids:
                self._metrics.active_can_ids.append(can_id)

            # Update sliding window & bus load
            self._update_sliding_window(now, dlc)

            # Update frame jitter for this specific CAN ID
            self._calculate_frame_jitter(can_id, now)

            # Decode standard PHANTOM GRID CAN protocol frames
            self._decode_can_frame(can_id, data, now)

            current_snapshot = VehicleTelemetrySnapshot(
                timestamp=self._snapshot.timestamp,
                bus_load_pct=self._metrics.bus_load_pct,
                frame_jitter_us=self._metrics.average_jitter_us,
                alive_counter=self._snapshot.alive_counter,
                motor_rpm=self._snapshot.motor_rpm,
                battery_mv=self._snapshot.battery_mv,
                motor_temp_c=self._snapshot.motor_temp_c,
                safety_state=self._snapshot.safety_state,
                pwm_limit_pct=self._snapshot.pwm_limit_pct,
                active_dtc=self._snapshot.active_dtc,
                last_arbitration_id=can_id,
            )

        # Notify subscribers outside lock
        for sub in self._subscribers:
            try:
                sub(current_snapshot)
            except Exception as cb_err:
                logger.error("Subscriber notification error: %s", cb_err)

    def _update_sliding_window(self, now: float, dlc: int) -> None:
        """
        Sliding-window bus load calculation:
        Standard 11-bit CAN frame length = SOF(1) + ID(11) + RTR(1) + IDE(1) + r0(1) +
        DLC(4) + Data(8*dlc) + CRC(15) + CRCDel(1) + ACK(2) + EOF(7) + IFS(3) = 47 + 8*dlc.
        Stuffing factor average ~ 1.15.
        """
        frame_bits = int((47 + 8 * dlc) * 1.15)
        self._frame_sliding_window.append((now, frame_bits))

        cutoff = now - self.window_sec
        while self._frame_sliding_window and self._frame_sliding_window[0][0] < cutoff:
            self._frame_sliding_window.popleft()

        total_bits = sum(bits for _, bits in self._frame_sliding_window)
        max_possible_bits = self.bitrate * self.window_sec
        if max_possible_bits > 0:
            load = min(100.0, (total_bits / max_possible_bits) * 100.0)
            self._metrics.bus_load_pct = round(load, 2)

    def _calculate_frame_jitter(self, can_id: int, now: float) -> None:
        """Computes frame arrival interval jitter against nominal 10ms (10,000μs)."""
        last = self._last_timestamps_by_id.get(can_id)
        self._last_timestamps_by_id[can_id] = now
        if last is not None:
            interval_us = (now - last) * 1e6
            nominal_us = 10000.0  # 10ms nominal period
            jitter_us = abs(interval_us - nominal_us)
            self._jitter_samples_us.append(jitter_us)

            avg_j = sum(self._jitter_samples_us) / len(self._jitter_samples_us)
            max_j = max(self._jitter_samples_us)
            self._metrics.average_jitter_us = round(avg_j, 1)
            self._metrics.max_jitter_us = round(max_j, 1)

    def _decode_can_frame(self, can_id: int, data: bytes, now: float) -> None:
        """Decodes standard vehicle CAN frames into internal snapshot."""
        self._snapshot.timestamp = now
        self._snapshot.last_arbitration_id = can_id

        if can_id == 0x120 and len(data) >= 8:
            # Master Gateway Powertrain Frame
            alive = data[1] & 0x0F
            self._snapshot.alive_counter = alive
            # Byte 2-3: Target RPM or Throttle
            target_pct = (data[2] / 255.0) * 100.0
            if target_pct > 0:
                self._snapshot.pwm_limit_pct = round(target_pct, 1)

        elif can_id == 0x280 and len(data) >= 8:
            # Powertrain Actuator / Inverter Telemetry Frame
            rpm = struct.unpack(">H", data[0:2])[0]
            battery_mv = struct.unpack(">H", data[2:4])[0]
            temp_c = data[4] - 40.0
            st_val = data[5]

            self._snapshot.motor_rpm = rpm
            self._snapshot.battery_mv = battery_mv
            self._snapshot.motor_temp_c = temp_c

            if st_val == 0:
                self._snapshot.safety_state = "NORMAL"
            elif st_val == 1:
                self._snapshot.safety_state = "DEGRADED"
                self._snapshot.active_dtc = "DTC_P0A80"
            elif st_val == 2:
                self._snapshot.safety_state = "BUS_OFF"
                self._snapshot.active_dtc = "DTC_U0001"

        elif can_id == 0x380 and len(data) >= 8:
            # Sensor Acquisition Frame
            sensor_temp = data[0] - 40.0
            if self._snapshot.motor_temp_c == 0.0:
                self._snapshot.motor_temp_c = sensor_temp


def run_standalone_telemetry_demo(duration_sec: float = 3.0) -> None:
    """Standalone live execution demo for verification and debugging."""
    print("=====================================================================")
    print("PHANTOM GRID: Real-Time SocketCAN Telemetry Streaming Engine Demo")
    print("=====================================================================")

    backend = SocketCANTelemetryBackend(channel="vcan0", bustype="virtual")
    backend.start()

    stop_gen = threading.Event()

    def generator_thread() -> None:
        counter = 0
        while not stop_gen.is_set():
            counter = (counter + 1) & 0x0F
            # 0x120 Master GW
            f120 = bytes([0xAA, counter, 0xC0, 0x12, 0x00, 0x00, 0x00, 0x1D])
            backend.send_frame(0x120, f120)

            # 0x280 Actuator
            f280 = struct.pack(">HHBBBB", 8200, 48500, 65 + 40, 0, counter, 0x00)
            backend.send_frame(0x280, f280)

            time.sleep(0.01)

    t_gen = threading.Thread(target=generator_thread, daemon=True)
    t_gen.start()

    start_time = time.time()
    try:
        while time.time() - start_time < duration_sec:
            snap = backend.get_snapshot()
            metrics = backend.get_metrics()
            print(
                f"[CAN Stream] Load: {metrics.bus_load_pct:5.1f}% | "
                f"Jitter: {metrics.average_jitter_us:5.1f}us | "
                f"RPM: {snap.motor_rpm:5d} | "
                f"Batt: {snap.battery_mv}mV | "
                f"State: {snap.safety_state} | "
                f"Counter: {snap.alive_counter}"
            )
            time.sleep(0.5)
    finally:
        stop_gen.set()
        t_gen.join(timeout=1.0)
        backend.stop()
        print("Demo completed cleanly.")


if __name__ == "__main__":
    run_standalone_telemetry_demo(3.0)
