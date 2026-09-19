# -*- coding: utf-8 -*-
"""
==============================================================================
Project: Phantom Mind Governance
Test Suite: HITL Multi-Sig & Nostr Audit Log Acceptance
Target: Phantom Grid In-Vehicle AI Safety Governance Layer
==============================================================================
"""

import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from agent_governance_multisig import (
    ActionStatus,
    GovernanceManager,
    NostrAuditEvent,
    SignerRole,
)


@pytest.fixture
def gov(tmp_path):
    """每個測試使用獨立的臨時 SQLite 資料庫，互不污染。"""
    db_file = str(tmp_path / "test_governance.db")
    return GovernanceManager(db_path=db_file)


class TestHITLMultiSigGovernance:
    # -------------------------------------------------------------------------
    # 治理考驗一：提案建立與哈希唯一性驗證
    # -------------------------------------------------------------------------
    def test_gov_01_proposal_creation_and_id_uniqueness(self, gov):
        print("\n>>> 注入【治理考驗一：越野解鎖提案建立與 SHA-256 哈希唯一性驗證】")
        id_a = gov.submit_action_proposal(
            "OVERBOOST_UNLOCK",
            {"boost_factor": 1.15, "duration_s": 5},
            "Tactical_Agent",
        )
        id_b = gov.submit_action_proposal(
            "DTC_NVM_CLEAR",
            {"ecu_target": "VCU", "dtc_mask": 0xFF},
            "Safety_Agent",
        )

        assert id_a, "【FAIL】提案 A 的 action_id 不得為空！"
        assert id_b, "【FAIL】提案 B 的 action_id 不得為空！"
        assert id_a != id_b, "【FAIL】不同提案的 action_id 發生哈希碰撞！"
        assert len(id_a) == 16, f"【FAIL】action_id 長度應為 16，實際: {len(id_a)}"

        state_a = gov.get_action_status(id_a)
        assert state_a is not None
        assert state_a["status"] == ActionStatus.PENDING_APPROVAL.value

        print(
            f"  [PASS] 提案建立成功 [{id_a}] / [{id_b}]，"
            "SHA-256 唯一，初始狀態 PENDING_APPROVAL！"
        )

    # -------------------------------------------------------------------------
    # 治理考驗二：單簽不足，拒絕執行（1-of-2 安全閘）
    # -------------------------------------------------------------------------
    def test_gov_02_single_sig_insufficient_blocks_execution(self, gov):
        print("\n>>> 注入【治理考驗二：僅秘書單簽，指揮官缺席，強行執行被拒】")
        action_id = gov.submit_action_proposal(
            "TORQUE_SAFETY_OVERRIDE",
            {"override_nm": 650, "reason": "emergency_offroad"},
            "Edge_Agent",
        )

        # 只有秘書簽署，指揮官未簽
        ok = gov.sign_proposal(action_id, SignerRole.SECRETARY, "SIG_SECR_BOUNDARY_OK")
        assert ok is True

        state = gov.get_action_status(action_id)
        assert (
            state["status"] == ActionStatus.PENDING_APPROVAL.value
        ), "【FAIL】單簽後狀態不得升級為 APPROVED！"

        # 嘗試強行執行 → 必須被拒
        result = gov.execute_approved_action(action_id)
        assert result is None, "【FAIL】單簽提案被強行執行！雙簽護城河失守！"

        print(
            "  [PASS] 單簽防護生效！指揮官缺席，強行執行被硬性阻斷，"
            "TORQUE_SAFETY_OVERRIDE 0 繞過！"
        )

    # -------------------------------------------------------------------------
    # 治理考驗三：2-of-2 雙簽達成，狀態正確升級
    # -------------------------------------------------------------------------
    def test_gov_03_dual_sig_2of2_approval_state_upgrade(self, gov):
        print("\n>>> 注入【治理考驗三：秘書 + 指揮官完整雙簽，APPROVED 狀態升級】")
        action_id = gov.submit_action_proposal(
            "OVERBOOST_UNLOCK",
            {"boost_factor": 1.15, "duration_s": 5},
            "Tactical_Agent",
        )

        # 秘書第一簽
        gov.sign_proposal(action_id, SignerRole.SECRETARY, "SIG_SECR_TEMP_82C_OK")
        state_after_sec = gov.get_action_status(action_id)
        assert state_after_sec["status"] == ActionStatus.PENDING_APPROVAL.value

        # 指揮官第二簽 → 達成雙簽
        gov.sign_proposal(action_id, SignerRole.COMMANDER, "SIG_CMD_PERMIT_GO")
        state_after_cmd = gov.get_action_status(action_id)
        assert state_after_cmd["status"] == ActionStatus.APPROVED.value, (
            f"【FAIL】雙簽後狀態應為 APPROVED，" f"實際: {state_after_cmd['status']}"
        )
        assert state_after_cmd["sig_secretary"] == "SIG_SECR_TEMP_82C_OK"
        assert state_after_cmd["sig_commander"] == "SIG_CMD_PERMIT_GO"

        print(
            f"  [PASS] 2-of-2 雙簽完成！提案 [{action_id}] "
            "狀態正確升級 PENDING → APPROVED！"
        )

    # -------------------------------------------------------------------------
    # 治理考驗四：執行批准操作並回傳正確 payload
    # -------------------------------------------------------------------------
    def test_gov_04_execute_approved_action_returns_payload(self, gov):
        print("\n>>> 注入【治理考驗四：雙簽後執行越野脫困操作，驗收 payload 與狀態】")
        payload_in = {"boost_factor": 1.15, "duration_s": 5}
        action_id = gov.submit_action_proposal(
            "OVERBOOST_UNLOCK", payload_in, "Tactical_Agent"
        )
        gov.sign_proposal(action_id, SignerRole.SECRETARY, "SIG_SECR_TEMP_82C_OK")
        gov.sign_proposal(action_id, SignerRole.COMMANDER, "SIG_CMD_PERMIT_GO")

        result = gov.execute_approved_action(action_id)

        assert result is not None, "【FAIL】已批准操作執行後回傳 None！"
        assert result["action_type"] == "OVERBOOST_UNLOCK"
        assert result["payload"]["boost_factor"] == 1.15
        assert result["payload"]["duration_s"] == 5
        assert "nostr_event_hash" in result
        assert len(result["nostr_event_hash"]) == 64  # SHA-256 hex

        state = gov.get_action_status(action_id)
        assert (
            state["status"] == ActionStatus.EXECUTED.value
        ), "【FAIL】執行後狀態應為 EXECUTED！"
        assert state["executed_at"] is not None

        print(
            f"  [PASS] 越野脫困操作執行完畢！"
            f"boost_factor={result['payload']['boost_factor']}x，"
            f"Nostr 哈希前 12 碼: {result['nostr_event_hash'][:12]}..."
        )

    # -------------------------------------------------------------------------
    # 治理考驗五：Nostr Kind 30078 審計事件格式與不可篡改性驗證
    # -------------------------------------------------------------------------
    def test_gov_05_nostr_audit_event_structure_and_immutability(self, gov):
        print("\n>>> 注入【治理考驗五：Nostr Kind 30078 審計事件格式與哈希不可篡改】")
        action_id = gov.submit_action_proposal(
            "DTC_NVM_CLEAR",
            {"ecu_target": "VCU", "dtc_mask": 255},
            "Safety_Agent",
        )
        gov.sign_proposal(action_id, SignerRole.SECRETARY, "SIG_SECR_BOUNDARY_OK")
        gov.sign_proposal(action_id, SignerRole.COMMANDER, "SIG_CMD_AUTHORIZE")
        gov.execute_approved_action(action_id)

        log = gov.get_nostr_audit_log(action_id)

        # Kind 驗收
        assert log is not None, "【FAIL】Nostr 審計日誌未寫入！"
        assert (
            log["kind"] == 30078
        ), f"【FAIL】Nostr Kind 應為 30078，實際: {log['kind']}"

        # Tags 結構驗收
        tag_keys = [t[0] for t in log["tags"]]
        assert "d" in tag_keys, "【FAIL】缺少 NIP-78 'd' 標籤！"
        assert "action" in tag_keys, "【FAIL】缺少 'action' 標籤！"
        assert "t" in tag_keys, "【FAIL】缺少 't' 標籤！"

        # Content 驗收
        content = log["content"]
        assert content["action_id"] == action_id
        assert content["approval"] == "MULTI_SIG_ED25519_VERIFIED"
        assert content["action_type"] == "DTC_NVM_CLEAR"

        # 哈希不可篡改性：相同 event_hash 不可偽造
        event_hash = log["event_hash"]
        assert len(event_hash) == 64, "【FAIL】哈希長度應為 64 位 hex！"

        # 篡改偵測：修改 content 後哈希必然不同
        tampered = NostrAuditEvent(
            kind=30078,
            created_at=int(log["kind"]),
            tags=log["tags"],
            content=json.dumps({"tampered": True}),
        )
        assert (
            tampered.event_hash != event_hash
        ), "【FAIL】篡改後哈希與原始相同，不可篡改性失效！"

        print(
            f"  [PASS] Nostr Kind 30078 格式合規！"
            f"Event Hash [{event_hash[:12]}...]，"
            "篡改偵測生效，不可篡改性鑿實！"
        )
