# -*- coding: utf-8 -*-
"""
ensemble_verifier.py - ARC-AGI-2 集成驗證與 Top-K 候選解排序器
"""

import os
import sys
import copy
from dataclasses import dataclass
from typing import List, Dict, Any, Tuple, Optional
import numpy as np

if sys.platform == "win32":
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import arc_dsl_primitives as dsl
from arc_dataset_loader import ARCPair, ARCTask
from arc2_program_synthesizer import ARC2ProgramSynthesizer, DSLOperation

@dataclass
class CandidatePrediction:
    """候選輸出預測結構體"""
    program_names: List[str]
    predicted_grid: np.ndarray
    train_score: float      # 在 Train Pairs 上的完美適配分數 (越低越好，0.0 為完全吻合)
    geometry_score: float   # 幾何一致性啟發分數 (例如顏色分佈、尺寸合理性)
    total_rank_score: float # 綜合排序分數

class ARC2EnsembleVerifier:
    """ARC-AGI-2 集成驗證與 Top-K 候選解排序器"""
    def __init__(self, synthesizer: Optional[ARC2ProgramSynthesizer] = None):
        self.synthesizer = synthesizer if synthesizer is not None else ARC2ProgramSynthesizer(max_depth=3)
        self.op_dict: Dict[str, DSLOperation] = {op.name: op for op in self.synthesizer.operators}

    def _execute_pipeline(self, grid: np.ndarray, program_names: List[str]) -> Optional[np.ndarray]:
        """依序執行指定的算子名稱序列"""
        curr = grid.copy()
        for name in program_names:
            op = self.op_dict.get(name)
            if op is None:
                return None
            try:
                curr = op.fn(curr)
            except Exception:
                return None
        return curr

    def _evaluate_train_fit(self, program_names: List[str], train_pairs: List[ARCPair]) -> float:
        """評估候選算子序列在所有 Train 範例上的平均像素誤差"""
        total_mismatch_ratio = 0.0
        for pair in train_pairs:
            pred = self._execute_pipeline(pair.input_grid, program_names)
            if pred is None or pred.shape != pair.output_grid.shape:
                total_mismatch_ratio += 1.0
            else:
                mismatches = np.sum(pred != pair.output_grid)
                total_mismatch_ratio += float(mismatches) / float(pair.output_grid.size)
        return total_mismatch_ratio / float(max(1, len(train_pairs)))

    def _evaluate_geometry_consistency(self, pred_grid: Optional[np.ndarray], train_pairs: List[ARCPair]) -> float:
        """
        評估預測網格與訓練範例輸出的幾何一致性特徵 (例如顏色分佈多樣性、邊界比例)
        分數越低表示一致性越高
        """
        if pred_grid is None:
            return 1.0
        
        # 收集訓練集 Output 的所有合法顏色集合
        valid_colors = set()
        for pair in train_pairs:
            valid_colors.update(np.unique(pair.output_grid).tolist())

        pred_colors = set(np.unique(pred_grid).tolist())
        # 若預測出從未在展示中出現的新顏色，給予懲罰
        unseen_colors = pred_colors - valid_colors
        penalty = 0.5 * (float(len(unseen_colors)) / float(max(1, len(pred_colors))))
        return penalty

    def rank_and_verify(
        self,
        candidate_programs: List[List[str]],
        train_pairs: List[ARCPair],
        test_input: np.ndarray,
        top_k: int = 3
    ) -> List[CandidatePrediction]:
        """對多條候選程式進行全量驗證與綜合評分排序，產出 Top-K 最佳預測"""
        candidates: List[CandidatePrediction] = []

        for prog in candidate_programs:
            train_fit = self._evaluate_train_fit(prog, train_pairs)
            pred_out = self._execute_pipeline(test_input, prog)

            if pred_out is None:
                continue

            geo_fit = self._evaluate_geometry_consistency(pred_out, train_pairs)
            # 綜合排序公式：優先考慮訓練集吻合度 (權重 0.8)，其次考慮幾何特徵合理性 (權重 0.2)
            total_score = (train_fit * 0.8) + (geo_fit * 0.2)

            candidates.append(CandidatePrediction(
                program_names=prog,
                predicted_grid=pred_out,
                train_score=train_fit,
                geometry_score=geo_fit,
                total_rank_score=total_score
            ))

        # 依照綜合分數由小到大排序 (分數越低越優)
        candidates.sort(key=lambda x: x.total_rank_score)

        # 去除預測網格完全相同的重複解，保留多樣性
        unique_results: List[CandidatePrediction] = []
        for cand in candidates:
            if not any(np.array_equal(cand.predicted_grid, u.predicted_grid) for u in unique_results):
                unique_results.append(cand)
            if len(unique_results) >= top_k:
                break

        return unique_results

if __name__ == "__main__":
    # 建立少樣本驗證題 (90 度旋轉 + 向下重力)
    in1 = np.array([[1, 0, 0], [0, 2, 0], [0, 0, 0]], dtype=np.uint8)
    out1 = dsl.apply_gravity(dsl.rotate_cw(in1, 1), "DOWN")

    in2 = np.array([[0, 3, 0], [0, 0, 4], [0, 0, 0]], dtype=np.uint8)
    out2 = dsl.apply_gravity(dsl.rotate_cw(in2, 1), "DOWN")

    test_in = np.array([[0, 0, 5], [6, 0, 0], [0, 0, 0]], dtype=np.uint8)
    expected_test_out = dsl.apply_gravity(dsl.rotate_cw(test_in, 1), "DOWN")

    train_data = [ARCPair(in1, out1), ARCPair(in2, out2)]

    # 模擬產生多組候選程式流水線
    candidate_pool = [
        ["rot90", "gravity_down"],     # 正確解
        ["rot90"],                     # 缺少重力步驟
        ["flip_h", "gravity_down"],    # 錯誤幾何變換
        ["rot180", "gravity_down"]     # 錯誤角度
    ]

    print("[*] 正在啟動 ARC-AGI-2 集成驗證器 (Ensemble Verifier)...")
    verifier = ARC2EnsembleVerifier()
    top_candidates = verifier.rank_and_verify(
        candidate_programs=candidate_pool,
        train_pairs=train_data,
        test_input=test_in,
        top_k=3
    )

    print(f"\n[★] 驗證完畢，挑選出 Top-{len(top_candidates)} 候選解：")
    for idx, cand in enumerate(top_candidates, 1):
        is_exact = np.array_equal(cand.predicted_grid, expected_test_out)
        print(f"\nRank {idx} | 算子流水線: {' -> '.join(cand.program_names)}")
        print(f"       | 訓練集吻合殘差: {cand.train_score:.4f}, 幾何懲罰: {cand.geometry_score:.4f}, 總分: {cand.total_rank_score:.4f}")
        print(f"       | 是否完美命中預期解: {'[✓] 是' if is_exact else '[x] 否'}")
        print("       | 輸出矩陣預測:")
        print(cand.predicted_grid)
