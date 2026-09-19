# -*- coding: utf-8 -*-
"""
code_inspection_search.py - Enterprise Codebase and Symbol Inspection Engine
Provides industrial-grade symbol detection, AST-based entity verification,
and physical filesystem scanning for AI Assistant Workspaces.
"""

import os
import ast
import re
import time
from typing import Dict, Any, List, Optional
from dataclasses import dataclass, asdict

@dataclass
class CodeSymbol:
    name: str
    symbol_type: str  # class, function, async_function, variable, file
    file_path: str
    rel_path: str
    line_number: int
    docstring: Optional[str] = None
    snippet: Optional[str] = None

@dataclass
class InspectionResult:
    target: str
    target_type: str  # file or symbol
    found: bool
    has_definition: bool
    definition_count: int
    total_matches: int
    files_scanned: int
    duration_sec: float
    exact_files: List[str]
    symbols: List[Dict[str, Any]]
    matches: List[Dict[str, Any]]
    summary: str

class CodeInspectionEngine:
    """
    High-performance, AST-aware code inspection and symbol tracking engine.
    Scans repositories and distinguishes physical files from pure conceptual mentions.
    """

    DEFAULT_IGNORE_DIRS = {
        '.git', 'node_modules', '__pycache__', '.venv', 'venv', 
        '.system_generated', '.history', 'dist', 'build', '.idea', '.vscode'
    }
    VALID_EXTENSIONS = {'.py', '.md', '.json', '.txt', '.js', '.ts', '.html', '.css', '.bat', '.ps1'}

    def __init__(self, root_dirs: Optional[List[str]] = None, cache_ttl_sec: int = 60):
        self.root_dirs = root_dirs or []
        self.cache_ttl_sec = cache_ttl_sec
        self._file_cache: List[str] = []
        self._last_cache_time = 0.0

    def add_root_dir(self, directory: str):
        if directory and os.path.exists(directory) and directory not in self.root_dirs:
            self.root_dirs.append(directory)

    def _refresh_file_list(self) -> List[str]:
        now = time.time()
        if self._file_cache and (now - self._last_cache_time < self.cache_ttl_sec):
            return self._file_cache

        files = []
        for root in self.root_dirs:
            if not os.path.exists(root):
                continue
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames[:] = [d for d in dirnames if d not in self.DEFAULT_IGNORE_DIRS and not d.startswith('.')]
                for fname in filenames:
                    ext = os.path.splitext(fname)[1].lower()
                    if ext in self.VALID_EXTENSIONS:
                        files.append(os.path.join(dirpath, fname))

        self._file_cache = files
        self._last_cache_time = now
        return files

    def inspect(self, target: str, max_results: int = 50) -> InspectionResult:
        target = target.strip()
        t0 = time.time()
        if not target:
            return InspectionResult(
                target="", target_type="unknown", found=False, has_definition=False,
                definition_count=0, total_matches=0, files_scanned=0, duration_sec=0.0,
                exact_files=[], symbols=[], matches=[], summary="反查標的為空"
            )

        files = self._refresh_file_list()
        is_file_target = bool(re.search(r'\.[a-zA-Z0-9]+$', target))
        target_lower = target.lower()

        exact_files = []
        symbols = []
        matches = []

        for fpath in files:
            fname = os.path.basename(fpath)
            if fname.lower() == target_lower or os.path.splitext(fname)[0].lower() == target_lower:
                exact_files.append(fpath)

            try:
                with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
                    content = f.read()

                if target_lower in content.lower():
                    lines = content.splitlines()
                    
                    if fpath.endswith('.py'):
                        try:
                            tree = ast.parse(content, filename=fpath)
                            for node in ast.walk(tree):
                                if isinstance(node, ast.ClassDef) and node.name.lower() == target_lower:
                                    symbols.append(CodeSymbol(
                                        name=node.name,
                                        symbol_type='class',
                                        file_path=fpath,
                                        rel_path=os.path.basename(fpath),
                                        line_number=node.lineno,
                                        docstring=ast.get_docstring(node),
                                        snippet=lines[node.lineno - 1].strip() if node.lineno <= len(lines) else ''
                                    ))
                                elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.lower() == target_lower:
                                    symbols.append(CodeSymbol(
                                        name=node.name,
                                        symbol_type='function' if isinstance(node, ast.FunctionDef) else 'async_function',
                                        file_path=fpath,
                                        rel_path=os.path.basename(fpath),
                                        line_number=node.lineno,
                                        docstring=ast.get_docstring(node),
                                        snippet=lines[node.lineno - 1].strip() if node.lineno <= len(lines) else ''
                                    ))
                        except Exception:
                            pass

                    for idx, line in enumerate(lines, 1):
                        if target_lower in line.lower():
                            is_def = bool(re.search(rf'\b(class|def)\s+{re.escape(target)}\b', line, re.IGNORECASE))
                            matches.append({
                                'file': fpath,
                                'rel_file': os.path.basename(fpath),
                                'line': idx,
                                'content': line.strip()[:140],
                                'is_definition': is_def
                            })
                            if len(matches) >= max_results:
                                break
            except Exception:
                continue

        duration = time.time() - t0
        found = len(exact_files) > 0 or len(matches) > 0 or len(symbols) > 0
        has_def = len(exact_files) > 0 or len(symbols) > 0 or any(m['is_definition'] for m in matches)
        def_count = len(exact_files) if is_file_target else (len(symbols) if symbols else sum(1 for m in matches if m['is_definition']))

        if is_file_target or len(exact_files) > 0:
            target_type = 'file'
            if len(exact_files) > 0:
                summary = f"【實體驗證通過】：確認實體檔案存在！檔案路徑：{exact_files[0]}，全域包含 {len(matches)} 處引用。"
            else:
                summary = f"【實體驗證失敗】：掃描全域 {len(files)} 個檔案，查無名為「{target}」的實體檔案。"
        else:
            target_type = 'symbol'
            if not found:
                summary = f"【實體反查結果】：掃描全域 {len(files)} 個檔案，完全未發現「{target}」定義或任何引用！證實為虛擬概念，尚未在磁碟建檔！"
            elif not has_def:
                summary = f"【實體反查結果】：發現文字提及，但未發現 class/def 實體代碼定義！仍屬概念提及階段。"
            else:
                summary = f"【實體驗證通過】：✅ 確認實體類別/函數存在！找到 {def_count} 處代碼定義與 {len(matches)} 處引用！"

        return InspectionResult(
            target=target,
            target_type=target_type,
            found=found,
            has_definition=has_def,
            definition_count=def_count,
            total_matches=len(matches),
            files_scanned=len(files),
            duration_sec=round(duration, 2),
            exact_files=exact_files,
            symbols=[asdict(s) for s in symbols],
            matches=matches,
            summary=summary
        )

_default_engine: Optional[CodeInspectionEngine] = None

def get_inspection_engine(root_dirs: Optional[List[str]] = None) -> CodeInspectionEngine:
    global _default_engine
    if _default_engine is None:
        _default_engine = CodeInspectionEngine(root_dirs)
    elif root_dirs:
        for r in root_dirs:
            _default_engine.add_root_dir(r)
    return _default_engine

def inspect_code(target: str, root_dirs: Optional[List[str]] = None) -> Dict[str, Any]:
    engine = get_inspection_engine(root_dirs)
    res = engine.inspect(target)
    return asdict(res)
