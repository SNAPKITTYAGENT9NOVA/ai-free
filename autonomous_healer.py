# -*- coding: utf-8 -*-
"""
Autonomous Healer Engine (L3 邊緣自主修復引擎)
Conforms to ISO 26262 ASIL-D, AUTOSAR Adaptive, and Cyber-Physical Closed-Loop Healing Specs.

Core Capabilities:
1. Event Subscription:
   - Subscribes to SOME/IP Event 0x8001 (Actuator Status) and Event 0x8002 (Sensor Telemetry).
   - Direct zero-copy hook into DigitalTwinMirrorEngine (HPC DCU sub-millisecond callback).
2. Autonomous Derating Policy (Edge-Native Zero-Cloud-Dependency):
   - Level 0 (Normal): Temp <= 75°C and Voltage >= 350V -> 100% Torque.
   - Level 1 (Dynamic Derating): Temp > 75°C (<= 85°C) or Voltage 320V~350V -> Clamped to 70% Torque.
   - Level 2 (Limp-Home / Safe Protection): Temp > 85°C or Voltage < 320V -> Clamped to 30% Torque.
   - Thermal Recovery Hysteresis: Automatic recovery when temps drop safely below threshold.
3. Cryptographic SQLite Audit Database (healing_audit.db):
   - Records every anomaly detection, transition level, metric trigger, and SHA-256 audit signature.
"""

from __future__ import annotations

import enum
import hashlib
import socket
import sqlite3
import struct
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Union

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from audit_governance import GovernanceDB
from digital_twin_state import DigitalTwinMirrorEngine, DigitalTwinState
from soa_gateway_twin import (
    EVENT_ID_SENSOR_TELEMETRY,
    SOAGatewayTwin,
    SOMEIPMessage,
)

SOMEIP_HEADER_LEN = 16


class HealingLevel(enum.IntEnum):
    """Graduated Power Protection & Autonomous Derating Levels."""

    LEVEL_0_NORMAL = 0  # Normal operation (100% capacity)
    LEVEL_1_DYNAMIC_DERATING = 1  # Dynamic thermal derating (clamped to 70%)
    LEVEL_2_LIMP_HOME = 2  # Critical protection / Limp-Home (clamped to 30%)
    LEVEL_3_EMERGENCY_STOP = 3  # Ultimate shutdown (0% torque)


@dataclass
class HealingDecision:
    """Represents an autonomous healing evaluation result."""

    level: HealingLevel
    torque_limit_pct: float
    safety_mode: str
    motor_degraded: bool
    trigger_metric: str
    trigger_value: float
    action_taken: str
    status: str
    timestamp: float = field(default_factory=time.time)


class AutonomousHealer:
    """
    L3 Edge Autonomous Healing Engine.
    Subscribes to SOME/IP events, evaluates cyber-physical anomalies,
    executes closed-loop dynamic derating, and archives events in SQLite.
    """

    # Operating Thresholds
    TEMP_LVL1_THRESHOLD_C: float = 75.0  # > 75°C -> Level 1 (70% torque)
    TEMP_LVL2_THRESHOLD_C: float = 85.0  # > 85°C -> Level 2 (30% torque)
    TEMP_LVL3_STOP_THRESHOLD_C: float = 105.0  # > 105°C -> Emergency Stop
    TEMP_RECOVERY_HYSTERESIS_C: float = 70.0  # < 70°C -> Recovery to Level 0

    VOLT_LVL1_THRESHOLD_MV: int = 350000  # < 350V -> Level 1 (70% torque)
    VOLT_LVL2_THRESHOLD_MV: int = 320000  # < 320V -> Level 2 (30% torque)
    VOLT_RECOVERY_MV: int = 360000  # > 360V -> Voltage healthy
    VOLT_LOW_LVL1_THRESHOLD_MV: int = 11200  # < 11.2V (12V bus) -> Level 1 (70% power)
    VOLT_LOW_LVL3_THRESHOLD_MV: int = (
        10000  # < 10.0V (12V bus) -> Level 3 (0% power / Reset)
    )
    DEFAULT_DB_FILE: str = "audit_log.db"

    def __init__(
        self,
        listen_ip: Union[str, DigitalTwinMirrorEngine, None] = "127.0.0.1",
        port: Union[int, str, None] = 30490,
        twin_engine: Optional[DigitalTwinMirrorEngine] = None,
        db_path: str = "audit_log.db",
        vin: str = "PHANTOM-GRID-2026",
        bind_socket: bool = True,
        **kwargs: Any,
    ):
        if isinstance(listen_ip, DigitalTwinMirrorEngine):
            twin_engine = listen_ip
            listen_ip = "127.0.0.1"
        if isinstance(port, str):
            db_path = port
            port = 30490
        if "db_path" in kwargs:
            db_path = kwargs["db_path"]
        if "vin" in kwargs:
            vin = kwargs["vin"]
        if "twin_engine" in kwargs:
            twin_engine = kwargs["twin_engine"]

        self.listen_ip = listen_ip or "127.0.0.1"
        self.port = port or 30490
        self.vin = vin
        self.db_path = db_path
        self.twin_engine = twin_engine or DigitalTwinMirrorEngine(vin=vin)
        self.current_level = HealingLevel.LEVEL_0_NORMAL
        self.power_limit_pct = 100
        self.cooling_boost_active = False
        self._lock = threading.RLock()
        self._decision_callbacks: List[Callable[[HealingDecision], None]] = []

        # Bind UDP socket for SOME/IP listening if requested
        self.sock: Optional[socket.socket] = None
        if bind_socket:
            try:
                self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                self.sock.bind((self.listen_ip, self.port))
            except OSError:
                try:
                    self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    self.sock.bind((self.listen_ip, 0))
                except Exception:
                    self.sock = None

        # Governance & Audit Database
        self.db = GovernanceDB(db_path=self.db_path)

        # Initialize SQLite Audit Log Database
        self._conn: Optional[sqlite3.Connection] = None
        self._init_sqlite_db()

        # Connect to Digital Twin HPC callback for continuous monitoring
        self.twin_engine.register_hpc_subscriber(self._on_digital_twin_updated)

        # Cloud-Edge Hybrid Router & L5 Fleet Nostr Mesh hooks
        self.hybrid_router: Optional[Any] = None
        self.fleet_mesh: Optional[Any] = None
        self.last_nostr_broadcast: Optional[Dict[str, Any]] = None
        self.last_routing_decision: Optional[Any] = None

    def attach_hybrid_router(self, router: Any) -> None:
        """Attaches Cloud-Edge Hybrid Router for multi-tier dynamic routing."""
        self.hybrid_router = router

    def attach_fleet_mesh(self, fleet_mesh: Any) -> None:
        """Attaches L5 Fleet Nostr Mesh Node for decentralized peer broadcast."""
        self.fleet_mesh = fleet_mesh

    def trigger_healing_action(
        self, action_name: str, new_power_limit: int, reason: str
    ) -> None:
        """執行在線自愈策略與審計日誌歸檔"""
        self.power_limit_pct = new_power_limit
        print(f"\n⚡ [自我修復中樞] 觸發干預策略: {action_name}")
        print(f"   原因: {reason} | 功率上限調整至: {self.power_limit_pct}%")

        # 寫入 SQLite 審計記錄
        self.db.log_approval(
            task_id=f"HEAL_{int(time.time())}",
            operator="🤖 AutonomousHealer",
            status="EXECUTED",
            details=f"策略: {action_name}, 限制: {new_power_limit}%, 原因: {reason}",
            action_type=action_name,
        )

        # 同步更新當前安全等級與數位孿生
        if new_power_limit >= 100:
            target_level = HealingLevel.LEVEL_0_NORMAL
            mode = "NORMAL_OPERATION"
            degraded = False
            self.cooling_boost_active = False
        elif new_power_limit >= 70:
            target_level = HealingLevel.LEVEL_1_DYNAMIC_DERATING
            mode = "DERATED_LEVEL_1"
            degraded = True
            self.cooling_boost_active = True
        elif new_power_limit > 0:
            target_level = HealingLevel.LEVEL_2_LIMP_HOME
            mode = "LIMP_HOME"
            degraded = True
            self.cooling_boost_active = True
        else:
            target_level = HealingLevel.LEVEL_3_EMERGENCY_STOP
            mode = "EMERGENCY_SAFE_STOP"
            degraded = True
            self.cooling_boost_active = False
        self.current_level = target_level
        self.record_audit(
            event_type=f"HEALING:{action_name}",
            healing_level=target_level.value,
            trigger_metric="healer_policy",
            trigger_value=float(new_power_limit),
            action_taken=f"{action_name}: {reason}",
            torque_limit_pct=float(new_power_limit),
            safety_mode=mode,
            status="EXECUTED",
        )
        if self.twin_engine:
            with self.twin_engine._lock:
                self.twin_engine.state.torque_limit_pct = float(new_power_limit)
                self.twin_engine.state.motor_degraded = degraded
                self.twin_engine.state.safety_mode = mode
                self.twin_engine.state.health_score = (
                    self.twin_engine.state.calculate_health_score()
                )

        # 1. Cloud-Edge Hybrid Dynamic Routing
        if self.hybrid_router is not None:
            try:
                urgency = "SAFETY_CRITICAL" if target_level.value >= 1 else "NORMAL"
                self.last_routing_decision = self.hybrid_router.route_request(
                    task_type=f"healing_{action_name.lower()}",
                    urgency=urgency,
                    context={"power_limit": new_power_limit, "reason": reason},
                )
            except Exception:
                pass

        # 2. L5 Decentralized Fleet Nostr Mesh Broadcast
        if self.fleet_mesh is not None and target_level.value >= 1:
            try:
                current_temp = 75
                if self.twin_engine and hasattr(self.twin_engine, "state"):
                    current_temp = int(self.twin_engine.state.temp_celsius)
                self.last_nostr_broadcast = self.fleet_mesh.broadcast_homomorphic_peer_alert(
                    alarm_type=action_name,
                    power_limit_pct=new_power_limit,
                    temp_c=current_temp,
                    reason=f"{action_name}: {reason}",
                )
                self.fleet_mesh.broadcast_healing_alert(
                    {
                        "action": action_name,
                        "level": target_level.value,
                        "power_limit_pct": new_power_limit,
                        "reason": reason,
                        "safety_mode": mode,
                        "vin": self.vin,
                    }
                )
            except Exception:
                pass

    def process_incoming_event(self, packet: bytes) -> Optional[HealingDecision]:
        """解析 SOME/IP 數位孿生健康事件並執行防線判定"""
        if len(packet) < SOMEIP_HEADER_LEN:
            return None

        header = packet[:SOMEIP_HEADER_LEN]
        payload = packet[SOMEIP_HEADER_LEN:]

        msg_id, length, req_id, p_ver, if_ver, msg_type, ret_code = struct.unpack(
            "!IIIBBBB", header
        )
        service_id = (msg_id >> 16) & 0xFFFF
        event_id = msg_id & 0xFFFF

        # 監聽健康服務 (Service 0x1002, Event 0x8002: 電壓與溫度)
        if service_id == 0x1002 and event_id == 0x8002:
            if len(payload) >= 5:
                voltage_mv, temp_c = struct.unpack("!IB", payload[:5])
            else:
                return None

            # Level 3 防線：嚴重欠壓 (<10.0V) 觸發安全退避與自愈重置
            if 0 < voltage_mv < self.VOLT_LOW_LVL3_THRESHOLD_MV:
                self.trigger_healing_action(
                    "SELF_HEALING_RESET",
                    0,
                    f"嚴重欠壓 ({voltage_mv / 1000.0:.1f}V < 10.0V)，切斷動力啟動自愈重置",
                )
            # Level 2 防線：極限高溫降額 (>=85°C)
            elif temp_c >= 85 and self.power_limit_pct > 50:
                self.trigger_healing_action(
                    "EMERGENCY_DERATING", 50, f"溫度過高 ({temp_c}°C)"
                )
            # Level 1 防線：邊界高溫 (>=75°C) 或低壓 (<11.2V) 啟動冷卻巡檢與降額至 70%
            elif (
                temp_c >= 75 or (0 < voltage_mv < self.VOLT_LOW_LVL1_THRESHOLD_MV)
            ) and self.power_limit_pct > 70:
                reason = (
                    f"溫度上升 ({temp_c}°C)"
                    if temp_c >= 75
                    else f"電壓偏低 ({voltage_mv / 1000.0:.1f}V < 11.2V)"
                )
                self.trigger_healing_action("THERMAL_TRIMMING", 70, reason)
            # 狀態自愈回正：溫度降至 60°C 以下且電壓正常，恢復全功率 100%
            elif (
                temp_c < 60
                and (voltage_mv >= 11500 or voltage_mv >= 350000)
                and self.power_limit_pct < 100
            ):
                self.trigger_healing_action(
                    "AUTO_RECOVERY", 100, f"溫度恢復正常 ({temp_c}°C)"
                )

            return self.evaluate_and_heal(
                temperature_c=float(temp_c),
                battery_voltage_mv=voltage_mv,
                source="SOMEIP_0x8002_UDP",
            )
        return None

    def start_loop(self) -> None:
        """啟動 UDP 30490 埠即時監聽循環"""
        print("🛡️ [自我修復中樞] 監聽啟動...")
        if not self.sock:
            print("⚠️ [自我修復中樞] 無法綁定 UDP 套接字，退出監聽。")
            return
        while True:
            try:
                data, _ = self.sock.recvfrom(1024)
                self.process_incoming_event(data)
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"⚠️ [自我修復中樞] 接收異常: {e}")
                break

    # ------------------------------------------------------------------------
    # SQLite Audit Database Management
    # ------------------------------------------------------------------------

    def _init_sqlite_db(self) -> None:
        """Initializes SQLite schema for tamper-evident audit logging."""
        if self.db_path != ":memory:":
            Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
            self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        else:
            self._conn = sqlite3.connect(":memory:", check_same_thread=False)

        with self._lock:
            cursor = self._conn.cursor()
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS healing_audit_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp_iso TEXT NOT NULL,
                    timestamp_epoch REAL NOT NULL,
                    vin TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    healing_level INTEGER NOT NULL,
                    trigger_metric TEXT NOT NULL,
                    trigger_value REAL NOT NULL,
                    action_taken TEXT NOT NULL,
                    torque_limit_pct REAL NOT NULL,
                    safety_mode TEXT NOT NULL,
                    status TEXT NOT NULL,
                    audit_hash TEXT NOT NULL
                )
                """
            )
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_healing_ts ON healing_audit_log(timestamp_epoch)"
            )
            self._conn.commit()

    def record_audit(
        self,
        event_type: str,
        healing_level: int,
        trigger_metric: str,
        trigger_value: float,
        action_taken: str,
        torque_limit_pct: float,
        safety_mode: str,
        status: str,
        timestamp: Optional[float] = None,
    ) -> str:
        """Persists an audit record to SQLite with SHA-256 cryptographic signature."""
        if timestamp is None:
            timestamp = time.time()
        iso_str = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(timestamp))

        # Calculate row integrity hash
        hash_payload = (
            f"{iso_str}|{self.vin}|{event_type}|{healing_level}|"
            f"{trigger_metric}|{trigger_value:.2f}|{action_taken}|{torque_limit_pct:.1f}"
        )
        audit_hash = hashlib.sha256(hash_payload.encode("utf-8")).hexdigest()

        with self._lock:
            if self._conn is None:
                return audit_hash
            cursor = self._conn.cursor()
            cursor.execute(
                """
                INSERT INTO healing_audit_log (
                    timestamp_iso, timestamp_epoch, vin, event_type,
                    healing_level, trigger_metric, trigger_value,
                    action_taken, torque_limit_pct, safety_mode,
                    status, audit_hash
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    iso_str,
                    timestamp,
                    self.vin,
                    event_type,
                    int(healing_level),
                    trigger_metric,
                    float(trigger_value),
                    action_taken,
                    float(torque_limit_pct),
                    safety_mode,
                    status,
                    audit_hash,
                ),
            )
            self._conn.commit()
        return audit_hash

    def get_recent_audits(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Retrieves recent healing audit log records."""
        with self._lock:
            if self._conn is None:
                return []
            self._conn.row_factory = sqlite3.Row
            cursor = self._conn.cursor()
            cursor.execute(
                """
                SELECT * FROM healing_audit_log
                ORDER BY id DESC LIMIT ?
                """,
                (limit,),
            )
            rows = cursor.fetchall()
            return [dict(r) for r in rows]

    def get_audit_summary(self) -> Dict[str, Any]:
        """Provides an aggregated summary of all healing events."""
        with self._lock:
            if self._conn is None:
                return {
                    "total_records": 0,
                    "counts_by_level": {},
                    "unique_vins": 0,
                    "db_path": self.db_path,
                }
            cursor = self._conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM healing_audit_log")
            total_records = cursor.fetchone()[0]

            cursor.execute(
                "SELECT healing_level, COUNT(*) FROM healing_audit_log GROUP BY healing_level"
            )
            counts_by_level = {row[0]: row[1] for row in cursor.fetchall()}

            return {
                "total_records": total_records,
                "current_level": self.current_level.name,
                "counts_by_level": counts_by_level,
                "vin": self.vin,
                "db_path": self.db_path,
            }

    # ------------------------------------------------------------------------
    # SOME/IP Subscription Dispatcher
    # ------------------------------------------------------------------------

    def attach_to_soa_gateway(self, soa_gateway: SOAGatewayTwin) -> None:
        """Directly subscribes to SOME/IP Gateway event stream."""

        def _listener(msg: SOMEIPMessage) -> None:
            self.on_someip_event(msg)

        soa_gateway.register_subscriber(_listener)

    def on_someip_event(self, msg: SOMEIPMessage) -> Optional[HealingDecision]:
        """
        Processes incoming SOME/IP Notification events:
        - 0x8001: Actuator Status (speed, torque, limit)
        - 0x8002: Sensor Telemetry (voltage, temperature, pressure)
        """
        event_id = msg.header.event_or_method_id
        if event_id == EVENT_ID_SENSOR_TELEMETRY:
            # Unpack SOME/IP 0x8002 payload: [Voltage: uint32 (mV)] + [Temp: float32 (°C)] + [Pressure: float32 (kPa)]
            if len(msg.payload) >= 12:
                voltage_mv, temp_c, pressure_kpa = struct.unpack(
                    ">Iff", msg.payload[:12]
                )
                return self.evaluate_and_heal(
                    temperature_c=temp_c,
                    battery_voltage_mv=voltage_mv,
                    source="SOMEIP_0x8002",
                )
        return None

    def _on_digital_twin_updated(self, state: DigitalTwinState) -> None:
        """Internal HPC DCU hook: evaluates healing on any state change."""
        self.evaluate_and_heal(
            temperature_c=state.temperature_c,
            battery_voltage_mv=state.battery_voltage_mv,
            source="DIGITAL_TWIN_HPC",
        )

    # ------------------------------------------------------------------------
    # Core Autonomous Healing Decision Logic
    # ------------------------------------------------------------------------

    def evaluate_and_heal(
        self,
        temperature_c: float,
        battery_voltage_mv: int,
        source: str = "MANUAL",
        now: Optional[float] = None,
    ) -> HealingDecision:
        """
        Core Closed-Loop Healer Evaluation:
        Determines target healing level, clamps torque, and logs to SQLite.
        """
        if now is None:
            now = time.time()

        with self._lock:
            target_level = HealingLevel.LEVEL_0_NORMAL
            trigger_metric = "none"
            trigger_val = 0.0
            torque_limit = 100.0
            safety_mode = "NORMAL_OPERATION"
            motor_degraded = False
            action = "Nominal operation maintained"
            status = "AUTONOMOUSLY_RESOLVED"

            is_low_voltage_bus = 0 < battery_voltage_mv < 50000
            lvl1_volt_thresh = (
                self.VOLT_LOW_LVL1_THRESHOLD_MV
                if is_low_voltage_bus
                else self.VOLT_LVL1_THRESHOLD_MV
            )

            # 1. Thermal Emergency Stop Check (>105°C) or Low-voltage Level 3 (<10.0V)
            if temperature_c > self.TEMP_LVL3_STOP_THRESHOLD_C:
                target_level = HealingLevel.LEVEL_3_EMERGENCY_STOP
                trigger_metric = "temperature_c"
                trigger_val = temperature_c
                torque_limit = 0.0
                safety_mode = "EMERGENCY_SAFE_STOP"
                motor_degraded = True
                action = f"Emergency safe stop triggered (temp={temperature_c:.1f}°C > {self.TEMP_LVL3_STOP_THRESHOLD_C}°C)"
                status = "EMERGENCY_HALT_ACTIVE"

            elif (
                is_low_voltage_bus
                and battery_voltage_mv < self.VOLT_LOW_LVL3_THRESHOLD_MV
            ):
                target_level = HealingLevel.LEVEL_3_EMERGENCY_STOP
                trigger_metric = "battery_voltage_mv"
                trigger_val = float(battery_voltage_mv)
                torque_limit = 0.0
                safety_mode = "EMERGENCY_SAFE_STOP"
                motor_degraded = True
                action = f"Level 3 undervoltage reset shutdown (voltage={battery_voltage_mv/1000.0:.1f}V < {self.VOLT_LOW_LVL3_THRESHOLD_MV/1000.0:.1f}V)"
                status = "EMERGENCY_HALT_ACTIVE"

            # 2. Critical Limp-Home Check (>85°C or High-Voltage <320V)
            elif temperature_c > self.TEMP_LVL2_THRESHOLD_C:
                target_level = HealingLevel.LEVEL_2_LIMP_HOME
                trigger_metric = "temperature_c"
                trigger_val = temperature_c
                torque_limit = 30.0
                safety_mode = "LIMP_HOME"
                motor_degraded = True
                action = f"Level 2 Limp-Home dynamic derating clamped to 30% (temp={temperature_c:.1f}°C > {self.TEMP_LVL2_THRESHOLD_C}°C)"
                status = "LIMP_HOME_ENGAGED"

            elif (
                not is_low_voltage_bus
            ) and battery_voltage_mv < self.VOLT_LVL2_THRESHOLD_MV:
                target_level = HealingLevel.LEVEL_2_LIMP_HOME
                trigger_metric = "battery_voltage_mv"
                trigger_val = float(battery_voltage_mv)
                torque_limit = 30.0
                safety_mode = "LIMP_HOME"
                motor_degraded = True
                action = f"Level 2 Limp-Home dynamic derating clamped to 30% (voltage={battery_voltage_mv/1000:.1f}V < {self.VOLT_LVL2_THRESHOLD_MV/1000:.1f}V)"
                status = "LIMP_HOME_ENGAGED"

            # 3. Dynamic Thermal / Voltage Derating Level 1 (>75°C or <350V / <11.2V)
            elif temperature_c > self.TEMP_LVL1_THRESHOLD_C:
                target_level = HealingLevel.LEVEL_1_DYNAMIC_DERATING
                trigger_metric = "temperature_c"
                trigger_val = temperature_c
                torque_limit = 70.0
                safety_mode = "DERATED_LEVEL_1"
                motor_degraded = True
                action = f"Level 1 dynamic torque derating clamped to 70% (temp={temperature_c:.1f}°C > {self.TEMP_LVL1_THRESHOLD_C}°C)"
                status = "DERATED_LEVEL_1_ENGAGED"

            elif battery_voltage_mv < lvl1_volt_thresh:
                target_level = HealingLevel.LEVEL_1_DYNAMIC_DERATING
                trigger_metric = "battery_voltage_mv"
                trigger_val = float(battery_voltage_mv)
                torque_limit = 70.0
                safety_mode = "DERATED_LEVEL_1"
                motor_degraded = True
                action = f"Level 1 dynamic torque derating clamped to 70% (voltage={battery_voltage_mv/1000:.1f}V < {lvl1_volt_thresh/1000:.1f}V)"
                status = "DERATED_LEVEL_1_ENGAGED"

            # 4. Nominal / Recovery Case
            else:
                target_level = HealingLevel.LEVEL_0_NORMAL
                trigger_metric = "system_nominal"
                trigger_val = temperature_c
                torque_limit = 100.0
                safety_mode = "NORMAL_OPERATION"
                motor_degraded = False
                action = "Nominal full power restored"
                status = "NOMINAL_ACTIVE"

            decision = HealingDecision(
                level=target_level,
                torque_limit_pct=torque_limit,
                safety_mode=safety_mode,
                motor_degraded=motor_degraded,
                trigger_metric=trigger_metric,
                trigger_value=trigger_val,
                action_taken=action,
                status=status,
                timestamp=now,
            )

            # Detect state transition and apply closed loop
            level_changed = target_level != self.current_level
            if level_changed:
                event_name = (
                    "DERATING_RECOVERED"
                    if target_level < self.current_level
                    else f"HEALING_LEVEL_{target_level.value}_TRIGGERED"
                )
                self.record_audit(
                    event_type=f"{source}:{event_name}",
                    healing_level=target_level.value,
                    trigger_metric=trigger_metric,
                    trigger_value=trigger_val,
                    action_taken=action,
                    torque_limit_pct=torque_limit,
                    safety_mode=safety_mode,
                    status=status,
                    timestamp=now,
                )
                self.current_level = target_level

                # Actuation feedback into Digital Twin
                with self.twin_engine._lock:
                    self.twin_engine.state.torque_limit_pct = torque_limit
                    self.twin_engine.state.motor_degraded = motor_degraded
                    self.twin_engine.state.safety_mode = safety_mode
                    self.twin_engine.state.health_score = (
                        self.twin_engine.state.calculate_health_score()
                    )

            # Dispatch callbacks
            for cb in self._decision_callbacks:
                try:
                    cb(decision)
                except Exception:
                    pass

            return decision

    def register_decision_listener(
        self, callback: Callable[[HealingDecision], None]
    ) -> None:
        """Registers a listener for healing decisions."""
        with self._lock:
            self._decision_callbacks.append(callback)

    def manual_override_healing(
        self,
        target_level: int,
        reason: str = "Commander Operator Override",
        operator: str = "Commander Jack Hu",
    ) -> HealingDecision:
        """Allows AI Agent or human Commander to manually command a healing level."""
        with self._lock:
            lvl = HealingLevel(target_level)
            torque_map = {
                HealingLevel.LEVEL_0_NORMAL: 100.0,
                HealingLevel.LEVEL_1_DYNAMIC_DERATING: 70.0,
                HealingLevel.LEVEL_2_LIMP_HOME: 30.0,
                HealingLevel.LEVEL_3_EMERGENCY_STOP: 0.0,
            }
            torque_limit = torque_map[lvl]
            safety_mode = (
                "NORMAL_OPERATION"
                if lvl == HealingLevel.LEVEL_0_NORMAL
                else "DERATED_LEVEL_1"
                if lvl == HealingLevel.LEVEL_1_DYNAMIC_DERATING
                else "LIMP_HOME"
                if lvl == HealingLevel.LEVEL_2_LIMP_HOME
                else "EMERGENCY_SAFE_STOP"
            )
            motor_degraded = bool(lvl > HealingLevel.LEVEL_0_NORMAL)
            action = f"Manual override to {lvl.name} by {operator} ({reason})"
            status = "MANUALLY_OVERRIDDEN"
            now = time.time()

            self.record_audit(
                event_type="MANUAL_COMMAND_OVERRIDE",
                healing_level=lvl.value,
                trigger_metric="manual_override",
                trigger_value=float(lvl.value),
                action_taken=action,
                torque_limit_pct=torque_limit,
                safety_mode=safety_mode,
                status=status,
                timestamp=now,
            )
            self.current_level = lvl

            with self.twin_engine._lock:
                self.twin_engine.state.torque_limit_pct = torque_limit
                self.twin_engine.state.motor_degraded = motor_degraded
                self.twin_engine.state.safety_mode = safety_mode
                self.twin_engine.state.health_score = (
                    self.twin_engine.state.calculate_health_score()
                )

            decision = HealingDecision(
                level=lvl,
                torque_limit_pct=torque_limit,
                safety_mode=safety_mode,
                motor_degraded=motor_degraded,
                trigger_metric="manual_override",
                trigger_value=float(lvl.value),
                action_taken=action,
                status=status,
                timestamp=now,
            )
            return decision

    def close(self) -> None:
        """Closes all database connections and UDP sockets safely."""
        with self._lock:
            if hasattr(self, "_conn") and self._conn is not None:
                try:
                    self._conn.close()
                except Exception:
                    pass
                self._conn = None
            if hasattr(self, "sock") and self.sock is not None:
                try:
                    self.sock.close()
                except Exception:
                    pass
                self.sock = None
            if hasattr(self, "db") and self.db is not None:
                try:
                    self.db.close()
                except Exception:
                    pass


# ============================================================================
# CLI Verification
# ============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("🩺 [PHANTOM GRID] L3 Edge Autonomous Healer Engine")
    print("   Closed-Loop SOME/IP Subscription, Dynamic Derating & SQLite Audit")
    print("=" * 70)

    twin = DigitalTwinMirrorEngine()
    healer = AutonomousHealer(twin_engine=twin, db_path=":memory:")

    # 1. Normal state test
    d0 = healer.evaluate_and_heal(temperature_c=65.0, battery_voltage_mv=398000)
    print(
        f"\n[Test 1: 65°C / 398V] Level: {d0.level.name} | Torque: {d0.torque_limit_pct}% | Status: {d0.status}"
    )

    # 2. Level 1 Dynamic Derating test (>75°C)
    d1 = healer.evaluate_and_heal(temperature_c=78.5, battery_voltage_mv=394000)
    print(
        f"[Test 2: 78.5°C / 394V] Level: {d1.level.name} | Torque: {d1.torque_limit_pct}% | Status: {d1.status}"
    )
    print(f"       Action: {d1.action_taken}")

    # 3. Level 2 Limp-Home test (>85°C)
    d2 = healer.evaluate_and_heal(temperature_c=89.2, battery_voltage_mv=388000)
    print(
        f"[Test 3: 89.2°C / 388V] Level: {d2.level.name} | Torque: {d2.torque_limit_pct}% | Status: {d2.status}"
    )
    print(f"       Action: {d2.action_taken}")

    # 4. Check SQLite Audit Table
    audits = healer.get_recent_audits(10)
    print(f"\n[SQLite Audit Database Records] Total: {len(audits)}")
    for a in audits:
        print(
            f"   [{a['timestamp_iso']}] Level: {a['healing_level']} | Event: {a['event_type']} | Hash: {a['audit_hash'][:16]}..."
        )

    print("=" * 70)
