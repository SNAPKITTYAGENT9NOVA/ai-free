# -*- coding: utf-8 -*-
"""
Governance & Runtime Core:
1. MultiSigGovernanceGate: 雙簽授權治理閘門 (👑 指揮官 + 秘書處 小米 雙簽解鎖)
2. TriTierMemoryEngine: 三層記憶自動沉澱管道 (00_System / 01_Memory / 02_Knowledge 創生即固化)
3. SafetyWatchdog: 安全狀態機與降級機制 (毫秒級 Fail-Silent / Fail-Operational)
4. AntiEntropyFilter: 語意抗熵過濾器 (剔除 AI 冗餘陳詞，維護指令純度)
"""

from __future__ import annotations

import enum
import hashlib
import json
import os
import re
import sqlite3
import threading
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple


# ============================================================================
# 1. 雙簽授權治理閘門 (MultiSigGovernanceGate)
# ============================================================================

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
                status=ProposalStatus.PENDING_SIGNATURES,
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
                # 計算密碼學審計哈希
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


# ============================================================================
# 2. 三層記憶自動沉澱管道 (TriTierMemoryEngine)
# ============================================================================

class TriTierMemoryEngine:
    """
    三層記憶自動沉澱管道：
    實體化 00_System（不變常數/協議）、01_Memory（動態日誌快照）與 02_Knowledge（固化的子節點藍圖），
    新創生的子模組藍圖自動寫入知識庫，達成「創生即固化」，重啟亦不遺失。
    """

    def __init__(self, root_dir: str = "."):
        self.root = Path(root_dir)
        self.system_dir = self.root / "00_System"
        self.memory_dir = self.root / "01_Memory"
        self.knowledge_dir = self.root / "02_Knowledge"
        self.blueprints_dir = self.knowledge_dir / "blueprints"

        # 確保三層目錄結構完整實體化
        self.system_dir.mkdir(parents=True, exist_ok=True)
        self.memory_dir.mkdir(parents=True, exist_ok=True)
        self.knowledge_dir.mkdir(parents=True, exist_ok=True)
        self.blueprints_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

    def persist_blueprint(
        self,
        node_name: str,
        blueprint_spec: Dict[str, Any],
        author: str = "PHANTOM_GRID",
    ) -> Path:
        """
        「創生即固化」：將新創生之子節點藍圖自動寫入 02_Knowledge/blueprints/
        """
        with self._lock:
            safe_name = re.sub(r"[^\w\-]", "_", node_name)
            file_path = self.blueprints_dir / f"{safe_name}_blueprint.json"
            md_path = self.blueprints_dir / f"{safe_name}_blueprint.md"

            blueprint_record = {
                "node_name": node_name,
                "author": author,
                "created_at_epoch": time.time(),
                "created_at_iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "specification": blueprint_spec,
                "integrity_sha256": hashlib.sha256(
                    json.dumps(blueprint_spec, sort_keys=True).encode("utf-8")
                ).hexdigest(),
            }

            # 固化 JSON 規格
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(blueprint_record, f, indent=2, ensure_ascii=False)

            # 固化 Markdown 藍圖
            with open(md_path, "w", encoding="utf-8") as f:
                f.write(
                    f"# 📐 子模組藍圖：{node_name}\n\n"
                    f"* **作者**: `{author}`\n"
                    f"* **沉澱時間**: `{blueprint_record['created_at_iso']}`\n"
                    f"* **完整性 SHA-256**: `{blueprint_record['integrity_sha256']}`\n\n"
                    f"## 規格定義\n```json\n"
                    f"{json.dumps(blueprint_spec, indent=2, ensure_ascii=False)}\n"
                    f"```\n"
                )

            return file_path

    def load_blueprint(self, node_name: str) -> Optional[Dict[str, Any]]:
        """讀取已固化之子節點藍圖"""
        with self._lock:
            safe_name = re.sub(r"[^\w\-]", "_", node_name)
            file_path = self.blueprints_dir / f"{safe_name}_blueprint.json"
            if not file_path.is_file():
                return None
            with open(file_path, "r", encoding="utf-8") as f:
                return json.load(f)

    def write_memory_snapshot(self, snapshot_name: str, state_data: Dict[str, Any]) -> Path:
        """沉澱動態運行時快照至 01_Memory"""
        with self._lock:
            snap_file = self.memory_dir / f"{snapshot_name}.json"
            with open(snap_file, "w", encoding="utf-8") as f:
                json.dump({
                    "snapshot": snapshot_name,
                    "timestamp": time.time(),
                    "state": state_data,
                }, f, indent=2, ensure_ascii=False)
            return snap_file


# ============================================================================
# 3. 安全狀態機與降級機制 (SafetyWatchdog)
# ============================================================================

class SafetyWatchdogState(enum.Enum):
    NORMAL = "NORMAL"                         # 正常運作
    FAIL_OPERATIONAL = "FAIL_OPERATIONAL"     # 故障維持 (降額至 50% 或開環維持)
    FAIL_SILENT = "FAIL_SILENT"               # 故障靜默 (立即切斷 PWM / 0% 輸出)
    SAFE_STATE_FAIL_SILENT = "SAFE_STATE_FAIL_SILENT"  # 靜默安全模式 (鎖定硬體防止暴衝)


class SafetyWatchdog:
    """
    安全狀態機與降級機制：
    即時監控節點心跳與硬體/律法異常，
    當遭遇因果悖論或硬體暴衝時在毫秒級切入 Fail-Silent / Fail-Operational 安全狀態。
    """

    def __init__(self, heartbeat_timeout_sec: float = 0.050):
        self.heartbeat_timeout = heartbeat_timeout_sec
        self.state = SafetyWatchdogState.NORMAL
        self._last_heartbeats: Dict[str, float] = {}
        self._lock = threading.RLock()
        self.pwm_duty_pct = 100.0
        self.power_limit_pct = 100.0

    def feed_heartbeat(self, node_id: str, timestamp: Optional[float] = None) -> None:
        """餵狗：記錄節點心跳"""
        with self._lock:
            ts = timestamp or time.time()
            self._last_heartbeats[node_id] = ts

    def inspect(self, now: Optional[float] = None) -> Tuple[SafetyWatchdogState, str]:
        """巡檢心跳是否超時"""
        with self._lock:
            t = now or time.time()
            for node_id, last_ts in self._last_heartbeats.items():
                if (t - last_ts) > self.heartbeat_timeout:
                    # 超時觸發降級
                    return self.trigger_transition(
                        target_state=SafetyWatchdogState.FAIL_OPERATIONAL,
                        reason=f"節點心跳超時: {node_id} (間隔: {(t - last_ts)*1000:.1f}ms > {self.heartbeat_timeout*1000:.1f}ms)",
                    )
            return self.state, "ALL_NODES_HEALTHY"

    def trigger_transition(
        self,
        target_state: SafetyWatchdogState,
        reason: str,
    ) -> Tuple[SafetyWatchdogState, str]:
        """執行毫秒級狀態機跳轉"""
        with self._lock:
            self.state = target_state

            if target_state in (SafetyWatchdogState.FAIL_SILENT, SafetyWatchdogState.SAFE_STATE_FAIL_SILENT):
                # 0ms 斷開 PWM，徹底防止硬體暴衝
                self.pwm_duty_pct = 0.0
                self.power_limit_pct = 0.0
                action = f"緊急觸發 SAFE_STATE_FAIL_SILENT: PWM 0ms 立即切斷 (0% Duty) | 原因: {reason}"
            elif target_state == SafetyWatchdogState.FAIL_OPERATIONAL:
                # 降額至 50% 或開環保底
                self.power_limit_pct = 50.0
                self.pwm_duty_pct = 50.0
                action = f"安全降級 FAIL_OPERATIONAL: 功率限制壓制在 50% | 原因: {reason}"
            else:
                self.pwm_duty_pct = 100.0
                self.power_limit_pct = 100.0
                action = f"恢復正常 NORMAL: 100% 全功率 | 原因: {reason}"

            return self.state, action


# ============================================================================
# 4. 語意抗熵過濾器 (AntiEntropyFilter)
# ============================================================================

class AntiEntropyFilter:
    """
    語意抗熵過濾器：
    在通訊匯流排出口自動剔除 AI 冗餘陳詞與空泛套話，
    維護高密度的指令執行純度。
    """

    # 內建過濾空泛與冗餘詞彙庫
    DEFAULT_ENTROPY_PATTERNS = [
        r"作為一個\s*AI(?:模型|助手)?(?:，|,)?",
        r"身為一個\s*AI(?:模型|助手)?(?:，|,)?",
        r"作為一名\s*AI(?:模型|助手)?(?:，|,)?",
        r"毋庸置疑(?:地)?(?:，|,)?",
        r"無可厚非(?:地)?(?:，|,)?",
        r"值得注意的是(?:，|,)?",
        r"總而言之(?:，|,)?",
        r"綜上所述(?:，|,)?",
        r"請放心(?:，|,)?",
        r"眾所周知(?:，|,)?",
        r"在某種程度上(?:，|,)?",
        r"不用擔心(?:，|,)?",
        r"如您所知(?:，|,)?",
        r"希望對(?:你|您)(?:有所)?(?:幫助|協助)(?:，|,)?(?:！|!)?",
    ]

    def __init__(self, custom_patterns: Optional[List[str]] = None):
        patterns = list(self.DEFAULT_ENTROPY_PATTERNS)
        if custom_patterns:
            patterns.extend(custom_patterns)
        self.regex = re.compile("|".join(f"(?:{p})" for p in patterns), re.IGNORECASE)

    def filter_egress(self, raw_command_text: str) -> Tuple[str, int, List[str]]:
        """
        過濾通訊匯流排出口文本：
        返回: (純淨指令字串, 剔除匹配次數, 匹配到的陳詞清單)
        """
        matched = self.regex.findall(raw_command_text)
        cleaned = self.regex.sub("", raw_command_text)

        # 清除可能殘留的多餘標點或首尾空格
        cleaned = re.sub(r"^[，,。！!\s]+", "", cleaned)
        cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()

        return cleaned, len(matched), matched

    @classmethod
    def purify(cls, raw_text: str) -> str:
        """快速指令提純：一鍵剔除空泛陳詞並返回純淨指令字串"""
        instance = cls()
        cleaned, _, _ = instance.filter_egress(raw_text)
        return cleaned

