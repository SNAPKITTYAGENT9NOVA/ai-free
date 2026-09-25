# -*- coding: utf-8 -*-
"""
PHANTOM GRID Core - Tri-Tier Memory Engine
三層記憶自動沉澱管道 (TriTierMemoryEngine)
實體化 00_System（不變常數/協議）、01_Memory（動態日誌快照）與 02_Knowledge（固化的子節點藍圖），
新創生的子模組藍圖自動寫入知識庫，達成「創生即固化」，重啟亦不遺失。
"""

from __future__ import annotations

import hashlib
import json
import re
import threading
import time
from pathlib import Path
from typing import Any, Dict, Optional


class TriTierMemoryEngine:
    """
    三層記憶自動沉澱管道：
    實體化 00_System（不變常數/協議）、01_Memory（動態日誌快照）與 02_Knowledge（固化的子節點藍圖），
    新創生的子模組藍圖自動寫入知識庫，達成「創生即固化」，重啟亦不遺失。
    """

    def __init__(self, root_dir: str = "."):
        self.root = Path(root_dir)
        self.system_dir = self.root / "00_System"
        self.memory_dir = self.root / "01_Memory"
        self.knowledge_dir = self.root / "02_Knowledge"
        self.blueprints_dir = self.knowledge_dir / "blueprints"

        # 確保三層目錄結構完整實體化
        self.system_dir.mkdir(parents=True, exist_ok=True)
        self.memory_dir.mkdir(parents=True, exist_ok=True)
        self.knowledge_dir.mkdir(parents=True, exist_ok=True)
        self.blueprints_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

    def persist_blueprint(
        self,
        node_name: str,
        blueprint_spec: Dict[str, Any],
        author: str = "PHANTOM_GRID",
    ) -> Path:
        """
        「創生即固化」：將新創生之子節點藍圖自動寫入 02_Knowledge/blueprints/
        """
        with self._lock:
            safe_name = re.sub(r"[^\w\-]", "_", node_name)
            file_path = self.blueprints_dir / f"{safe_name}_blueprint.json"
            md_path = self.blueprints_dir / f"{safe_name}_blueprint.md"

            blueprint_record = {
                "node_name": node_name,
                "author": author,
                "created_at_epoch": time.time(),
                "created_at_iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "specification": blueprint_spec,
                "integrity_sha256": hashlib.sha256(
                    json.dumps(blueprint_spec, sort_keys=True).encode("utf-8")
                ).hexdigest(),
            }

            # 固化 JSON 規格
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(blueprint_record, f, indent=2, ensure_ascii=False)

            # 固化 Markdown 藍圖
            with open(md_path, "w", encoding="utf-8") as f:
                f.write(
                    f"# 📐 子模組藍圖：{node_name}\n\n"
                    f"* **作者**: `{author}`\n"
                    f"* **沉澱時間**: `{blueprint_record['created_at_iso']}`\n"
                    f"* **完整性 SHA-256**: `{blueprint_record['integrity_sha256']}`\n\n"
                    f"## 規格定義\n```json\n"
                    f"{json.dumps(blueprint_spec, indent=2, ensure_ascii=False)}\n"
                    f"```\n"
                )

            return file_path

    def load_blueprint(self, node_name: str) -> Optional[Dict[str, Any]]:
        """讀取已固化之子節點藍圖"""
        with self._lock:
            safe_name = re.sub(r"[^\w\-]", "_", node_name)
            file_path = self.blueprints_dir / f"{safe_name}_blueprint.json"
            if not file_path.is_file():
                return None
            with open(file_path, "r", encoding="utf-8") as f:
                return json.load(f)

    def write_memory_snapshot(self, snapshot_name: str, state_data: Dict[str, Any]) -> Path:
        """沉澱動態運行時快照至 01_Memory"""
        with self._lock:
            snap_file = self.memory_dir / f"{snapshot_name}.json"
            with open(snap_file, "w", encoding="utf-8") as f:
                json.dump({
                    "snapshot": snapshot_name,
                    "timestamp": time.time(),
                    "state": state_data,
                }, f, indent=2, ensure_ascii=False)
            return snap_file
