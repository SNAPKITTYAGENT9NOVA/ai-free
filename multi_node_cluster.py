# -*- coding: utf-8 -*-
"""
L1 Multi-Node Topology Cluster (分散式三節點 CAN 總線模擬器)
Conforms to ISO 11898, ISO 26262 ASIL-D, and SAE J1850.

Nodes:
1. Master Gateway Node (CAN ID 0x120, 20ms sync)
2. Powertrain Actuator Node (CAN ID 0x280, 10ms telemetry)
3. Sensor Acquisition Node (CAN ID 0x380, 50ms telemetry)

Supports both virtual in-memory simulated bus and Linux SocketCAN vcan0.
"""

from __future__ import annotations

import logging
import signal
import sys
import threading
import time
from typing import Any, Dict, List, Optional

from can_l0_l1_matrix import (
    CANFrame,
    MultiNodeTopologyCluster,
    NodeSafetyState,
    CAN_ID_MASTER_GATEWAY,
    CAN_ID_POWERTRAIN_ACT,
    CAN_ID_SENSOR_ACQ,
)

logger = logging.getLogger("multi_node_cluster")


class MultiNodeClusterRunner:
    """
    Executes and coordinates the 3-Node Topology Cluster.
    Generates periodic frames with monotonic Alive Counters and SAE J1850 CRC-8,
    monitors heartbeat health, and applies ISO 26262 safety degradation.
    """

    def __init__(self, use_vcan: bool = False, vcan_channel: str = "vcan0", interval_sec: float = 0.01):
        self.cluster = MultiNodeTopologyCluster()
        self.use_vcan = use_vcan
        self.vcan_channel = vcan_channel
        self.interval_sec = interval_sec
        self.is_running = False
        self._stop_event = threading.Event()

        # Telemetry states
        self.total_frames_dispatched = 0
        self.current_motor_rpm = 3200.0
        self.current_temp_c = 68.5
        self.current_voltage_v = 48.2
        self.current_pressure_kpa = 220.0

        # Timing tracking for each node
        self._last_gw_tx = 0.0
        self._last_act_tx = 0.0
        self._last_sns_tx = 0.0

        self._can_bus = None
        if self.use_vcan:
            self._init_socketcan()

    def _init_socketcan(self) -> None:
        """Initializes python-can SocketCAN interface if running on Linux."""
        try:
            import can  # type: ignore
            self._can_bus = can.interface.Bus(channel=self.vcan_channel, bustype="socketcan")
            logger.info("SocketCAN interface %s initialized successfully.", self.vcan_channel)
        except Exception as e:
            logger.warning("SocketCAN unavailable (%s); falling back to virtual bus.", e)
            self._can_bus = None

    def step(self, now: Optional[float] = None) -> Dict[str, Any]:
        """
        Executes a single discrete step of the cluster simulation.
        Transmits frames whose periodic timer has elapsed.
        """
        if now is None:
            now = time.time()

        dispatched_in_step: List[CANFrame] = []

        # 1. Master Gateway Node (20ms cycle)
        if (now - self._last_gw_tx) >= self.cluster.gateway.period_sec:
            gw_frame = self.cluster.gateway.create_sync_command(
                global_safe=(self.cluster.cluster_safety_mode != NodeSafetyState.EMERGENCY_SAFE_STOP),
                target_speed_kph=60.0,
            )
            self.cluster.dispatch_frame(gw_frame, now=now)
            dispatched_in_step.append(gw_frame)
            self._last_gw_tx = now

        # 2. Powertrain Actuator Node (10ms cycle)
        if (now - self._last_act_tx) >= self.cluster.actuator.period_sec:
            act_frame = self.cluster.actuator.create_actuator_telemetry(
                actual_torque_nm=175.0
            )
            self.cluster.dispatch_frame(act_frame, now=now)
            dispatched_in_step.append(act_frame)
            self._last_act_tx = now

        # 3. Sensor Acquisition Node (50ms cycle)
        if (now - self._last_sns_tx) >= self.cluster.sensor.period_sec:
            sns_frame = self.cluster.sensor.create_sensor_telemetry(
                temp_c=self.current_temp_c,
                pressure_kpa=self.current_pressure_kpa,
            )
            self.cluster.dispatch_frame(sns_frame, now=now)
            dispatched_in_step.append(sns_frame)
            self._last_sns_tx = now

        # Relay to SocketCAN if active
        if self._can_bus:
            for f in dispatched_in_step:
                try:
                    import can
                    msg = can.Message(
                        arbitration_id=f.can_id,
                        data=bytes(f.data),
                        is_extended_id=f.is_extended,
                    )
                    self._can_bus.send(msg)
                except Exception:
                    pass

        self.total_frames_dispatched += len(dispatched_in_step)

        # Monitor heartbeat timeouts
        mode = self.cluster.monitor_heartbeats(now=now)

        return {
            "cluster_safety_mode": mode.value,
            "actuator_power_pct": self.cluster.actuator.torque_limit_pct,
            "dispatched_frames": len(dispatched_in_step),
            "total_frames": self.total_frames_dispatched,
            "nodes": {
                "gateway": {
                    "can_id": hex(CAN_ID_MASTER_GATEWAY),
                    "alive_counter": self.cluster.last_alive_counter[CAN_ID_MASTER_GATEWAY],
                    "status": self.cluster.gateway.safety_state.value,
                },
                "actuator": {
                    "can_id": hex(CAN_ID_POWERTRAIN_ACT),
                    "alive_counter": self.cluster.last_alive_counter[CAN_ID_POWERTRAIN_ACT],
                    "torque_limit_pct": self.cluster.actuator.torque_limit_pct,
                    "status": self.cluster.actuator.safety_state.value,
                },
                "sensor": {
                    "can_id": hex(CAN_ID_SENSOR_ACQ),
                    "alive_counter": self.cluster.last_alive_counter[CAN_ID_SENSOR_ACQ],
                    "temp_c": self.current_temp_c,
                    "status": self.cluster.sensor.safety_state.value,
                },
            },
        }

    def run_loop(self, duration: Optional[float] = None) -> None:
        """Runs the cluster simulation continuously until stopped or duration expires."""
        self.is_running = True
        self._stop_event.clear()
        start_time = time.time()

        try:
            while not self._stop_event.is_set():
                now = time.time()
                if duration and (now - start_time) >= duration:
                    break

                self.step(now=now)
                time.sleep(self.interval_sec)
        finally:
            self.stop()

    def stop(self) -> None:
        """Gracefully halts the cluster simulation."""
        self.is_running = False
        self._stop_event.set()
        if self._can_bus:
            try:
                self._can_bus.shutdown()
            except Exception:
                pass


def main() -> None:
    runner = MultiNodeClusterRunner(interval_sec=0.02)

    def handle_signal(sig, frame):
        print("\n[!] 接收到中斷訊號，正在關閉 L1 總線集群...")
        runner.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    print("==========================================================")
    print(" 🚗 [PHANTOM GRID] L1 分散式三節點 CAN 總線模擬器啟動")
    print("    - Master Gateway (0x120, 20ms)")
    print("    - Powertrain Actuator (0x280, 10ms)")
    print("    - Sensor Acquisition (0x380, 50ms)")
    print("    - E2E 滾動計數 (0~15) & SAE J1850 CRC-8 校驗保護")
    print("==========================================================")

    step_count = 0
    start = time.time()
    while not runner._stop_event.is_set():
        stats = runner.step()
        step_count += 1
        if step_count % 50 == 0:
            elapsed = time.time() - start
            print(
                f"[{elapsed:6.2f}s] Cluster State: {stats['cluster_safety_mode']} | "
                f"Actuator Power: {stats['actuator_power_pct']:.0f}% | "
                f"Total Frames: {stats['total_frames']} | "
                f"Sensor Temp: {stats['nodes']['sensor']['temp_c']}°C"
            )
        time.sleep(runner.interval_sec)


if __name__ == "__main__":
    main()

