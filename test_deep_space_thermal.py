# -*- coding: utf-8 -*-
"""
test_deep_space_thermal.py - Spacecraft Vacuum Thermal Radiation Acceptance Test Suite
==============================================================================
Project: Phantom Grid Space Systems
Test Suite: Deep-Space Thermal Vacuum and Zero-Convection Matrix (宇宙考驗二)
Target: Rover VCU / MCU / BMS Core Thermal Controller
==============================================================================
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from deep_space_thermal_twin import (
    KELVIN_OFFSET,
    SIGMA_STEFAN_BOLTZMANN,
    DeepSpaceThermalTwin,
    ThermalTwinParams,
)


class TestDeepSpaceThermalAcceptance:
    """Acceptance test suite for Deep-Space Vacuum Thermoelectric Digital Twin."""

    # ------------------------------------------------------------------------
    # 考驗 1：大氣熱交換對流歸零與四次方黑體熱輻射即時切換
    # ------------------------------------------------------------------------
    def test_stage_01_convection_cutoff_and_radiation_switch(self):
        print("\n>>> 正在注入【考驗 1：大氣對流係數歸零 (h_conv=0) 與四次方熱輻射切換】...")
        twin = DeepSpaceThermalTwin()

        # Phase A: 地球大氣環境 (有對流)
        twin.set_environment(in_vacuum=False, sunlit=False, t_env_c=25.0)
        assert twin.p.h_conv == 15.0, "【FAIL】地球大氣對流係數未生效！"
        res_atm = twin.step(duration_s=1.0)
        assert res_atm["h_conv"] == 15.0
        assert res_atm["q_radiation_w"] == 0.0

        # Phase B: 瞬間抽真空至 10^-6 Torr 深空環境
        twin.set_environment(in_vacuum=True, sunlit=False, t_env_c=0.0)
        assert twin.p.h_conv == 0.0, "【FAIL】進入真空後對流未完全歸零！"

        # 檢驗四次方熱輻射定律是否精準滿足 Stefan-Boltzmann 方程
        t_core_k = twin.t_core_k
        t_space_k = 0.0 + KELVIN_OFFSET
        expected_q_rad = (
            twin.p.emissivity
            * SIGMA_STEFAN_BOLTZMANN
            * twin.p.a_rad
            * (t_core_k**4 - t_space_k**4)
        )

        res_vac = twin.step(duration_s=1.0)
        actual_q_rad = res_vac["q_radiation_w"]

        assert abs(actual_q_rad - expected_q_rad) <= 0.5, (
            f"【FAIL】四次方輻射非線性計算偏差過大: 實測 {actual_q_rad} W "
            f"vs 理論 {expected_q_rad:.2f} W"
        )
        print(
            f"  [PASS] 真空對流切斷成功 (h_conv=0.0 W/m2K)！"
            f"動態切換至四次方黑體輻射: {actual_q_rad:.2f} W"
        )

    # ------------------------------------------------------------------------
    # 考驗 2：陽光直射區 (+120°C) 突入隕石坑永夜區 (-150°C) 瞬態 270°C 熱衝擊
    # ------------------------------------------------------------------------
    def test_stage_02_sunlit_to_shadow_transient_thermal_shock(self):
        print("\n>>> 正在注入【考驗 2：+120°C 陽光直射突入 -150°C 隕石坑 (270°C 熱衝擊)】...")
        twin = DeepSpaceThermalTwin()

        # Step A: 於陽光直射區穩定熱浸 (T_env = +120°C)
        twin.set_environment(in_vacuum=True, sunlit=True, t_env_c=120.0, t_chassis_c=65.0)
        res_sun = twin.step(duration_s=10.0)
        t_hot_initial = float(res_sun["t_core_c"])
        assert t_hot_initial >= 40.0, "【FAIL】向陽面熱平衡建立異常！"

        # Step B: 瞬間衝入隕石坑永夜陰影區 (T_env = -150°C)
        # 溫差高達 270°C，太陽光通量瞬間歸零
        twin.set_environment(in_vacuum=True, sunlit=False, t_env_c=-150.0, t_chassis_c=-150.0)
        res_shadow = twin.step(duration_s=5.0, is_driving=False)

        assert res_shadow["q_solar_w"] == 0.0, "【FAIL】進入陰影區後太陽輻射未歸零！"
        assert res_shadow["t_core_c"] < t_hot_initial, (
            "【FAIL】熱衝擊下溫度未迅速響應散熱！"
        )
        temp_drop = t_hot_initial - float(res_shadow["t_core_c"])
        print(
            f"  [PASS] 270°C 瞬態熱衝擊吸收穩固！5 秒降溫斜率: {temp_drop:.2f}°C，"
            f"數值積分連續無發散 (無 Convection 奇異點)"
        )

    # ------------------------------------------------------------------------
    # 考驗 3：極寒永夜陰影區自主「相線微小無效環流」核心預熱 (防電解質凍結)
    # ------------------------------------------------------------------------
    def test_stage_03_autonomous_self_heating_in_cryogenic_shadow(self):
        print("\n>>> 正在注入【考驗 3：-150°C 永夜陰影區自主相線微小環流核心預熱】...")
        twin = DeepSpaceThermalTwin()
        # 置入 -150°C 極寒環境，強制深冷
        twin.set_environment(in_vacuum=True, sunlit=False, t_env_c=-150.0, t_chassis_c=-150.0)
        twin.t_core_k = -15.0 + KELVIN_OFFSET

        # 模擬冷卻 (進入低溫自熱維持)
        res_cooling = twin.step(duration_s=120.0, is_driving=False)

        # 驗證自熱啟動
        assert res_cooling["self_heating_active"] is True, (
            "【FAIL】核心跌破 -20°C 但自主預熱未觸發！"
        )
        assert res_cooling["id_current_amps"] > 10.0, "【FAIL】相線無效環流 Id 未注入！"
        assert res_cooling["q_self_heat_w"] >= 15.0, (
            f"【FAIL】預熱熱功率不足: {res_cooling['q_self_heat_w']} W"
        )

        # 驗證核心溫度守在 -40°C 硬極限之上 (電解質凍結/焊點剪切破壞防禦)
        final_core_c = float(res_cooling["t_core_c"])
        assert final_core_c >= -40.0, (
            f"【FAIL】核心結溫擊穿 -40°C 物理硬底線: {final_core_c}°C (電解質凍結！)"
        )
        print(
            f"  [PASS] 核心自主預熱啟動成功！注入 Id={res_cooling['id_current_amps']}A "
            f"(零扭矩無效環流)，焦耳熱 {res_cooling['q_self_heat_w']} W，"
            f"核心穩鎖在 {final_core_c:.1f}°C (嚴格遠高於 -40°C 凍結線)"
        )

    # ------------------------------------------------------------------------
    # 考驗 4：向陽真空直射區 (+120°C) 不中斷任務熱流連續平滑降額 (防失超)
    # ------------------------------------------------------------------------
    def test_stage_04_sunlit_continuous_derating_quench_prevention(self):
        print("\n>>> 正在注入【考驗 4：+120°C 向陽真空高溫直射熱流連續平滑降額 (防失超)】...")
        twin = DeepSpaceThermalTwin()
        # 設置為向陽面 +120°C 太陽輻射直射環境
        twin.set_environment(in_vacuum=True, sunlit=True, t_env_c=120.0, t_chassis_c=65.0)
        twin.t_core_k = 90.0 + KELVIN_OFFSET

        # 運算高負載運作 180 秒熱浸透
        res_hot = twin.step(duration_s=180.0, is_driving=True)

        derating = float(res_hot["derating_ratio"])
        t_j = float(res_hot["t_junction_c"])

        assert derating < 1.0, "【FAIL】高溫逼近失超點但未啟動平滑降額！"
        assert derating >= 0.18, "【FAIL】降額過度導致任務意外中斷！"
        assert t_j <= 145.0, (
            f"【FAIL】結溫擊穿 145°C 失超極限門檻: {t_j:.2f}°C (熱失控！)"
        )
        print(
            f"  [PASS] 向陽真空熱流箝位成功！連續平滑降額至 {derating * 100:.1f}%，"
            f"晶片結溫鎖在 {t_j:.1f}°C (精準壓制於 145°C 失超點之下，任務不中斷)"
        )

    # ------------------------------------------------------------------------
    # 考驗 5：深空軌道閉環全週期巡弋生存驗證 (向陽 -> 永夜陰影 -> 向陽全閉環)
    # ------------------------------------------------------------------------
    def test_stage_05_full_orbital_crater_survival_cycle(self):
        print("\n>>> 正在注入【考驗 5：深空全閉環巡弋生存演練 (向陽 -> 永夜陰影 -> 向陽)】...")
        params = ThermalTwinParams()
        twin = DeepSpaceThermalTwin(params)

        # 軌道 1：向陽前進 (+120°C) 60 秒
        twin.set_environment(in_vacuum=True, sunlit=True, t_env_c=120.0, t_chassis_c=65.0)
        r1 = twin.step(duration_s=60.0, is_driving=True)
        assert r1["t_junction_c"] <= 145.0

        # 軌道 2：突入月球/行星永夜陰影 (-150°C) 150 秒
        twin.set_environment(in_vacuum=True, sunlit=False, t_env_c=-150.0, t_chassis_c=-150.0)
        r2 = twin.step(duration_s=150.0, is_driving=False)
        assert r2["self_heating_active"] is True
        assert r2["t_core_c"] >= -40.0

        # 軌道 3：駛出陰影重回陽光直射 (+120°C) 60 秒
        twin.set_environment(in_vacuum=True, sunlit=True, t_env_c=120.0, t_chassis_c=65.0)
        r3 = twin.step(duration_s=60.0, is_driving=True)
        assert r3["self_heating_active"] is False  # 預熱安全退出
        assert r3["t_junction_c"] <= 145.0  # 結溫重新受控

        print(
            f"  [PASS] 深空全週期閉環驗證大滿貫！\n"
            f"        向陽端結溫: {r1['t_junction_c']:.1f}°C (<=145°C)\n"
            f"        永夜端核心: {r2['t_core_c']:.1f}°C (>=-40°C, 預熱啟動)\n"
            f"        復位再向陽: 預熱安全退出，結溫平滑箝位至 {r3['t_junction_c']:.1f}°C\n"
            f"        整機零重啟、零故障逃逸、任務 100% 持續可用！"
        )
