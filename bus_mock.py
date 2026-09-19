# -*- coding: utf-8 -*-
"""
==============================================================================
Project: Phantom Grid Core Acceptance
Mock: bus_mock.py — CAN Babbling Idiot & Dual-Ring Failover Simulator
Description:
    模擬晶振溫漂 ±2.5% 導致節點 A 時鐘失步，並以最高優先權 ID 0x000 持續拉低
    CAN_A 總線（Babbling Idiot），收發器 DTO（Dominant Time-out）硬體切斷，
    備援 CAN_B 逆向遞送緊急制動（E-stop）訊框。
==============================================================================
"""

from typing import Tuple


# 硬體常數
TRANSCEIVER_DTO_TIMEOUT_MS: float = 1.2  # 收發器 DTO 切斷時間（TJA1051 spec ≈ 1.2ms）
DTO_MAX_SPEC_MS: float = 2.0  # 軍規門檻 ≤ 2.0ms
CAN_B_ESTOP_LATENCY_MS: float = 0.35  # CAN_B 備援環 E-stop 遞送延遲 ~0.35ms


def simulate_babbling_idiot_network(
    clock_drift_pct: float = 2.5,
    babbling_id: int = 0x000,
    dto_timeout_ms: float = TRANSCEIVER_DTO_TIMEOUT_MS,
) -> Tuple[bool, float]:
    """
    模擬 Babbling Idiot 攻擊下雙環 CAN 匯流排的容錯保護序列。

    物理機制：
    - 節點 A 晶振溫漂 ±2.5% → Bit Timing 失步 → 幀格式錯誤連發。
    - 節點 A 持續霸佔 CAN_A（ID 0x000 最高優先），填滿 Dominant 位。
    - 收發器 DTO：當 Dominant 持續時間超過 DTO 窗口，硬體強制切斷節點 A TX。
    - 備援 CAN_B：DTO 切斷後 0.35ms，節點 B/C 透過 CAN_B 遞送 E-stop 訊框。

    Args:
        clock_drift_pct: 晶振溫漂百分比（%），超過 ±1.58% 即超出 CAN 容忍範圍。
        babbling_id: 流氓節點注入的仲裁 ID（0x000 = 最高優先）。
        dto_timeout_ms: 收發器 DTO 切斷觸發時間（ms）。

    Returns:
        (estop_delivered, dto_tripped_time_ms)
        - estop_delivered: E-stop 是否成功透過 CAN_B 遞達。
        - dto_tripped_time_ms: DTO 切斷生效時間（ms）。
    """
    # 晶振溫漂校驗：超過 ±1.58% CAN bit timing 容忍範圍 → 觸發 Babbling Idiot
    clock_fault_triggered = clock_drift_pct >= 1.58

    # DTO 切斷：TJA1051 偵測到 Dominant 超時 → 硬體強制拉高 TXD 封鎖節點 A
    dto_tripped_time_ms: float = dto_timeout_ms if clock_fault_triggered else 0.0

    # 備援 CAN_B 遞送 E-stop：DTO 切斷後 0.35ms 備援環抵達
    total_estop_time_ms = dto_tripped_time_ms + CAN_B_ESTOP_LATENCY_MS
    estop_delivered = (
        clock_fault_triggered
        and dto_tripped_time_ms <= DTO_MAX_SPEC_MS
        and total_estop_time_ms < 5.0  # 整體 5ms 系統安全邊界
    )

    return estop_delivered, round(dto_tripped_time_ms, 2)
