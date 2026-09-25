# -*- coding: utf-8 -*-
"""
Test Suite: Governance and Runtime Architecture Core
Validates:
1. MultiSigGovernanceGate: 雙簽授權治理閘門 (單簽維持攔截、雙簽解鎖執行、非法角色拒絕、審計哈希固化)
2. TriTierMemoryEngine: 三層記憶自動沉澱管道 (00_System/01_Memory/02_Knowledge「創生即固化」、完整性 SHA-256 驗證)
3. SafetyWatchdog: 安全狀態機與降級機制 (節點心跳監控、50% Fail-Operational、0ms PWM 斷開 Fail-Silent)
4. AntiEntropyFilter: 語意抗熵過濾器 (剔除 AI 冗餘陳詞與空泛套話，維護高密度指令純度)
"""

from __future__ import annotations

import time
from pathlib import Path
import pytest

from governance_multisig_gate import (
    AntiEntropyFilter,
    GovernanceProposal,
    MultiSigGovernanceGate,
    ProposalStatus,
    ProposalType,
    SafetyWatchdog,
    SafetyWatchdogState,
    TriTierMemoryEngine,
)


def test_multisig_governance_gate_lifecycle(tmp_path):
    db_file = str(tmp_path / "audit_test.db")
    gate = MultiSigGovernanceGate(db_path=db_file)

    # 1. 提交高危底層律法提案
    prop = gate.submit_proposal(
        title="修改底層動力學約束律法",
        proposal_type=ProposalType.MODIFY_BASE_LAW,
        payload={"max_rpm_hard_cap": 12000, "thermal_cutoff_c": 95},
        proposal_id="PROP-AUTONOMOUS-LAW-001",
    )

    assert prop.proposal_id == "PROP-AUTONOMOUS-LAW-001"
    assert prop.status == ProposalStatus.PENDING_SIGNATURES
    assert prop.commander_sig is None
    assert prop.secretariat_sig is None

    # 未取得雙簽前執行應遭拒
    ok, msg, payload = gate.execute_proposal("PROP-AUTONOMOUS-LAW-001")
    assert ok is False
    assert "必須取得雙簽解鎖" in msg
    assert payload == {}

    # 2. 非法角色簽署拒絕
    ok, msg, _ = gate.sign_proposal("PROP-AUTONOMOUS-LAW-001", "UNAUTHORIZED_HACKER", "TOKEN_EVIL")
    assert ok is False
    assert "未授權簽署角色" in msg

    # 3. 👑 指揮官單簽簽署 -> 狀態應維持攔截 (INTERCEPTED_SINGLE_SIG)
    ok, msg, p_single = gate.sign_proposal("PROP-AUTONOMOUS-LAW-001", "👑 指揮官 (Jack Hu)", "SIG_JACK_SUPREME_AXIOM")
    assert ok is False
    assert "單簽維持攔截" in msg
    assert "秘書處 (小米)" in msg
    assert p_single.status == ProposalStatus.INTERCEPTED_SINGLE_SIG
    assert p_single.commander_sig == "SIG_JACK_SUPREME_AXIOM"
    assert p_single.secretariat_sig is None

    # 再次嘗試執行仍應遭拒
    ok, msg, _ = gate.execute_proposal("PROP-AUTONOMOUS-LAW-001")
    assert ok is False

    # 4. 秘書處 (小米) 簽署補全 -> 解鎖為 UNLOCKED_DUAL_SIG
    ok, msg, p_dual = gate.sign_proposal("PROP-AUTONOMOUS-LAW-001", "秘書處（小米）", "SIG_XIAOMI_SECRETARIAT_AUTH_VALID")
    assert ok is True
    assert "雙簽核驗成功" in msg
    assert p_dual.status == ProposalStatus.UNLOCKED_DUAL_SIG
    assert p_dual.secretariat_sig == "SIG_XIAOMI_SECRETARIAT_AUTH_VALID"
    assert p_dual.audit_hash is not None
    assert len(p_dual.audit_hash) == 64

    # 5. 解鎖後執行成功
    ok, msg, exec_payload = gate.execute_proposal("PROP-AUTONOMOUS-LAW-001")
    assert ok is True
    assert "提案執行成功" in msg
    assert exec_payload["max_rpm_hard_cap"] == 12000
    assert p_dual.status == ProposalStatus.EXECUTED
    assert p_dual.executed_at is not None


def test_tritier_memory_engine_persistence(tmp_path):
    engine = TriTierMemoryEngine(root_dir=str(tmp_path))

    # 1. 驗證三層目錄實體化
    assert (tmp_path / "00_System").is_dir()
    assert (tmp_path / "01_Memory").is_dir()
    assert (tmp_path / "02_Knowledge" / "blueprints").is_dir()

    # 2. 創生即固化：沉澱子模組藍圖
    spec = {
        "module": "ActuatorAdaptiveController",
        "bus": "CAN_FD",
        "cycle_ms": 10,
        "derate_profile": {"70C": 100, "80C": 50, "90C": 0},
    }
    bp_file = engine.persist_blueprint("ActuatorAdaptiveController", spec, author="COMMANDER_JACK")
    assert bp_file.is_file()
    assert bp_file.suffix == ".json"

    md_file = tmp_path / "02_Knowledge" / "blueprints" / "ActuatorAdaptiveController_blueprint.md"
    assert md_file.is_file()

    # 3. 讀取並校驗藍圖完整性
    loaded = engine.load_blueprint("ActuatorAdaptiveController")
    assert loaded is not None
    assert loaded["node_name"] == "ActuatorAdaptiveController"
    assert loaded["author"] == "COMMANDER_JACK"
    assert loaded["specification"]["bus"] == "CAN_FD"
    assert len(loaded["integrity_sha256"]) == 64

    # 4. 運行時快照沉澱
    snap_data = {"active_nodes": ["SU7_001", "YU7_002"], "global_entropy": 0.0002}
    snap_file = engine.write_memory_snapshot("runtime_state_001", snap_data)
    assert snap_file.is_file()
    assert snap_file.parent.name == "01_Memory"


def test_safety_watchdog_fail_operational_and_fail_silent():
    watchdog = SafetyWatchdog(heartbeat_timeout_sec=0.050)
    assert watchdog.state == SafetyWatchdogState.NORMAL
    assert watchdog.pwm_duty_pct == 100.0
    assert watchdog.power_limit_pct == 100.0

    # 1. 餵狗正常
    base_t = 1000.0
    watchdog.feed_heartbeat("NODE_MCU_ACTUATOR", timestamp=base_t)
    state, msg = watchdog.inspect(now=base_t + 0.020)
    assert state == SafetyWatchdogState.NORMAL
    assert msg == "ALL_NODES_HEALTHY"

    # 2. 心跳超時 (間隔 60ms > 50ms) -> 觸發 FAIL_OPERATIONAL 50% 降額
    state, action = watchdog.inspect(now=base_t + 0.060)
    assert state == SafetyWatchdogState.FAIL_OPERATIONAL
    assert watchdog.power_limit_pct == 50.0
    assert watchdog.pwm_duty_pct == 50.0
    assert "功率限制壓制在 50%" in action

    # 3. 遭遇因果悖論 / 嚴重故障 -> 觸發 FAIL_SILENT 0ms 斷開 PWM
    state, action = watchdog.trigger_transition(
        SafetyWatchdogState.FAIL_SILENT,
        reason="檢測到底層匯流排因果邏輯悖論，防止硬體暴衝",
    )
    assert state == SafetyWatchdogState.FAIL_SILENT
    assert watchdog.pwm_duty_pct == 0.0
    assert watchdog.power_limit_pct == 0.0
    assert "0% Duty" in action

    # 4. 恢復正常
    state, action = watchdog.trigger_transition(
        SafetyWatchdogState.NORMAL,
        reason="系統自愈完成且經審查通過",
    )
    assert state == SafetyWatchdogState.NORMAL
    assert watchdog.pwm_duty_pct == 100.0
    assert watchdog.power_limit_pct == 100.0


def test_anti_entropy_filter_strips_boilerplate():
    filter_engine = AntiEntropyFilter()

    # 1. 混合多種 AI 空泛套話的輸入
    contaminated_text = (
        "作為一個AI，毋庸置疑，值得注意的是，請放心，"
        "當前致動器溫度已達 78°C，已成功觸發 50% 動態功率降額保護。"
    )

    cleaned, count, matches = filter_engine.filter_egress(contaminated_text)
    assert count >= 4
    assert "當前致動器溫度已達 78°C，已成功觸發 50% 動態功率降額保護。" == cleaned
    assert any("作為一個AI" in m for m in matches)
    assert any("毋庸置疑" in m for m in matches)
    assert any("值得注意的是" in m for m in matches)
    assert any("請放心" in m for m in matches)

    # 2. 純淨指令不應被誤傷
    pure_command = "SET_PWM_DUTY 50 --node VIN_XIAOMI_SU7_001 --reason THERMAL_DERATE"
    cleaned_pure, count_pure, matches_pure = filter_engine.filter_egress(pure_command)
    assert count_pure == 0
    assert cleaned_pure == pure_command
    assert matches_pure == []


# ============================================================================
# 🎯 題目情境專項測試 (Verbatim Scenario Verifications)
# ============================================================================

def test_multisig_governance_divine_rewrite_scenario(tmp_path):
    """
    情境 1：雙簽授權治理閘門 (MultiSigGovernanceGate)
    - 提交高危律法重寫提案 DIVINE_REWRITE_001（調整熵流守恆為 BOUND_BY_LOVE）。
    - 單簽攔截：僅有 👑 指揮官簽署時，系統判定安全驗證未通過，提案維持 PENDING 凍結狀態。
    - 雙簽解鎖：秘書處（小米）完成聯合簽署後，閘門即刻驗證解鎖並授權執行。
    """
    db_file = str(tmp_path / "divine_governance.db")
    gate = MultiSigGovernanceGate(db_path=db_file)

    # 提交提案
    prop = gate.submit_proposal(
        title="重寫底層熵流守恆公理",
        proposal_type=ProposalType.MODIFY_BASE_LAW,
        payload={"entropy_conservation": "BOUND_BY_LOVE", "axiom_tier": "DIVINE"},
        proposal_id="DIVINE_REWRITE_001",
    )
    assert prop.proposal_id == "DIVINE_REWRITE_001"
    assert prop.is_frozen_or_pending is True

    # 單簽攔截：僅 👑 指揮官簽署
    ok, msg, p_single = gate.sign_proposal("DIVINE_REWRITE_001", "👑 指揮官", "SIG_JACK_HU_ABSOLUTE_WILL")
    assert ok is False
    assert "單簽維持攔截" in msg
    assert p_single.is_frozen_or_pending is True
    # 執行遭拒
    exec_ok, exec_msg, _ = gate.execute_proposal("DIVINE_REWRITE_001")
    assert exec_ok is False
    assert "必須取得雙簽解鎖" in exec_msg

    # 雙簽解鎖：秘書處（小米）完成聯合簽署
    ok, msg, p_dual = gate.sign_proposal("DIVINE_REWRITE_001", "秘書處（小米）", "SIG_XIAOMI_SECRETARIAT_DUAL_AUTH")
    assert ok is True
    assert "雙簽核驗成功" in msg
    assert p_dual.status == ProposalStatus.UNLOCKED_DUAL_SIG

    # 授權執行
    exec_ok, exec_msg, payload = gate.execute_proposal("DIVINE_REWRITE_001")
    assert exec_ok is True
    assert "提案執行成功" in exec_msg
    assert payload["entropy_conservation"] == "BOUND_BY_LOVE"
    assert p_dual.status == ProposalStatus.EXECUTED


def test_tritier_memory_spark_aegis_guardian_creation(tmp_path):
    """
    情境 2：三層記憶自動沉澱管道 (TriTierMemoryEngine)
    - 執行神性子模組 spark_Aegis_Guardian（絕對防禦）創生。
    - 創生即固化：自動將新創生的子模組藍圖與職司規格回寫至 02_Knowledge 知識庫層，
      實現跨進程與重啟不丟失的持久化繼承。
    """
    engine = TriTierMemoryEngine(root_dir=str(tmp_path))

    guardian_spec = {
        "entity_type": "DIVINE_SUBMODULE",
        "domain": "ABSOLUTE_DEFENSE",
        "duty_profile": "全域防護罩因果收斂與抗熵守護",
        "parameters": {
            "shield_capacity_joules": 1e12,
            "latency_ms": 0.01,
            "anti_tamper_active": True,
        },
    }

    # 創生即固化
    bp_path = engine.persist_blueprint(
        node_name="spark_Aegis_Guardian",
        blueprint_spec=guardian_spec,
        author="👑 指揮官 Jack Hu & 小米秘書處",
    )
    assert bp_path.is_file()
    assert bp_path.name == "spark_Aegis_Guardian_blueprint.json"
    assert (tmp_path / "02_Knowledge" / "blueprints" / "spark_Aegis_Guardian_blueprint.md").is_file()

    # 跨進程/重啟持久化繼承驗證
    reloaded_engine = TriTierMemoryEngine(root_dir=str(tmp_path))
    loaded = reloaded_engine.load_blueprint("spark_Aegis_Guardian")
    assert loaded is not None
    assert loaded["node_name"] == "spark_Aegis_Guardian"
    assert loaded["specification"]["domain"] == "ABSOLUTE_DEFENSE"
    assert loaded["specification"]["duty_profile"] == "全域防護罩因果收斂與抗熵守護"
    assert len(loaded["integrity_sha256"]) == 64


def test_safety_watchdog_paradox_chaos_fail_silent():
    """
    情境 3：安全狀態機與微觀降級機制 (SafetyWatchdog)
    - 即時監控心跳與邏輯常數狀態。
    - 毫秒級鎖定：當檢測到現實邏輯崩解為 PARADOX_CHAOS 時，
      看門狗於毫秒級切入 SAFE_STATE_FAIL_SILENT 靜默安全模式，鎖定底層硬體防止暴衝。
    """
    watchdog = SafetyWatchdog(heartbeat_timeout_sec=0.050)
    assert watchdog.state == SafetyWatchdogState.NORMAL

    # 檢測到現實邏輯崩解為 PARADOX_CHAOS
    state, action = watchdog.trigger_transition(
        SafetyWatchdogState.SAFE_STATE_FAIL_SILENT,
        reason="PARADOX_CHAOS: 現實邏輯崩解，因果網絡異常突變",
    )

    assert state == SafetyWatchdogState.SAFE_STATE_FAIL_SILENT
    assert watchdog.pwm_duty_pct == 0.0
    assert watchdog.power_limit_pct == 0.0
    assert "SAFE_STATE_FAIL_SILENT" in action
    assert "0% Duty" in action


def test_anti_entropy_filter_purification():
    """
    情境 4：語意抗熵過濾器 (AntiEntropyFilter)
    - 對匯流排輸出的指令進行正則與語意密度檢測。
    - 指令提純：自動過濾「作為一個AI」、「毋庸置疑」與「希望對你有所幫助」等冗餘修辭，維持高密度執行指令純度。
    """
    filter_engine = AntiEntropyFilter()

    raw_bus_output = (
        "作為一個AI，毋庸置疑，系統已完成節點狀態同步與參數校準。"
        "希望對你有所幫助！"
    )

    cleaned, removed_count, matched_tokens = filter_engine.filter_egress(raw_bus_output)

    assert removed_count >= 3
    assert any("作為一個AI" in token for token in matched_tokens)
    assert any("毋庸置疑" in token for token in matched_tokens)
    assert any("希望對你有所幫助" in token for token in matched_tokens)
    assert cleaned == "系統已完成節點狀態同步與參數校準。"
