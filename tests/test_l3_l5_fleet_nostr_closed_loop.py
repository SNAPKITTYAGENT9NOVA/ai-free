# -*- coding: utf-8 -*-
"""
End-to-End Test Suite:
L3 AutonomousHealer -> HybridModelRouter -> L5 FleetNostrMeshNode Swarm Mesh.

Validates:
1. AutonomousHealer triggering Level 2 derating dispatches to HybridModelRouter (EDGE_CRITICAL).
2. AutonomousHealer broadcasts homomorphic peer defense alerts across decentralized Nostr relays.
3. Fleet peer vehicles (SU7_PEER_002, YU7_PEER_003) verify signatures and take defensive actions.
4. AutonomousHealer emits Nostr Kind 30079 signed alert into the decentralized event pool.
5. Full closed loop from SOME/IP Sensor Telemetry (0x8002) to multi-vehicle swarm defense.
"""

from __future__ import annotations

import struct
from typing import Any

from autonomous_healer import AutonomousHealer, HealingLevel
from fleet_nostr_mesh import (
    NOSTR_KIND_HEALING_ALERT,
    NOSTR_KIND_VEHICLE_TELEMETRY,
    FleetNostrMeshNode,
)
from hybrid_model_router import ExecutionTier, HybridModelRouter
from soa_gateway_twin import SOAGateway


def test_healer_triggers_hybrid_router_and_fleet_nostr_mesh() -> None:
    vin = "VIN_XIAOMI_SU7_001"
    healer = AutonomousHealer(vin=vin, bind_socket=False)
    router = HybridModelRouter(vin=vin)
    fleet_mesh = FleetNostrMeshNode(vin=vin)

    # Attach L4 Router & L5 Swarm Mesh
    healer.attach_hybrid_router(router)
    healer.attach_fleet_mesh(fleet_mesh)

    # Trigger Level 2 Emergency Derating
    healer.trigger_healing_action(
        action_name="EMERGENCY_DERATING",
        new_power_limit=50,
        reason="高壓電池結溫驟升至 88°C，觸發保護",
    )

    # 1. Verify Hybrid Router Decision
    assert healer.last_routing_decision is not None
    decision = healer.last_routing_decision
    assert decision.target_tier == ExecutionTier.EDGE_CRITICAL
    assert decision.estimated_latency_ms <= 1.0
    assert decision.token_cost == 0

    # 2. Verify Fleet Nostr Mesh Peer Alert
    assert healer.last_nostr_broadcast is not None
    broadcast = healer.last_nostr_broadcast

    ev = broadcast["event"]
    assert ev["kind"] == NOSTR_KIND_VEHICLE_TELEMETRY
    assert ev["pubkey"] == fleet_mesh.pubkey_hex
    assert len(ev["id"]) == 64
    assert len(ev["sig"]) == 128
    assert ["p", "fleet_broadcast"] in ev["tags"]

    # 3. Verify Peer Vehicle Reactions
    peers = broadcast["peer_evaluations"]
    assert len(peers) >= 2
    peer_map = {p["peer_node"]: p for p in peers}

    assert "SU7_PEER_002" in peer_map
    assert peer_map["SU7_PEER_002"]["verified"] is True
    assert "+15m" in peer_map["SU7_PEER_002"]["action"]

    assert "YU7_PEER_003" in peer_map
    assert peer_map["YU7_PEER_003"]["verified"] is True

    # 4. Verify Kind 30079 Event in Pool
    recent = fleet_mesh.query_recent_events(limit=10)
    kinds = [e["kind"] for e in recent]
    assert NOSTR_KIND_HEALING_ALERT in kinds

    # 5. Verify SQLite Audit Entry
    audits = healer.get_recent_audits(limit=5)
    assert len(audits) > 0
    assert "EMERGENCY_DERATING" in audits[0]["action_taken"]
    assert audits[0]["torque_limit_pct"] == 50.0

    healer.close()


def test_full_chain_someip_to_healer_to_nostr_swarm() -> None:
    vin = "PHANTOM-SU7-LEADER"
    gateway = SOAGateway(enable_udp_broadcast=False)
    healer = AutonomousHealer(vin=vin, bind_socket=False)
    router = HybridModelRouter(vin=vin)
    fleet_mesh = FleetNostrMeshNode(vin=vin)

    healer.attach_hybrid_router(router)
    healer.attach_fleet_mesh(fleet_mesh)

    # Wire SOA Gateway callback directly to Healer
    def _on_event(m: Any) -> None:
        healer.process_incoming_event(m.serialize())

    gateway.register_subscriber(_on_event)

    # Craft SOME/IP Event 0x8002 (Sensor Telemetry: Voltage=11000mV, Temp=86°C)
    payload = struct.pack("!IB", 11000, 86)
    packet = gateway.pack_someip_event(service_id=0x1002, event_id=0x8002, payload=payload)

    # Inject packet into healer
    decision = healer.process_incoming_event(packet)
    assert decision is not None
    assert decision.level == HealingLevel.LEVEL_2_LIMP_HOME
    assert decision.torque_limit_pct == 30.0

    # Check that Nostr mesh received broadcast
    assert healer.last_nostr_broadcast is not None
    assert healer.last_nostr_broadcast["event"]["pubkey"] == fleet_mesh.pubkey_hex

    # Verify mesh status
    status = fleet_mesh.get_mesh_status()
    assert status["total_events_in_pool"] >= 2
    assert "Nostr" in status["protocol"]

    healer.close()
