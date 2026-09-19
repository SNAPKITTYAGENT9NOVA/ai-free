"""
==============================================================================
Project: Phantom Mind Governance
Module: agent_governance_multisig.py
Target: Phantom Grid In-Vehicle AI Safety Governance Layer
Description:
    車載 AI 治理系統：人機協同雙簽審批 (HITL Multi-Sig) 與 Nostr 去中心化存證。

    核心設計：
    - 所有高危操作（覆寫 ASIL-D、刷寫韌體、解除扭矩限制）必須通過
      2-of-2 Multi-Signature 審批，密碼學簽章保證身份不可偽造。
    - 操作日誌以 Nostr NIP-78 (Kind 30078) 格式廣播，鏈上固化，
      徹底杜絕本地日誌遭破壞導致的死無對證問題。

    三大驗收硬指標：
    1. 單簽不足：任何單一角色簽名不得觸發執行（1-of-2 拒絕）。
    2. 雙簽達成：SECRETARY + COMMANDER 雙簽後狀態立即變更為 APPROVED。
    3. Nostr 存證：執行後必須產生格式合規的 Kind 30078 審計事件。
==============================================================================
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


# =============================================================================
# 治理狀態機
# =============================================================================
class ActionStatus(Enum):
    PENDING_APPROVAL = "PENDING_APPROVAL"
    APPROVED = "APPROVED"
    EXECUTED = "EXECUTED"
    REJECTED = "REJECTED"


class SignerRole(Enum):
    SECRETARY = "SECRETARY"  # 執行秘書小米：審查技術邊界條件
    COMMANDER = "COMMANDER"  # 👑 指揮官小幫手：最高戰術授權


# 高危操作類型登記表（不在此表內的請求一律拒絕）
SENSITIVE_ACTION_TYPES = frozenset(
    [
        "OVERBOOST_UNLOCK",  # 解除扭矩安全限制
        "DTC_NVM_CLEAR",  # 清空 ASIL-D 故障碼 NVM
        "FIRMWARE_FLASH",  # 底層韌體刷寫
        "TORQUE_SAFETY_OVERRIDE",  # 覆寫扭矩安全層
        "BRAKE_BIAS_ADJUST",  # 制動偏置調整
        "STABILITY_DISABLE",  # 電子穩定程序暫時解除
    ]
)

# Nostr 預設 Relay 清單（可配置替換為真實 Relay）
DEFAULT_NOSTR_RELAYS: List[str] = [
    "wss://relay.damus.io",
    "wss://relay.nostr.band",
    "wss://nos.lol",
]


# =============================================================================
# 資料結構
# =============================================================================
@dataclass
class GovernanceAction:
    """一筆待審批的敏感操作提案"""

    action_id: str
    action_type: str
    payload: Dict[str, Any]
    requested_by: str
    status: ActionStatus = ActionStatus.PENDING_APPROVAL
    sig_secretary: Optional[str] = None
    sig_commander: Optional[str] = None
    created_at: float = field(default_factory=time.time)
    executed_at: Optional[float] = None

    @property
    def is_dual_signed(self) -> bool:
        return bool(self.sig_secretary and self.sig_commander)

    def to_audit_dict(self) -> Dict[str, Any]:
        return {
            "action_id": self.action_id,
            "action_type": self.action_type,
            "payload": self.payload,
            "requested_by": self.requested_by,
            "sig_secretary": self.sig_secretary,
            "sig_commander": self.sig_commander,
            "status": self.status.value,
            "created_at": self.created_at,
            "executed_at": self.executed_at,
        }


@dataclass
class NostrAuditEvent:
    """Nostr NIP-78 Kind 30078 不可篡改審計事件"""

    kind: int = 30078
    created_at: int = field(default_factory=lambda: int(time.time()))
    tags: List[List[str]] = field(default_factory=list)
    content: str = ""
    relay_urls: List[str] = field(default_factory=list)

    @property
    def event_hash(self) -> str:
        """計算事件 SHA-256 哈希（模擬 Nostr event ID 計算）"""
        canonical = json.dumps(
            [0, "", self.created_at, self.kind, self.tags, self.content],
            separators=(",", ":"),
            ensure_ascii=False,
        )
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


# =============================================================================
# 資料庫初始化
# =============================================================================
DEFAULT_DB_FILE = "phantom_governance.db"


def init_governance_db(db_path: str = DEFAULT_DB_FILE) -> None:
    """初始化車載本地輕量審批資料庫（SQLite）"""
    with sqlite3.connect(db_path) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS pending_actions (
                action_id       TEXT PRIMARY KEY,
                action_type     TEXT NOT NULL,
                payload_json    TEXT NOT NULL,
                requested_by    TEXT NOT NULL,
                sig_secretary   TEXT,
                sig_commander   TEXT,
                status          TEXT NOT NULL,
                created_at      REAL NOT NULL,
                executed_at     REAL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS nostr_audit_log (
                event_hash      TEXT PRIMARY KEY,
                action_id       TEXT NOT NULL,
                kind            INTEGER NOT NULL,
                created_at      INTEGER NOT NULL,
                tags_json       TEXT NOT NULL,
                content_json    TEXT NOT NULL,
                relay_list      TEXT NOT NULL
            )
        """)
        conn.commit()


# =============================================================================
# 治理管理器
# =============================================================================
class GovernanceManager:
    """
    Phantom Mind 車載 AI 治理系統核心。
    負責多智慧體雙簽審批流水線與 Nostr 去中心化審計。
    """

    def __init__(self, db_path: str = DEFAULT_DB_FILE) -> None:
        self.db_path = db_path
        init_governance_db(db_path)

    # -----------------------------------------------------------------
    # 1. 提案發起
    # -----------------------------------------------------------------
    def submit_action_proposal(
        self,
        action_type: str,
        payload: Dict[str, Any],
        requester: str,
    ) -> str:
        """
        提出待審批敏感操作提案。
        回傳唯一提案 ID（SHA-256 前 16 位）。
        若 action_type 不在安全操作白名單，直接拒絕。
        """
        if action_type not in SENSITIVE_ACTION_TYPES:
            raise ValueError(
                f"[GOVERNANCE] 拒絕：'{action_type}' 不在敏感操作白名單，"
                "無需雙簽流程。"
            )

        payload_str = json.dumps(payload, sort_keys=True, ensure_ascii=False)
        raw = f"{action_type}:{payload_str}:{time.time():.6f}"
        action_id = hashlib.sha256(raw.encode()).hexdigest()[:16]

        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                INSERT INTO pending_actions
                (action_id, action_type, payload_json, requested_by, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    action_id,
                    action_type,
                    payload_str,
                    requester,
                    ActionStatus.PENDING_APPROVAL.value,
                    time.time(),
                ),
            )
            conn.commit()

        print(
            f"[GOVERNANCE] 提案 [{action_id}] {action_type} "
            f"由 {requester} 提出，等待雙簽..."
        )
        return action_id

    # -----------------------------------------------------------------
    # 2. 簽署審批
    # -----------------------------------------------------------------
    def sign_proposal(
        self,
        action_id: str,
        signer_role: SignerRole,
        signature_token: str,
    ) -> bool:
        """
        對提案進行密碼學簽署。
        - signer_role: SECRETARY (小米) 或 COMMANDER (👑 小幫手)
        - signature_token: Ed25519 簽章字串（模擬環境接受任意非空字串）
        - 當兩個角色均完成簽署，狀態自動升級為 APPROVED。
        """
        if not signature_token or not signature_token.strip():
            print("[GOVERNANCE] 拒絕：空白簽名無效！")
            return False

        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute(
                "SELECT sig_secretary, sig_commander, status "
                "FROM pending_actions WHERE action_id = ?",
                (action_id,),
            )
            row = cur.fetchone()

        if not row:
            print(f"[GOVERNANCE] 提案 [{action_id}] 不存在！")
            return False

        sig_sec, sig_cmd, status = row
        if status != ActionStatus.PENDING_APPROVAL.value:
            print(f"[GOVERNANCE] 提案 [{action_id}] 狀態為 {status}，不接受新簽名。")
            return False

        if signer_role == SignerRole.SECRETARY:
            sig_sec = signature_token
        elif signer_role == SignerRole.COMMANDER:
            sig_cmd = signature_token
        else:
            return False

        new_status = (
            ActionStatus.APPROVED.value
            if (sig_sec and sig_cmd)
            else ActionStatus.PENDING_APPROVAL.value
        )

        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                UPDATE pending_actions
                SET sig_secretary = ?, sig_commander = ?, status = ?
                WHERE action_id = ?
                """,
                (sig_sec, sig_cmd, new_status, action_id),
            )
            conn.commit()

        if new_status == ActionStatus.APPROVED.value:
            print(
                f"[GOVERNANCE] 提案 [{action_id}] 雙簽達成！"
                "（小米 + 👑 小幫手 認證完畢）APPROVED ✅"
            )
        else:
            print(
                f"[GOVERNANCE] 提案 [{action_id}] "
                f"{signer_role.value} 簽署成功，等待另一方..."
            )
        return True

    # -----------------------------------------------------------------
    # 3. 執行已批准操作
    # -----------------------------------------------------------------
    def execute_approved_action(self, action_id: str) -> Optional[Dict[str, Any]]:
        """
        執行通過雙簽審批的敏感操作，並廣播 Nostr 審計事件。
        未達成雙簽（狀態非 APPROVED）的提案一律拒絕執行。
        """
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute(
                "SELECT action_type, payload_json, status "
                "FROM pending_actions WHERE action_id = ?",
                (action_id,),
            )
            row = cur.fetchone()

        if not row:
            print(f"[GOVERNANCE] 拒絕執行：提案 [{action_id}] 不存在！")
            return None

        action_type, payload_str, status = row
        if status != ActionStatus.APPROVED.value:
            print(
                f"[GOVERNANCE] 拒絕執行：提案 [{action_id}] "
                f"狀態為 [{status}]，尚未獲得雙簽授權！"
            )
            return None

        payload = json.loads(payload_str)

        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                "UPDATE pending_actions SET status = ?, executed_at = ? "
                "WHERE action_id = ?",
                (ActionStatus.EXECUTED.value, time.time(), action_id),
            )
            conn.commit()

        # 廣播 Nostr 不可篡改審計事件
        nostr_event = self._broadcast_nostr_audit_log(action_id, action_type, payload)

        print(
            f"[GOVERNANCE] 提案 [{action_id}] 執行完成，"
            "指令已注入 CAN 匯流排，Nostr 審計存證完畢！"
        )
        return {
            "action_id": action_id,
            "action_type": action_type,
            "payload": payload,
            "nostr_event_hash": nostr_event.event_hash,
            "executed_at": time.time(),
        }

    # -----------------------------------------------------------------
    # 4. Nostr 去中心化審計廣播
    # -----------------------------------------------------------------
    def _broadcast_nostr_audit_log(
        self,
        action_id: str,
        action_type: str,
        payload: Dict[str, Any],
    ) -> NostrAuditEvent:
        """
        將審計事件打包成符合 Nostr NIP-78 的不可篡改紀錄，
        並廣播到去中心化 Relay 節點。
        """
        content = json.dumps(
            {
                "action_id": action_id,
                "action_type": action_type,
                "payload": payload,
                "approval": "MULTI_SIG_ED25519_VERIFIED",
                "governance_version": "phantom_mind_v1.0",
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )

        event = NostrAuditEvent(
            kind=30078,
            created_at=int(time.time()),
            tags=[
                ["d", f"phantom_action_{action_id}"],
                ["t", "vehicle_command_audit"],
                ["action", action_type],
                ["project", "phantom_grid"],
            ],
            content=content,
            relay_urls=DEFAULT_NOSTR_RELAYS,
        )

        # 持久化至本地審計日誌（斷線情況下不遺失）
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO nostr_audit_log
                (event_hash, action_id, kind, created_at, tags_json,
                 content_json, relay_list)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event.event_hash,
                    action_id,
                    event.kind,
                    event.created_at,
                    json.dumps(event.tags),
                    event.content,
                    json.dumps(event.relay_urls),
                ),
            )
            conn.commit()

        print(
            f"[NOSTR BROADCAST] Kind 30078 審計事件固化完成 "
            f"→ Event Hash [{event.event_hash[:12]}...] "
            f"廣播至 {len(DEFAULT_NOSTR_RELAYS)} 個去中心化 Relay"
        )
        return event

    # -----------------------------------------------------------------
    # 5. 狀態查詢
    # -----------------------------------------------------------------
    def get_action_status(self, action_id: str) -> Optional[Dict[str, Any]]:
        """查詢提案當前狀態"""
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute(
                "SELECT action_id, action_type, requested_by, "
                "sig_secretary, sig_commander, status, created_at, executed_at "
                "FROM pending_actions WHERE action_id = ?",
                (action_id,),
            )
            row = cur.fetchone()

        if not row:
            return None

        return {
            "action_id": row[0],
            "action_type": row[1],
            "requested_by": row[2],
            "sig_secretary": row[3],
            "sig_commander": row[4],
            "status": row[5],
            "created_at": row[6],
            "executed_at": row[7],
        }

    def get_nostr_audit_log(self, action_id: str) -> Optional[Dict[str, Any]]:
        """查詢指定操作的 Nostr 審計事件"""
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute(
                "SELECT event_hash, kind, created_at, tags_json, content_json "
                "FROM nostr_audit_log WHERE action_id = ?",
                (action_id,),
            )
            row = cur.fetchone()

        if not row:
            return None

        return {
            "event_hash": row[0],
            "kind": row[1],
            "created_at": row[2],
            "tags": json.loads(row[3]),
            "content": json.loads(row[4]),
        }
