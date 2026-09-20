"""Fallback Pipeline 驗收測試."""

from __future__ import annotations

import asyncio

import pytest

from fallback_pipeline import FallbackPipeline, PipelineMode, SafeOutput


# ── 模擬服務 ─────────────────────────────────────────

async def _good_primary(**kwargs: object) -> dict[str, object]:
    """正常主路徑."""
    return {"engine": "primary", "data": 42}


async def _bad_primary(**kwargs: object) -> dict[str, object]:
    """永遠逾時的主路徑."""
    await asyncio.sleep(10)
    return {}


async def _good_fallback(**kwargs: object) -> dict[str, object]:
    """正常備援引擎."""
    return {"engine": "fallback", "data": 7, "status": "SAFE_MODE"}


async def _bad_fallback(**kwargs: object) -> dict[str, object]:
    """也會失敗的備援."""
    msg = "backup down"
    raise ConnectionError(msg)


# ── 測試 1：主路徑正常 → PRIMARY ─────────────────────

@pytest.mark.asyncio
async def test_primary_healthy() -> None:
    """主路徑健康應回傳 PRIMARY 數據."""
    pipe = FallbackPipeline(primary=_good_primary, fallback=_good_fallback)
    result = await pipe.execute(prompt="test")

    assert result.is_degraded is False
    assert result.source == "primary"
    assert result.core_data["engine"] == "primary"
    assert pipe.mode == PipelineMode.PRIMARY


# ── 測試 2：主路徑連續 2 次失敗 → DEGRADED ───────────

@pytest.mark.asyncio
async def test_auto_degrade_after_2_failures() -> None:
    """連續 2 次逾時應自動降級至備援."""
    degraded_flag: list[bool] = []

    pipe = FallbackPipeline(
        primary=_bad_primary,
        fallback=_good_fallback,
        timeout=0.05,
        on_degraded=lambda: degraded_flag.append(True),
    )
    result = await pipe.execute(prompt="test")

    assert result.is_degraded is True
    assert result.source == "fallback"
    assert pipe.mode == PipelineMode.DEGRADED
    assert pipe.consecutive_failures >= 2
    assert len(degraded_flag) == 1  # on_degraded 被觸發


# ── 測試 3：降級後僅輸出防護型核心數據 ────────────────

@pytest.mark.asyncio
async def test_degraded_safe_output() -> None:
    """降級狀態應輸出備援的防護型數據."""
    pipe = FallbackPipeline(
        primary=_bad_primary,
        fallback=_good_fallback,
        timeout=0.05,
    )
    # 先觸發降級
    await pipe.execute()
    assert pipe.mode == PipelineMode.DEGRADED

    # 降級後再次呼叫，直接走備援
    result = await pipe.execute()
    assert result.is_degraded is True
    assert result.source == "fallback"
    assert result.diagnostics_pending > 0  # 診斷日誌已生成


# ── 測試 4：備援也失敗 → SAFE_MODE 兜底 ──────────────

@pytest.mark.asyncio
async def test_double_failure_safe_mode() -> None:
    """主路徑 + 備援都失敗應輸出 SAFE_MODE 兜底."""
    pipe = FallbackPipeline(
        primary=_bad_primary,
        fallback=_bad_fallback,
        timeout=0.05,
    )
    result = await pipe.execute()

    assert result.is_degraded is True
    assert result.source == "rule_engine"
    assert result.core_data["status"] == "SAFE_MODE"


# ── 測試 5：手動恢復主路徑 ───────────────────────────

@pytest.mark.asyncio
async def test_manual_recovery() -> None:
    """降級後手動恢復主路徑."""
    pipe = FallbackPipeline(
        primary=_good_primary,
        fallback=_good_fallback,
        timeout=0.05,
    )
    pipe.force_degraded()
    assert pipe.mode == PipelineMode.DEGRADED

    result = await pipe.try_recover()
    assert result.is_degraded is False
    assert result.source == "primary"
    assert pipe.mode == PipelineMode.PRIMARY
