# -*- coding: utf-8 -*-
"""
PHANTOM GRID Core SDK (v1.0.0)
4 大工程補強核心模組：
1. MultiSigGovernanceGate: 雙簽授權治理閘門 (governance.py)
2. TriTierMemoryEngine: 三層記憶自動沉澱管道 (memory.py)
3. SafetyWatchdog: 安全狀態機與微觀降級機制 (watchdog.py)
4. AntiEntropyFilter: 語意抗熵過濾器 (anti_entropy.py)
"""

from __future__ import annotations

__version__ = "1.0.0"
__author__ = "Jack Hu (PHANTOM GRID)"

from .governance import (
    MultiSigGovernanceGate,
    GovernanceProposal,
    ProposalType,
    ProposalStatus,
)
from .memory import TriTierMemoryEngine
from .watchdog import SafetyWatchdog, SafetyWatchdogState
from .anti_entropy import AntiEntropyFilter

__all__ = [
    "__version__",
    "MultiSigGovernanceGate",
    "GovernanceProposal",
    "ProposalType",
    "ProposalStatus",
    "TriTierMemoryEngine",
    "SafetyWatchdog",
    "SafetyWatchdogState",
    "AntiEntropyFilter",
]
