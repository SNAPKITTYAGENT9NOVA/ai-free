# -*- coding: utf-8 -*-
"""
Unit Test Suite for DAG Task Pipeline Orchestrator (pipeline_orchestrator.py)
Validates:
1. Pipeline initialization & task registration
2. Linear and branching DAG topological sorting (Kahn's algorithm)
3. Cyclic dependency & missing dependency detection
4. Duplicate task ID protection
5. HITL (Human-in-the-Loop) multi-sig approval granting vs rejection
6. Cascading failure degradation & downstream task blocking
7. SDK export parity from phantom_grid
8. Standard automotive E2E pipeline assembly & execution
"""

from pathlib import Path

import pytest
from phantom_grid import (
    AgentTask as SDKAgentTask,
)
from phantom_grid import (
    TaskPipeline as SDKTaskPipeline,
)
from phantom_grid import (
    TaskStatus as SDKTaskStatus,
)

from pipeline_orchestrator import (
    AgentTask,
    TaskPipeline,
    TaskStatus,
    build_automotive_e2e_pipeline,
)


def test_pipeline_initialization():
    pipeline = TaskPipeline(commander_name="👑 測試指揮官")
    assert pipeline.commander == "👑 測試指揮官"
    assert len(pipeline.tasks) == 0


def test_duplicate_task_id_rejection():
    pipeline = TaskPipeline()
    task1 = AgentTask("T1", "Task 1", "Agent A", lambda: True)
    task2 = AgentTask("T1", "Task 1 Duplicate", "Agent B", lambda: True)
    pipeline.register_task(task1)
    with pytest.raises(ValueError, match="already registered"):
        pipeline.register_task(task2)


def test_linear_dag_execution():
    pipeline = TaskPipeline()
    execution_order = []

    def make_action(name: str):
        def _action() -> bool:
            execution_order.append(name)
            return True

        return _action

    pipeline.register_task(
        AgentTask("C", "Task C", "Agent 3", make_action("C"), dependencies=["B"])
    )
    pipeline.register_task(AgentTask("A", "Task A", "Agent 1", make_action("A"), dependencies=[]))
    pipeline.register_task(
        AgentTask("B", "Task B", "Agent 2", make_action("B"), dependencies=["A"])
    )

    sorted_ids = pipeline.topological_sort()
    assert sorted_ids == ["A", "B", "C"]

    success = pipeline.execute_all()
    assert success is True
    assert execution_order == ["A", "B", "C"]
    assert pipeline.tasks["A"].status == TaskStatus.SUCCESS
    assert pipeline.tasks["B"].status == TaskStatus.SUCCESS
    assert pipeline.tasks["C"].status == TaskStatus.SUCCESS
    assert pipeline.tasks["A"].execution_time_ms >= 0.0


def test_branching_dag_topological_sort():
    pipeline = TaskPipeline()
    # Topology:
    #     A
    #    / \
    #   B   C
    #    \ /
    #     D
    pipeline.register_task(AgentTask("D", "Task D", "Agent", lambda: True, dependencies=["B", "C"]))
    pipeline.register_task(AgentTask("B", "Task B", "Agent", lambda: True, dependencies=["A"]))
    pipeline.register_task(AgentTask("C", "Task C", "Agent", lambda: True, dependencies=["A"]))
    pipeline.register_task(AgentTask("A", "Task A", "Agent", lambda: True, dependencies=[]))

    sorted_ids = pipeline.topological_sort()
    assert sorted_ids[0] == "A"
    assert set(sorted_ids[1:3]) == {"B", "C"}
    assert sorted_ids[3] == "D"

    success = pipeline.execute_all()
    assert success is True


def test_cyclic_dependency_detection():
    pipeline = TaskPipeline()
    # Cycle: A -> B -> C -> A
    pipeline.register_task(AgentTask("A", "Task A", "Agent", lambda: True, dependencies=["C"]))
    pipeline.register_task(AgentTask("B", "Task B", "Agent", lambda: True, dependencies=["A"]))
    pipeline.register_task(AgentTask("C", "Task C", "Agent", lambda: True, dependencies=["B"]))

    with pytest.raises(ValueError, match="Cyclic dependency detected"):
        pipeline.topological_sort()

    assert pipeline.execute_all() is False


def test_missing_dependency_detection():
    pipeline = TaskPipeline()
    pipeline.register_task(
        AgentTask("A", "Task A", "Agent", lambda: True, dependencies=["NON_EXISTENT"])
    )

    with pytest.raises(ValueError, match="depends on non-existent task"):
        pipeline.topological_sort()


def test_hitl_approval_approved():
    pipeline = TaskPipeline()
    executed = []

    def action1() -> bool:
        executed.append("T1")
        return True

    def action2() -> bool:
        executed.append("T2")
        return True

    pipeline.register_task(AgentTask("T1", "Normal Task", "Agent", action1))
    pipeline.register_task(
        AgentTask(
            "T2_CRITICAL",
            "Critical High-Risk Action",
            "Agent",
            action2,
            dependencies=["T1"],
            requires_approval=True,
        )
    )

    success = pipeline.execute_all(approval_handler=lambda t_id: t_id == "T2_CRITICAL")
    assert success is True
    assert executed == ["T1", "T2"]
    assert pipeline.tasks["T2_CRITICAL"].status == TaskStatus.SUCCESS


def test_hitl_approval_rejected():
    pipeline = TaskPipeline()
    executed = []

    def action1() -> bool:
        executed.append("T1")
        return True

    def action2() -> bool:
        executed.append("T2")
        return True

    pipeline.register_task(AgentTask("T1", "Normal Task", "Agent", action1))
    pipeline.register_task(
        AgentTask(
            "T2_CRITICAL",
            "Critical High-Risk Action",
            "Agent",
            action2,
            dependencies=["T1"],
            requires_approval=True,
        )
    )

    success = pipeline.execute_all(approval_handler=lambda t_id: False)
    assert success is False
    assert executed == ["T1"]
    assert pipeline.tasks["T2_CRITICAL"].status == TaskStatus.BLOCKED
    assert "Approval Rejected" in pipeline.tasks["T2_CRITICAL"].error_message


def test_cascading_failure_blocks_downstream():
    pipeline = TaskPipeline()
    executed = []

    def good_action() -> bool:
        executed.append("A")
        return True

    def failing_action() -> bool:
        executed.append("FAIL_STEP")
        return False

    def dep_action() -> bool:
        executed.append("C")
        return True

    pipeline.register_task(AgentTask("A", "Good Step", "Agent", good_action))
    pipeline.register_task(
        AgentTask("B", "Failing Step", "Agent", failing_action, dependencies=["A"])
    )
    pipeline.register_task(
        AgentTask("C", "Dependent Step", "Agent", dep_action, dependencies=["B"])
    )

    success = pipeline.execute_all(fail_fast=True)
    assert success is False
    assert pipeline.tasks["A"].status == TaskStatus.SUCCESS
    assert pipeline.tasks["B"].status == TaskStatus.FAILED
    assert pipeline.tasks["C"].status == TaskStatus.PENDING

    # With fail_fast=False, C will be marked BLOCKED
    pipeline2 = TaskPipeline()
    pipeline2.register_task(AgentTask("A", "Good Step", "Agent", lambda: True))
    pipeline2.register_task(
        AgentTask("B", "Failing Step", "Agent", lambda: False, dependencies=["A"])
    )
    pipeline2.register_task(
        AgentTask("C", "Dependent Step", "Agent", lambda: True, dependencies=["B"])
    )

    success2 = pipeline2.execute_all(fail_fast=False)
    assert success2 is False
    assert pipeline2.tasks["B"].status == TaskStatus.FAILED
    assert pipeline2.tasks["C"].status == TaskStatus.BLOCKED


def test_sdk_import_parity():
    pipeline = SDKTaskPipeline(commander_name="SDK Commander")
    task = SDKAgentTask("SDK_T1", "SDK Task", "SDK Agent", lambda: True)
    pipeline.register_task(task)
    assert pipeline.execute_all() is True
    assert pipeline.tasks["SDK_T1"].status == SDKTaskStatus.SUCCESS


def test_automotive_pipeline_structure():
    workspace = Path(__file__).resolve().parent.parent
    pipeline = build_automotive_e2e_pipeline(workspace_root=workspace)

    assert len(pipeline.tasks) == 5
    assert "STAGE_1_STATIC_CHECK" in pipeline.tasks
    assert "STAGE_2_CAN_MATRIX" in pipeline.tasks
    assert "STAGE_3_E2E_10K" in pipeline.tasks
    assert "STAGE_4_HITL_MULTISIG" in pipeline.tasks
    assert "STAGE_5_THIRD_OFFICE_RELAY" in pipeline.tasks

    sorted_ids = pipeline.topological_sort()
    assert sorted_ids == [
        "STAGE_1_STATIC_CHECK",
        "STAGE_2_CAN_MATRIX",
        "STAGE_3_E2E_10K",
        "STAGE_4_HITL_MULTISIG",
        "STAGE_5_THIRD_OFFICE_RELAY",
    ]
