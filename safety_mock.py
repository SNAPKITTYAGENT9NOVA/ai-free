# -*- coding: utf-8 -*-
"""
==============================================================================
Project: Phantom Grid Core Acceptance
Mock: safety_mock.py — SEU (Single Event Upset) Bit-Flip Attack Simulator
Description:
    模擬宇宙射線單粒子翻轉攻擊（SRAM bit-flip），配合漢明反碼冗餘（Complementary
    Redundancy）偵測機制，驗收偵測延遲與自動鎖態切換能力。
==============================================================================
"""

from typing import Tuple


STATE_NORMAL: int = 0xA5  # 工作正常態
STATE_COMPLEMENT: int = 0x5A  # 反碼冗餘鏡像（0xA5 ^ 0xFF）
ANALOG_COMPARATOR_DELAY_US: float = 0.62  # 反碼比對器硬體響應延遲 ~0.62μs


def simulate_seu_attack(
    bit_idx: int = 3,
    base_value: int = STATE_NORMAL,
) -> Tuple[float, bool]:
    """
    模擬 SRAM 單粒子翻轉攻擊（SEU）與漢明反碼防禦捕捉機制。

    物理機制：
    - 宇宙射線高能粒子誘發 SRAM cell 電荷翻轉 → 狀態暫存器 bit 被強行反轉。
    - 漢明反碼冗餘儲存：STATE 與 ~STATE 雙重儲存。
    - 反碼比較器硬體電路：每 clock 比對正碼 XOR 反碼，若不等於 0xFF 則立即觸發。
    - 偵測延遲：類比比較器傳播延遲約 0.62μs，遠低於 1.5μs 軍規門檻。

    Args:
        bit_idx: 被翻轉的位元索引 (0~7)。
        base_value: 正常態原始值（預設 0xA5）。

    Returns:
        (detection_time_us, trapped_to_latched)
        - detection_time_us: 偵測耗時（μs）
        - trapped_to_latched: 是否成功捕捉並鎖態切換
    """
    # 正常態原始值與其反碼
    original = base_value
    complement_stored = original ^ 0xFF  # = 0x5A

    # 注入 SEU bit-flip
    flipped_value = original ^ (1 << bit_idx)

    # 反碼一致性檢查：flipped XOR complement_stored 應等於 0xFF（正常）
    # 若 bit 被翻轉，XOR 結果將偏離 0xFF
    xor_check = flipped_value ^ complement_stored
    seu_detected = xor_check != 0xFF  # 一旦不等於 0xFF 則偵測到翻轉

    # 偵測延遲：類比比較器硬體延遲 0.62μs（固定物理量）
    detection_time_us: float = ANALOG_COMPARATOR_DELAY_US if seu_detected else 0.0

    # 系統自動鎖態：偵測到翻轉後硬體直接切斷至 STATE_LATCHED
    trapped_to_latched: bool = seu_detected

    return round(detection_time_us, 2), trapped_to_latched
