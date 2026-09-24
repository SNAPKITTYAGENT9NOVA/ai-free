# -*- coding: utf-8 -*-
"""
Unit and Integration Test Suite for Digital Twin State Engine.
Verifies:
1. In-memory DigitalTwinState attributes (motor_rpm, motor_degraded, battery_voltage_mv, temperature_c).
2. Dynamic health gradient calculation and safety mode degradation.
3. Cyber-Physical Mapping Channels (HPC sub-ms hook, Cockpit HUD feed, Cloud V2X feed with SHA-256 audit).
4. Full integration with SOAGatewayTwin (CAN 0x280 & 0x380 ingestion).
5. Thread-safe snapshot isolation under concurrent mutations.
"""

import threading
import time
import pytest
from can_l0_l1_matrix import (
    CAN_ID_POWERTRAIN_ACT,
    CAN_ID_SENSOR_ACQ,
    PowertrainActuatorNode,
    SensorAcquisitionNode,
)
from digital_twin_state import (
    DigitalTwinMirrorEngine,
    DigitalTwinState,
)
from soa_gateway_twin import SOAGatewayTwin


def test_digital_twin_state_core_attributes():
    """Verify motor_rpm, motor_degraded, battery_voltage_mv, temperature_c."""
    engine = DigitalTwinMirrorEngine(vin="PHANTOM-TEST-VIN")

    # 1. Sync Powertrain (120 Nm, 100% limit)
    t0 = 1000.0
    engine.sync_powertrain_telemetry(actual_torque_nm=120.0, torque_limit_pct=100.0, alive_counter=1, now=t0)
    snap = engine.get_snapshot()

    assert abs(snap.motor_rpm - (120.0 * 24.5)) < 0.1  # 2940.0 RPM
    assert snap.motor_degraded is False
    assert snap.actual_torque_nm == 120.0
    assert snap.torque_limit_pct == 100.0

    # 2. Sync Sensor (60.0°C, 225 kPa)
    engine.sync_sensor_telemetry(temperature_c=60.0, pressure_kpa=225.0, alive_counter=1, now=t0 + 0.010)
    snap2 = engine.get_snapshot()

    assert snap2.temperature_c == 60.0
    assert snap2.coolant_pressure_kpa == 225.0
    # Battery voltage: (398.5 - 60.0 * 0.05) = 395.5 V -> 395500 mV
    assert snap2.battery_voltage_mv == 395500
    assert snap2.health_score == 100.0


def test_digital_twin_motor_degraded_flag_and_safety_mode():
    """Verify motor_degraded flag triggers on torque limitation and safety modes."""
    engine = DigitalTwinMirrorEngine()

    # Normal operation
    engine.sync_powertrain_telemetry(actual_torque_nm=100.0, torque_limit_pct=100.0)
    assert engine.get_snapshot().motor_degraded is False

    # Torque limit drops to 20% (Limp-Home)
    engine.sync_powertrain_telemetry(actual_torque_nm=20.0, torque_limit_pct=20.0)
    assert engine.get_snapshot().motor_degraded is True
    assert engine.get_snapshot().health_score < 100.0  # Penalized by degradation

    # Safety mode update
    engine.update_safety_mode("EMERGENCY_SAFE_STOP")
    snap = engine.get_snapshot()
    assert snap.safety_mode == "EMERGENCY_SAFE_STOP"
    assert snap.motor_degraded is True


def test_digital_twin_thermal_penalty_gradient():
    """Verify health score penalizes extreme temperatures."""
    engine = DigitalTwinMirrorEngine()

    # Moderate temperature: 75°C -> Health = 100%
    engine.sync_sensor_telemetry(temperature_c=75.0, pressure_kpa=220.0)
    assert engine.get_snapshot().health_score == 100.0

    # High temperature: 90°C (>85°C penalty -15) -> Health = 85%
    engine.sync_sensor_telemetry(temperature_c=90.0, pressure_kpa=220.0)
    assert engine.get_snapshot().health_score == 85.0

    # Overheat temperature: 105°C (>100°C penalty -40) -> Health = 60%
    engine.sync_sensor_telemetry(temperature_c=105.0, pressure_kpa=220.0)
    assert engine.get_snapshot().health_score == 60.0


def test_hpc_domain_controller_sub_millisecond_hook():
    """Verify HPC autonomous driving hook receives immediate push notifications."""
    engine = DigitalTwinMirrorEngine()
    dispatched_snapshots = []

    engine.register_hpc_subscriber(lambda s: dispatched_snapshots.append(s))

    engine.sync_powertrain_telemetry(actual_torque_nm=150.0, torque_limit_pct=100.0)
    engine.sync_sensor_telemetry(temperature_c=55.0, pressure_kpa=210.0)

    assert len(dispatched_snapshots) == 2
    assert dispatched_snapshots[0].motor_rpm == 150.0 * 24.5
    assert dispatched_snapshots[1].temperature_c == 55.0


def test_cockpit_ivi_hud_telemetry_feed():
    """Verify Cockpit SoC telemetry formatting and theme switching."""
    engine = DigitalTwinMirrorEngine()

    # Normal state
    engine.sync_powertrain_telemetry(actual_torque_nm=140.0, torque_limit_pct=100.0)
    engine.sync_sensor_telemetry(temperature_c=65.0, pressure_kpa=220.0)
    feed_normal = engine.to_cockpit_telemetry()

    assert feed_normal["channel"] == "COCKPIT_IVI_HUD"
    assert feed_normal["instrument_cluster"]["motor_rpm_dial"] == round(140.0 * 24.5, 1)
    assert feed_normal["hud_warning_telltales"]["motor_degraded_lamp"] is False
    assert feed_normal["ui_theme"] == "DARK_TACTICAL_CYAN"

    # Degraded state
    engine.sync_powertrain_telemetry(actual_torque_nm=20.0, torque_limit_pct=20.0)
    feed_degraded = engine.to_cockpit_telemetry()
    assert feed_degraded["hud_warning_telltales"]["motor_degraded_lamp"] is True
    assert feed_degraded["hud_warning_telltales"]["limp_home_active"] is True
    assert feed_degraded["ui_theme"] == "AMBER_DEGRADED_ALERT"


def test_cloud_v2x_fleet_telematics_payload_and_audit():
    """Verify Cloud V2X telemetry format and cryptographic SHA-256 audit hash."""
    engine = DigitalTwinMirrorEngine(vin="PHANTOM-CLOUD-01")
    engine.sync_powertrain_telemetry(actual_torque_nm=110.0, torque_limit_pct=100.0, alive_counter=7)
    engine.sync_sensor_telemetry(temperature_c=70.0, pressure_kpa=220.0, alive_counter=7)

    payload = engine.to_cloud_v2x_payload()
    assert payload["vin"] == "PHANTOM-CLOUD-01"
    assert "T" in payload["timestamp_iso"]
    assert "Z" in payload["timestamp_iso"]

    telemetry = payload["telemetry"]
    assert telemetry["motor_rpm"] == round(110.0 * 24.5, 2)
    assert telemetry["battery_voltage_mv"] > 390000
    assert telemetry["alive_counter"] == 7
    assert len(payload["audit_sha256"]) == 64  # SHA-256 hex string


def test_soa_gateway_integration_with_digital_twin():
    """Verify SOAGatewayTwin automatically updates DigitalTwinState upon CAN ingestion."""
    gateway = SOAGatewayTwin(service_id=0x1234)
    actuator = PowertrainActuatorNode()
    sensor = SensorAcquisitionNode()

    # Ingest CAN 0x280
    frame_act = actuator.create_actuator_telemetry(actual_torque_nm=130.0)
    gateway.ingest_can_frame(frame_act)

    # Ingest CAN 0x380
    frame_sns = sensor.create_sensor_telemetry(temp_c=58.0, pressure_kpa=215.0)
    gateway.ingest_can_frame(frame_sns)

    dt_state = gateway.get_digital_twin_state()
    assert abs(dt_state.motor_rpm - (130.0 * 24.5)) < 1.0
    assert dt_state.temperature_c == 58.0
    assert dt_state.coolant_pressure_kpa == 215.0
    assert dt_state.battery_voltage_mv > 390000
    assert dt_state.motor_degraded is False


def test_concurrent_snapshot_isolation():
    """Verify thread-safe concurrent reads and writes."""
    engine = DigitalTwinMirrorEngine()
    stop_event = threading.Event()

    def writer():
        counter = 0
        while not stop_event.is_set():
            counter = (counter + 1) % 16
            engine.sync_powertrain_telemetry(actual_torque_nm=float(100 + counter), torque_limit_pct=100.0, alive_counter=counter)
            engine.sync_sensor_telemetry(temperature_c=float(50 + (counter % 10)), pressure_kpa=220.0, alive_counter=counter)
            time.sleep(0.001)

    t = threading.Thread(target=writer)
    t.start()

    # Reader thread samples snapshots
    for _ in range(20):
        snap = engine.get_snapshot()
        assert snap.motor_rpm >= 2450.0
        assert snap.battery_voltage_mv > 300000
        time.sleep(0.002)

    stop_event.set()
    t.join()
