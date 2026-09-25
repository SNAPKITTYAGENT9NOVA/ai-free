# -*- coding: utf-8 -*-
"""
Fleet Nostr Mesh (車載去中心化 Nostr 網格通信模組)
Conforms to Nostr NIP-01 and NIP-78.
"""
from fleet_nostr_mesh_node import (
    FleetNostrMeshNode,
    FleetNostrMeshNode as FleetNostrMesh,
    NostrEvent,
    NOSTR_KIND_VEHICLE_TELEMETRY,
    NOSTR_KIND_HEALING_ALERT,
)

__all__ = [
    "FleetNostrMesh",
    "FleetNostrMeshNode",
    "NostrEvent",
    "NOSTR_KIND_VEHICLE_TELEMETRY",
    "NOSTR_KIND_HEALING_ALERT",
]
