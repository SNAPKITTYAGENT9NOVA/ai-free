# -*- coding: utf-8 -*-
from typing import Tuple

def simulate_digital_twin_step(i_rms: float, duration_ms: float) -> Tuple[float, float, float]:
    r_dson = 0.0032
    p_loss = (i_rms ** 2) * r_dson
    delta_t = (p_loss * 0.42) * (duration_ms / 1000.0) * 14.5
    tj_est = round(85.0 + delta_t, 1)
    tj_est = min(tj_est, 148.5)

    if tj_est > 125.0:
        over_temp = tj_est - 125.0
        derating_ratio = round(max(0.2, 1.0 - (over_temp / 25.0) * 0.45), 2)
    else:
        derating_ratio = 1.0

    p_max = 55000.0 * derating_ratio
    return tj_est, derating_ratio, p_max
