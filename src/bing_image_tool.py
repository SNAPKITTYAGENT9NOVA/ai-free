# -*- coding: utf-8 -*-
"""
Local package link for BingImageCreatorTool.
"""
from importlib.machinery import SourceFileLoader
import os

_target_path = r"G:\我的雲端硬碟\AI產出成品總庫\01_軟體源碼與系統\bing_image_tool.py"

if os.path.exists(_target_path):
    _mod = SourceFileLoader("bing_tool_core", _target_path).load_module()
    BingImageCreatorTool = _mod.BingImageCreatorTool
else:
    raise ImportError(f"Cannot locate BingImageCreatorTool at {_target_path}")

__all__ = ["BingImageCreatorTool"]

if __name__ == "__main__":
    _mod.main()
