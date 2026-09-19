"""
==============================================================================
Project: Phantom Mind Deep Space Core
Test Suite: Deep Space Neuro-OS Core Acceptance
Target: Phantom Grid Interplanetary Autonomous Brain
==============================================================================
"""

import numpy as np

from cosmic_weight_tmr import CosmicWeightGuardian
from space_thermal_governor import SpaceThermalGovernor


class TestDeepSpaceNeuroOS:
    def test_cosmic_weight_tmr_healing(self):
        print(
            "\n>>> 注入【宇宙級大腦考驗一：重離子擊穿 NPU 權重，三模冗餘 (TMR) 熱自癒】..."
        )
        guardian = CosmicWeightGuardian(weight_dim=512)
        orig_weights = guardian.bank_a.copy()

        # 模擬高能重離子穿透轟擊 Bank B 與 Bank C (不同時擊穿同一維度)
        guardian.inject_cosmic_seu(target_bank="B", index=42)
        assert np.abs(guardian.bank_b[42] - orig_weights[42]) > 900.0

        guardian.inject_cosmic_seu(target_bank="A", index=128)
        assert np.abs(guardian.bank_a[128] - orig_weights[128]) > 900.0

        # 執行 2-out-of-3 拜占庭多數校驗與熱修復
        healed_weights = guardian.verify_and_heal_weights()

        # 驗證權重是否完美復原，輸出 0 偏差
        assert np.allclose(healed_weights, orig_weights, atol=1e-4)
        assert guardian.repaired_counter == 2
        print(
            f"  [PASS] TMR 權重自癒成功！修復次數: {guardian.repaired_counter}，權重精度 100% 守護！"
        )

    def test_space_thermal_governor_profiles(self):
        print(
            "\n>>> 注入【宇宙級大腦考驗二：向陽真空 (+115°C) 四次方黑體熱輻射 TDP 箝位】..."
        )
        governor = SpaceThermalGovernor(surface_area_m2=0.08, emissivity=0.90)

        # 1. 常溫深空陰影區 (0°C = 273.15K) -> 應放行 FULL_TACTICAL
        shadow_profile = governor.arbitrate_ai_inference_profile(ambient_temp_c=0.0)
        assert shadow_profile["profile"] == "FULL_TACTICAL_THINKING"
        assert shadow_profile["max_tokens_per_sec"] == 35
        assert shadow_profile["npu_frequency_mhz"] == 1200
        print(
            f"  [PASS] 陰影區 (0°C): 算力全開 {shadow_profile['profile']} (TDP={shadow_profile['permitted_tdp_w']:.2f}W)"
        )

        # 2. 向陽面極端高溫 (+115°C) -> 算力必須連續平滑降額至 CONSTRAINED 或 HIBERNATION
        sunlit_profile = governor.arbitrate_ai_inference_profile(ambient_temp_c=115.0)
        assert sunlit_profile["profile"] in [
            "CONSTRAINED_SURVIVAL_THINKING",
            "HIBERNATION_PULSE_ONLY",
        ]
        assert sunlit_profile["permitted_tdp_w"] < shadow_profile["permitted_tdp_w"]
        print(
            f"  [PASS] 向陽高溫 (+115°C): 動態降額至 {sunlit_profile['profile']} (TDP={sunlit_profile['permitted_tdp_w']:.2f}W)"
        )

        # 3. 超過矽極限 (+130°C) -> 進入脈衝休眠態
        overheat_profile = governor.arbitrate_ai_inference_profile(ambient_temp_c=130.0)
        assert overheat_profile["profile"] == "HIBERNATION_PULSE_ONLY"
        assert overheat_profile["max_tokens_per_sec"] == 2
        print(
            f"  [PASS] 極限超溫 (+130°C): 強制進入 {overheat_profile['profile']} (0 失超保護)"
        )
