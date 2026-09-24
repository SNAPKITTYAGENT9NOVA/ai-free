"""Tests for DF-Mesh Autonomous Agentic Mesh."""

from __future__ import annotations

import pytest
from df_mesh.agents.components import (
    DiagnosticAgent,
    EdgeTelemetryMonitorAgent,
    PlantManagerAgent,
    RecoveryVerifierAgent,
)
from df_mesh.core.models import MachineHealthStatus, MachineTelemetry
from df_mesh.main import DFMeshPipeline


def test_plant_manager_schedule() -> None:
    pm = PlantManagerAgent()
    order = pm.schedule_order("ORD-TEST", 500)
    assert order.order_id == "ORD-TEST"
    assert order.target_units == 500
    assert order.assigned_line == "LINE-ALPHA"


def test_telemetry_optimal() -> None:
    monitor = EdgeTelemetryMonitorAgent()
    telemetry = MachineTelemetry(machine_id="M1", temperature_c=65.0, vibration_g=1.0)
    assert monitor.assess(telemetry) == MachineHealthStatus.OPTIMAL


def test_telemetry_warning_thermal() -> None:
    monitor = EdgeTelemetryMonitorAgent()
    telemetry = MachineTelemetry(machine_id="M2", temperature_c=88.0, vibration_g=1.0)
    assert monitor.assess(telemetry) == MachineHealthStatus.WARNING


def test_diagnostics_and_recovery_loop() -> None:
    diagnostics = DiagnosticAgent()
    recovery = RecoveryVerifierAgent()

    telemetry = MachineTelemetry(machine_id="M3", temperature_c=89.0, vibration_g=2.0)
    report = diagnostics.diagnose(telemetry, MachineHealthStatus.WARNING)
    assert "Thermal radiation" in report.root_cause

    action = recovery.remediate_and_verify(report)
    assert action.status == "EXECUTED"
    assert action.verification_passed is True
    assert "M3" in action.audit_log


def test_df_mesh_full_pipeline() -> None:
    pipeline = DFMeshPipeline()
    success = pipeline.run_cycle("ORD-TEST-99", "CNC-01", 90.0, 1.5)
    assert success is True
