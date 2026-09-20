"""Safety Interlock — 熔斷攔截規則模組.

監控範圍：底層配置覆寫、批次刪除、環境變數變更、韌體燒錄、高額 Token 消耗
自動鎖定：高危標籤 → 通道暫停態 → 隔離執行權限
呈報規格：觸發時彈出「單行變更摘要 + 預估影響範圍」，確認即放行，常規任務不受影響
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable

logger = logging.getLogger(__name__)


class RiskTag(Enum):
    """高危操作標籤."""

    CONFIG_OVERWRITE = "CONFIG_OVERWRITE"       # 底層配置覆寫
    BATCH_DELETE = "BATCH_DELETE"               # 批次刪除
    ENV_VAR_CHANGE = "ENV_VAR_CHANGE"           # 環境變數變更
    FIRMWARE_FLASH = "FIRMWARE_FLASH"           # 韌體燒錄
    HIGH_TOKEN_COST = "HIGH_TOKEN_COST"         # 高額外部 Token 消耗


class ChannelState(Enum):
    """通道狀態."""

    RUNNING = "RUNNING"       # 正常全速通行
    PAUSED = "PAUSED"         # 暫停態：等待確認
    RELEASED = "RELEASED"     # 已放行


@dataclass
class InterlockAlert:
    """熔斷攔截告警."""

    alert_id: str
    risk_tag: RiskTag
    summary: str                    # 單行變更摘要
    impact_scope: str               # 預估影響範圍
    timestamp: float = field(default_factory=time.time)
    state: ChannelState = ChannelState.PAUSED
    approved_by: str | None = None
    approved_at: float | None = None

    def to_prompt(self) -> str:
        """產生呈報給指揮官的單行提示."""
        return (
            f"⚠️ 熔斷攔截 [{self.risk_tag.value}]\n"
            f"  變更摘要：{self.summary}\n"
            f"  影響範圍：{self.impact_scope}\n"
            f"  → 請確認放行 (Y/N)"
        )


# 高危關鍵字對應表
_RISK_KEYWORDS: dict[RiskTag, list[str]] = {
    RiskTag.CONFIG_OVERWRITE: [
        "config overwrite", "覆寫配置", "reset config",
        "overwrite settings", "replace config",
    ],
    RiskTag.BATCH_DELETE: [
        "batch delete", "批次刪除", "rm -rf", "drop table",
        "delete all", "purge", "truncate",
    ],
    RiskTag.ENV_VAR_CHANGE: [
        "env var", "環境變數", "set env", "export ",
        "setx ", "os.environ", "putenv",
    ],
    RiskTag.FIRMWARE_FLASH: [
        "firmware", "韌體", "flash", "燒錄",
        "ota update", "bootloader",
    ],
    RiskTag.HIGH_TOKEN_COST: [
        "high token", "高額 token", "token cost >",
        "batch inference", "大量推論",
    ],
}


class SafetyInterlock:
    """熔斷攔截守衛.

    Example
    -------
    >>> interlock = SafetyInterlock()
    >>> result = interlock.check("rm -rf /data/*", "清除所有數據")
    >>> result.state  # ChannelState.PAUSED
    >>> interlock.approve(result.alert_id, approved_by="Jack")
    >>> result.state  # ChannelState.RELEASED
    """

    def __init__(
        self,
        *,
        on_alert: Callable[[InterlockAlert], None] | None = None,
        custom_rules: dict[RiskTag, list[str]] | None = None,
    ) -> None:
        self._alerts: dict[str, InterlockAlert] = {}
        self._on_alert = on_alert
        self._alert_counter = 0
        self._rules = dict(_RISK_KEYWORDS)
        if custom_rules:
            for tag, keywords in custom_rules.items():
                self._rules.setdefault(tag, []).extend(keywords)

    # ── 掃描指令 ─────────────────────────────────────

    def scan(self, command: str) -> list[RiskTag]:
        """掃描指令文字，回傳匹配的高危標籤."""
        command_lower = command.lower()
        matched: list[RiskTag] = []
        for tag, keywords in self._rules.items():
            if any(kw in command_lower for kw in keywords):
                matched.append(tag)
        return matched

    # ── 檢查並攔截 ───────────────────────────────────

    def check(
        self,
        command: str,
        impact_scope: str = "未知",
    ) -> InterlockAlert | None:
        """檢查指令是否觸發熔斷.

        Returns
        -------
        InterlockAlert | None
            觸發時回傳告警（通道已暫停）；安全指令回傳 None（全速通行）。
        """
        tags = self.scan(command)
        if not tags:
            return None  # 常規任務，全速通行

        # 取最嚴重的標籤
        primary_tag = tags[0]
        self._alert_counter += 1
        alert_id = f"INTERLOCK-{self._alert_counter:04d}"

        alert = InterlockAlert(
            alert_id=alert_id,
            risk_tag=primary_tag,
            summary=command[:80],        # 單行變更摘要（截取前 80 字元）
            impact_scope=impact_scope,
            state=ChannelState.PAUSED,
        )
        self._alerts[alert_id] = alert

        logger.warning(
            "SafetyInterlock: 熔斷攔截 [%s] %s — 通道已暫停",
            primary_tag.value,
            alert_id,
        )

        if self._on_alert:
            self._on_alert(alert)

        return alert

    # ── 放行 ─────────────────────────────────────────

    def approve(self, alert_id: str, *, approved_by: str = "指揮官") -> bool:
        """指揮官確認放行."""
        alert = self._alerts.get(alert_id)
        if alert is None or alert.state != ChannelState.PAUSED:
            return False

        alert.state = ChannelState.RELEASED
        alert.approved_by = approved_by
        alert.approved_at = time.time()
        logger.info(
            "SafetyInterlock: %s 由 %s 確認放行",
            alert_id,
            approved_by,
        )
        return True

    # ── 拒絕 ─────────────────────────────────────────

    def reject(self, alert_id: str) -> bool:
        """拒絕執行，維持暫停."""
        alert = self._alerts.get(alert_id)
        if alert is None:
            return False
        alert.state = ChannelState.PAUSED
        logger.info("SafetyInterlock: %s 被拒絕執行", alert_id)
        return True

    # ── 查詢 ─────────────────────────────────────────

    def is_cleared(self, alert_id: str) -> bool:
        """檢查告警是否已放行."""
        alert = self._alerts.get(alert_id)
        return alert is not None and alert.state == ChannelState.RELEASED

    def get_pending(self) -> list[InterlockAlert]:
        """取得所有待確認的攔截告警."""
        return [a for a in self._alerts.values() if a.state == ChannelState.PAUSED]

    def get_history(self) -> list[InterlockAlert]:
        """取得所有攔截歷史."""
        return list(self._alerts.values())
