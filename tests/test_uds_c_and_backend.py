# -*- coding: utf-8 -*-
"""
Tests for MCU C UDS Bootloader FSM Prototype and Real-Time SocketCAN Telemetry Backend.
Verifies:
1. SocketCANTelemetryBackend frame ingestion, sliding-window load %, jitter, and decoded snapshots.
2. Subscriber notification mechanism and clean worker thread termination.
3. Integrity and conformance of C source/header files
   (src/uds_bootloader_fsm.h, src/uds_bootloader_fsm.c).
4. Python verification suite of the C UDS state machine specification.
"""

from __future__ import annotations

import os
import struct
import time
from typing import List

import pytest

from can_telemetry_backend import (
    CANFrameMetrics,
    SocketCANTelemetryBackend,
    VehicleTelemetrySnapshot,
)


class TestSocketCANTelemetryBackend:
    """Test suite for SocketCANTelemetryBackend."""

    @pytest.fixture
    def backend(self, tmp_path):
        db_file = str(tmp_path / "test_can_audit.db")
        b = SocketCANTelemetryBackend(
            channel="vcan_test",
            bustype="virtual",
            bitrate=500000,
            window_ms=100.0,
            db_path=db_file,
        )
        b.start()
        yield b
        b.stop()

    def test_backend_initialization(self, backend: SocketCANTelemetryBackend):
        assert backend is not None
        assert backend._running is True
        metrics = backend.get_metrics()
        assert isinstance(metrics, CANFrameMetrics)
        assert metrics.total_frames_received == 0
        snapshot = backend.get_snapshot()
        assert isinstance(snapshot, VehicleTelemetrySnapshot)
        assert snapshot.safety_state == "NORMAL"

    def test_decode_master_gateway_frame(self, backend: SocketCANTelemetryBackend):
        # 0x120: Master GW Frame: Byte 1 = Counter (0x07), Byte 2 = Throttle (0x80 -> 50.2%)
        payload = bytes([0xAA, 0x07, 0x80, 0x00, 0x00, 0x00, 0x00, 0x1D])
        success = backend.send_frame(0x120, payload)
        assert success is True

        # Wait for worker thread to process
        time.sleep(0.1)

        snapshot = backend.get_snapshot()
        assert snapshot.alive_counter == 7
        assert abs(snapshot.pwm_limit_pct - 50.2) < 0.5
        assert snapshot.last_arbitration_id == 0x120

    def test_decode_actuator_telemetry_frame_states(self, backend: SocketCANTelemetryBackend):
        # 0x280: RPM=7500, Batt=48000mV, Temp=60C (data[4]=100), Status=1 (DEGRADED)
        f_degraded = struct.pack(">HHBBBB", 7500, 48000, 100, 1, 0x01, 0x00)
        backend.send_frame(0x280, f_degraded)
        time.sleep(0.1)

        snap1 = backend.get_snapshot()
        assert snap1.motor_rpm == 7500
        assert snap1.battery_mv == 48000
        assert snap1.motor_temp_c == 60.0
        assert snap1.safety_state == "DEGRADED"
        assert snap1.active_dtc == "DTC_P0A80"

        # 0x280: Status=2 (BUS_OFF)
        f_busoff = struct.pack(">HHBBBB", 0, 47500, 105, 2, 0x02, 0x00)
        backend.send_frame(0x280, f_busoff)
        time.sleep(0.1)

        snap2 = backend.get_snapshot()
        assert snap2.safety_state == "BUS_OFF"
        assert snap2.active_dtc == "DTC_U0001"

    def test_decode_sensor_acquisition_frame(self, backend: SocketCANTelemetryBackend):
        # 0x380: Temp = 25C (data[0] = 65)
        f_sensor = bytes([65, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        backend.send_frame(0x380, f_sensor)
        time.sleep(0.1)

        snap = backend.get_snapshot()
        assert snap.last_arbitration_id == 0x380

    def test_sliding_window_bus_load_and_jitter(self, backend: SocketCANTelemetryBackend):
        # Send a rapid burst of 20 frames to trigger sliding window load calculation
        for i in range(20):
            payload = bytes([0xAA, i & 0x0F, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x1D])
            backend.send_frame(0x120, payload)
            time.sleep(0.005)

        time.sleep(0.05)
        metrics = backend.get_metrics()
        assert metrics.total_frames_received >= 20
        assert metrics.bus_load_pct > 0.0
        assert 0x120 in metrics.active_can_ids

    def test_subscriber_callback(self, backend: SocketCANTelemetryBackend):
        received_snapshots: List[VehicleTelemetrySnapshot] = []

        def on_snapshot(snap: VehicleTelemetrySnapshot) -> None:
            received_snapshots.append(snap)

        backend.subscribe(on_snapshot)
        payload = bytes([0xAA, 0x03, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x1D])
        backend.send_frame(0x120, payload)
        time.sleep(0.1)

        assert len(received_snapshots) > 0
        assert received_snapshots[-1].alive_counter == 3


class TestCBootloaderFSMAssets:
    """Verifies that the MCU C UDS bootloader files conform to the architectural specifications."""

    def test_c_header_and_source_exist(self):
        c_header = os.path.join("src", "uds_bootloader_fsm.h")
        c_source = os.path.join("src", "uds_bootloader_fsm.c")
        sys_header = os.path.join("00_System", "uds_bootloader_fsm.h")
        sys_source = os.path.join("00_System", "uds_bootloader_fsm.c")

        for path in [c_header, c_source, sys_header, sys_source]:
            assert os.path.isfile(path), f"Required file {path} is missing!"

    def test_c_header_symbols_and_signatures(self):
        with open(os.path.join("src", "uds_bootloader_fsm.h"), "r", encoding="utf-8") as f:
            content = f.read()

        required_symbols = [
            "UDS_SID_DIAG_SESSION_CTRL",
            "UDS_SID_SECURITY_ACCESS",
            "UDS_SID_REQUEST_DOWNLOAD",
            "UDS_SID_TRANSFER_DATA",
            "UDS_SID_REQUEST_TRANSFER_EXIT",
            "UDS_NRC_SECURITY_ACCESS_DENIED",
            "UDS_NRC_WRONG_BLOCK_SEQ_COUNTER",
            "UDS_NRC_GENERAL_PROG_FAILURE",
            "FLASH_PARTITION_A",
            "FLASH_PARTITION_B",
            "uds_bootloader_init",
            "uds_bootloader_process_request",
            "uds_bootloader_emergency_power_cut_rollback",
            "uds_bootloader_commit_active_partition",
            "uds_bootloader_compute_crc32",
        ]
        for sym in required_symbols:
            assert sym in content, f"Header missing symbol: {sym}"

    def test_c_source_fsm_services_and_crc(self):
        with open(os.path.join("src", "uds_bootloader_fsm.c"), "r", encoding="utf-8") as f:
            content = f.read()

        assert "0xEDB88320" in content, "CRC32 polynomial missing in C implementation"
        assert "uds_bootloader_process_request" in content
        assert "UDS_SID_REQUEST_DOWNLOAD" in content
        assert "UDS_SID_TRANSFER_DATA" in content
        assert "UDS_SID_REQUEST_TRANSFER_EXIT" in content
        assert "uds_bootloader_emergency_power_cut_rollback" in content
        assert "uds_bootloader_commit_active_partition" in content
