# -*- coding: utf-8 -*-
"""
arc_dsl_primitives.py - ARC Static Geometry & Physics DSL Primitives
Provides pure functional grid manipulation operators.
"""

from typing import Any
import numpy as np

def rotate_cw(g: np.ndarray, k: int = 1) -> np.ndarray:
    """順時針旋轉 90 * k 度"""
    return np.rot90(g, -k)

def flip_h(g: np.ndarray) -> np.ndarray:
    """水平翻轉 (左右鏡射)"""
    return np.fliplr(g)

def flip_v(g: np.ndarray) -> np.ndarray:
    """垂直翻轉 (上下鏡射)"""
    return np.flipud(g)

def flip_diag(g: np.ndarray) -> np.ndarray:
    """主對角線翻轉 (轉置)"""
    return g.T

def apply_gravity(g: np.ndarray, direction: str = "DOWN") -> np.ndarray:
    """
    將非零像素沿指定方向掉落堆疊 (Gravity simulation)
    支援方向: DOWN, UP, LEFT, RIGHT
    """
    d = direction.upper()
    curr = g.copy()
    
    if d == "DOWN":
        res = np.zeros_like(curr)
        for col in range(curr.shape[1]):
            non_zeros = curr[:, col][curr[:, col] != 0]
            if len(non_zeros) > 0:
                res[-len(non_zeros):, col] = non_zeros
        return res
    elif d == "UP":
        res = np.zeros_like(curr)
        for col in range(curr.shape[1]):
            non_zeros = curr[:, col][curr[:, col] != 0]
            if len(non_zeros) > 0:
                res[:len(non_zeros), col] = non_zeros
        return res
    elif d == "LEFT":
        res = np.zeros_like(curr)
        for row in range(curr.shape[0]):
            non_zeros = curr[row, :][curr[row, :] != 0]
            if len(non_zeros) > 0:
                res[row, :len(non_zeros)] = non_zeros
        return res
    elif d == "RIGHT":
        res = np.zeros_like(curr)
        for row in range(curr.shape[0]):
            non_zeros = curr[row, :][curr[row, :] != 0]
            if len(non_zeros) > 0:
                res[row, -len(non_zeros):] = non_zeros
        return res
    else:
        return curr

def scale_kronecker(g: np.ndarray, sy: int = 2, sx: int = 2) -> np.ndarray:
    """克羅內克積等比放大網格"""
    return np.kron(g, np.ones((sy, sx), dtype=g.dtype))
