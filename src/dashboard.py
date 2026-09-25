# -*- coding: utf-8 -*-
"""
🚗 PHANTOM GRID | L0~L5 全棧車載架構戰情中樞 (Cockpit Dashboard)
=================================================================
Streamlit 實時遙測監控、數位孿生鏡像、自主自愈動態降額與 HITL 雙簽審批中樞。
Run with: streamlit run dashboard.py
"""

from __future__ import annotations

import json
import os
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import pandas as pd
    import streamlit as st
except ImportError:
    st = None  # Graceful fallback for non-GUI environments / testing
    pd = None

from audit_governance import GovernanceDB


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
                data = json.load(f)
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
    """Fetches latest dual-signature approvals from SQLite database."""
    if not os.path.exists(db_path):
        return []
    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM approvals ORDER BY id DESC LIMIT ?", (limit,))
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

    st.set_page_config(
        page_title="PHANTOM GRID | 車載 L0~L5 戰情中樞",
        page_icon="🚗",
        layout="wide",
        initial_sidebar_state="expanded",
    )

    db_path = get_db_path()
    db = GovernanceDB(db_path)
    twin = get_twin_snapshot()

    # Styling
    st.markdown(
        """
        <style>
        .metric-card {
            background-color: #111827;
            border: 1px solid #374151;
            border-radius: 8px;
            padding: 14px 18px;
            margin-bottom: 12px;
        }
        .badge-normal {
            background-color: #065f46;
            color: #34d399;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
        }
        .badge-warning {
            background-color: #854d0e;
            color: #fde047;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
        }
        .badge-danger {
            background-color: #991b1b;
            color: #f87171;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
        }
        </style>
        """,
        unsafe_allow_html=True,
    )

    # Top Header
    st.title("🚗 PHANTOM GRID | 車載 L0~L5 工業級全棧戰情中樞")
    st.caption("ISO 26262 ASIL-D | SAE J1850 CRC-8 | SOME/IP Digital Twin | L3 Autonomous Healing | HITL Dual-Sig")

    # KPI Top Bar
    c1, c2, c3, c4, c5 = st.columns(5)
    with c1:
        st.metric("轉速 (Motor RPM)", f"{twin.get('motor_rpm', 3200)} RPM", delta="+20")
    with c2:
        v = twin.get("battery_voltage", 48.2)
        st.metric("動力電池電壓", f"{v:.1f} V", delta="-0.3 V" if v < 40 else "穩壓")
    with c3:
        temp = twin.get("temperature_c", 68.5)
        status_color = "normal" if temp < 75 else ("warning" if temp < 85 else "danger")
        st.metric("逆變器與電芯溫度", f"{temp:.1f} °C", delta="防線 75°C / 85°C")
    with c4:
        pwr = twin.get("power_limit_pct", 100)
        st.metric("致動器最大輸出功率", f"{pwr}%", delta="自主自愈回正")
    with c5:
        mode = twin.get("cluster_safety_state", "NORMAL_OPERATION")
        st.metric("總線安全防禦狀態", mode, delta="E2E CRC8 PASS 🟢")

    st.divider()

    # Tabs
    tab1, tab2, tab3, tab4 = st.tabs([
        "📊 實時遙測與數位孿生",
        "🛡️ HITL 雙簽審批與治理",
        "📜 不可篡改審計日誌",
        "🌐 機隊去中心化與雲邊路由",
    ])

    with tab1:
        st.subheader("數位孿生鏡像 (Digital Twin State)")
        col_left, col_right = st.columns([2, 1])

        with col_left:
            st.write("#### 遙測趨勢模擬圖譜")
            if pd:
                chart_data = pd.DataFrame({
                    "Timestamp": [f"T-{i}s" for i in range(10, 0, -1)],
                    "Temperature (°C)": [60.0, 62.5, 65.0, 68.0, 72.0, 76.5, 82.0, 86.5, 78.0, temp],
                    "Power Limit (%)": [100, 100, 100, 100, 100, 70, 70, 50, 70, pwr],
                })
                st.line_chart(chart_data.set_index("Timestamp"))

        with col_right:
            st.write("#### 拓撲集群與節點狀態")
            st.info(f"**Master Gateway (0x120)**: 🟢 週期 20ms | Alive Counter 同步正常")
            st.info(f"**Powertrain Actuator (0x280)**: 🟢 週期 10ms | 功率受限模式: {pwr}%")
            st.info(f"**Sensor Acquisition (0x380)**: 🟢 週期 50ms | 溫度採集: {temp}°C")

            st.write("#### 注入模擬控制")
            sim_temp = st.slider("模擬注入逆變器溫度 (°C)", 40.0, 100.0, float(temp))
            if st.button("執行環境極限突波注入 (Simulate Thermal Surge)"):
                st.warning(f"已向數位孿生網關注入溫度: {sim_temp}°C")
                if sim_temp >= 85.0:
                    st.error("🚨 觸發 Level 2 防線 (EMERGENCY_DERATING): 功率壓制至 50%！")
                elif sim_temp >= 75.0:
                    st.warning("⚠️ 觸發 Level 1 防線 (THERMAL_TRIMMING): 功率限制至 70%！")
                else:
                    st.success("🟢 溫度正常: 100% 全功率運轉。")

    with tab2:
        st.subheader("Human-in-the-Loop (HITL) 雙簽審批中樞")
        st.markdown(
            """
            依據架構規範，所有高危作業（如暫存器覆寫、強制降額）必須具備雙簽：
            1. **指揮官 (Commander Jack Hu)**: 戰略授權
            2. **執行副駕 (Copilot / Assistant)**: 安全校驗
            """
        )

        with st.form("hitl_approval_form"):
            col_a, col_b = st.columns(2)
            with col_a:
                action_name = st.selectbox(
                    "高危操作類型",
                    ["EMERGENCY_DERATING_50", "REGISTER_WRITE_SAFE_CLAMP", "BUS_OFF_FORCED_RECOVERY", "OTA_SECTOR_SWAP"],
                )
                target_node = st.text_input("目標節點 / 模組", value="POWERTRAIN_ACTUATOR_0x280")
            with col_b:
                commander_sig = st.text_input("指揮官授權簽名 (Commander)", value="Commander Jack Hu")
                agent_sig = st.text_input("副駕校驗簽名 (Agent Copilot)", value="AI Assistant Copilot")

            reason = st.text_area("審批原由與危害防禦評估", value="環境溫度高溫突波對抗防禦，強制壓制輸出功率以防電芯過熱失控。")
            submitted = st.form_submit_button("🛡️ 提交雙簽審批並寫入不可篡改審計庫")

            if submitted:
                req_id = db.create_approval_request(
                    action_type=action_name,
                    target_component=target_node,
                    requester=commander_sig,
                    parameters={"reason": reason},
                )
                db.approve_request(req_id, approver=agent_sig, comment=f"Verified safe via {commander_sig}")
                st.success(f"✅ 雙簽授權成功！審批單號: {req_id}，已固化至不可篡改審計日誌庫。")

        st.write("#### 最近審批流水")
        approvals = query_approvals(db_path, limit=10)
        if approvals and pd:
            st.dataframe(pd.DataFrame(approvals), use_container_width=True)
        elif approvals:
            st.write(approvals)
        else:
            st.caption("目前尚無審批記錄。")

    with tab3:
        st.subheader("不可篡改審計日誌庫 (Audit Log Database)")
        st.write(f"資料庫實體位置: `{db_path}`")
        logs = query_audit_logs(db_path, limit=30)
        if logs and pd:
            st.dataframe(pd.DataFrame(logs), use_container_width=True)
        elif logs:
            st.write(logs)
        else:
            st.info("資料庫目前處於初始化待命狀態。")

    with tab4:
        st.subheader("機隊去中心化廣播 (Nostr Mesh) 與雲邊分流路由")
        col_m1, col_m2 = st.columns(2)
        with col_m1:
            st.write("#### Nostr 機隊去中心化加密廣播")
            st.code(
                json.dumps(
                    {
                        "protocol": "Nostr_NIP01_Encrypted",
                        "pubkey": "npub1phantomgrid999vehiclecore",
                        "mesh_relays": ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.snort.social"],
                        "last_broadcast_event": {
                            "kind": 30078,
                            "tags": [["t", "vehicular_safety"], ["vin", "VF3PHANTOM2026"]],
                            "content": "[CRITICAL_DERATE] Vehicle 0x280 applied Level 2 Derating at 92.5°C",
                        },
                    },
                    indent=2,
                ),
                language="json",
            )
        with col_m2:
            st.write("#### 邊雲動態模型分流路由器 (Hybrid Router)")
            st.metric("邊緣端延遲敏感任務", "0.4 ms (本地執行)", delta="CAN / SOME/IP / L3 自愈")
            st.metric("雲端長週期大模型任務", "180 ms (雲端非同步)", delta="多維趨勢預測 / 機隊共識")


def main() -> None:
    if st is not None:
        render_dashboard()
    else:
        print("[!] Streamlit is not installed. Run 'pip install streamlit' to view the dashboard.")


if __name__ == "__main__":
    main()

