# -*- coding: utf-8 -*-
"""
Local package link for ARCInteractiveEnv.
"""
from importlib.machinery import SourceFileLoader
import os

_target_path = r"G:\我的雲端硬碟\AI產出成品總庫\01_軟體源碼與系統\arc_interactive_env.py"

if os.path.exists(_target_path):
    _mod = SourceFileLoader("arc_env_core", _target_path).load_module()
    ARCInteractiveEnv = _mod.ARCInteractiveEnv
else:
    raise ImportError(f"Cannot locate ARCInteractiveEnv at {_target_path}")

__all__ = ["ARCInteractiveEnv"]
