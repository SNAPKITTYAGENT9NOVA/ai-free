# -*- coding: utf-8 -*-
"""
Tests for Axis 1: UDS Bootloader Pipeline & XCP on CAN Calibration Engine.
"""

from __future__ import annotations

import hashlib
import struct
import zlib

from uds_bootloader_pipeline import PartitionSlot, UdsBootloaderPipeline, UdsSession
from xcp_calibration import XcpCalibrationEngine


def test_uds_session_control_and_security_access() -> None:
    bl = UdsBootloaderPipeline()
    assert bl.session == UdsSession.DEFAULT
    assert bl.active_partition.slot == PartitionSlot.SLOT_A

    # 1. Switch to programming session
    ok, code, msg = bl.service_10_session_control(0x02)
    assert ok is True
    assert code == 0x50
    assert bl.session == UdsSession.PROGRAMMING

    # 2. Request Seed
    ok, code, seed = bl.service_27_security_access_request_seed()
    assert ok is True
    assert code == 0x67
    assert seed != 0

    # 3. Invalid key fails
    ok_bad, code_bad, _ = bl.service_27_security_access_send_key(seed ^ 0x12345678)
    assert ok_bad is False
    assert bl.security_unlocked is False

    # 4. Correct key unlocks
    ok, code, seed = bl.service_27_security_access_request_seed()
    correct_key = seed ^ UdsBootloaderPipeline.SECRET_KEY_SEED_XOR
    ok_good, code_good, _ = bl.service_27_security_access_send_key(correct_key)
    assert ok_good is True
    assert bl.security_unlocked is True


def test_uds_full_flashing_and_ab_partition_commit() -> None:
    bl = UdsBootloaderPipeline()
    bl.service_10_session_control(0x02)
    _, _, seed = bl.service_27_security_access_request_seed()
    bl.service_27_security_access_send_key(seed ^ UdsBootloaderPipeline.SECRET_KEY_SEED_XOR)

    # 1. Erase candidate partition (SLOT_B)
    ok_erase, _, _ = bl.service_31_erase_memory(0x02)
    assert ok_erase is True
    assert bl.standby_partition.slot == PartitionSlot.SLOT_B

    # 2. Prepare mock firmware payload (256 bytes)
    firmware_binary = bytes([(i % 256) for i in range(256)])
    fw_crc32 = zlib.crc32(firmware_binary) & 0xFFFFFFFF
    fw_sha256 = hashlib.sha256(firmware_binary).hexdigest()

    # 3. Request Download ($34)
    ok_req, code_req, max_blk = bl.service_34_request_download(
        memory_address=0x08008000,
        uncompressed_size=len(firmware_binary),
    )
    assert ok_req is True
    assert code_req == 0x74
    assert max_blk == 128

    # 4. Transfer Data ($36) in 2 blocks (128 bytes each)
    block1 = firmware_binary[:128]
    block2 = firmware_binary[128:]

    ok_t1, code_t1, _ = bl.service_36_transfer_data(block_sequence_counter=1, chunk_data=block1)
    assert ok_t1 is True
    assert code_t1 == 0x76

    ok_t2, code_t2, _ = bl.service_36_transfer_data(block_sequence_counter=2, chunk_data=block2)
    assert ok_t2 is True
    assert code_t2 == 0x76

    # 5. Request Transfer Exit ($37) with CRC32 & SHA-256 dual verification
    ok_exit, code_exit, msg = bl.service_37_request_transfer_exit(
        expected_crc32=fw_crc32,
        expected_sha256=fw_sha256,
        new_version="2.0.0",
    )
    assert ok_exit is True
    assert code_exit == 0x77

    # 6. Verify atomic partition switch to SLOT_B
    assert bl.active_partition.slot == PartitionSlot.SLOT_B
    assert bl.active_partition.version == "2.0.0"
    assert bl.active_partition.crc32 == fw_crc32
    assert bl.standby_partition.slot == PartitionSlot.SLOT_A
    assert bl.standby_partition.version == "1.0.0"  # Old version preserved for rollback


def test_uds_brownout_emergency_rollback() -> None:
    bl = UdsBootloaderPipeline()
    bl.service_10_session_control(0x02)
    _, _, seed = bl.service_27_security_access_request_seed()
    bl.service_27_security_access_send_key(seed ^ UdsBootloaderPipeline.SECRET_KEY_SEED_XOR)
    bl.service_34_request_download(0x08008000, 256)
    bl.service_36_transfer_data(1, b"partial_corrupt_data_chunk")

    # Simulate mid-flash brownout / power drop
    ok, msg = bl.trigger_emergency_power_cut_rollback()
    assert ok is True
    assert "0 變磚" in msg
    assert bl.active_partition.slot == PartitionSlot.SLOT_A
    assert bl.active_partition.version == "1.0.0"
    assert not bl.download_active


def test_xcp_calibration_protocol_engine() -> None:
    engine = XcpCalibrationEngine()
    assert not engine.is_connected

    # 1. Connect
    conn_info = engine.execute_connect()
    assert conn_info["status"] == "CONNECTED"
    assert engine.is_connected is True

    # 2. Read initial parameters via SET_MTA + UPLOAD
    assert engine.set_mta(0x1000) is True
    ok, data = engine.upload(4)
    assert ok is True
    pwm_freq = struct.unpack("<I", data)[0]
    assert pwm_freq == 20000

    # 3. Write new parameter via SET_MTA + DOWNLOAD (e.g. pwm_freq_hz -> 24000 Hz)
    assert engine.set_mta(0x1000) is True
    ok_down = engine.download(struct.pack("<I", 24000))
    assert ok_down is True
    assert engine.cal_map.pwm_freq_hz == 24000

    # 4. Calibrate PID Kp and Degraded Power Limit via SHORT_DOWNLOAD
    new_kp = 2.45
    assert engine.short_download(0x1004, struct.pack("<f", new_kp)) is True
    assert engine.cal_map.pid_kp == 2.45

    new_limit = 45.0
    assert engine.short_download(0x1010, struct.pack("<f", new_limit)) is True
    assert engine.cal_map.degraded_power_limit_pct == 45.0

    # 5. Read back via SHORT_UPLOAD
    ok_up, kp_bytes = engine.short_upload(0x1004, 4)
    assert ok_up is True
    read_kp = round(struct.unpack("<f", kp_bytes)[0], 2)
    assert read_kp == 2.45

    # 6. Disconnect
    disc_info = engine.execute_disconnect()
    assert disc_info["status"] == "DISCONNECTED"
    assert engine.is_connected is False
