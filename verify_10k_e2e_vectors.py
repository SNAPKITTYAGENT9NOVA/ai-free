# -*- coding: utf-8 -*-
"""
Python Worker: 10,000 Pseudo-Random Test Vector Verification
Directly validates the ISO 26262 ASIL-D E2E CRC8 & Safety State Machine logic:
- 4,000 Nominal Sequential Frames (0% False Positives)
- 2,000 CRC8 Bit-Flip & Poisoning Injections (100% Detection)
- 2,000 Counter Replay & Out-of-Order Injections (100% Detection)
- 1,000 Hysteresis Recovery Cycles (10 Consecutive Valid Frames Auto-Recovery)
- 1,000 Bus-Off, Hard Fault (DTC 0xD001), UDS $14 Unlock, and Watchdog Reset Cycles
"""

from __future__ import annotations

import random
import sys
import time
from dataclasses import dataclass
from typing import Dict, List, Tuple

# Ensure UTF-8 output on Windows console
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from e2e_state_matrix import (
    E2ERxState,
    Iso26262SafetyStateMachine,
    Iso26262State,
    build_e2e_frame,
    calculate_crc8_sae_j1850,
)


@dataclass
class TestVectorBenchmarkResults:
    total_vectors: int
    nominal_passed: int
    crc_poisoned_detected: int
    counter_anomalies_detected: int
    hysteresis_cycles_verified: int
    hard_fault_cycles_verified: int
    detection_rate_pct: float
    false_positive_rate_pct: float
    elapsed_seconds: float


def run_10k_vector_validation(seed: int = 42) -> TestVectorBenchmarkResults:
    random.seed(seed)
    t_start = time.perf_counter()

    rx_state = E2ERxState(expected_counter=0)
    state_machine = Iso26262SafetyStateMachine()

    nominal_count = 4000
    crc_poison_count = 2000
    counter_anomaly_count = 2000
    hysteresis_count = 1000
    hard_fault_count = 1000

    nominal_passed = 0
    crc_detected = 0
    counter_detected = 0
    hysteresis_passed = 0
    hard_fault_passed = 0

    print("=" * 70)
    print("🚀 [PYTHON WORKER] Initiating 10,000 Pseudo-Random E2E Test Vector Run")
    print(f"🎲 Seed: {seed} | Target: C-Driver Parity & ISO 26262 ASIL-D Logic")
    print("=" * 70)

    # ------------------------------------------------------------------------
    # Phase 1: 4,000 Nominal Sequential Packets
    # ------------------------------------------------------------------------
    for i in range(nominal_count):
        cnt = rx_state.expected_counter
        payload_6b = random.randbytes(6)
        frame = build_e2e_frame(payload_6b, cnt)

        valid = rx_state.validate_frame(frame)
        if valid and not rx_state.is_degraded:
            nominal_passed += 1
        else:
            raise AssertionError(f"Nominal packet false positive at iteration {i}")

    print(f"✅ Phase 1: 4,000/4,000 Nominal Sequential Packets Passed (0 False Positives)")

    # ------------------------------------------------------------------------
    # Phase 2: 2,000 CRC8 Bit-Flip & Poisoning Injections
    # ------------------------------------------------------------------------
    for i in range(crc_poison_count):
        cnt = rx_state.expected_counter
        payload_6b = random.randbytes(6)
        clean_frame = bytearray(build_e2e_frame(payload_6b, cnt))

        # Bit flip in payload or CRC
        corrupt_byte_idx = random.choice([1, 2, 3, 4, 5, 6, 7])
        bit_mask = 1 << random.randint(0, 7)
        clean_frame[corrupt_byte_idx] ^= bit_mask

        corrupted_frame = bytes(clean_frame)
        valid = rx_state.validate_frame(corrupted_frame)

        if not valid:
            crc_detected += 1
        else:
            raise AssertionError(f"Undetected CRC8 poison at injection {i}")

    print(f"✅ Phase 2: 2,000/2,000 CRC8 Poison Injections Intercepted (100% Detection)")

    # ------------------------------------------------------------------------
    # Phase 3: 2,000 Counter Replay & Out-of-Order Injections
    # ------------------------------------------------------------------------
    for i in range(counter_anomaly_count):
        expected = rx_state.expected_counter
        # Pick illegal counter (anything other than expected)
        illegal_offsets = [1, 2, 3, 5, 7, 10, 15]
        bad_counter = (expected + random.choice(illegal_offsets)) & 0x0F
        if bad_counter == expected:
            bad_counter = (expected + 1) & 0x0F

        payload_6b = random.randbytes(6)
        bad_frame = build_e2e_frame(payload_6b, bad_counter)

        valid = rx_state.validate_frame(bad_frame)
        if not valid:
            counter_detected += 1
            # Verify self-healing resynchronization to received_counter + 1
            assert rx_state.expected_counter == (bad_counter + 1) & 0x0F
        else:
            raise AssertionError(f"Undetected counter anomaly at injection {i}")

    print(f"✅ Phase 3: 2,000/2,000 Counter Replay / Anomaly Injections Intercepted (100% Detection)")

    # ------------------------------------------------------------------------
    # Phase 4: 1,000 Hysteresis Recovery Cycles (3 Bad -> 10 Good -> Recover)
    # ------------------------------------------------------------------------
    for cycle in range(hysteresis_count):
        # 1. Inject 3 consecutive corrupted frames
        for _ in range(3):
            bad_f = bytearray(build_e2e_frame(random.randbytes(6), state_machine.e2e_state.expected_counter))
            bad_f[7] ^= 0x5A
            ok, state, _ = state_machine.process_e2e_frame(bytes(bad_f))
            assert ok is False

        assert state_machine.state == Iso26262State.STATE_DEGRADED
        assert state_machine.power_limit_pct == 50.0

        # 2. Send 9 valid frames: must remain in STATE_DEGRADED (遲滯防抖)
        for _ in range(9):
            cnt = state_machine.e2e_state.expected_counter
            good_f = build_e2e_frame(random.randbytes(6), cnt)
            ok, state, _ = state_machine.process_e2e_frame(good_f)
            assert ok is True
            assert state == Iso26262State.STATE_DEGRADED
            assert state_machine.power_limit_pct == 50.0

        # 3. 10th valid frame: must recover to STATE_NORMAL
        cnt = state_machine.e2e_state.expected_counter
        good_f_10 = build_e2e_frame(random.randbytes(6), cnt)
        ok, state, _ = state_machine.process_e2e_frame(good_f_10)
        assert ok is True
        assert state == Iso26262State.STATE_NORMAL
        assert state_machine.power_limit_pct == 100.0
        hysteresis_passed += 1

    print(f"✅ Phase 4: 1,000/1,000 Hysteresis Recovery Cycles Validated (10-Frame Anti-Jitter Pass)")

    # ------------------------------------------------------------------------
    # Phase 5: 1,000 Bus-Off, Hard Fault (DTC 0xD001) & UDS $14 Unlock Cycles
    # ------------------------------------------------------------------------
    for cycle in range(hard_fault_count):
        # 1. TEC > 255 triggers Bus-Off
        st, msg = state_machine.handle_can_tec(tec=256)
        assert st == Iso26262State.STATE_BUS_OFF_SAFE
        assert state_machine.pwm_duty_pct == 0.0

        # 2. 3 failed restart attempts
        for attempt in range(1, 4):
            state_machine.step_bus_off_recovery(restart_succeeded=False)

        assert state_machine.state == Iso26262State.STATE_HARD_FAULT
        assert state_machine.is_permanently_locked is True
        assert state_machine.active_dtc == "0xD001"

        # 3. UDS $14 ClearDiagnosticInformation unlocks system
        unlocked, _ = state_machine.execute_uds_14_clear_dtc()
        assert unlocked is True
        assert state_machine.state == Iso26262State.STATE_NORMAL
        assert state_machine.is_permanently_locked is False
        assert state_machine.active_dtc is None

        # 4. Watchdog reset verification
        state_machine.handle_watchdog_timeout()
        assert state_machine.state == Iso26262State.STATE_RESET
        assert state_machine.hardware_reset_pin_asserted is True

        # 5. Cold reboot reset
        state_machine.power_cycle_cold_reboot()
        assert state_machine.state == Iso26262State.STATE_NORMAL
        hard_fault_passed += 1

    print(f"✅ Phase 5: 1,000/1,000 Hard Fault & UDS $14 Unlock Cycles Validated (100% Recovery)")

    t_end = time.perf_counter()
    elapsed = t_end - t_start
    total = nominal_count + crc_poison_count + counter_anomaly_count + hysteresis_count + hard_fault_count

    print("=" * 70)
    print("🏆 [BENCHMARK RESULTS] 10,000 / 10,000 Test Vectors 100% PASS")
    print(f"⏱️ Total Execution Time: {elapsed:.3f} seconds (Throughput: {total / elapsed:,.0f} vectors/sec)")
    print(f"🛡️ Fault Detection Rate: 100.00% | False Positive Rate: 0.00%")
    print("=" * 70)

    return TestVectorBenchmarkResults(
        total_vectors=total,
        nominal_passed=nominal_passed,
        crc_poisoned_detected=crc_detected,
        counter_anomalies_detected=counter_detected,
        hysteresis_cycles_verified=hysteresis_passed,
        hard_fault_cycles_verified=hard_fault_passed,
        detection_rate_pct=100.0,
        false_positive_rate_pct=0.0,
        elapsed_seconds=elapsed,
    )


if __name__ == "__main__":
    run_10k_vector_validation()
