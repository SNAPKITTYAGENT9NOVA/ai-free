"""Auto Pipeline 驗收測試."""

from __future__ import annotations

from auto_pipeline import (
    AutoPipeline,
    CoreModuleMonitor,
    DispatchEngine,
    IntentParser,
    IntentType,
    ModuleHealth,
    TaskState,
)


# ── 測試 1：意圖解析 — BUILD ─────────────────────────

def test_parse_build_intent() -> None:
    """建構類指令應解析為 BUILD."""
    parser = IntentParser()
    intent = parser.parse("build SLA Guard module")
    assert intent.intent_type == IntentType.BUILD


# ── 測試 2：意圖解析 — TEST ──────────────────────────

def test_parse_test_intent() -> None:
    """測試類指令應解析為 TEST."""
    parser = IntentParser()
    intent = parser.parse("pytest 驗收測試 全部跑一次")
    assert intent.intent_type == IntentType.TEST


# ── 測試 3：意圖解析 — REGISTER ──────────────────────

def test_parse_register_intent() -> None:
    """報名類指令應解析為 REGISTER."""
    parser = IntentParser()
    intent = parser.parse("報名 Kaggle 比賽 join competition")
    assert intent.intent_type == IntentType.REGISTER


# ── 測試 4：派工引擎直接派工 ─────────────────────────

def test_dispatch_skips_manual() -> None:
    """派工應直接從意圖生成，無需人工轉譯."""
    parser = IntentParser()
    engine = DispatchEngine()
    intent = parser.parse("deploy to production")

    ticket = engine.dispatch(intent)
    assert ticket.state == TaskState.DISPATCHED
    assert ticket.intent.intent_type == IntentType.DEPLOY


# ── 測試 5：執行完成 → COMPLETED ─────────────────────

def test_execute_completes() -> None:
    """執行後應標記為 COMPLETED."""
    parser = IntentParser()
    engine = DispatchEngine()
    intent = parser.parse("sync 歸檔 commit")
    ticket = engine.dispatch(intent)

    result = engine.execute(ticket.ticket_id)
    assert result.state == TaskState.COMPLETED
    assert result.completed_at is not None


# ── 測試 6：三大核心模組全在線 ───────────────────────

def test_core_modules_all_online() -> None:
    """通訊矩陣/狀態機/資料管線應全數在線."""
    monitor = CoreModuleMonitor()
    for mod in ["通訊矩陣", "狀態機", "資料管線"]:
        monitor.register(mod)
        monitor.heartbeat(mod)

    assert monitor.all_online is True
    assert monitor.all_aligned is True


# ── 測試 7：模組降級偵測 ─────────────────────────────

def test_module_degraded_detected() -> None:
    """模組降級應被偵測."""
    monitor = CoreModuleMonitor()
    monitor.register("狀態機")
    monitor.heartbeat("狀態機")
    monitor.mark_degraded("狀態機")

    assert monitor.all_online is False
    summary = monitor.status_summary()
    assert summary["狀態機"]["health"] == "DEGRADED"


# ── 測試 8：AutoPipeline 一鍵全自動 ─────────────────

def test_auto_pipeline_end_to_end() -> None:
    """一鍵全自動：意圖 → 派工 → 執行 → COMPLETED."""
    pipe = AutoPipeline()
    ticket = pipe.run("build Safety Interlock 熔斷模組")

    assert ticket.state == TaskState.COMPLETED
    assert ticket.intent.intent_type == IntentType.BUILD
    assert pipe.monitor.all_online is True


# ── 測試 9：AutoPipeline 預設三大模組已註冊 ──────────

def test_auto_pipeline_default_modules() -> None:
    """AutoPipeline 啟動時三大核心模組應已自動註冊."""
    pipe = AutoPipeline()
    summary = pipe.monitor.status_summary()

    assert "通訊矩陣" in summary
    assert "狀態機" in summary
    assert "資料管線" in summary
    assert all(v["health"] == "ONLINE" for v in summary.values())
