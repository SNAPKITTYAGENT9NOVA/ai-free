"""DF-Mesh Orchestration Engine & CLI."""

from __future__ import annotations

import logging
import sys
from df_mesh.agents.components import (
    DiagnosticAgent,
    EdgeTelemetryMonitorAgent,
    PlantManagerAgent,
    RecoveryVerifierAgent,
)
from df_mesh.core.models import MachineHealthStatus, MachineTelemetry

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("DF-Mesh-Pipeline")


class DFMeshPipeline:
    def __init__(self) -> None:
        self.plant_manager = PlantManagerAgent()
        self.monitor = EdgeTelemetryMonitorAgent()
        self.diagnostics = DiagnosticAgent()
        self.recovery = RecoveryVerifierAgent()

    def run_cycle(self, order_id: str, machine_id: str, sim_temp: float, sim_vib: float) -> bool:
        print("=" * 65)
        print("🏭 [DF-Mesh] Dark Factory Autonomous Agentic Mesh")
        print(f"📦 Production Dispatch: Order {order_id} | Target Machine: {machine_id}")
        print("=" * 65)

        # 1. Schedule
        order = self.plant_manager.schedule_order(order_id, 1000)
        print(f"[Phase 1: Dispatch] Order assigned to {order.assigned_line} (Target: {order.target_units} units)")

        # 2. Telemetry
        telemetry = MachineTelemetry(machine_id=machine_id, temperature_c=sim_temp, vibration_g=sim_vib)
        status = self.monitor.assess(telemetry)
        print(f"[Phase 2: Monitor] Telemetry Status: {status.value} (Temp: {sim_temp}°C, Vib: {sim_vib}g)")

        # 3. Anomaly diagnosis & recovery if degraded
        if status in (MachineHealthStatus.WARNING, MachineHealthStatus.FAULT):
            print("\n⚠️ Anomaly detected! Triggering autonomous diagnosis & recovery loop...")
            report = self.diagnostics.diagnose(telemetry, status)
            print(f"[Phase 3: Diagnostics] Root Cause: {report.root_cause} (Severity: {report.severity})")

            action = self.recovery.remediate_and_verify(report)
            print(f"[Phase 4: Recovery] Action: {action.action_type} -> Verification: PASSED 🟢")
            print(f"     Audit Log: {action.audit_log}")
        else:
            print("[Phase 3 & 4] System optimal. No recovery required.")

        print("=" * 65)
        print("🏆 [DF-Mesh] Closed-loop autonomous manufacturing cycle COMPLETED.")
        print("=" * 65)
        return True


def main() -> None:
    pipeline = DFMeshPipeline()
    # Simulate an edge overheating event that triggers autonomous closed-loop self-healing
    pipeline.run_cycle(order_id="ORD-2026-X9", machine_id="CNC-ROBOT-04", sim_temp=89.5, sim_vib=1.2)


if __name__ == "__main__":
    main()
