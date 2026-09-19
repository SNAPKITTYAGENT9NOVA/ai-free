# -*- coding: utf-8 -*-
"""
arc_dataset_loader.py - ARC Dataset & Pair Definitions
"""

from dataclasses import dataclass
from typing import List, Dict, Any, Optional
import numpy as np

@dataclass
class ARCPair:
    """封裝 ARC 任務中的單一輸入輸出網格對"""
    input_grid: np.ndarray
    output_grid: np.ndarray

@dataclass
class ARCTask:
    """封裝完整的 ARC 任務 (包含訓練集展示與測試題)"""
    task_id: str
    train_pairs: List[ARCPair]
    test_pairs: List[ARCPair]
