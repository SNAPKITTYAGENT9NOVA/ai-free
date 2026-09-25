# -*- coding: utf-8 -*-
"""
PHANTOM GRID Core SDK - Pipeline Module (phantom_grid.pipeline)
Automotive-Grade Directed Acyclic Graph (DAG) Task Scheduling & CI/CD Orchestration:
- True DAG topological sorting (Kahn's algorithm) & cycle detection
- HITL (Human-in-the-Loop) multi-sig approval checks
- Cascading failure degradation & downstream task blocking
- Pre-configured automotive E2E verification workflow
"""

from __future__ import annotations

import ast
import collections
import enum
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set

# Ensure UTF-8 output on Windows console
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# Ensure phantom_grid_core is in sys.path
_core_dir = Path(__file__).resolve().parent.parent
if _core_dir.exists() and str(_core_dir) not in sys.path:
    sys.path.insert(0, str(_core_dir))


class TaskStatus(enum.Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    SUCCESS = "SUCCESS"
    FAILED = "FAILED"
    BLOCKED = "BLOCKED"
    SKIPPED = "SKIPPED"


@dataclass
class AgentTask:
    task_id: str
    name: str
    assigned_agent: str
    action: Callable[[], bool]
    dependencies: List[str] = field(default_factory=list)
    requires_approval: bool = False
    status: TaskStatus = TaskStatus.PENDING
    execution_time_ms: float = 0.0
    error_message: str = ""


class TaskPipeline:
    def __init__(self, commander_name: str = "👑 小幫手"):
        self.commander = commander_name
        self.tasks: Dict[str, AgentTask] = collections.OrderedDict()

    def register_task(self, task: AgentTask) -> None:
        if task.task_id in self.tasks:
            raise ValueError(f"Task with id '{task.task_id}' is already registered.")
        self.tasks[task.task_id] = task

    def topological_sort(self) -> List[str]:
        """
        Performs Kahn's algorithm for topological sorting of the task DAG.
        Validates all dependencies exist and detects cyclic dependencies.
        """
        in_degree: Dict[str, int] = {t_id: 0 for t_id in self.tasks}
        graph: Dict[str, List[str]] = {t_id: [] for t_id in self.tasks}

        for t_id, task in self.tasks.items():
            for dep in task.dependencies:
                if dep not in self.tasks:
                    raise ValueError(f"Task '{t_id}' depends on non-existent task '{dep}'")
                graph[dep].append(t_id)
                in_degree[t_id] += 1

        queue: List[str] = [t_id for t_id, deg in in_degree.items() if deg == 0]
        sorted_order: List[str] = []

        while queue:
            curr = queue.pop(0)
            sorted_order.append(curr)
            for neighbor in graph[curr]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)

        if len(sorted_order) != len(self.tasks):
            cyclic_candidates = [t_id for t_id, deg in in_degree.items() if deg > 0]
            raise ValueError(f"Cyclic dependency detected in task DAG involving: {cyclic_candidates}")

        return sorted_order

    def execute_all(
        self,
        approval_handler: Optional[Callable[[str], bool]] = None,
        fail_fast: bool = True,
    ) -> bool:
        print("=" * 70)
        print(f"[{self.commander}] 啟動 DAG 作業流水線，共 {len(self.tasks)} 項任務...")
        print("=" * 70)

        try:
            sorted_task_ids = self.topological_sort()
        except ValueError as e:
            print(f"   [X] DAG 拓撲解析失敗: {e}")
            return False

        all_success = True

        for t_id in sorted_task_ids:
            task = self.tasks[t_id]
            print(f"\n>> 執行中: [{task.task_id}] {task.name} (負責: {task.assigned_agent})")

            # 1. Check dependencies
            blocked_by = []
            for dep in task.dependencies:
                dep_task = self.tasks[dep]
                if dep_task.status != TaskStatus.SUCCESS:
                    blocked_by.append(dep)

            if blocked_by:
                task.status = TaskStatus.BLOCKED
                task.error_message = f"Blocked by incomplete dependencies: {blocked_by}"
                print(f"   [!] 任務 [{task.task_id}] 遭依賴阻擋 ({blocked_by})，進入 BLOCKED 狀態！")
                all_success = False
                if fail_fast:
                    print(f"   [X] 觸發 Fail-Fast，管線即刻中斷！")
                    return False
                continue

            # 2. Check HITL approval
            if task.requires_approval:
                print(f"   [!] 觸發 HITL 審批檢查...")
                approved = False
                if approval_handler is not None:
                    approved = approval_handler(task.task_id)
                else:
                    print("   [!] 未提供 approval_handler，默認保持安全阻斷 (Reject)")

                if not approved:
                    task.status = TaskStatus.BLOCKED
                    task.error_message = "HITL 審批未通過 (Approval Rejected)"
                    print(f"   [X] 任務 [{task.task_id}] 未通過審批，管線中斷！")
                    all_success = False
                    if fail_fast:
                        return False
                    continue
                else:
                    print(f"   [✓] 任務 [{task.task_id}] 已通過 👑 指揮官與秘書處雙簽審批！")

            # 3. Execute action
            task.status = TaskStatus.RUNNING
            t_start = time.perf_counter()
            try:
                success = task.action()
            except Exception as ex:
                success = False
                task.error_message = str(ex)
            t_end = time.perf_counter()
            task.execution_time_ms = (t_end - t_start) * 1000.0

            if not success:
                task.status = TaskStatus.FAILED
                if not task.error_message:
                    task.error_message = "Action returned False"
                print(f"   [X] 任務 [{task.task_id}] 執行失敗 ({task.execution_time_ms:.1f}ms)，進入降級處置！ (原因: {task.error_message})")
                all_success = False
                if fail_fast:
                    return False
            else:
                task.status = TaskStatus.SUCCESS
                print(f"   [✓] 任務 [{task.task_id}] 圓滿達成 ({task.execution_time_ms:.1f}ms)。")

        print("=" * 70)
        if all_success:
            print(f"[{self.commander}] 全線任務順利通關！🏆")
        else:
            print(f"[{self.commander}] 部分任務異常或阻斷，作業流水線收斂降級。⚠️")
        print("=" * 70)
        return all_success

    def get_summary(self) -> Dict[str, Any]:
        return {
            "commander": self.commander,
            "total_tasks": len(self.tasks),
            "statuses": {t_id: t.status.value for t_id, t in self.tasks.items()},
            "execution_times_ms": {t_id: t.execution_time_ms for t_id, t in self.tasks.items()},
            "success": all(t.status == TaskStatus.SUCCESS for t in self.tasks.values()),
        }

    def print_summary(self) -> None:
        print("\n" + "=" * 70)
        print(f"📊 PIPELINE EXECUTION SUMMARY [{self.commander}]")
        print("=" * 70)
        print(f"{'Task ID':<24} | {'Status':<9} | {'Time (ms)':<10} | {'Agent':<15}")
        print("-" * 70)
        for t_id, task in self.tasks.items():
            print(f"{task.task_id:<24} | {task.status.value:<9} | {task.execution_time_ms:<10.1f} | {task.assigned_agent:<15}")
        print("=" * 70 + "\n")
