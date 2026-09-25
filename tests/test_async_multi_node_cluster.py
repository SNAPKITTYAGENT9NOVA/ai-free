# -*- coding: utf-8 -*-
"""
Tests for Asynchronous Multi-Node Concurrent Cluster Architecture
Verifies:
1. BaseNode alive counter rolling (0..15).
2. GatewayNode 10ms control frames (0x120) and 50ms heartbeat frames (0x080).
3. ActuatorNode 50ms heartbeat loss detection, entering degraded mode, and auto-recovery.
4. TelemetryNode 20ms voltage/temperature telemetry frames (0x380).
5. AsyncMultiNodeCluster concurrent coroutine lifecycle and message dispatch.
"""

from __future__ import annotations

import asyncio
import time
from typing import Any, List

import pytest

from multi_node_cluster import (
    ActuatorNode,
    AsyncMultiNodeCluster,
    BaseNode,
    GatewayNode,
    TelemetryNode,
)


class MockBusQueue:
    """Thread-safe and coroutine-friendly in-memory message queue for testing."""

    def __init__(self) -> None:
        self.sent_messages: List[Any] = []
        self._queue: List[Any] = []

    def send(self, msg: Any) -> None:
        self.sent_messages.append(msg)
        self._queue.append(msg)

    def recv(self, timeout: float = 0.01) -> Any:
        if self._queue:
            return self._queue.pop(0)
        return None


def test_base_node_counter():
    bus = MockBusQueue()
    node = BaseNode("TEST_NODE", 0x01, bus)
    for i in range(16):
        assert node.next_counter() == i
    assert node.next_counter() == 0  # Rollover


@pytest.mark.asyncio
async def test_gateway_node_frame_generation():
    bus = MockBusQueue()
    gw = GatewayNode("GW_NODE", 0x01, bus, target_power_pct=85)
    stop_event = asyncio.Event()

    task = asyncio.create_task(gw.run(stop_event))
    await asyncio.sleep(0.10)  # Enough for 8-10 control frames and heartbeat frames
    stop_event.set()
    await task

    assert gw.frames_sent >= 4
    ids_sent = [getattr(m, "arbitration_id", 0) for m in bus.sent_messages]
    assert 0x120 in ids_sent
    assert 0x080 in ids_sent


@pytest.mark.asyncio
async def test_actuator_heartbeat_timeout_and_recovery():
    bus = MockBusQueue()
    act = ActuatorNode("ACT_NODE", 0x02, bus)
    assert act.degraded is False

    # Simulate immediate 60ms passage since last command
    act.last_cmd_time = time.time() - 0.06
    stop_event = asyncio.Event()

    task = asyncio.create_task(act.run(stop_event))
    await asyncio.sleep(0.02)

    # Must have detected timeout and entered degraded mode
    assert act.degraded is True
    assert act.degraded_transitions >= 1

    # Send 0x120 command to recover
    fake_cmd = type(
        "FakeCANMessage",
        (),
        {
            "arbitration_id": 0x120,
            "data": bytes([0x01, 75, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAA]),
        },
    )()
    act.on_message_received(fake_cmd)

    assert act.degraded is False
    assert act.recovery_transitions >= 1

    stop_event.set()
    await task


@pytest.mark.asyncio
async def test_telemetry_node_frame_generation():
    bus = MockBusQueue()
    telem = TelemetryNode("TELEM_NODE", 0x03, bus, battery_mv=12600, temp_c=48)
    stop_event = asyncio.Event()

    task = asyncio.create_task(telem.run(stop_event))
    await asyncio.sleep(0.05)  # Enough for ~2 telemetry frames
    stop_event.set()
    await task

    assert telem.frames_sent >= 2
    sent_data = [getattr(m, "data", b"") for m in bus.sent_messages]
    # Check that temp_c (48) is encoded in byte 3
    assert any(len(d) >= 4 and d[3] == 48 for d in sent_data)


@pytest.mark.asyncio
async def test_async_multi_node_cluster_full_cycle():
    bus = MockBusQueue()
    cluster = AsyncMultiNodeCluster(bus=bus)

    res = await cluster.run_cluster(duration_sec=0.15)
    assert res["gw_frames"] >= 6
    assert res["act_frames"] >= 6
    assert res["telem_frames"] >= 3
    assert len(bus.sent_messages) >= 15


def test_sdk_exports_async_cluster():
    from phantom_grid import (  # type: ignore[import-untyped,import-not-found]
        ActuatorNode as SDKActuator,
    )
    from phantom_grid import (
        AsyncMultiNodeCluster as SDKCluster,
    )
    from phantom_grid import (
        BaseNode as SDKBase,
    )
    from phantom_grid import (
        GatewayNode as SDKGateway,
    )
    from phantom_grid import (
        TelemetryNode as SDKTelemetry,
    )

    assert SDKBase is not None
    assert SDKGateway is not None
    assert SDKActuator is not None
    assert SDKTelemetry is not None
    assert SDKCluster is not None
