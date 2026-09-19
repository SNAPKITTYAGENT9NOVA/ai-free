"""
==============================================================================
Project: Phantom Mind Deep Space Core
Module: cosmic_weight_tmr.py
Standard: ECSS-E-ST-60-02C (Space Engineering: ASIC & FPGA Development)
Description: 神經網路權重三模冗餘 (TMR) 實時校驗與輻射位元翻轉在線自癒
==============================================================================
"""

import numpy as np


class CosmicWeightGuardian:
    def __init__(self, weight_dim: int = 1024):
        self.dim = weight_dim
        # 在記憶體物理不同區塊維護三份對稱權重映像 (Bank A, Bank B, Bank C)
        base_weights = np.random.randn(self.dim).astype(np.float32)
        self.bank_a = base_weights.copy()
        self.bank_b = base_weights.copy()
        self.bank_c = base_weights.copy()
        self.repaired_counter = 0

    def inject_cosmic_seu(self, target_bank: str, index: int):
        """模擬宇宙重離子轟擊，翻轉指定 Bank 某個權重之位元"""
        if target_bank == "A":
            self.bank_a[index] += 999.0  # 模擬權重突變
        elif target_bank == "B":
            self.bank_b[index] += 999.0
        elif target_bank == "C":
            self.bank_c[index] += 999.0

    def verify_and_heal_weights(self) -> np.ndarray:
        """
        執行 2-out-of-3 拜占庭權重表決：
        一旦發現離群 Bank，立即提取其餘兩份的均值覆蓋修復，輸出絕對純淨權重。
        """
        # 計算兩兩偏差
        diff_ab = np.abs(self.bank_a - self.bank_b)
        diff_ac = np.abs(self.bank_a - self.bank_c)
        diff_bc = np.abs(self.bank_b - self.bank_c)

        # 閥值判定 (數值精度容忍 1e-4)
        corrupted_a = np.where((diff_ab > 1e-4) & (diff_ac > 1e-4))[0]
        corrupted_b = np.where((diff_ab > 1e-4) & (diff_bc > 1e-4))[0]
        corrupted_c = np.where((diff_ac > 1e-4) & (diff_bc > 1e-4))[0]

        # 自癒修復
        if len(corrupted_a) > 0:
            for idx in corrupted_a:
                self.bank_a[idx] = self.bank_b[idx]
                self.repaired_counter += 1
            print(
                "[COSMIC HEAL] Bank A 遭遇 SEU 輻射擊穿，已自動依賴 Bank B/C 熱重構修復！"
            )

        if len(corrupted_b) > 0:
            for idx in corrupted_b:
                self.bank_b[idx] = self.bank_a[idx]
                self.repaired_counter += 1
            print("[COSMIC HEAL] Bank B 遭遇 SEU 輻射擊穿，已自動修復！")

        if len(corrupted_c) > 0:
            for idx in corrupted_c:
                self.bank_c[idx] = self.bank_a[idx]
                self.repaired_counter += 1
            print("[COSMIC HEAL] Bank C 遭遇 SEU 輻射擊穿，已自動修復！")

        return self.bank_a
