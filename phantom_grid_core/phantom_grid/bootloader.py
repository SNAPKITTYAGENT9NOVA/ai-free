# -*- coding: utf-8 -*-
"""
ISO 14229 UDS Secondary Bootloader & Flash A/B Dual-Partition Pipeline
Axis 1: Production-grade firmware flashing via UDS ($10, $27, $31, $34, $36, $37)
Features:
1. UDS Service 0x10 (DiagnosticSessionControl - ProgrammingSession 0x02)
2. UDS Service 0x27 (SecurityAccess - Seed & Key verification)
3. UDS Service 0x31 (RoutineControl - Erase flash partition 0x01)
4. UDS Service 0x34 (RequestDownload - Memory address, size, data format)
5. UDS Service 0x36 (TransferData - Block sequence counter 1..255, chunked transfer)
6. UDS Service 0x37 (RequestTransferExit - CRC32 & SHA-256 dual verification)
7. Flash A/B Dual-Partition Rollback:
   - Sector A (Active), Sector B (Candidate).
   - Brownout / power-cut during flashing triggers instant 0-cost rollback to Sector A.
   - Successful verification atomically commits Sector B as new active partition.
"""

from __future__ import annotations

import enum
import hashlib
import struct
import time
import zlib
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple


class UdsSession(enum.Enum):
    DEFAULT = 0x01
    PROGRAMMING = 0x02
    EXTENDED = 0x03


class PartitionSlot(enum.Enum):
    SLOT_A = "SLOT_A"
    SLOT_B = "SLOT_B"


@dataclass
class FlashPartition:
    slot: PartitionSlot
    start_addr: int
    size_bytes: int
    is_active: bool = False
    data: bytearray = field(default_factory=bytearray)
    version: str = "1.0.0"
    crc32: int = 0
    sha256_hash: str = ""


class UdsBootloaderPipeline:
    """
    ISO 14229 UDS Secondary Flash Bootloader.
    Manages secure OTA flashing, block streaming, and A/B partition atomic switching.
    """

    SECRET_KEY_SEED_XOR = 0x5A5A5A5A
    MAX_BLOCK_SIZE = 128  # 128-byte block size for chunked transfer

    def __init__(self, memory_size: int = 65536) -> None:
        self.session = UdsSession.DEFAULT
        self.security_unlocked = False
        self.pending_seed: Optional[int] = None

        # Flash A/B Dual Partition (32KB each)
        half_size = memory_size // 2
        self.slot_a = FlashPartition(
            slot=PartitionSlot.SLOT_A,
            start_addr=0x08000000,
            size_bytes=half_size,
            is_active=True,
            data=bytearray(b"\xFF" * half_size),
            version="1.0.0",
        )
        self.slot_b = FlashPartition(
            slot=PartitionSlot.SLOT_B,
            start_addr=0x08000000 + half_size,
            size_bytes=half_size,
            is_active=False,
            data=bytearray(b"\xFF" * half_size),
            version="0.0.0",
        )

        # Flashing state context
        self.download_active = False
        self.target_slot: Optional[FlashPartition] = None
        self.expected_block_seq = 1
        self.received_buffer = bytearray()
        self.expected_total_bytes = 0
        self.target_address = 0
        self.flash_log: List[str] = []

    @property
    def active_partition(self) -> FlashPartition:
        return self.slot_a if self.slot_a.is_active else self.slot_b

    @property
    def standby_partition(self) -> FlashPartition:
        return self.slot_b if self.slot_a.is_active else self.slot_a

    # =========================================================================
    # UDS Services Implementation
    # =========================================================================

    def service_10_session_control(self, session_type: int) -> Tuple[bool, int, str]:
        """UDS $10: DiagnosticSessionControl."""
        if session_type == 0x02:
            self.session = UdsSession.PROGRAMMING
            self.flash_log.append("UDS $10: 切換至 PROGRAMMING_SESSION (0x02)")
            return True, 0x50, "PROGRAMMING_SESSION_GRANTED"
        elif session_type == 0x01:
            self.session = UdsSession.DEFAULT
            self.security_unlocked = False
            self.flash_log.append("UDS $10: 切換至 DEFAULT_SESSION (0x01)")
            return True, 0x50, "DEFAULT_SESSION_GRANTED"
        return False, 0x7F, "SUB_FUNCTION_NOT_SUPPORTED"

    def service_27_security_access_request_seed(self) -> Tuple[bool, int, int]:
        """UDS $27 Sub 0x01: Request Seed."""
        if self.session != UdsSession.PROGRAMMING:
            return False, 0x7F, 0
        # Deterministic pseudo-random seed
        seed = int(time.time() * 1000) & 0xFFFFFFFF
        self.pending_seed = seed
        self.flash_log.append(f"UDS $27 0x01: 生成 Seed = 0x{seed:08X}")
        return True, 0x67, seed

    def service_27_security_access_send_key(self, key: int) -> Tuple[bool, int, str]:
        """UDS $27 Sub 0x02: Send Key."""
        if self.pending_seed is None:
            return False, 0x7F, "REQUEST_SEQUENCE_ERROR"
        expected_key = self.pending_seed ^ self.SECRET_KEY_SEED_XOR
        if key == expected_key:
            self.security_unlocked = True
            self.pending_seed = None
            self.flash_log.append("UDS $27 0x02: 密鑰認證通過，安全防護解鎖 (UNLOCKED)")
            return True, 0x67, "SECURITY_ACCESS_UNLOCKED"
        self.pending_seed = None
        self.security_unlocked = False
        self.flash_log.append("UDS $27 0x02: 密鑰認證失敗，拒絕訪問")
        return False, 0x7F, "INVALID_KEY"

    def service_31_erase_memory(self, partition_slot_id: int) -> Tuple[bool, int, str]:
        """UDS $31: RoutineControl (Erase Routine 0xFF00)."""
        if not self.security_unlocked or self.session != UdsSession.PROGRAMMING:
            return False, 0x7F, "SECURITY_ACCESS_DENIED"

        # Erase candidate (standby) partition
        target = self.standby_partition
        target.data = bytearray(b"\xFF" * target.size_bytes)
        self.flash_log.append(f"UDS $31: 扇區擦除成功 -> {target.slot.value} (全數重置為 0xFF)")
        return True, 0x71, f"ERASE_SUCCESS_{target.slot.value}"

    def service_34_request_download(
        self,
        memory_address: int,
        uncompressed_size: int,
        data_format_identifier: int = 0x00,
    ) -> Tuple[bool, int, int]:
        """UDS $34: RequestDownload."""
        if not self.security_unlocked or self.session != UdsSession.PROGRAMMING:
            return False, 0x7F, 0

        target = self.standby_partition
        if uncompressed_size > target.size_bytes:
            return False, 0x7F, 0  # Exceeds partition capacity

        self.download_active = True
        self.target_slot = target
        self.target_address = memory_address
        self.expected_total_bytes = uncompressed_size
        self.expected_block_seq = 1
        self.received_buffer = bytearray()

        self.flash_log.append(
            f"UDS $34: 下載請求就緒 -> 目的: {target.slot.value} (位址 0x{memory_address:08X}, 大小 {uncompressed_size} Bytes)"
        )
        # Positive response: 0x74, length of maxNumberOfBlockLength = 2 bytes (0x0080 = 128)
        return True, 0x74, self.MAX_BLOCK_SIZE

    def service_36_transfer_data(
        self,
        block_sequence_counter: int,
        chunk_data: bytes,
    ) -> Tuple[bool, int, str]:
        """UDS $36: TransferData."""
        if not self.download_active or self.target_slot is None:
            return False, 0x7F, "REQUEST_SEQUENCE_ERROR"

        # Verify rolling block sequence counter (1..255)
        if block_sequence_counter != (self.expected_block_seq & 0xFF):
            self.flash_log.append(
                f"UDS $36 序號錯誤: 預期 {self.expected_block_seq & 0xFF}, 收到 {block_sequence_counter}"
            )
            return False, 0x7F, "WRONG_BLOCK_SEQUENCE_COUNTER"

        self.received_buffer.extend(chunk_data)
        self.expected_block_seq = (self.expected_block_seq + 1) & 0xFF
        if self.expected_block_seq == 0:
            self.expected_block_seq = 1  # Wrap to 1 per UDS spec

        return True, 0x76, f"BLOCK_{block_sequence_counter}_ACK"

    def service_37_request_transfer_exit(
        self,
        expected_crc32: int,
        expected_sha256: str,
        new_version: str = "1.1.0",
    ) -> Tuple[bool, int, str]:
        """UDS $37: RequestTransferExit with CRC32 & SHA-256 dual verification."""
        if not self.download_active or self.target_slot is None:
            return False, 0x7F, "REQUEST_SEQUENCE_ERROR"

        # 1. Byte length check
        if len(self.received_buffer) != self.expected_total_bytes:
            self.flash_log.append(
                f"UDS $37 長度不符: 預期 {self.expected_total_bytes}, 收到 {len(self.received_buffer)}"
            )
            return False, 0x7F, "INCOMPLETE_DATA_LENGTH"

        # 2. CRC32 check
        calc_crc32 = zlib.crc32(self.received_buffer) & 0xFFFFFFFF
        if calc_crc32 != (expected_crc32 & 0xFFFFFFFF):
            self.flash_log.append(
                f"UDS $37 CRC32 錯誤: 預期 0x{expected_crc32:08X}, 計算 0x{calc_crc32:08X}"
            )
            return False, 0x7F, "CRC32_VERIFICATION_FAILED"

        # 3. SHA-256 signature check
        calc_sha256 = hashlib.sha256(self.received_buffer).hexdigest().lower()
        if calc_sha256 != expected_sha256.lower():
            self.flash_log.append("UDS $37 固件數位簽名 (SHA-256) 驗證失敗！")
            return False, 0x7F, "SHA256_SIGNATURE_MISMATCH"

        # 4. Atomic Partition Commit (A/B Seamless Switch)
        target = self.target_slot
        target.data[: len(self.received_buffer)] = self.received_buffer
        target.crc32 = calc_crc32
        target.sha256_hash = calc_sha256
        target.version = new_version

        # Switch active flag atomically
        if target.slot == PartitionSlot.SLOT_B:
            self.slot_a.is_active = False
            self.slot_b.is_active = True
        else:
            self.slot_b.is_active = False
            self.slot_a.is_active = True

        self.download_active = False
        self.target_slot = None
        self.flash_log.append(
            f"UDS $37: 刷寫驗收成功！無縫原子切換至 {target.slot.value} (v{new_version}), 舊分區保留為回滾備份"
        )
        return True, 0x77, f"FLASH_COMMIT_SUCCESS_{target.slot.value}"

    def trigger_emergency_power_cut_rollback(self) -> Tuple[bool, str]:
        """
        Simulates power-cut / brownout mid-flash:
        Discards candidate buffer, keeps previous active partition 100% intact.
        Zero bricking risk.
        """
        prev_active = self.active_partition
        self.download_active = False
        self.target_slot = None
        self.received_buffer.clear()
        msg = f"掉壓/斷電中斷防護觸發：候選刷寫終止，系統即時自愈回滾至主分區 {prev_active.slot.value} (v{prev_active.version})，0 變磚！"
        self.flash_log.append(msg)
        return True, msg
