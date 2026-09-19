# -*- coding: utf-8 -*-
"""
Local package link for ARC3PolicyValueNet.
"""
from importlib.machinery import SourceFileLoader
import os

_target_path = r"G:\我的雲端硬碟\AI產出成品總庫\01_軟體源碼與系統\arc3_policy_value_net.py"

if os.path.exists(_target_path):
    _mod = SourceFileLoader("arc3_core", _target_path).load_module()
    ARC3PolicyValueNet = _mod.ARC3PolicyValueNet
else:
    raise ImportError(f"Cannot locate ARC3PolicyValueNet at {_target_path}")

__all__ = ["ARC3PolicyValueNet"]
