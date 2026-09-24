"""BobFlow Agentic Engine - Models & Data Structures.

Defines the contracts between Orchestrator, Architect, Coder, and Verifier.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class TaskStatus(Enum):
    PENDING = "PENDING"
    IN_REVIEW = "IN_REVIEW"
    CODING = "CODING"
    VERIFYING = "VERIFYING"
    PASSED = "PASSED"
    FAILED = "FAILED"


@dataclass
class TaskSpec:
    task_id: str
    title: str
    description: str
    constraints: list[str] = field(default_factory=list)
    status: TaskStatus = TaskStatus.PENDING


@dataclass
class ArchitectureReview:
    task_id: str
    approved: bool
    design_notes: list[str]
    interface_definition: str


@dataclass
class GeneratedCode:
    task_id: str
    filename: str
    code_content: str
    test_content: str
    bob_acceleration_tag: str = "IBM Bob 2.0 Accelerated"


@dataclass
class VerificationResult:
    task_id: str
    passed: bool
    linter_passed: bool
    tests_run: int
    tests_passed: int
    feedback: str = ""
    timestamp: float = field(default_factory=time.time)
