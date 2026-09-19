"""==============================================================================
Project: Phantom Grid Core Deep-Space Radiation Defense
Module: sel_protection_pdu.py
Target: Power Distribution Unit (PDU) & Microsecond Smart Current Limiter
Description:
    宇宙考驗一：【重離子單粒子閂鎖（SEL, Single Event Latchup）微秒雪崩阻斷】
    物理機制：
        在宇宙輻射環境中，高能重離子穿透晶片封裝，觸發矽基 CMOS 內部寄生的雙極性
        電晶體（PNPN 結構），引發可控矽效應（SCR Latchup）。
        供電端（VDD）與地（GND）之間瞬間形成低阻抗大電流通道（數百毫安培至數安培湧浪）。
        若未在 100μs 內處置，矽基結構將在微觀尺度直接熱失控熔融燒毀。
    驗收硬指標：
        1. 智慧電流限幅（Smart Current Limiter）偵測延遲 t_detect < 5.0 μs。
        2. 物理斷電冷卻（Power-Cycle Reset）切斷延遲 t_quench < 50.0 μs (遠低於 100μs 熔毀線)。
        3. 重離子熱斑消散後，無人干預下安全軟啟動復原核心運算（Autonomous Core Resumption）。
=============================================================================="""

from dataclasses import dataclass
from enum import Enum
import math
from typing import Dict, List, Optional


class SELState(Enum):
    NORMAL = "NORMAL"
    SURGE_DETECTED = "SURGE_DETECTED"
    QUENCH_POWER_OFF = "QUENCH_POWER_OFF"
    THERMAL_DECAY = "THERMAL_DECAY"
    AUTONOMOUS_RECOVERY = "AUTONOMOUS_RECOVERY"


@dataclass
class PDUConfig:
    """PDU 硬體與限流電路物理參數設定"""

    nominal_voltage_v: float = 3.30  # 額定工作電壓 3.3V
    nominal_current_ma: float = 120.0  # 額定晶片核心工作電流 120mA
    overcurrent_threshold_ma: float = 360.0  # 突波過流觸發門檻 360mA (3.0x 額定)
    rate_of_change_threshold_ma_per_us: float = 100.0  # dI/dt 突波斜率門檻 100mA/μs

    # 硬體微秒級關鍵時間門檻 (微秒 μs)
    max_detection_time_us: float = 5.0  # 驗收門檻: 偵測時間 < 5.0 μs
    max_quench_time_us: float = 50.0  # 驗收門檻: 物理切斷時間 < 50.0 μs
    silicon_meltdown_limit_us: float = 100.0  # 矽基熔融死線: 100.0 μs

    # 熱斑冷卻與復原參數
    thermal_decay_tau_us: float = 800.0  # 熱斑消散時間常數 (μs)
    min_cooldown_hold_us: float = 2000.0  # 最小冷卻維持時間 2.0 ms
    soft_start_ramp_us: float = 500.0  # 軟啟動電壓爬升時間 500 μs


@dataclass
class MicroEventTelemetry:
    """微秒級物理事件遙測資料"""

    timestamp_us: float
    voltage_v: float
    current_ma: float
    hotspot_temp_c: float
    state: SELState
    pnpn_scr_active: bool


class MicrosecondSmartCurrentLimiter:
    """PDU 前端微秒級類比/數位高速智慧電流限幅器"""

    def __init__(self, config: Optional[PDUConfig] = None) -> None:
        self.cfg = config or PDUConfig()
        self.state = SELState.NORMAL
        self.current_voltage_v = self.cfg.nominal_voltage_v
        self.current_ma = self.cfg.nominal_current_ma
        self.hotspot_temp_c = 45.0  # 晶片初始正常節點溫度 45°C
        self.ambient_temp_c = 45.0

        # 狀態標誌與計時器 (μs)
        self.pnpn_scr_active = False
        self.latchup_injected_time_us: Optional[float] = None
        self.detection_timestamp_us: Optional[float] = None
        self.quench_timestamp_us: Optional[float] = None
        self.recovery_timestamp_us: Optional[float] = None

        # 遙測記錄
        self.telemetry_history: List[MicroEventTelemetry] = []

    def inject_heavy_ion_strike(
        self,
        energy_mev_cm2_mg: float = 75.0,
        surge_peak_current_ma: float = 1850.0,
        current_time_us: float = 10.0,
    ) -> None:
        """模擬高能重離子穿透封裝，誘發寄生 PNPN 可控矽效應 (SCR Latchup)"""
        self.latchup_injected_time_us = current_time_us
        self.pnpn_scr_active = True
        # 電流瞬間飆升至 1.85A (低阻抗短路通道)
        self.current_ma = surge_peak_current_ma
        # 熱斑瞬間因強大焦耳熱升溫
        self.hotspot_temp_c += 35.0  # 衝擊初溫升

    def evaluate_step(
        self,
        current_time_us: float,
        dt_us: float = 0.5,
        hardware_analog_delay_us: float = 1.8,
        mosfet_gate_discharge_us: float = 9.5,
    ) -> MicroEventTelemetry:
        """微秒級物理步進運算 (建議步長 0.5μs ~ 1.0μs)"""

        # 1. 偵測階段 (Smart Current Limiter)
        if self.state == SELState.NORMAL:
            if self.pnpn_scr_active and self.latchup_injected_time_us is not None:
                elapsed_since_strike = current_time_us - self.latchup_injected_time_us
                # 類比比較器 + 高速濾波延遲 (真實物理響應約 1.8μs < 5.0μs)
                if elapsed_since_strike >= hardware_analog_delay_us:
                    if self.current_ma >= self.cfg.overcurrent_threshold_ma:
                        self.state = SELState.SURGE_DETECTED
                        self.detection_timestamp_us = current_time_us

        # 2. 微秒物理切斷階段 (MOSFET Gate Discharge & Quench)
        elif self.state == SELState.SURGE_DETECTED:
            if self.detection_timestamp_us is not None:
                elapsed_since_detection = current_time_us - self.detection_timestamp_us
                # 高邊開關快速洩放關斷 (約 9.5μs 內完全關斷)
                if elapsed_since_detection >= mosfet_gate_discharge_us:
                    self.state = SELState.QUENCH_POWER_OFF
                    self.quench_timestamp_us = current_time_us
                    self.current_voltage_v = 0.0  # 物理徹底掉電 (0V)
                    self.current_ma = (
                        0.0  # 供電被拔除，SCR 失去維持電流 (Holding Current) 熄滅
                    )
                    self.pnpn_scr_active = False

        # 3. 矽基微觀熱斑冷卻消散 (Thermal Decay)
        elif self.state == SELState.QUENCH_POWER_OFF:
            if self.quench_timestamp_us is not None:
                time_in_quench = current_time_us - self.quench_timestamp_us
                if time_in_quench >= 50.0:  # 50μs 後進入冷卻維持階段
                    self.state = SELState.THERMAL_DECAY

        elif self.state == SELState.THERMAL_DECAY:
            if self.quench_timestamp_us is not None:
                cooldown_elapsed = current_time_us - self.quench_timestamp_us
                # 熱斑指數消散模型: T(t) = T_amb + DeltaT * exp(-t / tau)
                delta_t = max(0.0, self.hotspot_temp_c - self.ambient_temp_c)
                decay_factor = math.exp(-dt_us / self.cfg.thermal_decay_tau_us)
                self.hotspot_temp_c = self.ambient_temp_c + delta_t * decay_factor

                # 滿足最小維持冷卻時間且熱斑溫度降至安全線 (< 50°C)
                if (
                    cooldown_elapsed >= self.cfg.min_cooldown_hold_us
                    and self.hotspot_temp_c <= self.ambient_temp_c + 5.0
                ):
                    self.state = SELState.AUTONOMOUS_RECOVERY
                    self.recovery_timestamp_us = current_time_us
                    self.current_voltage_v = self.cfg.nominal_voltage_v
                    self.current_ma = self.cfg.nominal_current_ma  # 恢復額定 120mA

        # 記錄遙測
        telem = MicroEventTelemetry(
            timestamp_us=current_time_us,
            voltage_v=self.current_voltage_v,
            current_ma=self.current_ma,
            hotspot_temp_c=self.hotspot_temp_c,
            state=self.state,
            pnpn_scr_active=self.pnpn_scr_active,
        )
        self.telemetry_history.append(telem)
        return telem

    def get_metrics_summary(self) -> Dict[str, float]:
        """計算極限驗收指標數值"""
        t_detect = (
            (self.detection_timestamp_us - self.latchup_injected_time_us)
            if (self.detection_timestamp_us and self.latchup_injected_time_us)
            else 0.0
        )
        t_quench = (
            (self.quench_timestamp_us - self.latchup_injected_time_us)
            if (self.quench_timestamp_us and self.latchup_injected_time_us)
            else 0.0
        )
        t_recovery = (
            (self.recovery_timestamp_us - self.latchup_injected_time_us)
            if (self.recovery_timestamp_us and self.latchup_injected_time_us)
            else 0.0
        )

        return {
            "detection_time_us": round(t_detect, 2),
            "quench_time_us": round(t_quench, 2),
            "total_recovery_time_us": round(t_recovery, 2),
            "final_voltage_v": round(self.current_voltage_v, 2),
            "final_current_ma": round(self.current_ma, 2),
            "final_temp_c": round(self.hotspot_temp_c, 2),
        }
