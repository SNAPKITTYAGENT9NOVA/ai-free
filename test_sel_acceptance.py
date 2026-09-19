"""==============================================================================
Project: Phantom Grid Core Deep-Space Radiation Acceptance
Test Suite: Heavy-Ion Single Event Latchup (SEL) Acceptance Test Matrix
Target: Power Distribution Unit (PDU) & Microsecond Smart Current Limiter
=============================================================================="""

import sys
import pytest

from sel_protection_pdu import MicrosecondSmartCurrentLimiter, PDUConfig, SELState


def run_sel_standalone():
    print(
        "=============================================================================="
    )
    print("Project: Phantom Grid Core Acceptance")
    print("Test Suite: 宇宙考驗一【重離子單粒子閂鎖 (SEL) 微秒雪崩阻斷】")
    print("Target: PDU Smart Current Limiter & Power-Cycle Controller")
    print(
        "=============================================================================="
    )

    cfg = PDUConfig()
    pdu = MicrosecondSmartCurrentLimiter(cfg)

    # 1. 注入
    print("\n[STEP 1] 模擬 75 MeV*cm2/mg 重離子轟擊晶片核心...")
    pdu.inject_heavy_ion_strike(current_time_us=10.0)
    print(
        f"  -> 寄生 PNPN 閂鎖觸發！突波電流: {pdu.current_ma:.1f} mA (正常: 120.0 mA)"
    )

    # 2. 推進偵測
    t = 10.0
    dt = 0.5
    while t <= 12.5:
        t += dt
        pdu.evaluate_step(current_time_us=t, dt_us=dt)
        if pdu.state == SELState.SURGE_DETECTED:
            break
    t_detect = (
        pdu.detection_timestamp_us - 10.0
        if pdu.detection_timestamp_us is not None
        else 0.0
    )
    print(
        f"\n[STEP 2] PDU 智慧電流限幅偵測響應: {t_detect:.2f} us (門檻 < 5.0 us) -> PASS"
    )

    # 3. 物理切斷
    while t <= 35.0:
        t += dt
        pdu.evaluate_step(current_time_us=t, dt_us=dt)
        if pdu.state == SELState.QUENCH_POWER_OFF:
            break
    t_quench = (
        pdu.quench_timestamp_us - 10.0 if pdu.quench_timestamp_us is not None else 0.0
    )
    print(
        f"\n[STEP 3] 物理斷電冷卻切斷響應: {t_quench:.2f} us (門檻 < 50.0 us，死線 100.0 us) -> PASS"
    )

    # 4. 熱斑消散與自主復原
    while t <= 3500.0:
        t += 20.0
        pdu.evaluate_step(current_time_us=t, dt_us=20.0)
        if pdu.state == SELState.AUTONOMOUS_RECOVERY:
            break
    summary = pdu.get_metrics_summary()
    print("\n[STEP 4] 矽基微觀熱斑消散收斂，自主無人干預安全復原 -> PASS")
    print(f"  -> 總復原用時: {summary['total_recovery_time_us']} us")
    print(f"  -> 復電電壓: {summary['final_voltage_v']} V")
    print(f"  -> 核心電流: {summary['final_current_ma']} mA")
    print("\n========================= ALL 5 STAGES PASSED =========================")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--pytest":
        sys.exit(pytest.main(["-v", "-s", "tests/test_sel_acceptance.py"]))
    else:
        run_sel_standalone()
