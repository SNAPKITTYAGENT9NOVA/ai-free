# -*- coding: utf-8 -*-
"""
Verification Test Suite for L0~L5 Industrial Automotive Release Manifest.
Validates:
1. Release Manifest directory structure and file existence.
2. 00_System: launch_stack.sh, docker-compose.yml, audit_governance.py.
3. 01_Memory: audit_log.db, telemetry_twin.json.
4. 02_Knowledge: CAN_MATRIX_E2E.md, ARCHITECTURE_SPEC.md.
5. src/: C drivers, multi_node_cluster, soa_gateway, autonomous_healer, vehicle_mcp, fleet_mesh, hybrid_router, dashboard.
6. Execution and runtime integrity of L1 cluster and dashboard data retrieval.
"""

import json
import os
import sqlite3
from pathlib import Path

import pytest
from audit_governance import GovernanceDB
from multi_node_cluster import MultiNodeClusterRunner
from can_l0_l1_matrix import NodeSafetyState


def test_manifest_directory_structure_exists():
    """Validates all manifest directory trees exist."""
    assert Path("00_System").is_dir(), "00_System directory missing"
    assert Path("01_Memory").is_dir(), "01_Memory directory missing"
    assert Path("02_Knowledge").is_dir(), "02_Knowledge directory missing"
    assert Path("src").is_dir(), "src directory missing"


def test_00_system_assets():
    """Validates 00_System files exist and contain valid contents."""
    launch_sh = Path("00_System/launch_stack.sh")
    assert launch_sh.is_file()
    content = launch_sh.read_text(encoding="utf-8")
    assert "vcan0" in content
    assert "multi_node_cluster.py" in content
    assert "autonomous_healer.py" in content
    assert "fleet_nostr_mesh.py" in content

    compose_yml = Path("00_System/docker-compose.yml")
    assert compose_yml.is_file()
    compose_content = compose_yml.read_text(encoding="utf-8")
    assert "can_cluster" in compose_content
    assert "gateway_healer" in compose_content
    assert "vehicle_mcp" in compose_content
    assert "fleet_mesh" in compose_content

    audit_gov = Path("00_System/audit_governance.py")
    assert audit_gov.is_file()
    assert "class GovernanceDB" in audit_gov.read_text(encoding="utf-8")


def test_01_memory_assets(tmp_path):
    """Validates 01_Memory audit database and digital twin snapshot."""
    audit_db = Path("01_Memory/audit_log.db")
    assert audit_db.is_file()
    assert audit_db.stat().st_size > 0

    # Test reading SQLite tables
    conn = sqlite3.connect(str(audit_db))
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [r[0] for r in cursor.fetchall()]
    conn.close()
    assert "audit_logs" in tables

    twin_json = Path("01_Memory/telemetry_twin.json")
    assert twin_json.is_file()
    with open(twin_json, "r", encoding="utf-8") as f:
        twin_data = json.load(f)
    assert "vin" in twin_data
    assert "motor_rpm" in twin_data
    assert "temperature_c" in twin_data


def test_02_knowledge_assets():
    """Validates 02_Knowledge protocol matrix and architecture specification whitepaper."""
    can_matrix = Path("02_Knowledge/CAN_MATRIX_E2E.md")
    assert can_matrix.is_file()
    matrix_text = can_matrix.read_text(encoding="utf-8")
    assert "ISO 26262" in matrix_text
    assert "SAE J1850" in matrix_text
    assert "0x1D" in matrix_text
    assert "Alive Counter" in matrix_text

    arch_spec = Path("02_Knowledge/ARCHITECTURE_SPEC.md")
    assert arch_spec.is_file()
    spec_text = arch_spec.read_text(encoding="utf-8")
    assert "PHANTOM GRID" in spec_text
    assert "SOME/IP" in spec_text
    assert "HITL" in spec_text
    assert "fleet_nostr_mesh" in spec_text


def test_src_assets_present():
    """Validates all src files specified in the manifest exist."""
    expected_src_files = [
        "e2e_crc8_driver.c",
        "uds_bootloader_fsm.c",
        "multi_node_cluster.py",
        "soa_gateway_twin.py",
        "autonomous_healer.py",
        "vehicle_mcp_server.py",
        "fleet_nostr_mesh.py",
        "edge_cloud_hybrid_router.py",
        "dashboard.py",
    ]
    for filename in expected_src_files:
        p = Path("src") / filename
        assert p.is_file(), f"Missing expected src file: {filename}"
        assert p.stat().st_size > 0, f"File {filename} is empty"


def test_c_drivers_source_integrity():
    """Validates C driver files contain correct algorithm tokens."""
    crc_c = Path("src/e2e_crc8_driver.c").read_text(encoding="utf-8")
    assert "CRC8_SAE_J1850_POLY" in crc_c
    assert "0x1D" in crc_c
    assert "calculate_crc8_sae_j1850" in crc_c

    uds_c = Path("src/uds_bootloader_fsm.c").read_text(encoding="utf-8")
    assert "uds_bootloader_process_request" in uds_c
    assert "UDS_SESSION_PROGRAMMING" in uds_c
    assert "uds_bootloader_emergency_power_cut_rollback" in uds_c
    assert "Sector B" in uds_c


def test_multi_node_cluster_runtime_execution():
    """Validates L1 Multi-Node Cluster discrete execution and safety state handling."""
    runner = MultiNodeClusterRunner(interval_sec=0.01)
    # Step 1: Initial dispatch
    stats = runner.step(now=100.0)
    assert stats["cluster_safety_mode"] == NodeSafetyState.NORMAL_OPERATION.value
    assert stats["actuator_power_pct"] == 100.0
    assert stats["total_frames"] == 3

    # Step 2: Next step within short time (actuator at 10ms should fire again at 100.010)
    stats2 = runner.step(now=100.012)
    assert stats2["total_frames"] >= 4

    # Stop runner
    runner.stop()
    assert not runner.is_running


def test_dashboard_components_and_twin_data():
    """Validates dashboard query utilities without requiring GUI rendering."""
    import dashboard

    db_path = dashboard.get_db_path()
    assert os.path.exists(db_path)

    twin = dashboard.get_twin_snapshot()
    assert "cluster_safety_state" in twin or "safety_mode" in twin
    assert "motor_rpm" in twin
    assert "battery_voltage" in twin

    logs = dashboard.query_audit_logs(db_path, limit=5)
    assert isinstance(logs, list)

    approvals = dashboard.query_approvals(db_path, limit=5)
    assert isinstance(approvals, list)

