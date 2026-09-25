# -*- coding: utf-8 -*-
"""
PHANTOM GRID Core - Governance Gate
雙簽授權治理閘門 (MultiSigGovernanceGate)
任何涉及修改底層律法或衍生新實體的高危提案，必須取得 👑 指揮官與秘書處（小米）的雙重簽署驗證才能解鎖執行，
單簽則自動維持狀態攔截，防止單點誤觸。
"""

from __future__ import annotations

import enum
import hashlib
import json
import os
import sqlite3
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


class ProposalType(enum.Enum):
    MODIFY_BASE_LAW = "MODIFY_BASE_LAW"          # 修改底層律法
    DERIVE_NEW_ENTITY = "DERIVE_NEW_ENTITY"      # 衍生新實體
    CRITICAL_FIRMWARE_FLASH = "CRITICAL_FLASH"    # 關鍵韌體刷寫
    REGISTER_OVERWRITE = "REGISTER_OVERWRITE"    # 暫存器強制覆寫


class ProposalStatus(enum.Enum):
    PENDING = "PENDING"
    PENDING_SIGNATURES = "PENDING_SIGNATURES"
    INTERCEPTED_SINGLE_SIG = "INTERCEPTED_SINGLE_SIG"
    UNLOCKED_DUAL_SIG = "UNLOCKED_DUAL_SIG"
    REJECTED = "REJECTED"
    EXECUTED = "EXECUTED"


@dataclass
class GovernanceProposal:
    proposal_id: str
    title: str
    proposal_type: ProposalType
    payload: Dict[str, Any]
    commander_sig: Optional[str] = None
    secretariat_sig: Optional[str] = None
    status: ProposalStatus = ProposalStatus.PENDING
    created_at: float = field(default_factory=time.time)
    executed_at: Optional[float] = None
    audit_hash: Optional[str] = None

    @property
    def is_frozen_or_pending(self) -> bool:
        return self.status in (
            ProposalStatus.PENDING,
            ProposalStatus.PENDING_SIGNATURES,
            ProposalStatus.INTERCEPTED_SINGLE_SIG,
        )


class MultiSigGovernanceGate:
    """
    雙簽授權治理閘門：
    任何涉及修改底層律法或衍生新實體的高危提案，
    必須取得 👑 指揮官與秘書處（小米）的雙重簽署驗證才能解鎖執行，
    單簽則自動維持狀態攔截，防止單點誤觸。
    """

    COMMANDER_ROLE = "COMMANDER"
    SECRETARIAT_ROLE = "SECRETARIAT"

    def __init__(self, db_path: str = "01_Memory/audit_log.db"):
        self.db_path = db_path
        self._proposals: Dict[str, GovernanceProposal] = {}
        self._lock = threading.RLock()
        self._init_db()

    def _init_db(self) -> None:
        if self.db_path != ":memory:":
            Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self.db_path)
        with conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS multisig_proposals (
                    proposal_id TEXT PRIMARY KEY,
                    title TEXT,
                    proposal_type TEXT,
                    payload_json TEXT,
                    commander_sig TEXT,
                    secretariat_sig TEXT,
                    status TEXT,
                    created_at REAL,
                    executed_at REAL,
                    audit_hash TEXT
                )
            """)
        conn.close()

    def submit_proposal(
        self,
        title: str,
        proposal_type: ProposalType,
        payload: Dict[str, Any],
        proposal_id: Optional[str] = None,
    ) -> GovernanceProposal:
        """提交高危提案進入雙簽審批流"""
        with self._lock:
            pid = proposal_id or f"PROP-{int(time.time() * 1000)}"
            proposal = GovernanceProposal(
                proposal_id=pid,
                title=title,
                proposal_type=proposal_type,
                payload=payload,
                status=ProposalStatus.PENDING,
            )
            self._proposals[pid] = proposal
            self._sync_db(proposal)
            return proposal

    def sign_proposal(
        self,
        proposal_id: str,
        signer_role: str,
        signature_token: str,
    ) -> Tuple[bool, str, GovernanceProposal]:
        """對提案進行簽署驗證"""
        with self._lock:
            if proposal_id not in self._proposals:
                raise KeyError(f"Proposal {proposal_id} not found")

            prop = self._proposals[proposal_id]
            signer_upper = signer_role.upper()

            if "COMMANDER" in signer_upper or "👑" in signer_role or "哥" in signer_role:
                prop.commander_sig = signature_token
            elif "SECRETARIAT" in signer_upper or "小米" in signer_role:
                prop.secretariat_sig = signature_token
            else:
                return False, f"未授權簽署角色: {signer_role}", prop

            # 評估雙簽狀態
            has_commander = bool(prop.commander_sig and len(prop.commander_sig.strip()) > 0)
            has_secretariat = bool(prop.secretariat_sig and len(prop.secretariat_sig.strip()) > 0)

            if has_commander and has_secretariat:
                prop.status = ProposalStatus.UNLOCKED_DUAL_SIG
                # 計算密碼學審計哈希 (SHA-256)
                seal_raw = f"{prop.proposal_id}:{prop.proposal_type.value}:{prop.commander_sig}:{prop.secretariat_sig}"
                prop.audit_hash = hashlib.sha256(seal_raw.encode("utf-8")).hexdigest()
                self._sync_db(prop)
                return True, "雙簽核驗成功：提案已正式解鎖！", prop
            else:
                prop.status = ProposalStatus.INTERCEPTED_SINGLE_SIG
                self._sync_db(prop)
                missing = "秘書處 (小米)" if not has_secretariat else "👑 指揮官"
                return False, f"單簽維持攔截：尚缺 [{missing}] 簽署授權", prop

    def execute_proposal(self, proposal_id: str) -> Tuple[bool, str, Dict[str, Any]]:
        """執行已解鎖之雙簽提案"""
        with self._lock:
            if proposal_id not in self._proposals:
                raise KeyError(f"Proposal {proposal_id} not found")

            prop = self._proposals[proposal_id]
            if prop.status != ProposalStatus.UNLOCKED_DUAL_SIG:
                return False, f"執行遭拒：當前狀態為 [{prop.status.value}]，必須取得雙簽解鎖", {}

            prop.status = ProposalStatus.EXECUTED
            prop.executed_at = time.time()
            self._sync_db(prop)
            return True, "提案執行成功：底層變更已套用並固化", prop.payload

    def _sync_db(self, prop: GovernanceProposal) -> None:
        try:
            conn = sqlite3.connect(self.db_path)
            with conn:
                conn.execute("""
                    INSERT OR REPLACE INTO multisig_proposals (
                        proposal_id, title, proposal_type, payload_json,
                        commander_sig, secretariat_sig, status,
                        created_at, executed_at, audit_hash
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    prop.proposal_id,
                    prop.title,
                    prop.proposal_type.value,
                    json.dumps(prop.payload, ensure_ascii=False),
                    prop.commander_sig,
                    prop.secretariat_sig,
                    prop.status.value,
                    prop.created_at,
                    prop.executed_at,
                    prop.audit_hash,
                ))
            conn.close()
        except Exception:
            pass


class GovernanceDB:
    """
    SQLite Governance and Audit Trail Manager.
    Logs every autonomous healing action, MCP derate command, and HITL approval.
    """

    def __init__(self, db_path: str = "audit_log.db"):
        self.db_path = db_path
        self._conn = None
        if self.db_path == ":memory:":
            self._conn = sqlite3.connect(":memory:", check_same_thread=False)
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        if self._conn is not None:
            return self._conn
        return sqlite3.connect(self.db_path)

    def _init_db(self) -> None:
        """Initializes audit_logs schema."""
        if self.db_path != ":memory:":
            dir_name = os.path.dirname(self.db_path)
            if dir_name:
                os.makedirs(dir_name, exist_ok=True)
        conn = self._get_connection()
        with conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS audit_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT DEFAULT (datetime('now')),
                    task_id TEXT,
                    operator TEXT,
                    status TEXT,
                    action_type TEXT,
                    details TEXT
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_audit_logs_task ON audit_logs(task_id)
            """)
        if self._conn is None:
            conn.close()

    def log_approval(
        self,
        task_id: str,
        operator: str,
        status: str,
        details: str = "",
        action_type: str = "HITL_APPROVAL",
    ) -> None:
        """Logs an approval or execution event into audit_logs."""
        conn = self._get_connection()
        with conn:
            conn.execute("""
                INSERT INTO audit_logs (timestamp, task_id, operator, status, action_type, details)
                VALUES (datetime('now'), ?, ?, ?, ?, ?)
            """, (task_id, operator, status, action_type, details))
        if self._conn is None:
            conn.close()

    def is_approved_by_brother(self, task_id: str) -> bool:
        """
        Checks if the task has been explicitly approved by '哥' in audit_logs.
        Strictly requires operator = '哥' (or Commander alias) and status = 'APPROVED'.
        """
        conn = self._get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT status FROM audit_logs 
            WHERE task_id = ? AND (operator = '哥' OR operator = '👑 哥' OR operator = '👑 指揮官' OR operator LIKE '%Jack%') AND status = 'APPROVED'
            ORDER BY id DESC LIMIT 1
        """, (task_id,))
        row = cursor.fetchone()
        if self._conn is None:
            conn.close()
        return row is not None

    def query_logs(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Queries recent audit logs."""
        conn = self._get_connection()
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("""
            SELECT id, timestamp, task_id, operator, status, action_type, details
            FROM audit_logs ORDER BY id DESC LIMIT ?
        """, (limit,))
        rows = cursor.fetchall()
        result = [dict(r) for r in rows]
        if self._conn is None:
            conn.close()
        return result

    def close(self) -> None:
        """Closes the underlying SQLite database connection if persistent."""
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None

