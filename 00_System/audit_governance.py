# -*- coding: utf-8 -*-
"""
Audit Governance Module (audit_governance.py)
Provides SQLite-based immutable audit trail for autonomous healing,
emergency derating, and Human-In-The-Loop (HITL) approvals.
Database: audit_log.db
Table: audit_logs
"""

from __future__ import annotations

import os
import sqlite3
import time
from typing import Any, Dict, List, Optional


class GovernanceDB:
    """
    SQLite Governance and Audit Trail Manager.
    Logs every autonomous healing action, MCP derate command, and HITL approval.
    """

    def __init__(self, db_path: str = "audit_log.db"):
        self.db_path = db_path
        self._conn = None
        if self.db_path == ":memory:":
            self._conn = sqlite3.connect(":memory:", check_same_thread=False)
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        if self._conn is not None:
            return self._conn
        return sqlite3.connect(self.db_path)

    def _init_db(self) -> None:
        """Initializes audit_logs schema."""
        if self.db_path != ":memory:":
            dir_name = os.path.dirname(self.db_path)
            if dir_name:
                os.makedirs(dir_name, exist_ok=True)
        conn = self._get_connection()
        with conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS audit_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT DEFAULT (datetime('now')),
                    task_id TEXT,
                    operator TEXT,
                    status TEXT,
                    action_type TEXT,
                    details TEXT
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_audit_logs_task ON audit_logs(task_id)
            """)
        if self._conn is None:
            conn.close()

    def log_approval(
        self,
        task_id: str,
        operator: str,
        status: str,
        details: str,
        action_type: str = "SELF_HEALING",
    ) -> None:
        """Logs an approval or execution event into audit_logs."""
        conn = self._get_connection()
        with conn:
            conn.execute("""
                INSERT INTO audit_logs (timestamp, task_id, operator, status, action_type, details)
                VALUES (datetime('now'), ?, ?, ?, ?, ?)
            """, (task_id, operator, status, action_type, details))
        if self._conn is None:
            conn.close()

    def query_logs(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Queries recent audit logs."""
        conn = self._get_connection()
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("""
            SELECT id, timestamp, task_id, operator, status, action_type, details
            FROM audit_logs ORDER BY id DESC LIMIT ?
        """, (limit,))
        rows = cursor.fetchall()
        result = [dict(r) for r in rows]
        if self._conn is None:
            conn.close()
        return result

    def close(self) -> None:
        """Closes the underlying SQLite database connection if persistent."""
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None


