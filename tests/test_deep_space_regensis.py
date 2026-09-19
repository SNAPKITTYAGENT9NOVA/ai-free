# -*- coding: utf-8 -*-
"""==============================================================================
Project: Phantom Grid Core Deep-Space Acceptance
Test Suite: test_deep_space_regensis.py
Target: Deep-Space Light-Time Delay & Autonomous Re-genesis Controller
Description:
    宇宙考驗三：【長延遲光速通訊斷絕與自主降維】
    驗收硬指標:
        1. 掩膜 ROM 固化三階黃金核心微秒自主回滾 < 50.0 us
        2. 本地三節點 BFT 共識自主降維，功耗降至 14.2W (星際休眠生存態)
        3. 完全斷聯 24 小時極限續航，死守姿態漂移 <= 0.5 deg (生存角)
=============================================================================="""

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from deep_space_regensis_core import (
    DeepSpaceRegensisController,
    RegensisConfig,
    RegensisState,
)


class TestDeepSpaceRegensisAcceptance:
    @pytest.fixture(autouse=True)
    def setup_controller(self) -> None:
        self.cfg = RegensisConfig(
            light_time_delay_sec=1200.0,
            ground_timeout_threshold_sec=1200.0,
            max_rollback_time_us=50.0,
            max_attitude_drift_deg=0.50,
            normal_power_w=185.0,
            hibernation_power_w=14.2,
        )
        self.ctrl = DeepSpaceRegensisController(self.cfg)

    def test_regensis_stage_01_light_time_delay(self) -> None:
        """Stage 1: 地火軌道單向 20 分鐘 (1200s) 光速延遲注入與地面超時判定"""
        assert self.ctrl.state == RegensisState.NORMAL_CRUISE
        assert self.ctrl.dsn_silent_elapsed_sec == 0.0

        # 模擬 1200 秒無地面心跳
        timed_out = self.ctrl.simulate_light_time_loss(1200.0)
        assert timed_out is True
        assert self.ctrl.state == RegensisState.DSN_TIMED_OUT
        print("\n[Regensis Stage 1 PASS] DSN light-time delay 1200s triggered autonomous takeover")

    def test_regensis_stage_02_tid_flash_crc_break(self) -> None:
        """Stage 2: TID 累積電離輻射導致 Flash 主代碼段多重 CRC32 破裂"""
        self.ctrl.simulate_light_time_loss(1200.0)
        corrupted = self.ctrl.inject_tid_flash_corruption(bit_flips=14)

        assert corrupted is True
        assert self.ctrl.crc_checksum_valid is False
        assert self.ctrl.state == RegensisState.CRC_CORRUPTED
        print("\n[Regensis Stage 2 PASS] TID radiation corrupts Flash CRC32 checksum as expected")

    def test_regensis_stage_03_mask_rom_golden_rollback(self) -> None:
        """Stage 3: 掩膜 ROM 固化三階黃金核心微秒自主回滾 (< 50.0 us)"""
        self.ctrl.simulate_light_time_loss(1200.0)
        self.ctrl.inject_tid_flash_corruption()

        rollback_ok = self.ctrl.execute_mask_rom_golden_rollback(elapsed_us=18.5)
        assert rollback_ok is True
        assert self.ctrl.state == RegensisState.GOLDEN_ROLLBACK
        assert self.ctrl.active_image == "MASK_ROM_GOLDEN_L3"
        assert self.ctrl.crc_checksum_valid is True
        assert self.ctrl.rollback_duration_us is not None
        assert self.ctrl.rollback_duration_us < self.cfg.max_rollback_time_us
        print(f"\n[Regensis Stage 3 PASS] Mask ROM took {self.ctrl.rollback_duration_us} us")
        assert self.ctrl.rollback_duration_us < self.cfg.max_rollback_time_us

    def test_regensis_stage_04_bft_dimensionality_reduction(self) -> None:
        """Stage 4: 本地三節點 BFT 拜占庭共識自主降維至星際休眠生存態 (14.2W)"""
        self.ctrl.simulate_light_time_loss(1200.0)
        self.ctrl.inject_tid_flash_corruption()
        self.ctrl.execute_mask_rom_golden_rollback(18.5)

        reduction_ok = self.ctrl.evaluate_bft_dimensionality_reduction()
        assert reduction_ok is True
        assert self.ctrl.state == RegensisState.HIBERNATION_SURVIVAL
        assert self.ctrl.current_power_w == 14.2
        summary = self.ctrl.get_metrics_summary()
        assert summary["power_saving_ratio"] > 90.0
        print(f"\n[Regensis Stage 4 PASS] BFT sheds power to {self.ctrl.current_power_w}W (92.3%)")

    def test_regensis_stage_05_24h_attitude_stabilization(self) -> None:
        """Stage 5: 24 小時長斷聯極限續航，死守姿態漂移 <= 0.5 deg 生存角"""
        self.ctrl.simulate_light_time_loss(1200.0)
        self.ctrl.inject_tid_flash_corruption()
        self.ctrl.execute_mask_rom_golden_rollback(18.5)
        self.ctrl.evaluate_bft_dimensionality_reduction()

        # 模擬 24 小時姿態死區閉環控反推
        drift = self.ctrl.step_24h_attitude_hold(total_hours=24.0, dt_minutes=10.0)
        assert drift <= self.cfg.max_attitude_drift_deg
        assert self.ctrl.thruster_firing_count > 0

        summary = self.ctrl.get_metrics_summary()
        p_w = summary["power_reduction_w"]
        p_r = summary["power_saving_ratio"]
        print("\n[Regensis Stage 5 PASS] 24h Autonomous Cruise Hold SUCCESS:")
        print(f"  - Ground Delay: {summary['ground_delay_sec']} s")
        print(f"  - Rollback Latency: {summary['rollback_time_us']} us (Limit < 50.0 us)")
        print(f"  - Survival Power: {p_w} W ({p_r}%)")
        print(f"  - 24h Attitude Drift: {summary['attitude_drift_24h_deg']} deg (Limit <= 0.5 deg)")
        print(f"  - Thruster Correction Pulses: {summary['thruster_pulses']}")
