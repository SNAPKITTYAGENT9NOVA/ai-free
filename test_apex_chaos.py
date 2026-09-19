# -*- coding: utf-8 -*-
"""
==============================================================================
Project: Phantom Grid Core Acceptance
Test Suite: Apex Chaos & Single Event Upset (天頂宇航級複合考驗)
Target: Phantom Grid Dual-Ring Controller Cluster
==============================================================================
"""

import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


class TestApexChaosMatrix:
    # -------------------------------------------------------------------------
    # 天頂絕殺一：ISO 7637-2 Pulse 5a (+87V 拋負載) 複合 3.0V 驟降
    # -------------------------------------------------------------------------
    def test_apex_01_load_dump_and_instant_drop(self):
        print("\n>>> 正在注入【天頂第一絕殺：+87V 突波瞬衝 400ms + 3.0V 斷崖跌落】...")
        from pwr_mock import simulate_extreme_power_transient

        # 階段 1：注入 87V / 400ms 拋負載湧浪
        # 階段 2：緊接跌落至 3.0V / 20ms
        pwr_result = simulate_extreme_power_transient(
            surge_v=87.0,
            surge_duration_ms=400,
            drop_v=3.0,
            drop_duration_ms=20,
        )

        assert pwr_result["tvs_clamped"] is True, "【FAIL】TVS 鉗位失效，後級電路穿透！"
        assert (
            pwr_result["mcu_vcc_min"] >= 2.75
        ), f"【FAIL】MCU 核心電壓塌陷: {pwr_result['mcu_vcc_min']}V < 2.75V"
        assert (
            pwr_result["flash_corrupted"] is False
        ), "【FAIL】電壓振盪導致 Flash 擦寫破包！"
        assert (
            pwr_result["oscillation_lockout"] is True
        ), "【FAIL】未鎖死低壓反覆重啟振盪！"

        print(
            f"  [PASS] 拋負載強行吸收！VCC 穩守 {pwr_result['mcu_vcc_min']:.2f}V，"
            "Flash 磁區 0 損毀，重啟死循環鎖死成功"
        )

    # -------------------------------------------------------------------------
    # 天頂絕殺二：SRAM 宇宙射線單粒子翻轉 (Bit-Flip SEU Assault)
    # -------------------------------------------------------------------------
    def test_apex_02_cosmic_ray_seu_bitflip(self):
        print("\n>>> 正在注入【天頂第二絕殺：執行期隨機 SRAM 記憶體位元翻轉】...")
        from safety_mock import simulate_seu_attack

        # 模擬狀態機變數 STATE_NORMAL (0xA5，反碼 0x5A)
        # 隨機挑選 1 個 bit 進行硬性翻轉 (0xA5 ^ (1 << n))
        flip_bit = random.randint(0, 7)
        detection_time_us, trapped_to_latched = simulate_seu_attack(bit_idx=flip_bit)

        assert (
            trapped_to_latched is True
        ), "【FAIL】單粒子翻轉未被反碼冗餘捕捉，邏輯脫韁跑飛！"
        assert (
            detection_time_us <= 1.5
        ), f"【FAIL】異常捕捉延遲過高: {detection_time_us} μs > 1.5 μs"

        print(
            f"  [PASS] 漢明反碼防禦生效！Bit {flip_bit} 遭擊穿後，"
            f"在 {detection_time_us:.2f} μs 內瞬間自鎖至 STATE_LATCHED，安全切斷！"
        )

    # -------------------------------------------------------------------------
    # 天頂絕殺三：晶振溫漂 ±2.5% + 喋喋不休傻瓜 (Babbling Idiot CAN ID 0x000)
    # -------------------------------------------------------------------------
    def test_apex_03_clock_drift_and_babbling_idiot(self):
        print(
            "\n>>> 注入【天頂第三絕殺：時鐘漂移 2.5% 崩潰 + ID 0x000 惡意霸凌總線】..."
        )
        from bus_mock import simulate_babbling_idiot_network

        # 節點 A 時鐘失步並持續拉低 CAN_A（ID 0x000 滿佔用）
        # 節點 B/C 依靠收發器 DTO（Dominant Time-out）硬體切斷
        # 並由 CAN_B 逆向送達 E-stop
        estop_delivered, dto_tripped_time_ms = simulate_babbling_idiot_network()

        assert (
            dto_tripped_time_ms <= 2.0
        ), f"【FAIL】收發器 DTO 切斷超時: {dto_tripped_time_ms} ms"
        assert (
            estop_delivered is True
        ), "【FAIL】主環遭流氓癱瘓期間，備援環未能遞送緊急制動訊框！"

        print(
            f"  [PASS] 硬體收發器 DTO 於 {dto_tripped_time_ms:.2f} ms 強制切斷流氓節點 A，"
            "CAN_B 備援環成功遞送 E-stop 緊急制動！"
        )

    # -------------------------------------------------------------------------
    # 天頂絕殺四：EEPROM 10^6 次梯度磨耗均衡遷移 (Gradient Wear Leveling)
    # -------------------------------------------------------------------------
    def test_apex_04_eeprom_gradient_wear_leveling(self):
        print("\n>>> 注入【天頂第四絕殺：EEPROM 熱塊 10^6 次寫入超限梯度磨耗】...")
        from apex_chaos_core import EEPROMWearLevelingEngine

        engine = EEPROMWearLevelingEngine(block_count=128, wear_threshold=950_000)
        result = engine.inject_gradient_wear(hot_block=0, write_cycles=1_000_001)

        assert (
            result["bad_block_detected"] is True
        ), "【FAIL】壞塊偵測失效，10^6 次超限寫入未被標記！"
        assert (
            result["data_loss_bytes"] == 0
        ), f"【FAIL】磨耗遷移期間發生數據遺失: {result['data_loss_bytes']} bytes！"
        assert (
            result["migrated_to_block"] != result["hot_block"]
        ), "【FAIL】磨耗均衡遷移目標塊與熱塊相同，均衡失敗！"
        assert result["wear_gap_cycles"] > 0, "【FAIL】磨耗差距為零，均衡無效！"

        print(
            f"  [PASS] EEPROM 壞塊偵測生效！熱塊 Block#{result['hot_block']} "
            f"({result['original_writes']:,} 次) 透明遷移至 Block#{result['migrated_to_block']}，"
            "零數據遺失！"
        )

    # -------------------------------------------------------------------------
    # 天頂絕殺五：四重故障同時疊加 (Quadruple Fault Simultaneous Injection)
    # -------------------------------------------------------------------------
    def test_apex_05_quadruple_fault_safe_state_convergence(self):
        print("\n>>> 注入【天頂第五絕殺：電源+SEU+CAN+EEPROM 四重故障同時疊加】...")
        from apex_chaos_core import MultiFaultSafeStateController

        ctrl = MultiFaultSafeStateController()
        ctrl.inject_faults(
            power_fault=True,
            seu_fault=True,
            can_fault=True,
            eeprom_fault=True,
        )
        result = ctrl.evaluate_safe_state_convergence()

        assert (
            result["active_fault_count"] >= 2
        ), "【FAIL】多重故障注入數量不足，FMEA 測試無效！"
        assert (
            result["safe_state_active"] is True
        ), "【FAIL】四重故障下系統未強制收斂至安全態！SIL-2 防護失效！"
        assert (
            result["fmea_firewall_blocked"] is True
        ), "【FAIL】FMEA 防火牆未啟動，故障蔓延未被阻擋！"
        assert (
            result["output_torque_nm"] == 0.0
        ), f"【FAIL】安全態下輸出扭矩未歸零: {result['output_torque_nm']} Nm！"
        assert (
            result["gpio_all_off"] is True
        ), "【FAIL】安全態下 GPIO 未全部拉低，高邊開關存在漏電風險！"

        faults_str = ", ".join(result["active_faults"])  # type: ignore[arg-type]
        print(
            f"  [PASS] SIL-2 FMEA 防火牆全面生效！{result['active_fault_count']} 重故障"
            f" [{faults_str}] 同時注入，系統強制收斂安全態："
            f"扭矩歸零 {result['output_torque_nm']} Nm，"
            f"GPIO 全部拉低，{result['isolation_count']} 個故障各自隔離！"
        )
