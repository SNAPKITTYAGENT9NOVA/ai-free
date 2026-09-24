"""Test suite for BobFlow Agentic Engine."""

from __future__ import annotations

import pytest
from bobflow.agents.components import (
    ArchitectAgent,
    CoderAgent,
    OrchestratorAgent,
    VerifierAgent,
)
from bobflow.core.models import GeneratedCode, TaskSpec, TaskStatus
from bobflow.main import BobFlowPipeline


def test_orchestrator_decomposition() -> None:
    orchestrator = OrchestratorAgent()
    tasks = orchestrator.decompose("建立一個具有重試機制的 REST API 客戶端模組")
    assert len(tasks) >= 1
    assert tasks[0].task_id == "TASK-001"
    assert "REST" in tasks[0].title


def test_architect_review() -> None:
    architect = ArchitectAgent()
    task = TaskSpec(
        task_id="TASK-TEST",
        title="Test Task",
        description="Verify architectural review",
    )
    review = architect.review(task)
    assert review.approved is True
    assert len(review.design_notes) >= 1
    assert task.status == TaskStatus.IN_REVIEW


def test_coder_implementation() -> None:
    architect = ArchitectAgent()
    coder = CoderAgent()
    task = TaskSpec(
        task_id="TASK-TEST",
        title="Test Task",
        description="REST API client test",
    )
    review = architect.review(task)
    code = coder.implement(task, review)
    assert code.filename == "resilient_client.py"
    assert "IBM Bob 2.0" in code.bob_acceleration_tag
    assert "class ResilientRestClient" in code.code_content


def test_verifier_pass() -> None:
    verifier = VerifierAgent()
    task = TaskSpec(
        task_id="TASK-TEST",
        title="Test Task",
        description="Verify pass",
    )
    code = GeneratedCode(
        task_id="TASK-TEST",
        filename="dummy.py",
        code_content="x = 1\n",
        test_content="assert True\n",
    )
    result = verifier.verify(task, code)
    assert result.passed is True
    assert task.status == TaskStatus.PASSED


def test_verifier_syntax_error() -> None:
    verifier = VerifierAgent()
    task = TaskSpec(
        task_id="TASK-FAIL",
        title="Fail Task",
        description="Verify syntax fail",
    )
    code = GeneratedCode(
        task_id="TASK-FAIL",
        filename="syntax_err.py",
        code_content="def bad_func(:\n",
        test_content="assert True\n",
    )
    result = verifier.verify(task, code)
    assert result.passed is False
    assert task.status == TaskStatus.FAILED


def test_full_bobflow_pipeline() -> None:
    pipeline = BobFlowPipeline()
    success = pipeline.run("建立一個具有重試機制與結構化日誌的 REST API 客戶端模組")
    assert success is True
