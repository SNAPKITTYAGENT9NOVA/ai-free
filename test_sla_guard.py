"""SLA Guard 驗收測試."""

from __future__ import annotations

import asyncio

import pytest

from sla_guard import (
    HEARTBEAT_INTERVAL_S,
    MAX_RETRIES,
    RETRY_BACKOFF_S,
    TIMEOUT_THRESHOLD_S,
    NodeStatus,
    SLAGuard,
)


# ── 模擬探針 ─────────────────────────────────────────

async def _fast_probe(node_id: str) -> float:
    """模擬健康節點：50ms 回應."""
    await asyncio.sleep(0.05)
    return 50.0


async def _slow_probe(node_id: str) -> float:
    """模擬逾時節點：6 秒回應（超過 5 秒門檻）."""
    await asyncio.sleep(6.0)
    return 6000.0


_attempt_count: int = 0


async def _flaky_probe(node_id: str) -> float:
    """模擬瞬態抖動：第一次逾時，第二次正常."""
    global _attempt_count  # noqa: PLW0603
    _attempt_count += 1
    if _attempt_count % 2 == 1:
        await asyncio.sleep(6.0)  # 第一次逾時
        return 6000.0
    await asyncio.sleep(0.05)     # 第二次正常
    return 50.0


# ── 測試常數 ─────────────────────────────────────────

def test_constants() -> None:
    """驗證 SLA Guard 常數符合規格."""
    assert HEARTBEAT_INTERVAL_S == 3.0
    assert TIMEOUT_THRESHOLD_S == 5.0
    assert RETRY_BACKOFF_S == 1.5
    assert MAX_RETRIES == 1


# ── 測試健康節點 ─────────────────────────────────────

@pytest.mark.asyncio
async def test_healthy_node() -> None:
    """健康節點應回傳 HEALTHY 狀態."""
    guard = SLAGuard(probe=_fast_probe, timeout_threshold=5.0)
    guard.register("node-A")

    result = await guard.check_once()

    health = result["node-A"]
    assert health.status == NodeStatus.HEALTHY
    assert health.consecutive_failures == 0
    assert health.latency_ms == pytest.approx(50.0, abs=5.0)


# ── 測試逾時節點 → STAGNANT ──────────────────────────

@pytest.mark.asyncio
async def test_stagnant_node() -> None:
    """連續逾時節點應判定為 STAGNANT."""
    stagnant_nodes: list[str] = []

    guard = SLAGuard(
        probe=_slow_probe,
        timeout_threshold=0.1,       # 故意設極短門檻
        retry_backoff=0.05,          # 加速測試
        on_stagnant=lambda nid: stagnant_nodes.append(nid),
    )
    guard.register("node-B")

    result = await guard.check_once()

    health = result["node-B"]
    assert health.status == NodeStatus.STAGNANT
    assert health.consecutive_failures == 2  # 首次 + 重試
    assert "node-B" in stagnant_nodes


# ── 測試瞬態抖動重試成功 ─────────────────────────────

@pytest.mark.asyncio
async def test_flaky_retry_recovers() -> None:
    """瞬態抖動第一次逾時、重試成功應回傳 HEALTHY."""
    global _attempt_count  # noqa: PLW0603
    _attempt_count = 0

    guard = SLAGuard(
        probe=_flaky_probe,
        timeout_threshold=0.1,
        retry_backoff=0.05,
    )
    guard.register("node-C")

    result = await guard.check_once()

    health = result["node-C"]
    assert health.status == NodeStatus.HEALTHY
    assert health.consecutive_failures == 0


# ── 測試註冊 / 移除 ──────────────────────────────────

def test_register_unregister() -> None:
    """節點註冊與移除."""
    guard = SLAGuard(probe=_fast_probe)
    guard.register("x")
    assert guard.get_health("x") is not None
    guard.unregister("x")
    assert guard.get_health("x") is None
