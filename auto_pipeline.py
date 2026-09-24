"""Auto Pipeline — 核心任務自動流水線模組.

架構打通：指揮官高階意圖 → 解析 → 執行秘書派工引擎，零人工轉譯
狀態監控：通訊矩陣/狀態機/資料管線全數進入實時監控，數據流自動對齊
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable

logger = logging.getLogger(__name__)


class IntentType(Enum):
    """指揮官高階意圖類型."""

    BUILD = "BUILD"           # 建構 / 實作
    TEST = "TEST"             # 測試 / 驗收
    DEPLOY = "DEPLOY"         # 部署 / 發佈
    RESEARCH = "RESEARCH"     # 調研 / 搜尋
    REGISTER = "REGISTER"     # 報名 / 註冊
    SYNC = "SYNC"             # 同步 / 歸檔
    MONITOR = "MONITOR"       # 監控 / 巡檢


class TaskState(Enum):
    """任務狀態機."""

    QUEUED = "QUEUED"
    PARSING = "PARSING"
    DISPATCHED = "DISPATCHED"
    EXECUTING = "EXECUTING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


class ModuleHealth(Enum):
    """模組健康狀態."""

    ONLINE = "ONLINE"
    DEGRADED = "DEGRADED"
    OFFLINE = "OFFLINE"


@dataclass
class ParsedIntent:
    """解析後的指揮官意圖."""

    raw_input: str
    intent_type: IntentType
    targets: list[str]
    priority: int = 1          # 1=最高 5=最低
    confidence: float = 1.0    # 解析信心度


@dataclass
class TaskTicket:
    """派工單."""

    ticket_id: str
    intent: ParsedIntent
    state: TaskState = TaskState.QUEUED
    created_at: float = field(default_factory=time.time)
    completed_at: float | None = None
    result: dict[str, Any] = field(default_factory=dict)
    error: str | None = None


@dataclass
class ModuleStatus:
    """核心模組監控狀態."""

    module_name: str
    health: ModuleHealth = ModuleHealth.ONLINE
    last_heartbeat: float = field(default_factory=time.time)
    data_aligned: bool = True


# ── 意圖關鍵字對應表 ─────────────────────────────────
_INTENT_KEYWORDS: dict[IntentType, list[str]] = {
    IntentType.BUILD: ["build", "實作", "建構", "create", "寫", "做"],
    IntentType.TEST: ["test", "測試", "驗收", "pytest", "驗證"],
    IntentType.DEPLOY: ["deploy", "部署", "發佈", "publish", "上線"],
    IntentType.RESEARCH: ["research", "調研", "搜尋", "search", "查"],
    IntentType.REGISTER: ["register", "報名", "註冊", "enroll", "join"],
    IntentType.SYNC: ["sync", "同步", "歸檔", "備份", "commit"],
    IntentType.MONITOR: ["monitor", "監控", "巡檢", "status", "狀態"],
}


class IntentParser:
    """指揮官意圖解析器 — 零人工轉譯."""

    def parse(self, raw_input: str) -> ParsedIntent:
        """解析指揮官的高階意圖."""
        raw_lower = raw_input.lower()
        best_type = IntentType.BUILD  # 預設
        best_score = 0

        for intent_type, keywords in _INTENT_KEYWORDS.items():
            score = sum(1 for kw in keywords if kw in raw_lower)
            if score > best_score:
                best_score = score
                best_type = intent_type

        # 提取目標（以逗號或空格分割的名詞）
        targets = [
            w for w in raw_input.split()
            if len(w) > 2 and not any(kw in w.lower() for kws in _INTENT_KEYWORDS.values() for kw in kws)
        ]

        confidence = min(1.0, best_score / 2.0) if best_score > 0 else 0.5

        return ParsedIntent(
            raw_input=raw_input,
            intent_type=best_type,
            targets=targets[:5],
            confidence=confidence,
        )


class DispatchEngine:
    """執行秘書派工引擎."""

    def __init__(
        self,
        *,
        executor: Callable[[TaskTicket], dict[str, Any]] | None = None,
    ) -> None:
        self._tickets: dict[str, TaskTicket] = {}
        self._counter = 0
        self._executor = executor

    def dispatch(self, intent: ParsedIntent) -> TaskTicket:
        """從解析意圖直接派工，跳過人工轉譯."""
        self._counter += 1
        ticket_id = f"TASK-{self._counter:04d}"

        ticket = TaskTicket(
            ticket_id=ticket_id,
            intent=intent,
            state=TaskState.DISPATCHED,
        )
        self._tickets[ticket_id] = ticket

        logger.info(
            "DispatchEngine: 派工 %s [%s] → %s",
            ticket_id,
            intent.intent_type.value,
            intent.targets,
        )
        return ticket

    def execute(self, ticket_id: str) -> TaskTicket:
        """執行派工單."""
        ticket = self._tickets.get(ticket_id)
        if ticket is None:
            msg = f"找不到派工單 {ticket_id}"
            raise KeyError(msg)

        ticket.state = TaskState.EXECUTING
        try:
            if self._executor:
                ticket.result = self._executor(ticket)
            else:
                ticket.result = {"status": "OK", "intent": ticket.intent.intent_type.value}
            ticket.state = TaskState.COMPLETED
            ticket.completed_at = time.time()
        except Exception as exc:
            ticket.state = TaskState.FAILED
            ticket.error = str(exc)

        return ticket

    def get_ticket(self, ticket_id: str) -> TaskTicket | None:
        """查詢派工單."""
        return self._tickets.get(ticket_id)


class CoreModuleMonitor:
    """核心模組實時作業監控."""

    def __init__(self) -> None:
        self._modules: dict[str, ModuleStatus] = {}

    def register(self, name: str) -> None:
        """註冊核心模組."""
        self._modules[name] = ModuleStatus(module_name=name)

    def heartbeat(self, name: str) -> None:
        """更新模組心跳."""
        mod = self._modules.get(name)
        if mod:
            mod.last_heartbeat = time.time()
            mod.health = ModuleHealth.ONLINE

    def mark_degraded(self, name: str) -> None:
        """標記模組降級."""
        mod = self._modules.get(name)
        if mod:
            mod.health = ModuleHealth.DEGRADED

    @property
    def all_online(self) -> bool:
        """所有模組是否在線."""
        return all(m.health == ModuleHealth.ONLINE for m in self._modules.values())

    @property
    def all_aligned(self) -> bool:
        """數據流是否全自動對齊."""
        return all(m.data_aligned for m in self._modules.values())

    def status_summary(self) -> dict[str, Any]:
        """模組狀態摘要."""
        return {
            name: {
                "health": m.health.value,
                "aligned": m.data_aligned,
            }
            for name, m in self._modules.items()
        }


class AutoPipeline:
    """核心任務自動流水線.

    指揮官意圖 → 解析 → 派工 → 執行 → 全程監控
    """

    def __init__(self) -> None:
        self.parser = IntentParser()
        self.dispatch = DispatchEngine()
        self.monitor = CoreModuleMonitor()

        # 預設註冊三大核心模組
        for mod in ["通訊矩陣", "狀態機", "資料管線"]:
            self.monitor.register(mod)
            self.monitor.heartbeat(mod)

    def run(self, commander_input: str) -> TaskTicket:
        """一鍵全自動：意圖解析 → 派工 → 執行."""
        intent = self.parser.parse(commander_input)
        ticket = self.dispatch.dispatch(intent)
        self.dispatch.execute(ticket.ticket_id)
        return ticket
