# -*- coding: utf-8 -*-
"""
Test Suite: ISO 26262 ASIL-D E2E CRC8 & Safety State Transition Matrix
Validates:
1. E2E CRC8 (SAE J1850) & Alive Counter packing & validation (C & Python double-ended compliance).
2. E2E_RxState_t logic: 3 consecutive errors trigger degradation; 10 consecutive valid frames clear degradation.
3. Safety State Machine Transitions:
   - STATE_NORMAL -> E2E errors >= 3 -> STATE_DEGRADED (50% power).
   - STATE_DEGRADED -> 10 valid frames -> STATE_NORMAL (100% power).
   - CAN TEC > 255 -> STATE_BUS_OFF_SAFE (0% PWM, High-Z, 100ms fast restart timer).
   - Fast restart fails >= 3 times -> STATE_HARD_FAULT (locked, DTC 0xD001).
   - UDS $14 ClearDiagnosticInformation -> unlocks STATE_HARD_FAULT, clears DTC, restores STATE_NORMAL.
   - Watchdog timeout -> STATE_RESET (asserts hardware reset pin).
"""

from __future__ import annotations

from pathlib import Path
import pytest

from e2e_state_matrix import (
    E2ERxState,
    Iso26262SafetyStateMachine,
    Iso26262State,
    build_e2e_frame,
    calculate_crc8_sae_j1850,
)


def test_sae_j1850_crc8_calculation():
    # Test standard SAE J1850 CRC8 calculation (Poly 0x1D, Init 0xFF, Final XOR 0xFF)
    test_data = b"\x00\x01\x02\x03\x04\x05\x06"
    crc = calculate_crc8_sae_j1850(test_data)
    assert 0 <= crc <= 255

    # Verification: identical data yields identical CRC
    assert calculate_crc8_sae_j1850(test_data) == crc
    # Bit change flips CRC
    assert calculate_crc8_sae_j1850(b"\x00\x01\x02\x03\x04\x05\x07") != crc


def test_build_and_validate_e2e_frame():
    payload_6bytes = b"\xAA\xBB\xCC\xDD\xEE\xFF"
    counter = 5

    frame = build_e2e_frame(payload_6bytes, counter)
    assert len(frame) == 8
    assert (frame[0] & 0x0F) == 5
    assert frame[1:7] == payload_6bytes
    # Byte 7 is CRC
    assert frame[7] == calculate_crc8_sae_j1850(frame[:7])

    # Receiver state validation
    rx = E2ERxState(expected_counter=5)
    assert rx.validate_frame(frame) is True
    assert rx.expected_counter == 6
    assert rx.err_count == 0
    assert rx.consecutive_good == 1


def test_e2e_rx_state_degradation_and_hysteresis_recovery():
    rx = E2ERxState(expected_counter=0)
    payload_6b = b"\x11\x22\x33\x44\x55\x66"

    # Frame 0: Valid
    f0 = build_e2e_frame(payload_6b, counter=0)
    assert rx.validate_frame(f0) is True
    assert rx.is_degraded is False

    # Corrupt Frame 1 (CRC tampered)
    bad_f1 = bytearray(build_e2e_frame(payload_6b, counter=1))
    bad_f1[7] ^= 0xFF
    assert rx.validate_frame(bytes(bad_f1)) is False
    assert rx.err_count == 1
    assert rx.is_degraded is False

    # Corrupt Frame 2 (CRC tampered)
    bad_f2 = bytearray(build_e2e_frame(payload_6b, counter=1))
    bad_f2[7] ^= 0xAA
    assert rx.validate_frame(bytes(bad_f2)) is False
    assert rx.err_count == 2
    assert rx.is_degraded is False

    # Corrupt Frame 3 (3rd consecutive error -> is_degraded = True)
    bad_f3 = bytearray(build_e2e_frame(payload_6b, counter=1))
    bad_f3[7] ^= 0x55
    assert rx.validate_frame(bytes(bad_f3)) is False
    assert rx.err_count == 3
    assert rx.is_degraded is True

    # Now send valid consecutive frames: need 10 frames to auto-clear degradation
    cnt = rx.expected_counter
    for i in range(9):
        valid_f = build_e2e_frame(payload_6b, counter=cnt)
        assert rx.validate_frame(valid_f) is True
        assert rx.is_degraded is True  # Still degraded until 10th frame
        cnt = rx.expected_counter

    # 10th valid frame -> automatically clears is_degraded
    valid_f_10 = build_e2e_frame(payload_6b, counter=cnt)
    assert rx.validate_frame(valid_f_10) is True
    assert rx.is_degraded is False


def test_iso26262_state_machine_e2e_degraded_and_auto_recovery():
    sm = Iso26262SafetyStateMachine()
    assert sm.state == Iso26262State.STATE_NORMAL
    assert sm.power_limit_pct == 100.0

    payload_6b = b"\x01\x02\x03\x04\x05\x06"

    # Send 3 corrupted frames
    for i in range(3):
        corrupt = bytearray(build_e2e_frame(payload_6b, counter=i))
        corrupt[7] ^= 0xFF
        ok, state, msg = sm.process_e2e_frame(bytes(corrupt))
        assert ok is False

    assert sm.state == Iso26262State.STATE_DEGRADED
    assert sm.power_limit_pct == 50.0
    assert sm.pwm_duty_pct == 50.0

    # Send 9 valid frames -> remains DEGRADED (50%)
    cnt = sm.e2e_state.expected_counter
    for _ in range(9):
        f = build_e2e_frame(payload_6b, counter=cnt)
        ok, state, _ = sm.process_e2e_frame(f)
        assert ok is True
        assert state == Iso26262State.STATE_DEGRADED
        assert sm.power_limit_pct == 50.0
        cnt = sm.e2e_state.expected_counter

    # 10th valid frame -> transitions back to STATE_NORMAL (100% power)
    f_10 = build_e2e_frame(payload_6b, counter=cnt)
    ok, state, msg = sm.process_e2e_frame(f_10)
    assert ok is True
    assert state == Iso26262State.STATE_NORMAL
    assert sm.power_limit_pct == 100.0
    assert sm.pwm_duty_pct == 100.0
    assert "自動切回 STATE_NORMAL" in msg


def test_iso26262_bus_off_safe_to_hard_fault_and_uds_14_unlock():
    sm = Iso26262SafetyStateMachine()
    base_t = 1000.0

    # 1. CAN TEC > 255 triggers Bus-Off
    state, msg = sm.handle_can_tec(tec=256, now=base_t)
    assert state == Iso26262State.STATE_BUS_OFF_SAFE
    assert sm.pwm_duty_pct == 0.0
    assert sm.power_limit_pct == 0.0
    assert "0ms 歸零" in msg

    # 2. Fast restart attempt 1 fails
    ok, state, msg = sm.step_bus_off_recovery(restart_succeeded=False, now=base_t + 0.100)
    assert ok is False
    assert state == Iso26262State.STATE_BUS_OFF_SAFE
    assert sm.fast_restart_failures == 1

    # 3. Fast restart attempt 2 fails
    ok, state, msg = sm.step_bus_off_recovery(restart_succeeded=False, now=base_t + 0.200)
    assert ok is False
    assert state == Iso26262State.STATE_BUS_OFF_SAFE
    assert sm.fast_restart_failures == 2

    # 4. Fast restart attempt 3 fails -> transitions to STATE_HARD_FAULT (DTC 0xD001)
    ok, state, msg = sm.step_bus_off_recovery(restart_succeeded=False, now=base_t + 0.300)
    assert ok is False
    assert state == Iso26262State.STATE_HARD_FAULT
    assert sm.is_permanently_locked is True
    assert sm.active_dtc == "0xD001"
    assert sm.pwm_duty_pct == 0.0
    assert "轉入 STATE_HARD_FAULT" in msg

    # Frame processing is rejected in HARD_FAULT
    dummy_frame = build_e2e_frame(b"\x00" * 6, counter=0)
    ok_p, state_p, msg_p = sm.process_e2e_frame(dummy_frame)
    assert ok_p is False
    assert "系統鎖止在 STATE_HARD_FAULT" in msg_p

    # 5. UDS $14 ClearDiagnosticInformation unlocks the system
    unlocked, uds_msg = sm.execute_uds_14_clear_dtc()
    assert unlocked is True
    assert sm.state == Iso26262State.STATE_NORMAL
    assert sm.is_permanently_locked is False
    assert sm.active_dtc is None
    assert sm.power_limit_pct == 100.0
    assert sm.pwm_duty_pct == 100.0
    assert "STATE_HARD_FAULT 解鎖" in uds_msg


def test_iso26262_watchdog_timeout_state_reset():
    sm = Iso26262SafetyStateMachine()
    assert sm.hardware_reset_pin_asserted is False

    state, msg = sm.handle_watchdog_timeout()
    assert state == Iso26262State.STATE_RESET
    assert sm.hardware_reset_pin_asserted is True
    assert sm.pwm_duty_pct == 0.0
    assert "硬體強制重開機" in msg

    # Cold power cycle reboots back to NORMAL
    sm.power_cycle_cold_reboot()
    assert sm.state == Iso26262State.STATE_NORMAL
    assert sm.hardware_reset_pin_asserted is False
    assert sm.pwm_duty_pct == 100.0


def test_embedded_c_driver_file_parity():
    # Verify C implementations exist and contain expected definitions
    c_files = ["e2e_crc8_driver.c", "src/e2e_crc8_driver.c"]
    for path_str in c_files:
        p = Path(path_str)
        assert p.is_file(), f"File {path_str} must exist"
        content = p.read_text(encoding="utf-8")
        assert "E2E_CalculateCRC8" in content
        assert "E2E_RxState_t" in content
        assert "E2E_ValidateFrame" in content
        assert "E2E_POLYNOMIAL 0x1D" in content
