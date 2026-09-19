"""==============================================================================
Project: Phantom Grid Core Deep-Space Acceptance
Test Suite: test_sel_acceptance.py
Target: Heavy-Ion Single Event Latchup (SEL) Microsecond Quench & Power-Cycle
Description:
    宇宙考驗一：【重離子單粒子閂鎖（SEL）微秒雪崩阻斷】
    驗收硬指標:
        1. 智慧電流限幅 (Smart Current Limiter) 偵測延遲 < 5.0 us
        2. 物理斷電冷卻 (Power-Cycle Reset) 截斷延遲 < 50.0 us (遠低於 100us 熔融線)
        3. 重離子熱斑消散後，無人干預下安全復原核心運算
=============================================================================="""

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sel_protection_pdu import MicrosecondSmartCurrentLimiter, PDUConfig, SELState


class TestSELAcceptance:
    @pytest.fixture(autouse=True)
    def setup_pdu(self) -> None:
        self.cfg = PDUConfig(
            nominal_voltage_v=3.30,
            nominal_current_ma=120.0,
            overcurrent_threshold_ma=360.0,
            max_detection_time_us=5.0,
            max_quench_time_us=50.0,
            silicon_meltdown_limit_us=100.0,
        )
        self.pdu = MicrosecondSmartCurrentLimiter(self.cfg)

    def test_sel_stage_01_heavy_ion_scr_avalanche_surge(self) -> None:
        """Stage 1: 高能重離子穿透封裝，誘發寄生 PNPN 可控矽雪崩大電流"""
        assert self.pdu.state == SELState.NORMAL
        assert self.pdu.current_ma == 120.0
        assert not self.pdu.pnpn_scr_active

        # 模擬 75 MeV*cm2/mg 重離子轟擊
        self.pdu.inject_heavy_ion_strike(
            energy_mev_cm2_mg=75.0,
            surge_peak_current_ma=1850.0,
            current_time_us=10.0,
        )

        assert self.pdu.pnpn_scr_active is True
        assert self.pdu.current_ma == 1850.0
        assert self.pdu.hotspot_temp_c > 70.0
        print("\n[SEL Stage 1 PASS] Heavy-Ion PNPN SCR Latchup triggered! Current surge: 1850.0 mA")

    def test_sel_stage_02_smart_current_limiter_ultrafast_detection(self) -> None:
        """Stage 2: 智慧電流限幅在 < 5.0 us 內偵測到異常電流突波"""
        # 10.0 us 入射重離子
        self.pdu.inject_heavy_ion_strike(
            energy_mev_cm2_mg=75.0,
            surge_peak_current_ma=1850.0,
            current_time_us=10.0,
        )

        # 步進至 12.0 us (間隔 2.0 us)
        t = 10.0
        dt = 0.5
        while t <= 12.5:
            t += dt
            self.pdu.evaluate_step(current_time_us=t, dt_us=dt)
            if self.pdu.state == SELState.SURGE_DETECTED:
                break

        assert self.pdu.state == SELState.SURGE_DETECTED
        assert self.pdu.detection_timestamp_us is not None
        t_detect = self.pdu.detection_timestamp_us - 10.0
        print(f"\n[SEL Stage 2 PASS] Limiter detection: {t_detect:.2f} us (< 5.0 us)")
        assert t_detect < self.cfg.max_detection_time_us

    def test_sel_stage_03_hardware_microsecond_quench_cut_off(self) -> None:
        """Stage 3: 系統在 < 50.0 us 內執行物理斷電冷卻，強制關斷 SCR (遠低於 100us 熔融線)"""
        # 注入與微步推進
        self.pdu.inject_heavy_ion_strike(current_time_us=10.0)

        t = 10.0
        dt = 0.5
        while t <= 35.0:
            t += dt
            self.pdu.evaluate_step(current_time_us=t, dt_us=dt)
            if self.pdu.state == SELState.QUENCH_POWER_OFF:
                break

        assert self.pdu.state == SELState.QUENCH_POWER_OFF
        assert self.pdu.quench_timestamp_us is not None
        t_quench = self.pdu.quench_timestamp_us - 10.0
        print(
            f"\n[SEL Stage 3 PASS] Microsecond Quench Cut-Off time: {t_quench:.2f} us "
            f"(Limit < 50.0 us, far below 100.0 us meltdown limit)"
        )
        assert t_quench < self.cfg.max_quench_time_us
        assert self.pdu.current_voltage_v == 0.0
        assert self.pdu.current_ma == 0.0
        assert not self.pdu.pnpn_scr_active  # SCR 失去維持電流已徹底熄滅

    def test_sel_stage_04_silicon_micro_hotspot_thermal_decay(self) -> None:
        """Stage 4: 矽基微觀熱斑指數消散模型收斂，避免載流子殘留"""
        self.pdu.inject_heavy_ion_strike(current_time_us=10.0)

        # 模擬微秒初期高頻步進切斷 (0.5us)，隨後推進至熱斑消散
        t = 10.0
        while t <= 50.0:
            t += 0.5
            self.pdu.evaluate_step(current_time_us=t, dt_us=0.5)

        while t <= 1500.0:
            t += 10.0
            self.pdu.evaluate_step(current_time_us=t, dt_us=10.0)

        assert self.pdu.state == SELState.THERMAL_DECAY
        # 驗證熱斑溫度顯著降溫
        assert self.pdu.hotspot_temp_c < 60.0
        print(f"\n[SEL Stage 4 PASS] Thermal decay converged, T={self.pdu.hotspot_temp_c:.2f}C")

    def test_sel_stage_05_autonomous_core_resumption_unattended(self) -> None:
        """Stage 5: 重離子熱斑消散後，無人干預下安全復原核心運算 (Autonomous Core Resumption)"""
        self.pdu.inject_heavy_ion_strike(current_time_us=10.0)

        # 1. 微秒初期高頻步進完成偵測與物理切斷
        t = 10.0
        while t <= 50.0:
            t += 0.5
            self.pdu.evaluate_step(current_time_us=t, dt_us=0.5)

        # 2. 推進至冷卻維持時間滿足 (min_cooldown_hold_us 2000us)
        while t <= 3500.0:
            t += 20.0
            self.pdu.evaluate_step(current_time_us=t, dt_us=20.0)
            if self.pdu.state == SELState.AUTONOMOUS_RECOVERY:
                break

        assert self.pdu.state == SELState.AUTONOMOUS_RECOVERY
        summary = self.pdu.get_metrics_summary()
        print("\n[SEL Stage 5 PASS] Unattended Autonomous Resumption SUCCESS:")
        print(f"  - Detection Latency: {summary['detection_time_us']} us (Target < 5.0 us)")
        print(f"  - Physical Quench: {summary['quench_time_us']} us (Target < 50.0 us)")
        print(f"  - Total Recovery Time: {summary['total_recovery_time_us']} us")
        print(f"  - Restored Voltage: {summary['final_voltage_v']} V (Nominal 3.3V)")
        print(f"  - Core Current: {summary['final_current_ma']} mA (Nominal 120mA)")
        print(f"  - Die Temperature: {summary['final_temp_c']} degC (Cooled to baseline)")

        assert summary["detection_time_us"] < 5.0
        assert summary["quench_time_us"] < 50.0
        assert summary["final_voltage_v"] == 3.30
        assert summary["final_current_ma"] == 120.0
