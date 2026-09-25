# -*- coding: utf-8 -*-
"""
Unit Test Suite for Audit Governance & Xiaomi Secretary Pipeline
Validates:
1. GovernanceDB initialization & is_approved_by_brother checks
2. Blocked execution when Brother approval is absent
3. Approved execution and hardware lock when Brother signs 'APPROVED'
4. End-to-end flow across TASK_01 (10k E2E), TASK_02 (Lint), TASK_03 (Register Lock)
"""

from pathlib import Path

from audit_governance import GovernanceDB
from pipeline_orchestrator import (
    TaskStatus,
    build_secretary_xiaomi_pipeline,
)


def test_governance_db_brother_approval_check():
    db = GovernanceDB(db_path=":memory:")

    # Initial check: no logs
    assert db.is_approved_by_brother("TASK_03") is False

    # Log from someone else (not Brother)
    db.log_approval(
        task_id="TASK_03",
        operator="秘書處 (小米)",
        status="APPROVED",
        details="小米單方面核准",
    )
    assert db.is_approved_by_brother("TASK_03") is False

    # Log from Brother but status is PENDING
    db.log_approval(
        task_id="TASK_03",
        operator="哥",
        status="PENDING",
        details="研議中",
    )
    assert db.is_approved_by_brother("TASK_03") is False

    # Log from Brother with APPROVED status
    db.log_approval(
        task_id="TASK_03",
        operator="哥",
        status="APPROVED",
        details="哥親批放行暫存器寫入",
    )
    assert db.is_approved_by_brother("TASK_03") is True


def test_secretary_pipeline_structure():
    workspace = Path(__file__).resolve().parent.parent
    db = GovernanceDB(db_path=":memory:")
    pipeline = build_secretary_xiaomi_pipeline(workspace_root=workspace, governance_db=db)

    assert len(pipeline.tasks) == 3
    assert "TASK_01" in pipeline.tasks
    assert "TASK_02" in pipeline.tasks
    assert "TASK_03" in pipeline.tasks

    sorted_ids = pipeline.topological_sort()
    assert sorted_ids == ["TASK_01", "TASK_02", "TASK_03"]
    assert pipeline.tasks["TASK_03"].requires_approval is True


def test_secretary_pipeline_blocked_without_brother_approval():
    workspace = Path(__file__).resolve().parent.parent
    db = GovernanceDB(db_path=":memory:")
    pipeline = build_secretary_xiaomi_pipeline(workspace_root=workspace, governance_db=db)

    # Handler consults SQLite db: brother hasn't approved yet
    success = pipeline.execute_all(approval_handler=lambda t_id: db.is_approved_by_brother(t_id))
    assert success is False
    assert pipeline.tasks["TASK_01"].status == TaskStatus.SUCCESS
    assert pipeline.tasks["TASK_02"].status == TaskStatus.SUCCESS
    assert pipeline.tasks["TASK_03"].status == TaskStatus.BLOCKED


def test_secretary_pipeline_success_with_brother_approval():
    workspace = Path(__file__).resolve().parent.parent
    db = GovernanceDB(db_path=":memory:")

    # Brother signs approval into SQLite audit_log
    db.log_approval(
        task_id="TASK_03",
        operator="哥",
        status="APPROVED",
        details="哥親自簽署授權暫存器安全配置變更 (REG_0x4002)",
    )

    pipeline = build_secretary_xiaomi_pipeline(workspace_root=workspace, governance_db=db)
    success = pipeline.execute_all(approval_handler=lambda t_id: db.is_approved_by_brother(t_id))
    assert success is True
    assert pipeline.tasks["TASK_01"].status == TaskStatus.SUCCESS
    assert pipeline.tasks["TASK_02"].status == TaskStatus.SUCCESS
    assert pipeline.tasks["TASK_03"].status == TaskStatus.SUCCESS

    # Verify audit log recorded execution
    logs = db.query_logs(limit=5)
    executed_logs = [item for item in logs if item["status"] == "EXECUTED"]
    assert len(executed_logs) >= 1
    assert executed_logs[0]["task_id"] == "TASK_03"
    assert executed_logs[0]["action_type"] == "HARDWARE_LOCK"
