# -*- coding: utf-8 -*-
"""
PHANTOM GRID Core - Anti-Entropy Filter
語意抗熵過濾器 (AntiEntropyFilter)
在通訊匯流排出口自動剔除 AI 冗餘陳詞與空泛套話，
維護高密度的指令執行純度。
支援直接調用: AntiEntropyFilter.purify(text)
"""

from __future__ import annotations

import re
from typing import List, Optional, Tuple


class AntiEntropyFilter:
    """
    語意抗熵過濾器：
    在通訊匯流排出口自動剔除 AI 冗餘陳詞與空泛套話，
    維護高密度的指令執行純度。
    """

    # 內建過濾空泛與冗餘詞彙庫
    DEFAULT_ENTROPY_PATTERNS = [
        r"作為一個\s*AI(?:模型|助手)?(?:，|,)?",
        r"身為一個\s*AI(?:模型|助手)?(?:，|,)?",
        r"作為一名\s*AI(?:模型|助手)?(?:，|,)?",
        r"毋庸置疑(?:地)?(?:，|,)?",
        r"無可厚非(?:地)?(?:，|,)?",
        r"值得注意的是(?:，|,)?",
        r"總而言之(?:，|,)?",
        r"綜上所述(?:，|,)?",
        r"請放心(?:，|,)?",
        r"眾所周知(?:，|,)?",
        r"在某種程度上(?:，|,)?",
        r"不用擔心(?:，|,)?",
        r"如您所知(?:，|,)?",
        r"希望對(?:你|您)(?:有所)?(?:幫助|協助)(?:，|,)?(?:！|!)?",
    ]

    def __init__(self, custom_patterns: Optional[List[str]] = None):
        patterns = list(self.DEFAULT_ENTROPY_PATTERNS)
        if custom_patterns:
            patterns.extend(custom_patterns)
        self.regex = re.compile("|".join(f"(?:{p})" for p in patterns), re.IGNORECASE)

    def filter_egress(self, raw_command_text: str) -> Tuple[str, int, List[str]]:
        """
        過濾通訊匯流排出口文本：
        返回: (純淨指令字串, 剔除匹配次數, 匹配到的陳詞清單)
        """
        matched = self.regex.findall(raw_command_text)
        cleaned = self.regex.sub("", raw_command_text)

        # 清除可能殘留的多餘標點或首尾空格
        cleaned = re.sub(r"^[，,。！!\s]+", "", cleaned)
        cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()

        return cleaned, len(matched), matched

    @classmethod
    def purify(cls, raw_text: str) -> str:
        """快速指令提純：一鍵剔除空泛陳詞並返回純淨指令字串"""
        instance = cls()
        cleaned, _, _ = instance.filter_egress(raw_text)
        return cleaned
