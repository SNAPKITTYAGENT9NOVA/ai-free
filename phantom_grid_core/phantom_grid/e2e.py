# -*- coding: utf-8 -*-
"""
PHANTOM GRID Core - ISO 26262 ASIL-D E2E CRC8 & Safety State Machine
"""

from __future__ import annotations

import enum
import time
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


def calculate_crc8_sae_j1850(data: bytes) -> int:
    """計算 CRC-8 (SAE J1850, Poly=0x1D, Init=0xFF, FinalXOR=0xFF)"""
    crc = 0xFF
    poly = 0x1D
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ poly) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc ^ 0xFF


def build_e2e_frame(payload_data_6bytes: bytes, counter: int) -> bytes:
    """構建 8-byte E2E CAN 報文 (Byte 0: Counter 低 4-bit, Bytes 1..6: 數據, Byte 7: CRC8)"""
    cnt_nibble = counter & 0x0F
    byte_0 = cnt_nibble.to_bytes(1, "big")
    raw_7 = byte_0 + payload_data_6bytes[:6]
    crc = calculate_crc8_sae_j1850(raw_7)
    return raw_7 + bytes([crc])


@dataclass
class E2ERxState:
    """MCU / 上位機接收端狀態結構體 (對應 C 語言 E2E_RxState_t)"""
    expected_counter: int = 0
    err_count: int = 0
    is_degraded: bool = False
    consecutive_good: int = 0

    def validate_frame(self, payload: bytes) -> bool:
        if len(payload) != 8:
            return False

        received_crc = payload[7]
        calculated_crc = calculate_crc8_sae_j1850(payload[:7])

        if received_crc != calculated_crc:
            self.err_count += 1
            self.consecutive_good = 0
            if self.err_count >= 3:
                self.is_degraded = True
            return False

        received_counter = payload[0] & 0x0F
        if received_counter != self.expected_counter:
            self.err_count += 1
            self.consecutive_good = 0
            self.expected_counter = (received_counter + 1) & 0x0F
            if self.err_count >= 3:
                self.is_degraded = True
            return False

        # 校驗成功
        self.err_count = 0
        self.expected_counter = (received_counter + 1) & 0x0F
        self.consecutive_good += 1

        # 連續 10 幀 E2E 正確則自動切回 NORMAL
        if self.consecutive_good >= 10:
            self.is_degraded = False

        return True


class Iso26262State(enum.Enum):
    STATE_NORMAL = "STATE_NORMAL"              # 全功率運轉 (100% 輸出)
    STATE_DEGRADED = "STATE_DEGRADED"          # 降級運轉 (50% 輸出功率壓制)
    STATE_BUS_OFF_SAFE = "STATE_BUS_OFF_SAFE"  # Bus-Off 0ms PWM 歸零，高阻態，100ms 快速重啟
    STATE_HARD_FAULT = "STATE_HARD_FAULT"      # 重啟失敗 >= 3，永久鎖止，DTC 0xD001，UDS $14 解鎖
    STATE_RESET = "STATE_RESET"                # 看門狗逾時，硬體重置引腳觸發，強制重開機


class Iso26262SafetyStateMachine:
    """ISO 26262 車規狀態轉換機"""

    FAST_RESTART_INTERVAL_SEC = 0.100  # 100ms
    MAX_FAST_RESTART_FAILURES = 3
    DTC_HARD_FAULT = "0xD001"

    def __init__(self):
        self.state = Iso26262State.STATE_NORMAL
        self.e2e_state = E2ERxState()
        self.tec = 0
        self.fast_restart_failures = 0
        self.last_restart_attempt_time = 0.0
        self.pwm_duty_pct = 100.0
        self.power_limit_pct = 100.0
        self.active_dtc: Optional[str] = None
        self.is_permanently_locked = False
        self.hardware_reset_pin_asserted = False
        self.incident_history: List[str] = []

    def process_e2e_frame(self, frame_8bytes: bytes) -> Tuple[bool, Iso26262State, str]:
        if self.is_permanently_locked:
            return False, self.state, f"系統鎖止在 STATE_HARD_FAULT (DTC {self.active_dtc})，拒絕執行"

        if self.state in (Iso26262State.STATE_BUS_OFF_SAFE, Iso26262State.STATE_RESET):
            return False, self.state, f"系統處於 {self.state.value}，通訊已中斷"

        valid = self.e2e_state.validate_frame(frame_8bytes)

        if not valid:
            if self.e2e_state.is_degraded and self.state == Iso26262State.STATE_NORMAL:
                self.state = Iso26262State.STATE_DEGRADED
                self.power_limit_pct = 50.0
                self.pwm_duty_pct = 50.0
                msg = f"連續偵測到 3 幀異常 -> 切入 STATE_DEGRADED (輸出限縮至 50%)"
                self.incident_history.append(msg)
                return False, self.state, msg
            return False, self.state, f"幀異常 (當前錯誤累積: {self.e2e_state.err_count})"
        else:
            if self.state == Iso26262State.STATE_DEGRADED and not self.e2e_state.is_degraded:
                self.state = Iso26262State.STATE_NORMAL
                self.power_limit_pct = 100.0
                self.pwm_duty_pct = 100.0
                msg = f"連續 10 幀 E2E 正確 -> 自動切回 STATE_NORMAL (全功率 100% 恢復)"
                self.incident_history.append(msg)
                return True, self.state, msg
            return True, self.state, "E2E_FRAME_VALID"

    def handle_can_tec(self, tec: int, now: Optional[float] = None) -> Tuple[Iso26262State, str]:
        self.tec = tec
        t = now or time.time()
        if self.tec > 255:
            if self.state != Iso26262State.STATE_HARD_FAULT:
                self.state = Iso26262State.STATE_BUS_OFF_SAFE
                self.pwm_duty_pct = 0.0
                self.power_limit_pct = 0.0
                self.last_restart_attempt_time = t
                msg = f"CAN TEC={self.tec} > 255 觸發 Bus-Off -> STATE_BUS_OFF_SAFE (PWM 0ms 歸零高阻態，啟動 100ms 重啟計時器)"
                self.incident_history.append(msg)
                return self.state, msg
        return self.state, f"TEC_NORMAL ({self.tec})"

    def step_bus_off_recovery(self, restart_succeeded: bool, now: Optional[float] = None) -> Tuple[bool, Iso26262State, str]:
        t = now or time.time()
        if self.state != Iso26262State.STATE_BUS_OFF_SAFE:
            return False, self.state, "非 Bus-Off 狀態，忽略重啟"

        if restart_succeeded:
            self.state = Iso26262State.STATE_NORMAL
            self.pwm_duty_pct = 100.0
            self.power_limit_pct = 100.0
            self.fast_restart_failures = 0
            self.tec = 0
            msg = "Bus-Off 快速重啟成功 -> 恢復 STATE_NORMAL (100% 功率)"
            self.incident_history.append(msg)
            return True, self.state, msg

        self.fast_restart_failures += 1
        self.last_restart_attempt_time = t

        if self.fast_restart_failures >= self.MAX_FAST_RESTART_FAILURES:
            self.state = Iso26262State.STATE_HARD_FAULT
            self.is_permanently_locked = True
            self.active_dtc = self.DTC_HARD_FAULT
            self.pwm_duty_pct = 0.0
            self.power_limit_pct = 0.0
            msg = f"快速重啟失敗達 3 次 -> 轉入 STATE_HARD_FAULT (DTC {self.active_dtc} 鎖止)"
            self.incident_history.append(msg)
            return False, self.state, msg

        return False, self.state, f"快速重啟嘗試失敗 ({self.fast_restart_failures}/3)，等待下個 100ms"

    def execute_uds_14_clear_dtc(self) -> Tuple[bool, str]:
        if self.state == Iso26262State.STATE_HARD_FAULT or self.active_dtc == self.DTC_HARD_FAULT:
            cleared_dtc = self.active_dtc
            self.active_dtc = None
            self.is_permanently_locked = False
            self.fast_restart_failures = 0
            self.tec = 0
            self.e2e_state = E2ERxState()
            self.state = Iso26262State.STATE_NORMAL
            self.pwm_duty_pct = 100.0
            self.power_limit_pct = 100.0
            msg = f"UDS $14 授權清除 DTC {cleared_dtc} 成功：STATE_HARD_FAULT 解鎖，系統恢復 STATE_NORMAL"
            self.incident_history.append(msg)
            return True, msg
        return False, "無進行中之 HARD_FAULT DTC，忽略清除請求"

    def handle_watchdog_timeout(self) -> Tuple[Iso26262State, str]:
        self.state = Iso26262State.STATE_RESET
        self.hardware_reset_pin_asserted = True
        self.pwm_duty_pct = 0.0
        self.power_limit_pct = 0.0
        msg = "主循環 Watchdog 逾時 -> STATE_RESET！觸發硬體重置引腳，拉高安全迴路警報，硬體強制重開機"
        self.incident_history.append(msg)
        return self.state, msg

    def power_cycle_cold_reboot(self) -> Tuple[Iso26262State, str]:
        self.state = Iso26262State.STATE_NORMAL
        self.e2e_state = E2ERxState()
        self.tec = 0
        self.fast_restart_failures = 0
        self.pwm_duty_pct = 100.0
        self.power_limit_pct = 100.0
        self.active_dtc = None
        self.is_permanently_locked = False
        self.hardware_reset_pin_asserted = False
        msg = "硬體冷開機完成：重置回 STATE_NORMAL"
        self.incident_history.append(msg)
        return self.state, msg
