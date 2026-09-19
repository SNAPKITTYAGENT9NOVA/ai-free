# -*- coding: utf-8 -*-
from typing import Dict, Tuple

def arbitrate_bft(inputs: Dict[str, float], tolerance_nm: float = 15.0) -> Tuple[float, bool, int]:
    vcu = inputs.get('vcu', 0.0)
    mcu = inputs.get('mcu', 0.0)
    bms = inputs.get('bms', 0.0)

    diff_vcu_mcu = abs(vcu - mcu)
    diff_mcu_bms = abs(mcu - bms)
    diff_vcu_bms = abs(vcu - bms)

    if diff_mcu_bms <= tolerance_nm:
        agreed_val = (mcu + bms) / 2.0
        consensus = True
        rogue_mask = 0x01 if diff_vcu_mcu > tolerance_nm and diff_vcu_bms > tolerance_nm else 0x00
        return agreed_val, consensus, rogue_mask
    elif diff_vcu_mcu <= tolerance_nm:
        agreed_val = (vcu + mcu) / 2.0
        consensus = True
        rogue_mask = 0x04
        return agreed_val, consensus, rogue_mask
    elif diff_vcu_bms <= tolerance_nm:
        agreed_val = (vcu + bms) / 2.0
        consensus = True
        rogue_mask = 0x02
        return agreed_val, consensus, rogue_mask
    else:
        return min(vcu, mcu, bms), False, 0x07
