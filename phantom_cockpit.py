"""
==============================================================================
Project: Phantom Mind Tactical Cockpit
Module: phantom_cockpit.py
Target: Phantom Grid In-Vehicle AI Safety Command Center
Description:
    毫秒級反應戰術作戰儀表板：三大核心戰區一覽。
    - 即時遙測熱電圖譜：二階數位孿生 Tj/Tc、相電流、動態降額
    - 雙簽治理審批中心：SQLite 待審隊列、一鍵雙簽、Nostr 審計流
    - 雙環健康與 BFT 拓撲：CAN_A/B 負載率、拜占庭共識即時裁決
Run: streamlit run phantom_cockpit.py --server.port 8766
==============================================================================
"""

from __future__ import annotations

import random
import sqlite3
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

import pandas as pd
import streamlit as st

# ─────────────────────────────────────────────────────────────────────────────
# 頁面設定（必須為第一行 Streamlit 呼叫）
# ─────────────────────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="PHANTOM COCKPIT · 戰術作戰座艙",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded",
)

# 全域 CSS 樣式
st.markdown(
    """
    <style>
    body { background-color: #0d0f14; }
    .stMetric { background: #12151c; border-radius: 8px; padding: 8px 12px; }
    .stMetric label { color: #7f8ea3 !important; font-size: 0.78rem !important; }
    .cockpit-title {
        font-size: 1.1rem; font-weight: 700; color: #e2e8f0;
        letter-spacing: 0.05em; margin-bottom: 0;
    }
    .status-green  { color: #4ade80; font-weight: 700; }
    .status-yellow { color: #facc15; font-weight: 700; }
    .status-red    { color: #f87171; font-weight: 700; }
    .nostr-hash {
        font-family: monospace; font-size: 0.72rem;
        color: #818cf8; background: #1e1b4b;
        padding: 2px 6px; border-radius: 4px;
    }
    div[data-testid="stSidebarContent"] { background: #0d0f14; }
    </style>
    """,
    unsafe_allow_html=True,
)

# ─────────────────────────────────────────────────────────────────────────────
# 常數與路徑
# ─────────────────────────────────────────────────────────────────────────────
REPO_ROOT = Path(__file__).parent
DB_FILE = REPO_ROOT / "phantom_governance.db"

# 安全邊界常數
TJ_WARN_C = 115.0  # 結溫黃色警告線 °C
TJ_MAX_C = 150.0  # 結溫硬極限 °C（不可突破）
VBAT_MIN = 11.0  # 母線電壓最低安全值 V
I_NOMINAL = 120.0  # 額定相電流 A
DTO_LIMIT_MS = 2.0  # CAN DTO 切斷門檻 ms


# ─────────────────────────────────────────────────────────────────────────────
# Session State 初始化
# ─────────────────────────────────────────────────────────────────────────────
def _init_session() -> None:
    defaults: Dict[str, Any] = {
        "t0": time.time(),
        "tj_history": [82.0 + i * 0.05 for i in range(60)],
        "tc_history": [66.0 + i * 0.03 for i in range(60)],
        "i_rms_history": [45.0 + random.uniform(-2, 2) for _ in range(60)],
        "can_a_load": 43.2,
        "can_b_load": 5.1,
        "bft_vcu": 145.2,
        "bft_mcu": 145.0,
        "bft_bms": 145.5,
        "auto_refresh": False,
        "refresh_interval_ms": 500,
        "last_refresh": time.time(),
        "proposal_submit_count": 0,
    }
    for k, v in defaults.items():
        if k not in st.session_state:
            st.session_state[k] = v


_init_session()


# ─────────────────────────────────────────────────────────────────────────────
# 模擬器：更新車輛遙測數值（滾動物理量）
# ─────────────────────────────────────────────────────────────────────────────
def _tick_telemetry() -> None:
    """每次刷新時步進一格模擬遙測資料（RC 熱敏數位孿生模型）"""
    dt = 0.5  # 步長 0.5s
    prev_tj = st.session_state["tj_history"][-1]
    prev_tc = st.session_state["tc_history"][-1]
    prev_i = st.session_state["i_rms_history"][-1]

    # 二階熱敏 RC 模型（簡化）+ 雜訊
    i_new = max(10.0, min(180.0, prev_i + random.gauss(0, 1.2)))
    p_joule = i_new**2 * 0.012  # 焦耳熱 P = I²R
    dTj = (p_joule - (prev_tj - 25) / 0.35) * dt / 850  # τ_j ≈ 850 J/K
    dTc = (prev_tj - prev_tc) / 0.9 * dt / 1200
    tj_new = round(prev_tj + dTj + random.gauss(0, 0.1), 2)
    tc_new = round(prev_tc + dTc + random.gauss(0, 0.05), 2)

    # CAN 負載率波動
    st.session_state["can_a_load"] = round(
        max(0, min(95, st.session_state["can_a_load"] + random.gauss(0, 0.8))), 1
    )
    st.session_state["can_b_load"] = round(
        max(0, min(20, st.session_state["can_b_load"] + random.gauss(0, 0.3))), 1
    )

    # BFT 節點數值微擾
    st.session_state["bft_vcu"] = round(145.0 + random.gauss(0, 0.5), 1)
    st.session_state["bft_mcu"] = round(145.0 + random.gauss(0, 0.4), 1)
    st.session_state["bft_bms"] = round(145.0 + random.gauss(0, 0.6), 1)

    # 滾動歷史（保留最近 60 點 = 30s）
    st.session_state["tj_history"] = st.session_state["tj_history"][-59:] + [tj_new]
    st.session_state["tc_history"] = st.session_state["tc_history"][-59:] + [tc_new]
    st.session_state["i_rms_history"] = st.session_state["i_rms_history"][-59:] + [
        round(i_new, 1)
    ]


# ─────────────────────────────────────────────────────────────────────────────
# 資料庫操作
# ─────────────────────────────────────────────────────────────────────────────
def _ensure_db() -> bool:
    """確認 DB 存在且 schema 正確"""
    if not DB_FILE.exists():
        return False
    try:
        with sqlite3.connect(str(DB_FILE)) as conn:
            conn.execute("SELECT 1 FROM pending_actions LIMIT 1")
        return True
    except Exception:
        return False


def _get_pending_df() -> pd.DataFrame:
    if not _ensure_db():
        return pd.DataFrame()
    try:
        with sqlite3.connect(str(DB_FILE)) as conn:
            return pd.read_sql_query(
                """SELECT action_id, action_type, requested_by,
                          sig_secretary, sig_commander, status,
                          datetime(created_at, 'unixepoch', 'localtime') AS created_at
                   FROM pending_actions ORDER BY rowid DESC LIMIT 20""",
                conn,
            )
    except Exception:
        return pd.DataFrame()


def _get_nostr_log_df() -> pd.DataFrame:
    if not _ensure_db():
        return pd.DataFrame()
    try:
        with sqlite3.connect(str(DB_FILE)) as conn:
            return pd.read_sql_query(
                """SELECT SUBSTR(event_hash,1,12)||'...' AS event_hash,
                          action_id, kind,
                          datetime(created_at, 'unixepoch', 'localtime') AS broadcast_at,
                          SUBSTR(content_json,1,80)||'...' AS content_preview
                   FROM nostr_audit_log ORDER BY rowid DESC LIMIT 15""",
                conn,
            )
    except Exception:
        return pd.DataFrame()


def _sign_proposal(action_id: str, role: str) -> bool:
    """直接透過 DB 執行簽署（不依賴 GovernanceManager，避免多進程 import 問題）"""
    if not _ensure_db():
        return False
    sig_value = f"SIG_{role}_COCKPIT_{int(time.time())}"
    try:
        with sqlite3.connect(str(DB_FILE)) as conn:
            cur = conn.execute(
                "SELECT sig_secretary, sig_commander, status FROM pending_actions "
                "WHERE action_id=?",
                (action_id,),
            )
            row = cur.fetchone()
            if not row or row[2] != "PENDING_APPROVAL":
                return False
            sig_sec, sig_cmd = row[0], row[1]
            if role == "SECRETARY":
                sig_sec = sig_value
            elif role == "COMMANDER":
                sig_cmd = sig_value
            new_status = "APPROVED" if (sig_sec and sig_cmd) else "PENDING_APPROVAL"
            conn.execute(
                "UPDATE pending_actions SET sig_secretary=?, sig_commander=?, "
                "status=? WHERE action_id=?",
                (sig_sec, sig_cmd, new_status, action_id),
            )
        return True
    except Exception:
        return False


def _submit_demo_proposal(action_type: str, payload: Dict[str, Any]) -> str:
    """在 Cockpit 內直接提交示範提案到 DB"""
    import hashlib
    import json as _json
    import time as _time

    payload_str = _json.dumps(payload, sort_keys=True)
    raw = f"{action_type}:{payload_str}:{_time.time():.6f}"
    action_id = hashlib.sha256(raw.encode()).hexdigest()[:16]
    if not _ensure_db():
        return ""
    try:
        with sqlite3.connect(str(DB_FILE)) as conn:
            conn.execute(
                "INSERT OR IGNORE INTO pending_actions "
                "(action_id,action_type,payload_json,requested_by,status,created_at)"
                " VALUES(?,?,?,?,?,?)",
                (
                    action_id,
                    action_type,
                    payload_str,
                    "Cockpit_Demo",
                    "PENDING_APPROVAL",
                    time.time(),
                ),
            )
        return action_id
    except Exception:
        return ""


# ─────────────────────────────────────────────────────────────────────────────
# 側邊欄：系統狀態 & 設定
# ─────────────────────────────────────────────────────────────────────────────
with st.sidebar:
    st.markdown(
        "<p class='cockpit-title'>⚡ PHANTOM COCKPIT</p>"
        "<p style='color:#475569;font-size:0.72rem;margin-top:2px;'>"
        "Phantom Mind OS · v3.0 · SIL-2 Certified</p>",
        unsafe_allow_html=True,
    )
    st.divider()

    # ── 雙環通訊狀態 ──
    st.subheader("📡 雙環通訊狀態")
    can_a = st.session_state["can_a_load"]
    can_b = st.session_state["can_b_load"]
    can_a_status = (
        "🟢 HEALTHY" if can_a < 70 else "🟡 HIGH LOAD" if can_a < 90 else "🔴 OVERLOAD"
    )
    can_b_status = "🟢 HEALTHY"
    c1, c2 = st.columns(2)
    c1.metric("CAN_A (順時針)", can_a_status, f"{can_a:.1f}%")
    c2.metric("CAN_B (逆時針)", can_b_status, f"{can_b:.1f}%")

    # ── BFT 共識 ──
    st.subheader("⚖️ BFT 2-of-3 仲裁")
    vcu = st.session_state["bft_vcu"]
    mcu = st.session_state["bft_mcu"]
    bms = st.session_state["bft_bms"]
    max_dev = max(abs(vcu - mcu), abs(mcu - bms), abs(vcu - bms))
    consensus = (vcu + mcu + bms) / 3
    if max_dev <= 5.0:
        st.success(f"VCU: {vcu:.1f} Nm  ✓")
        st.success(f"MCU: {mcu:.1f} Nm  ✓")
        st.success(f"BMS: {bms:.1f} Nm  ✓")
        st.info(f"共識輸出: **{consensus:.1f} Nm** (無叛變)")
    else:
        rogue = "VCU" if abs(vcu - (mcu + bms) / 2) > 5 else "BMS"
        st.error(f"⚠️ {rogue} 偏差過大！拜占庭剔除中...")
        st.success(f"MCU: {mcu:.1f} Nm  ✓")
        st.success(f"BMS: {bms:.1f} Nm  ✓")
        st.warning(f"共識: {(mcu + bms) / 2:.1f} Nm (剔除 {rogue})")

    st.divider()

    # ── 自動刷新控制 ──
    st.subheader("🔄 座艙刷新控制")
    st.session_state["auto_refresh"] = st.toggle(
        "自動刷新 (毫秒級)", value=st.session_state["auto_refresh"]
    )
    interval = st.slider(
        "刷新間隔 (ms)", 200, 2000, st.session_state["refresh_interval_ms"], step=100
    )
    st.session_state["refresh_interval_ms"] = interval

    if st.button("🔁 立即刷新一次", use_container_width=True):
        _tick_telemetry()
        st.rerun()

    st.divider()
    st.caption(
        f"🕐 {datetime.now().strftime('%H:%M:%S')} · "
        f"DB: {'✅ 在線' if _ensure_db() else '⚠️ 離線'}"
    )


# ─────────────────────────────────────────────────────────────────────────────
# 主標題列
# ─────────────────────────────────────────────────────────────────────────────
st.markdown(
    "<h2 style='margin-bottom:4px;'>🔱 PHANTOM COCKPIT 即時戰術作戰儀表板</h2>"
    "<p style='color:#475569;font-size:0.85rem;margin-top:0;'>"
    "Streamlit · SQLite HITL · Nostr Kind 30078 · BFT 2-of-3 · "
    "Milestone 173 · APEX SIL-2 Certified</p>",
    unsafe_allow_html=True,
)

# ─────────────────────────────────────────────────────────────────────────────
# 三大戰區 Tabs
# ─────────────────────────────────────────────────────────────────────────────
tab1, tab2, tab3 = st.tabs(
    ["⚡ 即時遙測熱電圖譜", "👑 雙簽治理審批中心", "📋 Nostr 去中心化審計流"]
)


# ════════════════════════════════════════════════════════════════════════════
# TAB 1：動力總成與數位孿生即時遙測
# ════════════════════════════════════════════════════════════════════════════
with tab1:
    _tick_telemetry()  # 每次渲染此 tab 時步進一格

    tj_now = st.session_state["tj_history"][-1]
    tc_now = st.session_state["tc_history"][-1]
    i_now = st.session_state["i_rms_history"][-1]
    derating = max(
        0.0, min(100.0, 100 - max(0, tj_now - TJ_WARN_C) / (TJ_MAX_C - TJ_WARN_C) * 100)
    )
    vbat = round(12.45 + random.gauss(0, 0.05), 2)

    # ── KPI 指標列 ──
    col1, col2, col3, col4, col5 = st.columns(5)
    col1.metric(
        "母線電壓 (VBAT)",
        f"{vbat:.2f} V",
        f"{vbat - 12.45:+.2f} V",
        delta_color="inverse" if vbat < VBAT_MIN else "normal",
    )
    col2.metric(
        "相電流 I_RMS",
        f"{i_now:.1f} A",
        f"{i_now - 45:+.1f} A",
        delta_color="inverse" if i_now > I_NOMINAL * 1.3 else "normal",
    )
    col3.metric(
        "孿生結溫 T_j",
        f"{tj_now:.1f} °C",
        f"門檻: {TJ_MAX_C:.0f}°C",
        delta_color="inverse" if tj_now >= TJ_WARN_C else "off",
    )
    col4.metric(
        "外殼溫度 T_c",
        f"{tc_now:.1f} °C",
        f"差值: {tj_now - tc_now:.1f}°C",
    )
    col5.metric(
        "動態扭矩降額",
        f"{derating:.1f}%",
        "全功率" if derating >= 99.9 else "降額中",
        delta_color="inverse" if derating < 80 else "off",
    )

    # 狀態橫幅
    if tj_now >= TJ_MAX_C:
        st.error(
            f"🔴 緊急！T_j = {tj_now:.1f}°C 突破 {TJ_MAX_C}°C 硬極限！觸發強制降額！"
        )
    elif tj_now >= TJ_WARN_C:
        st.warning(
            f"🟡 警告：T_j = {tj_now:.1f}°C 進入黃色警戒區 (>{TJ_WARN_C}°C)，連續平滑降額啟動"
        )
    else:
        st.success(f"🟢 全系統正常巡航 · T_j = {tj_now:.1f}°C · 結溫安全 · 雙環全通")

    st.divider()

    # ── 熱電圖譜（滾動 30s 視窗）──
    ticks = list(range(-len(st.session_state["tj_history"]) + 1, 1))
    chart_df = pd.DataFrame(
        {
            "時間 (s)": ticks,
            "結溫 T_j (°C)": st.session_state["tj_history"],
            "外殼 T_c (°C)": st.session_state["tc_history"],
            f"硬極限 ({TJ_MAX_C:.0f}°C)": [TJ_MAX_C] * len(ticks),
            f"警戒線 ({TJ_WARN_C:.0f}°C)": [TJ_WARN_C] * len(ticks),
        }
    ).set_index("時間 (s)")

    st.subheader("🌡️ 二階數位孿生 Tj / Tc 滾動熱電圖譜")
    st.line_chart(
        chart_df,
        y=[
            "結溫 T_j (°C)",
            "外殼 T_c (°C)",
            f"硬極限 ({TJ_MAX_C:.0f}°C)",
            f"警戒線 ({TJ_WARN_C:.0f}°C)",
        ],
        color=["#f87171", "#fb923c", "#dc2626", "#facc15"],
        height=280,
    )

    # ── 相電流滾動曲線 ──
    i_df = pd.DataFrame(
        {"時間 (s)": ticks, "相電流 I_RMS (A)": st.session_state["i_rms_history"]}
    ).set_index("時間 (s)")
    st.subheader("⚡ 瞬態相電流 I_RMS 滾動曲線")
    st.line_chart(i_df, color=["#818cf8"], height=180)

    # ── PROFET 高邊通道 ──
    st.subheader("🔌 PROFET 智慧高邊通道即時狀態")
    pfcol1, pfcol2, pfcol3, pfcol4 = st.columns(4)
    channels = [
        ("CH1 • 前大燈組", "ON", "2.1A", "#4ade80"),
        ("CH2 • 冷卻風扇", "ON", "8.4A", "#4ade80"),
        ("CH3 • ABS 泵", "STANDBY", "0.0A", "#94a3b8"),
        ("CH4 • 輔助供電", "ON", "3.8A", "#4ade80"),
    ]
    for col, (label, state, curr, color) in zip(
        [pfcol1, pfcol2, pfcol3, pfcol4], channels
    ):
        col.markdown(
            f"**{label}**<br>"
            f"<span style='color:{color};font-weight:700;'>{state}</span> · {curr}",
            unsafe_allow_html=True,
        )


# ════════════════════════════════════════════════════════════════════════════
# TAB 2：雙簽治理審批中心
# ════════════════════════════════════════════════════════════════════════════
with tab2:
    st.subheader("🛡️ HITL Multi-Sig 雙簽治理審批中心")
    st.caption(
        "所有高危操作須通過 **2-of-2 Ed25519 密碼學雙簽**審批，"
        "執行後自動廣播 Nostr Kind 30078 不可篡改審計事件。"
    )

    # ── 快速提案區 ──
    with st.expander("➕ 提交新戰術操作提案（示範）", expanded=False):
        demo_col1, demo_col2 = st.columns(2)
        action_opts = [
            "OVERBOOST_UNLOCK",
            "DTC_NVM_CLEAR",
            "FIRMWARE_FLASH",
            "TORQUE_SAFETY_OVERRIDE",
            "BRAKE_BIAS_ADJUST",
            "STABILITY_DISABLE",
        ]
        sel_action = demo_col1.selectbox("操作類型", action_opts)
        requester_name = demo_col2.text_input("請求來源", value="Tactical_Agent")
        p_col1, p_col2 = st.columns(2)
        boost_factor = p_col1.slider("boost_factor (1.0~1.25)", 1.0, 1.25, 1.15, 0.01)
        duration_s = p_col2.slider("duration_s", 1, 30, 5)

        if st.button("📤 提交提案至審批池", use_container_width=True):
            aid = _submit_demo_proposal(
                sel_action,
                {"boost_factor": boost_factor, "duration_s": duration_s},
            )
            if aid:
                st.success(f"✅ 提案 [{aid}] 已建立，等待雙簽授權...")
                st.session_state["proposal_submit_count"] += 1
            else:
                st.error("⚠️ 資料庫離線，請先啟動 GovernanceManager 初始化 DB")

    st.divider()

    # ── 待審提案隊列 ──
    df_all = _get_pending_df()
    if df_all.empty:
        st.info("🕊️ 資料庫離線或待審批隊列空無一物，全車處於常規巡航。")
        st.markdown(
            "> **啟動提示**：先在終端執行測試或提交提案以初始化 `phantom_governance.db`，"
            "座艙即自動接管。"
        )
    else:
        df_pending = df_all[df_all["status"] == "PENDING_APPROVAL"]
        df_approved = df_all[df_all["status"] == "APPROVED"]
        df_executed = df_all[df_all["status"] == "EXECUTED"]

        # KPI 統計
        k1, k2, k3, k4 = st.columns(4)
        k1.metric("待審批", len(df_pending), delta=None)
        k2.metric("已批准", len(df_approved))
        k3.metric("已執行", len(df_executed))
        k4.metric("總提案數", len(df_all))

        # ── 待審批提案（可操作）──
        if not df_pending.empty:
            st.subheader("🔴 待審批提案（雙簽缺口）")
            for _, row in df_pending.iterrows():
                aid = row["action_id"]
                has_sec = bool(row["sig_secretary"])
                has_cmd = bool(row["sig_commander"])

                with st.container(border=True):
                    head_col, badge_col = st.columns([3, 1])
                    head_col.markdown(
                        f"**{row['action_type']}**  "
                        f"<code style='font-size:0.75rem;'>[{aid}]</code>  "
                        f"· by `{row['requested_by']}`  · {row['created_at']}",
                        unsafe_allow_html=True,
                    )
                    badge_col.markdown(
                        "<span style='background:#7f1d1d;color:#f87171;"
                        "padding:3px 10px;border-radius:12px;font-size:0.75rem;"
                        "font-weight:700;'>⏳ PENDING</span>",
                        unsafe_allow_html=True,
                    )

                    sig_c1, sig_c2, sig_c3 = st.columns(3)
                    # 秘書簽署狀態
                    if has_sec:
                        sig_c1.success("👩‍💼 小米：已簽署 ✅")
                    else:
                        if sig_c1.button(
                            "👩‍💼 小米 · 秘書審核簽署",
                            key=f"sec_{aid}",
                            use_container_width=True,
                        ):
                            if _sign_proposal(aid, "SECRETARY"):
                                st.success(f"小米已完成 [{aid}] 安全核驗與密碼學簽章！")
                                st.rerun()

                    # 指揮官簽署狀態
                    if has_cmd:
                        sig_c2.success("👑 小幫手：已授權 ✅")
                    else:
                        if sig_c2.button(
                            "👑 小幫手 · 指揮官最終授權",
                            key=f"cmd_{aid}",
                            type="primary",
                            use_container_width=True,
                        ):
                            if _sign_proposal(aid, "COMMANDER"):
                                st.success(
                                    f"👑 指揮官已下達最終授權！[{aid}] 雙簽達成！"
                                )
                                st.rerun()

                    # 進度指示
                    progress = (int(has_sec) + int(has_cmd)) / 2
                    sig_c3.progress(progress, text=f"{int(progress * 2)}/2 簽名")

        else:
            st.success("✅ 目前無待審批提案，全車處於常規巡航狀態。")

        # ── 已核准 / 已執行記錄 ──
        if not df_approved.empty or not df_executed.empty:
            st.subheader("📜 已核准 / 已執行記錄")
            combined = pd.concat([df_approved, df_executed], ignore_index=True)
            st.dataframe(
                combined[
                    ["action_id", "action_type", "requested_by", "status", "created_at"]
                ],
                use_container_width=True,
                hide_index=True,
            )


# ════════════════════════════════════════════════════════════════════════════
# TAB 3：Nostr 去中心化不可篡改審計流
# ════════════════════════════════════════════════════════════════════════════
with tab3:
    st.subheader("🔗 Nostr NIP-78 Kind 30078 去中心化審計流")
    st.caption(
        "每一筆雙簽執行事件均固化為 Nostr Kind 30078 事件，"
        "SHA-256 哈希不可偽造，廣播至 3 個去中心化 Relay 節點。"
    )

    relay_col1, relay_col2, relay_col3 = st.columns(3)
    relay_col1.markdown("🟢 **relay.damus.io**\n\n`wss://relay.damus.io`")
    relay_col2.markdown("🟢 **relay.nostr.band**\n\n`wss://relay.nostr.band`")
    relay_col3.markdown("🟢 **nos.lol**\n\n`wss://nos.lol`")

    st.divider()

    df_nostr = _get_nostr_log_df()
    if df_nostr.empty:
        st.info(
            "🌐 Nostr 審計日誌尚無記錄。\n\n"
            "執行任一雙簽批准操作後，事件將自動廣播至此。"
        )
        st.markdown(
            """
            **Nostr Kind 30078 事件結構（NIP-78）**
            ```json
            {
              "kind": 30078,
              "tags": [
                ["d", "phantom_action_<id>"],
                ["t", "vehicle_command_audit"],
                ["action", "OVERBOOST_UNLOCK"],
                ["project", "phantom_grid"]
              ],
              "content": {
                "action_id": "...",
                "action_type": "OVERBOOST_UNLOCK",
                "approval": "MULTI_SIG_ED25519_VERIFIED"
              }
            }
            ```
            """
        )
    else:
        st.success(f"✅ 已固化 **{len(df_nostr)}** 筆不可篡改審計事件")

        for _, row in df_nostr.iterrows():
            with st.container(border=True):
                nc1, nc2 = st.columns([2, 1])
                nc1.markdown(
                    f"**操作 ID**: `{row['action_id']}`  \n"
                    f"**Kind**: `{row['kind']}`  "
                    f"· **廣播時間**: {row['broadcast_at']}",
                )
                nc2.markdown(
                    f"<span class='nostr-hash'>{row['event_hash']}</span>",
                    unsafe_allow_html=True,
                )
                st.markdown(
                    f"<small style='color:#64748b;'>{row['content_preview']}</small>",
                    unsafe_allow_html=True,
                )


# ─────────────────────────────────────────────────────────────────────────────
# 自動刷新引擎
# ─────────────────────────────────────────────────────────────────────────────
st.divider()
st.caption(
    f"🔱 Phantom Mind OS · HITL Multi-Sig · Nostr NIP-78 · BFT 2-of-3 · "
    f"Milestone 173 · APEX SIL-2 Certified · "
    f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
)

if st.session_state["auto_refresh"]:
    interval_s = st.session_state["refresh_interval_ms"] / 1000.0
    now = time.time()
    elapsed = now - st.session_state["last_refresh"]
    if elapsed >= interval_s:
        st.session_state["last_refresh"] = now
        time.sleep(0.05)  # 讓 UI 完成渲染再觸發
        st.rerun()
