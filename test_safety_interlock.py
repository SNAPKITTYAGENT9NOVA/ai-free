"""Safety Interlock 驗收測試."""

from __future__ import annotations

import pytest

from safety_interlock import (
    ChannelState,
    InterlockAlert,
    RiskTag,
    SafetyInterlock,
)


# ── 測試 1：安全指令 → 全速通行 ──────────────────────

def test_safe_command_passes_through() -> None:
    """安全指令不觸發攔截，回傳 None."""
    interlock = SafetyInterlock()
    result = interlock.check("git status")
    assert result is None


# ── 測試 2：批次刪除 → 自動暫停 ──────────────────────

def test_batch_delete_triggers_pause() -> None:
    """批次刪除指令應觸發熔斷暫停."""
    interlock = SafetyInterlock()
    result = interlock.check("rm -rf /data/*", "全部數據將被清除")

    assert result is not None
    assert result.risk_tag == RiskTag.BATCH_DELETE
    assert result.state == ChannelState.PAUSED
    assert "rm -rf" in result.summary


# ── 測試 3：配置覆寫偵測 ─────────────────────────────

def test_config_overwrite_detected() -> None:
    """配置覆寫關鍵字應被偵測."""
    interlock = SafetyInterlock()
    tags = interlock.scan("config overwrite production.yaml")
    assert RiskTag.CONFIG_OVERWRITE in tags


# ── 測試 4：環境變數變更偵測 ─────────────────────────

def test_env_var_change_detected() -> None:
    """環境變數變更應被偵測."""
    interlock = SafetyInterlock()
    tags = interlock.scan("export API_KEY=secret123")
    assert RiskTag.ENV_VAR_CHANGE in tags


# ── 測試 5：韌體燒錄偵測 ─────────────────────────────

def test_firmware_flash_detected() -> None:
    """韌體燒錄應被偵測."""
    interlock = SafetyInterlock()
    tags = interlock.scan("firmware flash v2.1 to ECU")
    assert RiskTag.FIRMWARE_FLASH in tags


# ── 測試 6：確認放行流程 ─────────────────────────────

def test_approve_releases_channel() -> None:
    """指揮官確認後通道應從 PAUSED → RELEASED."""
    interlock = SafetyInterlock()
    alert = interlock.check("batch delete old logs", "日誌目錄")
    assert alert is not None
    assert alert.state == ChannelState.PAUSED

    success = interlock.approve(alert.alert_id, approved_by="Jack")
    assert success is True
    assert alert.state == ChannelState.RELEASED
    assert alert.approved_by == "Jack"
    assert interlock.is_cleared(alert.alert_id) is True


# ── 測試 7：呈報格式包含摘要與影響 ───────────────────

def test_alert_prompt_format() -> None:
    """呈報應包含單行變更摘要 + 預估影響範圍."""
    interlock = SafetyInterlock()
    alert = interlock.check("drop table users", "users 資料表將被永久刪除")
    assert alert is not None

    prompt = alert.to_prompt()
    assert "熔斷攔截" in prompt
    assert "drop table users" in prompt
    assert "users 資料表將被永久刪除" in prompt
    assert "確認放行" in prompt


# ── 測試 8：on_alert 回呼觸發 ────────────────────────

def test_on_alert_callback_fired() -> None:
    """高危操作應觸發 on_alert 回呼."""
    fired: list[InterlockAlert] = []
    interlock = SafetyInterlock(on_alert=lambda a: fired.append(a))

    interlock.check("高額 token 推論批次", "預估消耗 50K tokens")
    assert len(fired) == 1
    assert fired[0].risk_tag == RiskTag.HIGH_TOKEN_COST


# ── 測試 9：待確認清單 ───────────────────────────────

def test_pending_alerts_list() -> None:
    """應能查詢所有待確認的攔截告警."""
    interlock = SafetyInterlock()
    interlock.check("rm -rf /tmp", "暫存區")
    interlock.check("export SECRET=abc", "環境變數")

    pending = interlock.get_pending()
    assert len(pending) == 2

    interlock.approve(pending[0].alert_id)
    assert len(interlock.get_pending()) == 1
