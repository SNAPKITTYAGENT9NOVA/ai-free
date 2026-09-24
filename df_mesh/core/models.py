"""DF-Mesh (Dark Factory Agentic Mesh) - Core Data Models.

Defines schemas for Work Orders, Telemetry, Diagnostics, and Recovery Actions.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class MachineHealthStatus(Enum):
    OPTIMAL = "OPTIMAL"
    WARNING = "WARNING"
    DEGRADED = "DEGRADED"
    FAULT = "FAULT"
    RECOVERED = "RECOVERED"


@dataclass
class JobOrder:
    order_id: str
    target_units: int
    assigned_line: str = "LINE-01"
    priority: int = 1
    status: str = "SCHEDULED"


@dataclass
class MachineTelemetry:
    machine_id: str
    temperature_c: float
    vibration_g: float
    error_code: int = 0
    timestamp: float = field(default_factory=time.time)

    @property
    def is_anomalous(self) -> bool:
        return self.temperature_c > 85.0 or self.vibration_g > 2.5 or self.error_code != 0


@dataclass
class DiagnosticReport:
    machine_id: str
    root_cause: str
    recommended_action: str
    severity: str
    timestamp: float = field(default_factory=time.time)


@dataclass
class RecoveryAction:
    machine_id: str
    action_type: str  # e.g., "THROTTLE_TDP", "AUTO_REBOOT_CAN", "REROUTE_LINE"
    status: str  # "EXECUTED" | "VERIFIED"
    verification_passed: bool
    audit_log: str
