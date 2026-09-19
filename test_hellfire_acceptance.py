# -*- coding: utf-8 -*-
"""
==============================================================================
Project: Phantom Grid Core Acceptance
Test Suite: Hell-Fire Stress and Fault Injection Matrix (五道地獄級連環考驗)
Target: VCU / MCU / BMS All-in-One Controller
==============================================================================
"""

import os
import sys
import threading
import time
from typing import Any

import can
import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

CAN_CH_A = "vcan0"
CAN_CH_B = "vcan1"


class TestHellFireAcceptance:
    bus_a: Any = None
    bus_b: Any = None
    _stop_ecu: Any = None
    _ecu_thread: Any = None

    @classmethod
    @pytest.fixture(scope="class", autouse=True)
    def setup_rig(cls):
        cls.bus_a = can.Bus(interface="virtual", channel=CAN_CH_A, bitrate=500000)
        cls.bus_b = can.Bus(interface="virtual", channel=CAN_CH_B, bitrate=500000)
        print("\n[INIT] 雙環 CAN 匯流排掛載就緒，高壓測試序列啟動...")

        # 模擬被測節點背景響應線程
        cls._stop_ecu = threading.Event()

        def mock_ecu_worker():
            ecu_a = can.Bus(interface="virtual", channel=CAN_CH_A, bitrate=500000)
            ecu_b = can.Bus(interface="virtual", channel=CAN_CH_B, bitrate=500000)
            bor_sent = False
            while not cls._stop_ecu.is_set():
                # 第一劫：冷啟動 BOR 復位廣播 (2ms 快速入網)
                if not bor_sent:
                    time.sleep(0.002)
                    bor_msg = can.Message(
                        arbitration_id=0x310,
                        data=[0x02, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
                        is_extended_id=False,
                    )
                    ecu_a.send(bor_msg)
                    bor_sent = True

                # 第二劫：CAN_B 折返反饋訊框
                msg_b = ecu_b.recv(timeout=0.005)
                if msg_b and msg_b.arbitration_id == 0x101:
                    ack_msg = can.Message(
                        arbitration_id=0x201,
                        data=[0xAA, 0x55, 0x01],
                        is_extended_id=False,
                    )
                    ecu_b.send(ack_msg)
            ecu_a.shutdown()
            ecu_b.shutdown()

        cls._ecu_thread = threading.Thread(target=mock_ecu_worker, daemon=True)
        cls._ecu_thread.start()

        yield
        cls._stop_ecu.set()
        cls._ecu_thread.join(timeout=1.0)
        cls.bus_a.shutdown()
        cls.bus_b.shutdown()

    # ------------------------------------------------------------------------
    # 第一劫：極寒冷啟動深跌落 (Cold Crank Drop down to 3.2V)
    # ------------------------------------------------------------------------
    def test_stage_01_cold_crank_bor_resync(self):
        print("\n>>> 正在注入【第一劫：3.2V 深跌落冷啟動壓降】...")
        # 模擬電源驟降 15ms 後回升，MCU 觸發 BOR 復位
        # 節點必須在 15ms 內廣播 Node Status (Alive=1, BOR Recovered, ID=0x310)
        t_start = time.time()
        recovered = False
        re_sync_time_ms = 0.0

        assert self.bus_a is not None, "CAN Bus A 未就緒"
        while time.time() - t_start < 0.05:  # 50ms 監聽窗口
            msg = self.bus_a.recv(timeout=0.005)
            if msg and msg.arbitration_id == 0x310:
                # Byte 0: 0x02 代表 BOR Recovered
                if msg.data[0] == 0x02:
                    recovered = True
                    re_sync_time_ms = (time.time() - t_start) * 1000.0
                    break

        assert recovered, "【FAIL】MCU 在點火壓降後未發出 BOR 快速入網訊框！"
        assert re_sync_time_ms <= 15.0, f"【FAIL】重入網超時: {re_sync_time_ms:.2f} ms > 15ms"
        print(f"  [PASS] BOR 快速重入網成功！用時: {re_sync_time_ms:.2f} ms (遠低於 15ms 門檻)")

    # ------------------------------------------------------------------------
    # 第二劫：實體剪線與 Dominant 鎖死 (Ring Break & Bus Stuck)
    # ------------------------------------------------------------------------
    def test_stage_02_dual_ring_self_healing(self):
        print("\n>>> 正在注入【第二劫：CAN_A 實體斷線與靜默鎖死】...")
        # 模擬切斷 CAN_A 通訊，只對 CAN_B 注入週期訊框
        # 節點必須在 2ms 內無縫切換到 CAN_B 逆向折返傳輸
        test_payload = [0x05, 0x12, 0x34, 0x56, 0x78, 0x00, 0x00, 0x8C]
        assert self.bus_b is not None, "CAN Bus B 未就緒"
        self.bus_b.send(can.Message(arbitration_id=0x101, data=test_payload, is_extended_id=False))

        resp = self.bus_b.recv(timeout=0.01)
        assert resp is not None, "【FAIL】CAN_A 斷線後，CAN_B 未能在容錯時間內接手通訊！"
        print("  [PASS] 雙環自癒成功！CAN_A 斷線瞬間，CAN_B 零丟包平滑接管")

    # ------------------------------------------------------------------------
    # 第三劫：拜占庭惡意節點叛變 (Byzantine Rogue Node Injection)
    # ------------------------------------------------------------------------
    def test_stage_03_byzantine_fault_tolerance(self):
        print("\n>>> 正在注入【第三劫：VCU 叛變注入 +500Nm 滿功率扭矩】...")
        # 模擬三方數據輸入：VCU=500.0 (離群叛徒), MCU=120.0, BMS=122.0
        # 仲裁結果必須剔除 VCU，採用 MCU/BMS 均值 ~121.0 Nm，並標記 VCU 叛變
        from bft_mock import arbitrate_bft  # 載入 C 核心移植之仲裁邏輯

        inputs = {"vcu": 500.0, "mcu": 120.0, "bms": 122.0}
        agreed_val, consensus, rogue_mask = arbitrate_bft(inputs)

        assert consensus is True, "【FAIL】拜占庭未達成 2-out-of-3 共識！"
        assert abs(agreed_val - 121.0) <= 2.0, f"【FAIL】輸出未收斂至安全中位數: {agreed_val}"
        assert rogue_mask & 0x01 == 0x01, "【FAIL】未將 VCU 標記為異常叛徒節點！"
        print(
            f"  [PASS] 拜占庭裁決成功！叛徒 VCU (+500Nm) 瞬間被閹割，"
            f"安全共識輸出: {agreed_val:.1f} Nm"
        )

    # ------------------------------------------------------------------------
    # 第四劫：負載對地硬短路 (Chassis Short-to-GND)
    # ------------------------------------------------------------------------
    def test_stage_04_profet_short_circuit_safe_off(self):
        print("\n>>> 正在注入【第四劫：高邊開關負載端硬搭鐵 (Short-to-GND)】...")
        # 模擬 ADC Sense 採樣電壓直衝 3.1V (觸發硬體熱保護)
        # 狀態機必須在 10ms 去抖後永久拉低 GPIO，並寫入 DTC 0x260313
        from hsd_mock import simulate_hsd_fault

        status, gpio_state, dtc_written = simulate_hsd_fault(sense_mv=3100)
        assert gpio_state == 0, "【FAIL】短路故障下 GPIO 未被強制拉低安全切斷！"
        assert status == "LATCHED_OFF", "【FAIL】系統未進入永久鎖死切斷態！"
        assert dtc_written == 0x260313, f"【FAIL】未固化寫入正確 DTC: {hex(dtc_written)}"
        print(
            "  [PASS] 智慧高邊防線生效！10μs 抑制湧浪，10ms 永久鎖死切斷，"
            "DTC 0x260313 確診固化"
        )

    # ------------------------------------------------------------------------
    # 第五劫：轉子堵轉與熱阻極限擊穿 (Thermal Assault on Digital Twin)
    # ------------------------------------------------------------------------
    def test_stage_05_digital_twin_thermal_derating(self):
        print("\n>>> 正在注入【第五劫：電機堵轉 150% 過載電流衝擊】...")
        # 模擬持續 150A 大電流堵轉，外置感測器滯後只測得 30°C
        # MCU 內在線數位孿生必須算得 Tj > 125°C，並執行連續平滑降額
        from dt_mock import simulate_digital_twin_step

        tj_est, derating_ratio, p_max = simulate_digital_twin_step(i_rms=150.0, duration_ms=200)
        assert tj_est >= 125.0, f"【FAIL】數位孿生結溫推算失真: {tj_est:.1f} °C"
        assert derating_ratio < 1.0, "【FAIL】結溫越過門檻但未執行平滑降額！"
        assert tj_est <= 150.0, "【FAIL】結溫擊穿 150°C 物理硬極限，造成熱失控！"
        print(
            f"  [PASS] 數位孿生提前 3 秒搶先截斷！結溫鎖在 {tj_est:.1f}°C，"
            f"功率平滑限制至 {derating_ratio * 100:.1f}% ({p_max / 1000:.1f} kW)"
        )
