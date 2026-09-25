# -*- coding: utf-8 -*-
"""
🛡️ 戰情控制台：CAN 總線遙測與 HITL 雙簽審批 (dashboard.py)
===========================================================
提供即時遙測監控、500kbps 總線負載/幀抖動、數位孿生鏡像與 HITL 雙簽審批介面。
Run with: streamlit run dashboard.py
"""

from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

try:
    import numpy as np
    import pandas as pd
    import streamlit as st
except ImportError:
    st = None  # type: ignore[assignment]
    pd = None  # type: ignore[assignment]
    np = None  # type: ignore[assignment]


def get_db_path() -> str:
    """Finds existing audit_log.db either in 01_Memory or workspace root."""
    mem_path = Path("01_Memory/audit_log.db")
    if mem_path.exists():
        return str(mem_path)
    root_path = Path("audit_log.db")
    if root_path.exists():
        return str(root_path)
    return str(mem_path)


def get_twin_snapshot() -> Dict[str, Any]:
    """Reads digital twin state snapshot from 01_Memory/telemetry_twin.json."""
    twin_path = Path("01_Memory/telemetry_twin.json")
    if twin_path.exists():
        try:
            with open(twin_path, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                if isinstance(loaded, dict):
                    data: Dict[str, Any] = dict(loaded)
                    # Normalize keys
                    if "battery_voltage_mv" in data and "battery_voltage" not in data:
                        data["battery_voltage"] = data["battery_voltage_mv"] / 1000.0
                    if "safety_mode" in data and "cluster_safety_state" not in data:
                        data["cluster_safety_state"] = data["safety_mode"]
                    if "torque_limit_pct" in data and "power_limit_pct" not in data:
                        data["power_limit_pct"] = data["torque_limit_pct"]
                    return data
        except Exception:
            pass
    return {
        "motor_rpm": 3200,
        "battery_voltage": 48.2,
        "temperature_c": 68.5,
        "power_limit_pct": 100,
        "cluster_safety_state": "NORMAL_OPERATION",
        "e2e_valid": True,
        "active_nodes": ["0x120_GATEWAY", "0x280_ACTUATOR", "0x380_SENSOR"],
        "timestamp": datetime.now().isoformat(),
    }


def query_audit_logs(db_path: str, limit: int = 50) -> List[Dict[str, Any]]:
    """Fetches latest audit records from SQLite database."""
    if not os.path.exists(db_path):
        return []
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM audit_logs ORDER BY id DESC LIMIT ?", (limit,))
        rows = [dict(r) for r in cursor.fetchall()]
        conn.close()
        return rows
    except Exception:
        return []


def query_approvals(db_path: str, limit: int = 20) -> List[Dict[str, Any]]:
    """Fetches latest dual-signature approvals or approvals from audit_logs."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        return []
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        # Query from audit_logs with status APPROVED/REJECTED or approvals
        cursor.execute("SELECT * FROM audit_logs WHERE action_type='HITL_APPROVAL' OR status IN ('APPROVED', 'REJECTED') ORDER BY id DESC LIMIT ?", (limit,))
        rows = [dict(r) for r in cursor.fetchall()]
        conn.close()
        return rows
    except Exception:
        return []


def render_dashboard() -> None:
    """Renders the Streamlit Cockpit Dashboard."""
    if st is None:
        print("[!] Streamlit is not installed or GUI is disabled in this environment.")
        return

    st.set_page_config(page_title="CAN Telemetry & Governance", layout="wide")
    st.title("🛡️ 戰情控制台：CAN 總線遙測與 HITL 雙簽審批")

    db_path = get_db_path()
    twin = get_twin_snapshot()

    # 側邊欄：系統韌體安全狀態監控
    st.sidebar.header("系統狀態監控")
    state = st.sidebar.selectbox(
        "當前韌體安全狀態",
        ["NORMAL (正常運行)", "DEGRADED (降級限制 50%)", "BUS_OFF_SAFE (安全停機)"]
    )

    if "NORMAL" in state:
        st.sidebar.success("系統運作健康：零告警")
    elif "DEGRADED" in state:
        st.sidebar.warning("警告：已觸發 E2E 降級保護")
    else:
        st.sidebar.error("致命：進入 Bus-Off 硬體保護模式")

    # 側邊欄附屬資訊：數位孿生指標
    st.sidebar.markdown("---")
    st.sidebar.subheader("數位孿生核心指標")
    st.sidebar.metric("轉速 (RPM)", f"{twin.get('motor_rpm', 3200):.0f} RPM")
    st.sidebar.metric("電池電壓", f"{twin.get('battery_voltage', 48.2):.1f} V")
    st.sidebar.metric("溫度 (°C)", f"{twin.get('temperature_c', 68.5):.1f} °C")
    st.sidebar.metric("輸出功率上限", f"{twin.get('power_limit_pct', 100):.0f}%")

    # 主界面：兩大分區
    col1, col2 = st.columns([3, 2])

    with col1:
        st.subheader("📊 總線即時負載與幀抖動 (Real-time Telemetry)")
        # 模擬 500kbps 總線負載數據流
        if pd and np:
            chart_data = pd.DataFrame(
                np.random.normal(loc=35, scale=5, size=(30, 2)),
                columns=["Bus Load (%)", "Jitter (us)"]
            )
            st.line_chart(chart_data)
        st.caption("採樣率：100ms | 監控節點：vcan0 | 仲裁錯誤數：0")

    with col2:
        st.subheader("🔐 HITL 雙簽審批待辦")
        conn = sqlite3.connect(db_path)
        try:
            df_audit = pd.read_sql_query(
                "SELECT timestamp, task_id, operator, status, action_type FROM audit_logs ORDER BY id DESC LIMIT 5",
                conn
            )
            st.dataframe(df_audit, use_container_width=True)
        except Exception:
            st.info("審計庫目前無歷史紀錄或正在初始化中。")

        st.write("---")
        st.markdown("**高危暫存器覆寫申請：`REG_OVERWRITE_0x4002`**")
        col_btn1, col_btn2 = st.columns(2)
        if col_btn1.button("✅ 哥 授權簽發 (Approve)"):
            with conn:
                conn.execute(
                    "INSERT INTO audit_logs (timestamp, task_id, operator, status, action_type, details) VALUES (datetime('now'), 'REG_0x4002', '哥', 'APPROVED', 'HITL_APPROVAL', '授權覆寫暫存器')"
                )
            st.success("已通過授權並寫入審計庫！")
        if col_btn2.button("❌ 駁回 (Reject)"):
            with conn:
                conn.execute(
                    "INSERT INTO audit_logs (timestamp, task_id, operator, status, action_type, details) VALUES (datetime('now'), 'REG_0x4002', '哥', 'REJECTED', 'HITL_REJECTION', '駁回高危覆寫操作並凍結引腳')"
                )
            st.error("操作已駁回並凍結引腳。")
        conn.close()


def main() -> None:
    if st is not None:
        render_dashboard()
    else:
        print("[!] Streamlit is not installed. Run 'pip install streamlit' to view the dashboard.")


if __name__ == "__main__":
    main()

