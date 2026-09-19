# -*- coding: utf-8 -*-
"""
arc2_program_synthesizer.py - ARC-AGI-2 靜態幾何 A* 程式合成引擎

【交付產出與核心亮點】：
1. A* 啟發式剪枝：以所有訓練範例的「平均像素殘差比率」做為 h(n)，優先展開殘差下降最顯著的幾何算子分支。
2. 多樣本嚴格約束：候選程式必須同時在所有 Few-Shot 範例（Train pairs）上達到 h(n) = 0.0 才判定通過，避免單一樣本過擬合。
3. 時限與深度安全鎖：內建 timeout_sec 與 max_depth，確保程式合成搜尋不會陷入無窮遞迴卡死。
"""

import os
import sys
import time
import heapq
from dataclasses import dataclass, field
from typing import List, Callable, Tuple, Optional, Dict, Any
import numpy as np

if sys.platform == "win32":
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
    except Exception:
        pass

import arc_dsl_primitives as dsl
from arc_dataset_loader import ARCPair

@dataclass
class DSLOperation:
    """封裝單一 DSL 算子與其呼叫參數"""
    name: str
    fn: Callable[[np.ndarray], np.ndarray]

@dataclass(order=True)
class SearchNode:
    """A* 搜尋節點，依 f_score = cost + heuristic 排序"""
    f_score: float
    cost: int = field(compare=False)
    program: List[DSLOperation] = field(compare=False)

class ARC2ProgramSynthesizer:
    """ARC-AGI-2 靜態幾何 A* 程式合成引擎"""
    def __init__(self, max_depth: int = 3, timeout_sec: float = 10.0):
        self.max_depth = max_depth
        self.timeout_sec = timeout_sec
        self.operators: List[DSLOperation] = self._init_operators()

    def _init_operators(self) -> List[DSLOperation]:
        """初始化基礎 DSL 算子候選庫"""
        ops = [
            DSLOperation("rot90", lambda g: dsl.rotate_cw(g, k=1)),
            DSLOperation("rot180", lambda g: dsl.rotate_cw(g, k=2)),
            DSLOperation("rot270", lambda g: dsl.rotate_cw(g, k=3)),
            DSLOperation("flip_h", dsl.flip_h),
            DSLOperation("flip_v", dsl.flip_v),
            DSLOperation("flip_diag", dsl.flip_diag),
            DSLOperation("gravity_down", lambda g: dsl.apply_gravity(g, direction="DOWN")),
            DSLOperation("gravity_up", lambda g: dsl.apply_gravity(g, direction="UP")),
            DSLOperation("gravity_left", lambda g: dsl.apply_gravity(g, direction="LEFT")),
            DSLOperation("gravity_right", lambda g: dsl.apply_gravity(g, direction="RIGHT")),
            DSLOperation("scale_2x", lambda g: dsl.scale_kronecker(g, 2, 2)),
        ]
        return ops

    def _apply_program(self, grid: np.ndarray, program: List[DSLOperation]) -> Optional[np.ndarray]:
        """依序執行候選算子流水線"""
        curr = grid.copy()
        for op in program:
            try:
                curr = op.fn(curr)
            except Exception:
                return None
        return curr

    def _heuristic(self, program: List[DSLOperation], train_pairs: List[ARCPair]) -> float:
        """
        啟發式評估函數 h(n)：
        計算目前候選程式在所有展示對上的平均像素殘差比例
        """
        total_error = 0.0
        for pair in train_pairs:
            pred = self._apply_program(pair.input_grid, program)
            if pred is None or pred.shape != pair.output_grid.shape:
                total_error += 1.0  # 尺寸不合給予最高懲罰
            else:
                mismatches = float(np.sum(pred != pair.output_grid))
                total_error += mismatches / float(pair.output_grid.size)
        return total_error / float(len(train_pairs))

    def synthesize(self, train_pairs: List[ARCPair]) -> Optional[List[str]]:
        """透過 A* 搜尋演算法，尋找能完美適配所有展示樣本的 DSL 組合"""
        start_time = time.time()
        open_set: List[SearchNode] = []
        
        # 初始根節點 (空程式)
        initial_h = self._heuristic([], train_pairs)
        heapq.heappush(open_set, SearchNode(f_score=initial_h, cost=0, program=[]))

        visited_programs = set()

        while open_set:
            if time.time() - start_time > self.timeout_sec:
                print(f"[!] A* 搜尋超時 ({self.timeout_sec}s)，提前終止！")
                break

            current_node = heapq.heappop(open_set)
            prog = current_node.program
            prog_names = tuple(op.name for op in prog)

            if prog_names in visited_programs:
                continue
            visited_programs.add(prog_names)

            # 驗證是否完美契合所有展示範例
            h_score = self._heuristic(prog, train_pairs)
            if h_score == 0.0:
                print(f"[OK] 成功合成最佳流水線: {' -> '.join(prog_names)} (步數: {len(prog)})")
                return [op.name for op in prog]

            # 剪枝：若已達最大搜尋深度則不再往下展開
            if len(prog) >= self.max_depth:
                continue

            # 擴展子算子節點
            for op in self.operators:
                new_prog = prog + [op]
                new_cost = current_node.cost + 1
                new_h = self._heuristic(new_prog, train_pairs)
                # f(n) = g(n) * 權重 + h(n)
                f_score = (new_cost * 0.1) + new_h
                heapq.heappush(open_set, SearchNode(f_score=f_score, cost=new_cost, program=new_prog))

        print("[x] 未能在預設深度與時限內合成完全吻合的解。")
        return None

if __name__ == "__main__":
    demo_in_1 = np.array([[1, 0, 0], [0, 2, 0], [0, 0, 0]], dtype=np.uint8)
    temp_1 = dsl.rotate_cw(demo_in_1, 1)
    demo_out_1 = dsl.apply_gravity(temp_1, "DOWN")

    demo_in_2 = np.array([[0, 3, 0], [0, 0, 4], [0, 0, 0]], dtype=np.uint8)
    temp_2 = dsl.rotate_cw(demo_in_2, 1)
    demo_out_2 = dsl.apply_gravity(temp_2, "DOWN")

    pairs = [
        ARCPair(input_grid=demo_in_1, output_grid=demo_out_1),
        ARCPair(input_grid=demo_in_2, output_grid=demo_out_2)
    ]

    print("[*] 正在啟動 ARC-2 靜態幾何 A* 程式合成器測試...")
    synthesizer = ARC2ProgramSynthesizer(max_depth=3, timeout_sec=5.0)
    solution = synthesizer.synthesize(pairs)
    print(f"[*] 最終合成解: {solution}")
