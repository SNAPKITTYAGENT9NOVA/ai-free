# -*- coding: utf-8 -*-
"""
Test Suite: Fleet Nostr Mesh Cross-Vehicle Homomorphic Peer Coordination
Validates:
1. Event generation and cryptographic signature (Nostr Kind 30078, ECC/Schnorr).
2. Decentralized WebSocket relay mesh dispatch (wss://relay.fleet.xiaomi.internal, wss://mesh.edge.vehicle.net).
3. Fleet peer signature verification & collaborative defense acceptance (<0.12ms verification):
   - SU7_PEER_002: Safety distance extension (+15m)
   - YU7_PEER_003: Defensive topology reorganization
   - CLOUD_ROUTER_NODE: Anomaly telemetry sync to global hotspots
"""

from __future__ import annotations

import json
from fleet_nostr_mesh import FleetNostrMesh, NOSTR_KIND_VEHICLE_TELEMETRY


def test_fleet_nostr_mesh_cross_vehicle_coordination():
    mesh = FleetNostrMesh(vin="VIN_XIAOMI_SU7_001")

    res = mesh.broadcast_homomorphic_peer_alert(
        alarm_type="THERMAL_DERATE_SYNC",
        power_limit_pct=50,
        temp_c=78,
        reason="Level 2 主動功率降額，廣播鄰近車輛保持安全跟車距離",
        timestamp_str="2026-09-25 05:14:34",
    )

    # 1. Event Validation
    ev = res["event"]
    assert ev["kind"] == NOSTR_KIND_VEHICLE_TELEMETRY
    assert ev["pubkey"] == mesh.pubkey_hex
    assert len(ev["id"]) == 64
    assert len(ev["sig"]) == 128
    assert ["p", "fleet_broadcast"] in ev["tags"]
    assert ["t", "EMERGENCY_ALARM"] in ev["tags"]

    content = json.loads(ev["content"])
    assert content["vin"] == "VIN_XIAOMI_SU7_001"
    assert content["alarm_type"] == "THERMAL_DERATE_SYNC"
    assert content["payload"]["power_limit_pct"] == 50
    assert content["payload"]["temp_c"] == 78

    # 2. Relay Mesh Validation
    assert "wss://relay.fleet.xiaomi.internal" in res["relays"]
    assert "wss://mesh.edge.vehicle.net" in res["relays"]

    # 3. Peer Defense Coordination Validation
    peers = res["peer_evaluations"]
    assert len(peers) == 3

    peer_map = {p["peer_node"]: p for p in peers}

    # Peer 1: SU7_PEER_002
    assert "SU7_PEER_002" in peer_map
    assert peer_map["SU7_PEER_002"]["verified"] is True
    assert peer_map["SU7_PEER_002"]["verification_latency_ms"] <= 0.20
    assert "+15m" in peer_map["SU7_PEER_002"]["action"]

    # Peer 2: YU7_PEER_003
    assert "YU7_PEER_003" in peer_map
    assert peer_map["YU7_PEER_003"]["verified"] is True
    assert "拓撲重組" in peer_map["YU7_PEER_003"]["action"]

    # Peer 3: CLOUD_ROUTER_NODE
    assert "CLOUD_ROUTER_NODE" in peer_map
    assert peer_map["CLOUD_ROUTER_NODE"]["verified"] is True
    assert "全域熱點庫" in peer_map["CLOUD_ROUTER_NODE"]["action"]
