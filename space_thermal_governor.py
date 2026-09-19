"""
==============================================================================
Project: Phantom Mind Deep Space Core
Module: space_thermal_governor.py
Description: 真空環境純輻射散熱 (Stefan-Boltzmann) 動態算力 TDP 負載調度器
==============================================================================
"""


class SpaceThermalGovernor:
    def __init__(self, surface_area_m2: float = 0.08, emissivity: float = 0.90):
        self.sigma = 5.670374e-8  # 斯蒂芬-玻爾茲曼常數 W/(m^2 * K^4)
        self.area = surface_area_m2
        self.emissivity = emissivity
        self.max_silicon_temp_k = 398.15  # 矽基安全上限 125°C = 398.15K

    def calculate_max_permitted_tdp(self, ambient_radiation_temp_k: float) -> float:
        """
        逆向解算真空散熱能力：
        P_rad = ε * σ * A * (T_die^4 - T_space^4)
        輸出在當前環境下，大腦 NPU 允許消耗的最大瓦數 (W)
        """
        if ambient_radiation_temp_k >= self.max_silicon_temp_k:
            # 環境熱源已超過矽極限，強制進入 0W 休眠態
            return 0.5

        t_die_4 = self.max_silicon_temp_k**4
        t_space_4 = ambient_radiation_temp_k**4
        p_max = self.emissivity * self.sigma * self.area * (t_die_4 - t_space_4)

        # 考慮底盤結構熱容，留 20% 安全冗餘
        return max(1.0, p_max * 0.8)

    def arbitrate_ai_inference_profile(self, ambient_temp_c: float) -> dict:
        """根據熱輻射餘量，動態切換大腦思考深度"""
        ambient_k = ambient_temp_c + 273.15
        permitted_tdp = self.calculate_max_permitted_tdp(ambient_k)

        if permitted_tdp >= 15.0:
            return {
                "profile": "FULL_TACTICAL_THINKING",
                "max_tokens_per_sec": 35,
                "npu_frequency_mhz": 1200,
                "permitted_tdp_w": permitted_tdp,
            }
        elif permitted_tdp >= 5.0:
            return {
                "profile": "CONSTRAINED_SURVIVAL_THINKING",
                "max_tokens_per_sec": 12,
                "npu_frequency_mhz": 600,
                "permitted_tdp_w": permitted_tdp,
            }
        else:
            return {
                "profile": "HIBERNATION_PULSE_ONLY",
                "max_tokens_per_sec": 2,
                "npu_frequency_mhz": 200,
                "permitted_tdp_w": permitted_tdp,
            }
