# -*- coding: utf-8 -*-
"""
Vehicle MCP Server (車載 Model Context Protocol Server)
Conforms to Model Context Protocol (MCP) JSON-RPC 2.0 Specifications & ISO 26262 ASIL-D.

Exposes vehicle digital twin telemetry, autonomous healing controls, ISO 14229 UDS DTC diagnostics,
Nostr decentralized mesh broadcasting, and hybrid cloud-edge routing as standard MCP tool endpoints.
Enables AI Agents and Commanders to conduct natural language scheduling, diagnostics, and intervention.
"""

from __future__ import annotations

import json
import os
import sys
import threading
import time
from typing import Any, Callable, Dict, List, Optional, Union

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from aegis_emc_canceller import ActiveAntiNoiseCanceller, CancellationResult, EMCInjectionSpec
from autonomous_healer import AutonomousHealer, HealingDecision, HealingLevel
from digital_twin_state import DigitalTwinMirrorEngine, DigitalTwinState
from efuse_isolation_engine import AttackType, EFuseIsolationEvent, EFuseProtectionEngine, EFuseState
from fleet_nostr_mesh_node import FleetNostrMeshNode, NostrEvent
from hpc_swarm_throughput_engine import ChannelStreamSpec, HPCBenchmarkResult, HPCSwarmThroughputEngine
from hybrid_model_router import ExecutionTier, HybridModelRouter, RoutingDecision

SERVER_NAME = "phantom-grid-vehicle-mcp"
SERVER_VERSION = "2026.4.0"


class VehicleMCPServer:
    """
    Standard In-Vehicle MCP (Model Context Protocol) JSON-RPC Server.
    Bridges local cyber-physical automotive state to LLM Agents and Commander consoles.
    """

    def __init__(
        self,
        vin: str = "PHANTOM-GRID-2026",
        twin_engine: Optional[DigitalTwinMirrorEngine] = None,
        healer: Optional[AutonomousHealer] = None,
        mesh_node: Optional[FleetNostrMeshNode] = None,
        router: Optional[HybridModelRouter] = None,
        efuse_engine: Optional[EFuseProtectionEngine] = None,
        emc_canceller: Optional[ActiveAntiNoiseCanceller] = None,
        hpc_swarm_engine: Optional[HPCSwarmThroughputEngine] = None,
    ):
        self.vin = vin
        self.twin_engine = twin_engine or DigitalTwinMirrorEngine(vin=vin)
        self.healer = healer or AutonomousHealer(twin_engine=self.twin_engine, vin=vin, db_path=":memory:")
        self.mesh_node = mesh_node or FleetNostrMeshNode(vin=vin)
        self.router = router or HybridModelRouter(vin=vin)
        self.efuse_engine = efuse_engine or EFuseProtectionEngine(vin=vin, db_path=":memory:")
        self.emc_canceller = emc_canceller or ActiveAntiNoiseCanceller(vin=vin, db_path=":memory:")
        self.hpc_swarm_engine = hpc_swarm_engine or HPCSwarmThroughputEngine(vin=vin, db_path=":memory:")
        self._lock = threading.RLock()

        # Tool registry
        self._tools: Dict[str, Dict[str, Any]] = self._register_tool_schemas()

    # ------------------------------------------------------------------------
    # 1. MCP Tool Schemas
    # ------------------------------------------------------------------------

    def _register_tool_schemas(self) -> Dict[str, Dict[str, Any]]:
        """Defines official tool metadata conforming to standard MCP schemas."""
        return {
            "get_digital_twin_telemetry": {
                "name": "get_digital_twin_telemetry",
                "description": "Retrieves real-time cyber-physical Digital Twin telemetry, health scores, motor RPM, and battery thermal metrics.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "detailed": {
                            "type": "boolean",
                            "description": "If true, includes cockpit HUD dials and cloud audit hashes.",
                            "default": False,
                        }
                    },
                },
            },
            "trigger_autonomous_healing": {
                "name": "trigger_autonomous_healing",
                "description": "Commands or overrides the edge autonomous healing level (0: Normal, 1: Dynamic Derating 70%, 2: Limp-Home 30%, 3: Safe Stop 0%).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "force_level": {
                            "type": "integer",
                            "description": "Target healing level (0 to 3)",
                            "minimum": 0,
                            "maximum": 3,
                        },
                        "reason": {
                            "type": "string",
                            "description": "Operator rationale for intervention",
                            "default": "AI Agent Supervisory Command",
                        },
                    },
                    "required": ["force_level"],
                },
            },
            "query_uds_dtc_diagnostics": {
                "name": "query_uds_dtc_diagnostics",
                "description": "Inspects ISO 14229 UDS active Diagnostic Trouble Codes (DTCs), severity ratings, and recommended remediation.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "clear_codes": {
                            "type": "boolean",
                            "description": "Whether to request clearing non-critical codes (requires safety check)",
                            "default": False,
                        }
                    },
                },
            },
            "broadcast_nostr_mesh_telemetry": {
                "name": "broadcast_nostr_mesh_telemetry",
                "description": "Signs and broadcasts current digital twin telemetry across decentralized Nostr mesh nodes using NIP-78 custom events.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "note": {
                            "type": "string",
                            "description": "Operator note or situational context",
                            "default": "Autonomous situational dispatch",
                        }
                    },
                },
            },
            "route_hybrid_cloud_edge": {
                "name": "route_hybrid_cloud_edge",
                "description": "Evaluates task priority and dynamically determines execution tier (Edge Critical vs Edge Local Agent vs Cloud Fleet Global).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "task_type": {
                            "type": "string",
                            "description": "Type of computational or healing task",
                        },
                        "urgency": {
                            "type": "string",
                            "description": "Urgency rating (SAFETY_CRITICAL | DIAGNOSTIC_QUERY | FLEET_ORCHESTRATION)",
                            "default": "NORMAL",
                        },
                    },
                    "required": ["task_type"],
                },
            },
            "get_healing_audit_history": {
                "name": "get_healing_audit_history",
                "description": "Retrieves the immutable SQLite audit log of past autonomous healing actions and cryptographic signatures.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "limit": {
                            "type": "integer",
                            "description": "Maximum number of audit records to return",
                            "default": 10,
                        }
                    },
                },
            },
            "trigger_efuse_hardware_isolation": {
                "name": "trigger_efuse_hardware_isolation",
                "description": "Commands smart E-Fuse 100A peak cutoff and pin hardware physical isolation against a malicious/unauthorized node.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "node_id": {
                            "type": "string",
                            "description": "Target ECU node identifier (e.g. UNAUTHORIZED_NODE_0x666)",
                        },
                        "can_id": {
                            "type": "integer",
                            "description": "Target CAN ID (e.g. 0x666)",
                            "default": 0x666,
                        },
                        "reason": {
                            "type": "string",
                            "description": "Remediation reason for physical fuse blowout",
                            "default": "Unauthorized firmware tampering or torque spoofing attack",
                        },
                    },
                    "required": ["node_id"],
                },
            },
            "get_efuse_blacklist": {
                "name": "get_efuse_blacklist",
                "description": "Queries the hardware-isolated node blacklist and cryptographic SHA-256 seals.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "limit": {
                            "type": "integer",
                            "description": "Maximum number of blacklist entries to retrieve",
                            "default": 20,
                        }
                    },
                },
            },
            "simulate_emc_anti_noise_cancellation": {
                "name": "simulate_emc_anti_noise_cancellation",
                "description": "Executes 30ps 180° active anti-phase noise cancellation against extreme RF/EMI interference (+95.5 dBm down to -120 dBm).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "channel_name": {
                            "type": "string",
                            "description": "Target analog frontend or bus channel (e.g. CAN_H_ANALOG_IN)",
                            "default": "CAN_H_ANALOG_IN",
                        },
                        "raw_emi_power_dbm": {
                            "type": "number",
                            "description": "Injected EMI power in dBm",
                            "default": 95.5,
                        },
                    },
                },
            },
            "get_emc_cancellation_records": {
                "name": "get_emc_cancellation_records",
                "description": "Retrieves the SQLite audit records of EMC noise suppression events and SHA-256 proofs.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "limit": {
                            "type": "integer",
                            "description": "Maximum number of audit records to retrieve",
                            "default": 10,
                        }
                    },
                },
            },
            "run_hpc_swarm_throughput_drill": {
                "name": "run_hpc_swarm_throughput_drill",
                "description": "Executes 100-channel massive concurrency ingestion (50 CAN-FD + 50 SOME/IP) and validates 5.00 Gbps line-rate throughput with zero packet loss.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "num_channels": {
                            "type": "integer",
                            "description": "Number of concurrent channels (default: 100)",
                            "default": 100,
                        },
                        "burst_duration_sec": {
                            "type": "number",
                            "description": "Burst test duration in seconds (default: 0.1)",
                            "default": 0.1,
                        },
                    },
                },
            },
            "get_hpc_swarm_benchmarks": {
                "name": "get_hpc_swarm_benchmarks",
                "description": "Retrieves past HPC swarm 5Gbps benchmark records and cryptographic SHA-256 seals.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "limit": {
                            "type": "integer",
                            "description": "Maximum number of benchmark records to return",
                            "default": 10,
                        }
                    },
                },
            },
        }

    # ------------------------------------------------------------------------
    # 2. Tool Implementations
    # ------------------------------------------------------------------------

    def execute_tool(self, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatches an MCP tool call and returns structured JSON output."""
        with self._lock:
            if name == "get_digital_twin_telemetry":
                return self._tool_get_telemetry(arguments.get("detailed", False))
            elif name == "trigger_autonomous_healing":
                return self._tool_trigger_healing(
                    force_level=arguments.get("force_level", 1),
                    reason=arguments.get("reason", "Operator Override"),
                )
            elif name == "query_uds_dtc_diagnostics":
                return self._tool_query_dtcs(arguments.get("clear_codes", False))
            elif name == "broadcast_nostr_mesh_telemetry":
                return self._tool_broadcast_nostr(arguments.get("note", "Situational dispatch"))
            elif name == "route_hybrid_cloud_edge":
                return self._tool_route_hybrid(
                    task_type=arguments.get("task_type", "diagnostic"),
                    urgency=arguments.get("urgency", "NORMAL"),
                )
            elif name == "get_healing_audit_history":
                return self._tool_get_audit_history(arguments.get("limit", 10))
            elif name == "trigger_efuse_hardware_isolation":
                return self._tool_trigger_efuse_isolation(
                    node_id=arguments.get("node_id", "UNAUTHORIZED_NODE_0x666"),
                    can_id=arguments.get("can_id", 0x666),
                    reason=arguments.get("reason", "Malicious node isolation"),
                )
            elif name == "get_efuse_blacklist":
                return self._tool_get_efuse_blacklist(arguments.get("limit", 20))
            elif name == "simulate_emc_anti_noise_cancellation":
                return self._tool_simulate_emc_cancellation(
                    channel_name=arguments.get("channel_name", "CAN_H_ANALOG_IN"),
                    raw_emi_power_dbm=arguments.get("raw_emi_power_dbm", 95.5),
                )
            elif name == "get_emc_cancellation_records":
                return self._tool_get_emc_records(arguments.get("limit", 10))
            elif name == "run_hpc_swarm_throughput_drill":
                return self._tool_run_hpc_swarm(
                    num_channels=arguments.get("num_channels", 100),
                    burst_duration_sec=arguments.get("burst_duration_sec", 0.1),
                )
            elif name == "get_hpc_swarm_benchmarks":
                return self._tool_get_hpc_benchmarks(arguments.get("limit", 10))
            else:
                raise ValueError(f"Unknown MCP tool: {name}")

    def _tool_get_telemetry(self, detailed: bool) -> Dict[str, Any]:
        snap = self.twin_engine.get_snapshot()
        res: Dict[str, Any] = {
            "vin": self.vin,
            "status": "ONLINE",
            "telemetry": {
                "motor_rpm": round(snap.motor_rpm, 1),
                "motor_degraded": snap.motor_degraded,
                "battery_voltage_mv": snap.battery_voltage_mv,
                "battery_voltage_v": round(snap.battery_voltage_mv / 1000.0, 2),
                "temperature_c": round(snap.temperature_c, 1),
                "actual_torque_nm": round(snap.actual_torque_nm, 1),
                "torque_limit_pct": round(snap.torque_limit_pct, 1),
                "coolant_pressure_kpa": round(snap.coolant_pressure_kpa, 1),
                "health_score_pct": round(snap.health_score, 1),
                "safety_mode": snap.safety_mode,
                "alive_counter": snap.alive_counter,
                "sync_cycles": snap.total_sync_cycles,
            },
            "healing_engine_level": self.healer.current_level.name,
        }
        if detailed:
            res["cockpit_display"] = self.twin_engine.to_cockpit_telemetry()
            res["cloud_v2x_feed"] = self.twin_engine.to_cloud_v2x_payload()
        return res

    def _tool_trigger_healing(self, force_level: int, reason: str) -> Dict[str, Any]:
        decision = self.healer.manual_override_healing(
            target_level=force_level,
            reason=reason,
            operator="AI Agent / Commander Console",
        )
        return {
            "status": "SUCCESS",
            "commanded_level": decision.level.name,
            "torque_limit_pct": decision.torque_limit_pct,
            "safety_mode": decision.safety_mode,
            "action_taken": decision.action_taken,
            "audit_status": decision.status,
            "timestamp": decision.timestamp,
        }

    def _tool_query_dtcs(self, clear_codes: bool) -> Dict[str, Any]:
        snap = self.twin_engine.get_snapshot()
        dtcs: List[Dict[str, Any]] = []

        # Thermal Over-Temperature DTC
        if snap.temperature_c > 85.0:
            dtcs.append({
                "dtc": "P0A2F",
                "severity": "CRITICAL",
                "description": "Drive Motor 'A' Temperature Exceeded High Threshold (>85°C)",
                "action": "Level 2 Limp-Home dynamic derating engaged; inspect coolant flow.",
            })
        elif snap.temperature_c > 75.0:
            dtcs.append({
                "dtc": "P0A2E",
                "severity": "WARNING",
                "description": "Drive Motor 'A' Temperature Warning (>75°C)",
                "action": "Level 1 dynamic thermal derating clamped to 70%.",
            })

        # Under-Voltage DTC
        if snap.battery_voltage_mv < 320000:
            dtcs.append({
                "dtc": "P0562",
                "severity": "CRITICAL",
                "description": "System High Voltage Potential Low (<320V Droop)",
                "action": "Engage battery protection circuit, clamp auxiliary loads.",
            })

        # Degradation DTC
        if snap.motor_degraded:
            dtcs.append({
                "dtc": "P0A80",
                "severity": "CAUTION",
                "description": "Powertrain Dynamic Power Derating Active",
                "action": "Torque ceiling active; maintain safe vehicle velocity.",
            })

        return {
            "vin": self.vin,
            "total_active_dtcs": len(dtcs),
            "dtc_list": dtcs if dtcs else [{"dtc": "P0000", "severity": "NOMINAL", "description": "No active DTCs. All vehicle systems optimal."}],
            "clear_requested": clear_codes,
            "cleared_status": "DTCs are real-time sensory faults; cleared on thermal/voltage recovery." if clear_codes else "Active monitoring",
        }

    def _tool_broadcast_nostr(self, note: str) -> Dict[str, Any]:
        snap = self.twin_engine.get_snapshot()
        telemetry_payload = {
            "vin": self.vin,
            "motor_rpm": round(snap.motor_rpm, 1),
            "temperature_c": round(snap.temperature_c, 1),
            "battery_voltage_mv": snap.battery_voltage_mv,
            "torque_limit_pct": round(snap.torque_limit_pct, 1),
            "health_score_pct": round(snap.health_score, 1),
            "safety_mode": snap.safety_mode,
        }
        event = self.mesh_node.broadcast_telemetry(
            digital_twin_telemetry=telemetry_payload,
            healing_level=self.healer.current_level.value,
            note=note,
        )
        return {
            "status": "BROADCAST_SUCCESS",
            "nostr_event_id": event.id,
            "kind": event.kind,
            "pubkey": event.pubkey,
            "signature": f"{event.sig[:24]}...",
            "verified": event.verify(),
            "relays_dispatched": self.mesh_node.mesh_relays,
        }

    def _tool_route_hybrid(self, task_type: str, urgency: str) -> Dict[str, Any]:
        decision = self.router.route_request(task_type=task_type, urgency=urgency)
        return {
            "task_id": decision.task_id,
            "target_tier": decision.target_tier.value,
            "target_engine": decision.target_engine,
            "dispatch_channel": decision.dispatch_channel,
            "estimated_latency_ms": decision.estimated_latency_ms,
            "token_cost": decision.token_cost,
            "rationale": decision.rationale,
        }

    def _tool_get_audit_history(self, limit: int) -> Dict[str, Any]:
        audits = self.healer.get_recent_audits(limit=limit)
        summary = self.healer.get_audit_summary()
        return {
            "total_audit_records": summary["total_records"],
            "current_healer_level": summary["current_level"],
            "recent_audits": audits,
        }

    def _tool_trigger_efuse_isolation(self, node_id: str, can_id: int, reason: str) -> Dict[str, Any]:
        event = self.efuse_engine.trigger_efuse_burnout_isolation(
            node_id=node_id,
            can_id=can_id,
            attack_type=AttackType.UNAUTHORIZED_NODE_INJECTION,
            reason=reason,
        )
        return {
            "status": "HARDWARE_ISOLATED",
            "incident_id": event.incident_id,
            "target_node_id": event.target_node_id,
            "target_can_id": f"0x{event.target_can_id:03X}",
            "trip_current_a": event.peak_trip_current_a,
            "efuse_state": event.efuse_state.value,
            "pin_isolated": event.pin_isolated,
            "blacklisted": event.blacklisted,
            "security_sha256": event.security_hash,
            "action_taken": event.action_taken,
        }

    def _tool_get_efuse_blacklist(self, limit: int) -> Dict[str, Any]:
        records = self.efuse_engine.get_blacklist_records(limit=limit)
        return {
            "vin": self.vin,
            "total_isolated_nodes": len(records),
            "blacklist_records": records,
        }

    def _tool_simulate_emc_cancellation(self, channel_name: str, raw_emi_power_dbm: float) -> Dict[str, Any]:
        spec = EMCInjectionSpec(
            channel_name=channel_name,
            raw_emi_power_dbm=raw_emi_power_dbm,
        )
        res = self.emc_canceller.execute_active_cancellation(spec)
        return {
            "status": "CANCELLATION_SUCCESS",
            "incident_id": res.incident_id,
            "channel_name": res.channel_name,
            "raw_noise_dbm": res.raw_noise_dbm,
            "anti_phase_angle_deg": res.anti_phase_angle_deg,
            "residual_noise_dbm": res.residual_noise_dbm,
            "total_attenuation_db": round(res.total_attenuation_db, 1),
            "response_latency_ps": res.response_latency_ps,
            "signal_snr_db": round(res.signal_snr_db, 1),
            "emc_compliance": res.emc_compliance,
            "security_sha256": res.security_hash,
        }

    def _tool_get_emc_records(self, limit: int) -> Dict[str, Any]:
        records = self.emc_canceller.get_recent_emc_records(limit=limit)
        return {
            "vin": self.vin,
            "total_emc_records": len(records),
            "emc_audit_records": records,
        }

    def _tool_run_hpc_swarm(self, num_channels: int, burst_duration_sec: float) -> Dict[str, Any]:
        res = self.hpc_swarm_engine.run_hpc_swarm_benchmark(
            num_channels=num_channels,
            burst_duration_sec=burst_duration_sec,
        )
        return {
            "status": "BENCHMARK_SUCCESS",
            "run_id": res.run_id,
            "total_channels": res.total_channels,
            "can_fd_channels": res.can_fd_channels,
            "someip_channels": res.someip_channels,
            "effective_throughput_gbps": res.effective_throughput_gbps,
            "packet_loss_rate_pct": res.packet_loss_rate_pct,
            "avg_latency_us": res.avg_latency_us,
            "total_bytes_processed": res.total_bytes_processed,
            "hpc_status": res.hpc_status,
            "security_sha256": res.security_hash,
        }

    def _tool_get_hpc_benchmarks(self, limit: int) -> Dict[str, Any]:
        records = self.hpc_swarm_engine.get_recent_benchmarks(limit=limit)
        return {
            "vin": self.vin,
            "total_benchmarks": len(records),
            "benchmark_records": records,
        }

    # ------------------------------------------------------------------------
    # 3. Standard JSON-RPC 2.0 Dispatcher
    # ------------------------------------------------------------------------

    def handle_jsonrpc(self, request_bytes_or_str: Union[str, bytes, Dict[str, Any]]) -> Dict[str, Any]:
        """Processes a standard JSON-RPC 2.0 MCP request."""
        if isinstance(request_bytes_or_str, (str, bytes)):
            try:
                req = json.loads(request_bytes_or_str)
            except Exception as e:
                return {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": -32700, "message": f"Parse error: {str(e)}"},
                }
        else:
            req = request_bytes_or_str

        req_id = req.get("id")
        method = req.get("method")
        params = req.get("params", {})

        # MCP Method: initialize
        if method == "initialize":
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "serverInfo": {
                        "name": SERVER_NAME,
                        "version": SERVER_VERSION,
                    },
                    "capabilities": {
                        "tools": {"listChanged": False},
                    },
                },
            }

        # MCP Method: ping
        elif method == "ping":
            return {"jsonrpc": "2.0", "id": req_id, "result": {}}

        # MCP Method: tools/list
        elif method == "tools/list":
            tools_list = list(self._tools.values())
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"tools": tools_list},
            }

        # MCP Method: tools/call
        elif method == "tools/call":
            tool_name = params.get("name")
            arguments = params.get("arguments", {})
            try:
                tool_output = self.execute_tool(tool_name, arguments)
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(tool_output, indent=2, ensure_ascii=False),
                            }
                        ],
                        "isError": False,
                    },
                }
            except Exception as e:
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [{"type": "text", "text": f"Error: {str(e)}"}],
                        "isError": True,
                    },
                }

        else:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"},
            }


if __name__ == "__main__":
    print("=" * 70)
    print("🤖 [PHANTOM GRID] Vehicle MCP Server (JSON-RPC 2.0)")
    print("   Standard Model Context Protocol for Automotive Cyber-Physical Twins")
    print("=" * 70)

    server = VehicleMCPServer()

    # 1. Initialize
    init_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "initialize"})
    print(f"[1. MCP Initialize] Server: {init_res['result']['serverInfo']['name']}")

    # 2. Tools List
    tools_res = server.handle_jsonrpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    print(f"[2. MCP Tools List] Exposed Tools: {len(tools_res['result']['tools'])}")
    for t in tools_res['result']['tools']:
        print(f"   - {t['name']}: {t['description'][:60]}...")

    # 3. Call get_digital_twin_telemetry
    call_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_digital_twin_telemetry",
            "arguments": {"detailed": True}
        }
    })
    print(f"\n[3. Tool Call: get_digital_twin_telemetry]")
    print(call_res['result']['content'][0]['text'][:300] + "...\n")

    # 4. Call broadcast_nostr_mesh_telemetry
    nostr_res = server.handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {
            "name": "broadcast_nostr_mesh_telemetry",
            "arguments": {"note": "Pre-flight health check"}
        }
    })
    print(f"[4. Tool Call: broadcast_nostr_mesh_telemetry]")
    print(nostr_res['result']['content'][0]['text'])

    print("=" * 70)
