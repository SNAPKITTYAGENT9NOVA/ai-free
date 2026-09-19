# -*- coding: utf-8 -*-
from typing import Tuple

def simulate_hsd_fault(sense_mv: int) -> Tuple[str, int, int]:
    if sense_mv >= 2500:
        status = "LATCHED_OFF"
        gpio_state = 0
        dtc_written = 0x260313
        return status, gpio_state, dtc_written
    else:
        return "NORMAL_ON", 1, 0x000000
