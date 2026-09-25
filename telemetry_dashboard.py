# -*- coding: utf-8 -*-
"""
Real-Time Telemetry Dashboard & Web HITL Dual-Signature Approval Center
Axis 2: Visual battle situation dashboard & one-click Commander Jack Hu authorization.
"""

from __future__ import annotations

import argparse
import random
import sys
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from audit_governance import GovernanceDB
from e2e_state_matrix import Iso26262SafetyStateMachine, Iso26262State


@dataclass
class TelemetrySnapshot:
    timestamp: float
    bus_load_pct: float
    frame_jitter_us: float
    alive_counter: int
    motor_rpm: int
    battery_mv: int
    motor_temp_c: float
    safety_state: str
    pwm_limit_pct: float
    active_dtc: Optional[str] = None


class TelemetryStreamEngine:
    """
    Simulates / processes real-time telemetry stream from CAN bus and state machine.
    """

    def __init__(
        self,
        state_machine: Optional[Iso26262SafetyStateMachine] = None,
        db_path: str = "audit_log.db",
    ) -> None:
        self.state_machine = state_machine or Iso26262SafetyStateMachine()
        self.db = GovernanceDB(db_path=db_path)
        self.rolling_counter = 0

    def generate_snapshot(self) -> TelemetrySnapshot:
        """Generates a high-fidelity real-time telemetry frame snapshot."""
        self.rolling_counter = (self.rolling_counter + 1) & 0x0F
        st = self.state_machine.state.value

        # Calculate dynamic bus load & jitter according to state
        if st == Iso26262State.STATE_NORMAL.value:
            load = round(random.uniform(25.0, 42.0), 1)
            jitter = round(random.uniform(5.0, 18.0), 1)
            rpm = random.randint(7800, 8500)
            temp = round(random.uniform(55.0, 68.0), 1)
        elif st == Iso26262State.STATE_DEGRADED.value:
            load = round(random.uniform(55.0, 75.0), 1)
            jitter = round(random.uniform(45.0, 95.0), 1)
            rpm = random.randint(4000, 4500)  # Clamped to 50%
            temp = round(random.uniform(72.0, 84.0), 1)
        else:  # BUS_OFF_SAFE / HARD_FAULT
            load = round(random.uniform(88.0, 98.0), 1)
            jitter = round(random.uniform(150.0, 320.0), 1)
            rpm = 0
            temp = round(random.uniform(85.0, 95.0), 1)

        return TelemetrySnapshot(
            timestamp=time.time(),
            bus_load_pct=load,
            frame_jitter_us=jitter,
            alive_counter=self.rolling_counter,
            motor_rpm=rpm,
            battery_mv=random.randint(12300, 12600),
            motor_temp_c=temp,
            safety_state=st,
            pwm_limit_pct=self.state_machine.power_limit_pct,
            active_dtc=self.state_machine.active_dtc,
        )

    def get_traffic_light_color(self) -> Tuple[str, str, str]:
        """
        Returns (Color, Label, Description) for the safety state:
        - GREEN: NORMAL
        - YELLOW: DEGRADED
        - RED: BUS_OFF_SAFE / HARD_FAULT / RESET
        """
        st = self.state_machine.state
        if st == Iso26262State.STATE_NORMAL:
            return "🟢 綠燈 (NORMAL)", "正常運轉", "系統運作健康：全功率 100% 輸出，零告警"
        elif st == Iso26262State.STATE_DEGRADED:
            return "🟡 黃燈 (DEGRADED)", "降額運轉", "警告：偵測到連續 E2E 異常，輸出已限縮至 50%"
        elif st == Iso26262State.STATE_BUS_OFF_SAFE:
            return "🔴 紅燈 (BUS_OFF_SAFE)", "總線隔離", "致命：CAN TEC > 255，0ms PWM 切斷，快速重啟中"
        elif st == Iso26262State.STATE_HARD_FAULT:
            return "🔴 紅燈 (HARD_FAULT)", "永久鎖死", f"嚴重故障：重啟超限，DTC {self.state_machine.active_dtc} 鎖止"
        else:
            return "🔴 紅燈 (RESET)", "看門狗重置", "硬體重置引腳觸發，強制重啟中"

    def approve_task_by_brother(self, task_id: str, details: str = "") -> bool:
        """
        HITL Quick Dual-Signature: Commander Jack Hu one-click approval.
        Immediately writes APPROVED status into SQLite audit log.
        """
        self.db.log_approval(
            task_id=task_id,
            operator="哥",
            status="APPROVED",
            details=details or f"哥 親自簽署核准高危操作 ({task_id})",
            action_type="HITL_WEB_APPROVAL",
        )
        return True

    def reject_task_by_brother(self, task_id: str, reason: str = "") -> bool:
        """
        HITL Quick Dual-Signature: Commander Jack Hu one-click rejection.
        Immediately writes REJECTED status into SQLite audit log.
        """
        self.db.log_approval(
            task_id=task_id,
            operator="哥",
            status="REJECTED",
            details=reason or f"哥 駁回並凍結操作 ({task_id})",
            action_type="HITL_WEB_REJECTION",
        )
        return True

    def query_recent_audit_logs(self, limit: int = 5) -> List[Dict[str, Any]]:
        """Queries recent audit logs from SQLite."""
        return self.db.query_logs(limit=limit)


def render_cli_preview(engine: TelemetryStreamEngine) -> None:
    """Renders a text preview of the dashboard for terminal / headless verification."""
    print("=" * 65)
    print("🚀 [PHANTOM GRID] 車載即時戰情遙測與 HITL 雙簽審批中心 (CLI Preview)")
    print("=" * 65)
    snap = engine.generate_snapshot()
    color_tag, label, desc = engine.get_traffic_light_color()

    print(f"📡 系統狀態燈: {color_tag} [{label}] - {desc}")
    print(f"📊 CAN 總線負載: {snap.bus_load_pct}% | 幀間抖動 (Jitter): {snap.frame_jitter_us} μs")
    print(f"⚡ Alive Counter: 0x{snap.alive_counter:X} | 電機轉速: {snap.motor_rpm} RPM | 功率限制: {snap.pwm_limit_pct}%")
    print(f"🔋 電池電壓: {snap.battery_mv} mV | 電機溫度: {snap.motor_temp_c} °C")
    print("-" * 65)
    print("🏛️ 最近 3 筆 SQLite 審計記錄 (audit_log.db):")
    logs = engine.query_recent_audit_logs(limit=3)
    for log_item in logs:
        print(f" - [{log_item['timestamp']}] ({log_item['operator']}) [{log_item['task_id']}] -> {log_item['status']}: {log_item['details'][:45]}...")
    print("=" * 65)


def run_streamlit_app() -> None:
    """Streamlit Web Application entry point."""
    try:
        import streamlit as st
    except ImportError:
        print("Streamlit not installed, falling back to CLI preview.")
        render_cli_preview(TelemetryStreamEngine())
        return

    st.set_page_config(page_title="PHANTOM GRID 戰情儀表板", page_icon="🚗", layout="wide")
    st.title("🚗 PHANTOM GRID 車載即時戰情遙測與 HITL 雙簽審批中心")

    engine = TelemetryStreamEngine()
    snap = engine.generate_snapshot()
    color_tag, label, desc = engine.get_traffic_light_color()

    # Sidebar: Safety Status
    st.sidebar.header("🛡️ 安全防護狀態機")
    st.sidebar.markdown(f"### {color_tag}")
    st.sidebar.info(desc)
    st.sidebar.metric("功率限制 (Power Clamp)", f"{snap.pwm_limit_pct}%")

    # Main Grid: Telemetry
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("CAN 總線負載", f"{snap.bus_load_pct}%")
    col2.metric("幀間抖動 (Jitter)", f"{snap.frame_jitter_us} μs")
    col3.metric("電機轉速 (RPM)", f"{snap.motor_rpm} RPM")
    col4.metric("電機溫度", f"{snap.motor_temp_c} °C")

    # HITL Dual-Signature Approval Section
    st.subheader("🏛️ HITL 快速雙簽審批台")
    st.markdown("當前待處理高危指令：`REG_OVERWRITE_0x4002` (降額暫存器重配置)")
    col_btn1, col_btn2 = st.columns([1, 1])

    with col_btn1:
        if st.button("👑 哥 親簽授權 (Approve)", type="primary"):
            engine.approve_task_by_brother("REG_OVERWRITE_0x4002")
            st.success("✅ 授權簽發成功！審計日誌已秒級固化入庫。")

    with col_btn2:
        if st.button("❌ 駁回凍結 (Reject)"):
            engine.reject_task_by_brother("REG_OVERWRITE_0x4002")
            st.warning("⚠️ 提案已駁回，暫存器維持硬體安全鎖定。")

    # Audit Logs Table
    st.subheader("📋 最新 SQLite 審計軌跡 (audit_log.db)")
    logs = engine.query_recent_audit_logs(limit=5)
    st.table(logs)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="PHANTOM GRID Telemetry Dashboard")
    parser.add_argument("--cli", action="store_true", help="Run text CLI preview")
    args = parser.parse_args()

    engine = TelemetryStreamEngine()
    if args.cli or "streamlit" not in sys.modules:
        render_cli_preview(engine)
    else:
        run_streamlit_app()
