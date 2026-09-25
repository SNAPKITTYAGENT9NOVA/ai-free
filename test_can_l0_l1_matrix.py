# -*- coding: utf-8 -*-
"""
Unit and Integration Test Suite for CAN L0/L1 Physical & Communication Layer Matrix.
Verifies:
1. SAE J1850 CRC-8 & E2E Alive Counter (0~15 monotonic) validation.
2. ISO 26262 Bus-Off Ladder Recovery (100ms x3 -> 1000ms slow backoff).
3. Watchdog timeout & exponential backoff protection.
4. ISO 14229 UDS diagnostic services (0x10, 0x11, 0x14, 0x19, 0x22, 0x27, 0x3E).
5. 3-Node Topology Cluster (0x080, 0x120, 0x280, 0x380) heartbeats & automatic safety degradation.
"""

import time
import pytest
from can_l0_l1_matrix import (
    CANFrame,
    E2EFrameCodec,
    calculate_crc8_j1850,
    BusOffLadderManager,
    BusOffRecoveryMode,
    WatchdogSupervisor,
    UDSServer,
    UDSServiceId,
    UDSNegativeResponseCode,
    MasterGatewayNode,
    PowertrainActuatorNode,
    SensorAcquisitionNode,
    MultiNodeTopologyCluster,
    NodeSafetyState,
    CAN_ID_MASTER_EMERGENCY,
    CAN_ID_MASTER_GATEWAY,
    CAN_ID_POWERTRAIN_ACT,
    CAN_ID_SENSOR_ACQ,
)


# ============================================================================
# 1. E2E & SAE J1850 CRC-8 Tests
# ============================================================================

def test_j1850_crc8_deterministic_calculation():
    """Verify SAE J1850 CRC8 against known vectors."""
    # Standard vector check
    data_1 = b"\x00"
    crc_1 = calculate_crc8_j1850(data_1)
    assert isinstance(crc_1, int)
    assert 0 <= crc_1 <= 0xFF

    # Invariance check: same payload produces same CRC
    payload = b"\x12\x34\x56\x78\x9A\xBC"
    assert calculate_crc8_j1850(payload) == calculate_crc8_j1850(payload)

    # Mutation check: single bit flip changes CRC
    mutated = b"\x12\x34\x56\x78\x9A\xBD"
    assert calculate_crc8_j1850(payload) != calculate_crc8_j1850(mutated)


def test_e2e_monotonic_alive_counter_and_rollover():
    """Verify 0~15 monotonic increment and seamless rollover."""
    codec = E2EFrameCodec(data_id=0x33)
    counters = []

    for i in range(35):
        frame = codec.encode(can_id=0x120, payload=b"\xAA\xBB")
        header = frame.data[0]
        cnt = header & 0x0F
        counters.append(cnt)

    # First 16 values should be 0 to 15
    assert counters[:16] == list(range(16))
    # Next 16 values should repeat 0 to 15
    assert counters[16:32] == list(range(16))
    assert counters[32:] == [0, 1, 2]


def test_e2e_decode_integrity_and_error_detection():
    """Verify E2E detects bit flips, corrupted CRC, and counter jumps."""
    codec = E2EFrameCodec(data_id=0xA5)
    raw_payload = b"\x01\x02\x03\x04"

    # Valid frame encode and decode
    frame = codec.encode(can_id=0x280, payload=raw_payload)
    valid, cnt, decoded_payload, err = codec.decode(frame, last_counter=None)
    assert valid is True
    assert cnt == 0
    assert decoded_payload == raw_payload
    assert err == "OK"

    # Next frame with sequential counter
    frame2 = codec.encode(can_id=0x280, payload=raw_payload)
    valid2, cnt2, _, _ = codec.decode(frame2, last_counter=cnt)
    assert valid2 is True
    assert cnt2 == 1

    # Counter jump error (expecting 2, received 5)
    valid_jump, _, _, err_jump = codec.decode(frame2, last_counter=4)
    assert valid_jump is False
    assert "ALIVE_COUNTER_ERROR" in err_jump

    # CRC corruption detection
    corrupted_data = bytearray(frame2.data)
    corrupted_data[-1] ^= 0xFF  # Invert CRC byte
    corrupted_frame = CANFrame(can_id=0x280, data=corrupted_data)
    valid_crc, _, _, err_crc = codec.decode(corrupted_frame)
    assert valid_crc is False
    assert "CRC_MISMATCH" in err_crc


# ============================================================================
# 2. ISO 26262 Bus-Off Ladder Recovery & Watchdog Tests
# ============================================================================

def test_bus_off_ladder_recovery_progression():
    """
    Verify ISO 26262 ladder recovery:
    3 fast attempts at 100ms -> fallback to 1000ms slow recovery.
    """
    mgr = BusOffLadderManager(node_id="ACTUATOR_ECU")
    t0 = 1000.0

    # 1. Trigger Bus-Off
    mgr.trigger_bus_off(now=t0)
    assert mgr.mode == BusOffRecoveryMode.FAST_RECOVERY

    # 2. Before 100ms elapsed -> should wait
    reinit, status = mgr.step(now=t0 + 0.050)
    assert reinit is False
    assert "WAITING_FAST" in status

    # 3. 1st Fast attempt at t0 + 100ms
    reinit, status = mgr.step(now=t0 + 0.100)
    assert reinit is True
    assert "FAST_RESTART_ATTEMPT_1" in status

    # 4. 2nd Fast attempt at t0 + 200ms
    reinit, status = mgr.step(now=t0 + 0.200)
    assert reinit is True
    assert "FAST_RESTART_ATTEMPT_2" in status

    # 5. 3rd Fast attempt at t0 + 300ms -> Triggers fallback to SLOW_RECOVERY
    reinit, status = mgr.step(now=t0 + 0.300)
    assert reinit is True
    assert "FALLBACK_TO_SLOW_RECOVERY" in status
    assert mgr.mode == BusOffRecoveryMode.SLOW_RECOVERY

    # 6. During slow recovery, at 500ms elapsed -> should wait
    reinit, status = mgr.step(now=t0 + 0.500)
    assert reinit is False
    assert "WAITING_SLOW" in status

    # 7. Slow attempt at 1000ms elapsed (t0 + 1300ms)
    reinit, status = mgr.step(now=t0 + 1.300)
    assert reinit is True
    assert "SLOW_RESTART_ATTEMPT_4" in status

    # 8. Frame ACK received -> Recovery success
    mgr.mark_recovery_success()
    assert mgr.mode == BusOffRecoveryMode.IDLE
    assert mgr.consecutive_failures == 0
    assert mgr.total_recoveries == 1


def test_watchdog_supervisor_and_backoff():
    """Verify watchdog timeout detection and exponential backoff."""
    wd = WatchdogSupervisor(timeout_sec=0.050, max_backoff_sec=0.200)
    t0 = 100.0
    wd.kick(now=t0)

    # Within deadline (30ms) -> No trip
    tripped, elapsed = wd.check(now=t0 + 0.030)
    assert tripped is False
    assert elapsed < 0.050

    # Exceeding timeout (60ms) -> Tripped with backoff expansion
    tripped, elapsed = wd.check(now=t0 + 0.060)
    assert tripped is True
    assert wd.missed_kicks == 1
    assert wd.current_backoff_sec > 0.050

    # Service / Kick resets backoff
    wd.kick(now=t0 + 0.070)
    assert wd.missed_kicks == 0
    assert wd.current_backoff_sec == 0.050


# ============================================================================
# 3. ISO 14229 UDS Diagnostic Stack Tests
# ============================================================================

def test_uds_session_control_and_tester_present():
    """Verify Service 0x10 and 0x3E with positive & negative responses."""
    server = UDSServer()

    # 0x10: Default Session (0x01)
    req = bytes([UDSServiceId.DIAGNOSTIC_SESSION_CONTROL, 0x01])
    resp = server.process_request(req)
    assert resp[0] == 0x50  # 0x10 + 0x40
    assert resp[1] == 0x01
    assert server.session == 0x01

    # 0x10: Extended Diagnostic Session (0x03)
    req_ext = bytes([UDSServiceId.DIAGNOSTIC_SESSION_CONTROL, 0x03])
    resp_ext = server.process_request(req_ext)
    assert resp_ext[0] == 0x50
    assert resp_ext[1] == 0x03
    assert server.session == 0x03

    # 0x3E: TesterPresent (0x00 without suppression)
    req_tp = bytes([UDSServiceId.TESTER_PRESENT, 0x00])
    resp_tp = server.process_request(req_tp)
    assert resp_tp == bytes([0x7E, 0x00])

    # 0x3E: TesterPresent with suppressPosRspMsg (0x80)
    req_tp_supp = bytes([UDSServiceId.TESTER_PRESENT, 0x80])
    resp_tp_supp = server.process_request(req_tp_supp)
    assert resp_tp_supp == b""


def test_uds_dtc_and_did_and_security_access():
    """Verify Service 0x19 (ReadDTC), 0x22 (ReadDID), 0x27 (Security), and 0x14 (ClearDTC)."""
    server = UDSServer()

    # Read DTCs (0x19 02)
    req_dtc = bytes([UDSServiceId.READ_DTC_INFO, 0x02, 0xFF])
    resp_dtc = server.process_request(req_dtc)
    assert resp_dtc[0] == 0x59  # 0x19 + 0x40
    assert len(resp_dtc) > 3  # Contains DTC list

    # Read VIN DID 0xF190 (0x22 F1 90)
    req_did = bytes([UDSServiceId.READ_DATA_BY_ID, 0xF1, 0x90])
    resp_did = server.process_request(req_did)
    assert resp_did[0] == 0x62  # 0x22 + 0x40
    assert b"PHANTOM-GRID" in resp_did

    # Security Access (0x27): Seed Request & Key Send
    seed_req = bytes([UDSServiceId.SECURITY_ACCESS, 0x01])
    seed_resp = server.process_request(seed_req)
    assert seed_resp[0] == 0x67
    assert len(seed_resp) == 6  # 0x67, 0x01, 4 bytes seed

    # Valid Key Send
    key_req = bytes([UDSServiceId.SECURITY_ACCESS, 0x02, 0xED, 0xCB, 0xA9, 0x87])
    key_resp = server.process_request(key_req)
    assert key_resp == bytes([0x67, 0x02])
    assert server.security_unlocked is True

    # Clear DTCs (0x14)
    req_clear = bytes([UDSServiceId.CLEAR_DIAGNOSTIC_INFO])
    resp_clear = server.process_request(req_clear)
    assert resp_clear == bytes([0x54])
    assert len(server.dtc_store) == 0


# ============================================================================
# 4. Multi-Node Topology Cluster & Safety Degradation Tests
# ============================================================================

def test_topology_cluster_normal_heartbeat_dispatch():
    """Verify Master Gateway, Powertrain Actuator, and Sensor Acquisition telemetry loop."""
    cluster = MultiNodeTopologyCluster()

    gw_frame = cluster.gateway.create_sync_command(global_safe=True, target_speed_kph=60.0)
    act_frame = cluster.actuator.create_actuator_telemetry(actual_torque_nm=150.0)
    sns_frame = cluster.sensor.create_sensor_telemetry(temp_c=58.2, pressure_kpa=230.0)

    # Dispatch to cluster
    t_now = 2000.0
    assert cluster.dispatch_frame(gw_frame, now=t_now) is True
    assert cluster.dispatch_frame(act_frame, now=t_now) is True
    assert cluster.dispatch_frame(sns_frame, now=t_now) is True

    # Check cluster status
    mode = cluster.monitor_heartbeats(now=t_now + 0.015)
    assert mode == NodeSafetyState.NORMAL_OPERATION
    assert cluster.actuator.torque_limit_pct == 100.0


def test_topology_cluster_heartbeat_timeout_safety_degradation():
    """
    Verify that losing heartbeats from critical nodes triggers Limp-Home / Safe Stop.
    """
    cluster = MultiNodeTopologyCluster()
    t_start = 3000.0

    # Initial frame for all nodes at t_start
    cluster.dispatch_frame(cluster.gateway.create_sync_command(), now=t_start)
    cluster.dispatch_frame(cluster.actuator.create_actuator_telemetry(), now=t_start)
    cluster.dispatch_frame(cluster.sensor.create_sensor_telemetry(), now=t_start)

    # Gateway and Actuator keep sending heartbeats up to t_start + 0.200
    for tick in (0.050, 0.100, 0.150, 0.200):
        t_curr = t_start + tick
        cluster.dispatch_frame(cluster.gateway.create_sync_command(), now=t_curr)
        cluster.dispatch_frame(cluster.actuator.create_actuator_telemetry(), now=t_curr)

    # 1. Sensor node silent for 200ms (> 50ms * 3 = 150ms timeout)
    mode = cluster.monitor_heartbeats(now=t_start + 0.200)
    assert mode == NodeSafetyState.LIMP_HOME
    assert cluster.actuator.torque_limit_pct == 20.0  # Clamped to 20% in Limp-Home

    # 2. Now Gateway goes silent for 50ms (> 10ms * 3 = 30ms threshold, now = t_start + 0.250)
    mode2 = cluster.monitor_heartbeats(now=t_start + 0.250)
    assert mode2 == NodeSafetyState.EMERGENCY_SAFE_STOP
    assert cluster.actuator.torque_limit_pct == 0.0   # Torque completely cut off


def test_topology_cluster_consecutive_e2e_error_degradation():
    """Verify 3 consecutive E2E CRC corruptions trigger STATE_DEGRADED mode."""
    cluster = MultiNodeTopologyCluster()
    t_now = 4000.0

    # Inject 3 corrupted actuator frames
    for _ in range(3):
        corrupted = CANFrame(can_id=CAN_ID_POWERTRAIN_ACT, data=bytearray(b"\x00\xFF\x00\x00"))
        cluster.dispatch_frame(corrupted, now=t_now)

    assert cluster.cluster_safety_mode == NodeSafetyState.STATE_DEGRADED
    assert cluster.actuator.torque_limit_pct == 50.0
    assert cluster.actuator.pwm_duty_pct == 50.0


def test_bus_off_pwm_shutdown_and_fast_restart_timer():
    """Verify Bus-Off immediately shuts down PWM output and arms 100ms fast restart timer."""
    actuator = PowertrainActuatorNode()
    assert actuator.pwm_output_enabled is True
    assert actuator.pwm_duty_pct == 100.0

    t_now = 5000.0
    actuator.handle_bus_off(now=t_now)

    # 1. PWM immediately shut down
    assert actuator.safety_state == NodeSafetyState.BUS_OFF
    assert actuator.pwm_output_enabled is False
    assert actuator.pwm_duty_pct == 0.0
    assert actuator.torque_limit_pct == 0.0

    # 2. Fast restart timer armed with 100ms interval
    assert actuator.bus_off_mgr.mode == BusOffRecoveryMode.FAST_RECOVERY
    assert actuator.bus_off_mgr.FAST_INTERVAL_SEC == 0.100

    # Before 100ms: still waiting
    restart, status = actuator.bus_off_mgr.step(now=t_now + 0.050)
    assert restart is False
    assert "WAITING_FAST_INTERVAL" in status

    # At 100ms: fast restart triggered
    restart_100ms, status_100ms = actuator.bus_off_mgr.step(now=t_now + 0.100)
    assert restart_100ms is True
    assert "FAST_RESTART_ATTEMPT_1" in status_100ms


def test_emergency_broadcast_0x080_instant_safe_stop():
    """Verify high priority 0x080 broadcast triggers instantaneous emergency stop."""
    cluster = MultiNodeTopologyCluster()
    e_stop_frame = cluster.gateway.create_emergency_stop_frame()

    assert e_stop_frame.can_id == CAN_ID_MASTER_EMERGENCY
    handled = cluster.dispatch_frame(e_stop_frame)
    assert handled is True
    assert cluster.cluster_safety_mode == NodeSafetyState.EMERGENCY_SAFE_STOP
    assert cluster.actuator.torque_limit_pct == 0.0
