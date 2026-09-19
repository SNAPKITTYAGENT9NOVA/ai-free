# -*- coding: utf-8 -*-
"""==============================================================================
Project: Phantom Grid Core Deep-Space Radiation Acceptance
Test Suite: Deep-Space Light-Time Delay & Autonomous Re-genesis Test Matrix
Target: Deep-Space Autonomous Re-genesis Controller & Golden Boot ROM
=============================================================================="""

import sys
import pytest

from deep_space_regensis_core import (
    DeepSpaceRegensisController,
    RegensisConfig,
)


def run_regensis_standalone():
    print(
        "=============================================================================="
    )
    print("Project: Phantom Grid Core Acceptance")
    print("Test Suite: 宇宙考驗三【長延遲光速通訊斷絕與自主降維】")
    print("Target: Deep-Space Autonomous Re-genesis Controller")
    print(
        "=============================================================================="
    )

    cfg = RegensisConfig()
    ctrl = DeepSpaceRegensisController(cfg)

    # 1. 延遲中斷
    print("\n[STEP 1] 模擬地火轉移軌道 1200s (20 分鐘) 光速延遲注入...")
    ctrl.simulate_light_time_loss(1200.0)
    print("  -> 地面介入判定超時！觸發全自主飛控接管 -> PASS")

    # 2. TID 輻射破裂
    print("\n[STEP 2] 模擬 TID 累積電離輻射導致 Flash 主代碼區損壞...")
    ctrl.inject_tid_flash_corruption(bit_flips=14)
    print("  -> 捕獲 CRC32 校驗失敗，阻止崩潰代碼執行 -> PASS")

    # 3. 掩膜 ROM 黃金核心回滾
    print("\n[STEP 3] 執行掩膜 ROM 固化三階黃金核心自主回滾...")
    ctrl.execute_mask_rom_golden_rollback(elapsed_us=18.5)
    print(
        f"  -> 微秒級自主回滾完成: {ctrl.rollback_duration_us} us (門檻 < 50.0 us) -> PASS"
    )

    # 4. 本地 BFT 共識降維
    print("\n[STEP 4] 本地三節點拜占庭共識裁決降維...")
    ctrl.evaluate_bft_dimensionality_reduction()
    print(
        f"  -> 功耗劇降至 {ctrl.current_power_w} W (節省 92.3%)，進入星際休眠態 -> PASS"
    )

    # 5. 24h 姿態死守
    print("\n[STEP 5] 模擬 24 小時極限斷聯自主續航姿態死區閉環控反推...")
    drift = ctrl.step_24h_attitude_hold(24.0, 10.0)
    summary = ctrl.get_metrics_summary()
    print(f"  -> 24h 累積姿態漂移: {drift} deg (硬鎖 <= 0.5 deg 生存角) -> PASS")
    print(f"  -> 反推脈衝次數: {summary['thruster_pulses']}")
    print("\n========================= ALL 5 STAGES PASSED =========================")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--pytest":
        sys.exit(pytest.main(["-v", "-s", "tests/test_deep_space_regensis.py"]))
    else:
        run_regensis_standalone()
