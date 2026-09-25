# -*- coding: utf-8 -*-
"""
Universal Measurement and Calibration Protocol (XCP on CAN) Engine
Axis 1: Real-time on-line calibration for automotive ECU without firmware reflashing.
Commands:
- CONNECT (0xFF)
- DISCONNECT (0xFE)
- GET_STATUS (0xFD)
- SET_MTA (0xF6) - Set Memory Transfer Address
- UPLOAD (0xF5) - Read RAM calibration parameters
- SHORT_UPLOAD (0xF4)
- DOWNLOAD (0xF0) - Write RAM calibration parameters
- SHORT_DOWNLOAD (0xED)
"""

from __future__ import annotations

import enum
import struct
from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Tuple


class XcpCommand(enum.Enum):
    CONNECT = 0xFF
    DISCONNECT = 0xFE
    GET_STATUS = 0xFD
    SET_MTA = 0xF6
    UPLOAD = 0xF5
    SHORT_UPLOAD = 0xF4
    DOWNLOAD = 0xF0
    SHORT_DOWNLOAD = 0xED


class XcpErrorCode(enum.Enum):
    SUCCESS = 0x00
    ERR_CMD_SYNTAX = 0x20
    ERR_OUT_OF_RANGE = 0x22
    ERR_ACCESS_DENIED = 0x24
    ERR_ACCESS_LOCKED = 0x25
    ERR_PAGE_NOT_VALID = 0x26


@dataclass
class CalibrationMemoryMap:
    """RAM Address Map for Live Calibration."""
    pwm_freq_hz: int = 20000              # 0x1000 (uint32)
    pid_kp: float = 1.25                  # 0x1004 (float32)
    pid_ki: float = 0.05                  # 0x1008 (float32)
    pid_kd: float = 0.01                  # 0x100C (float32)
    degraded_power_limit_pct: float = 50.0 # 0x1010 (float32)
    fast_restart_interval_ms: int = 100   # 0x1014 (uint32)


class XcpCalibrationEngine:
    """
    XCP on CAN Protocol Slave Handler.
    Allows real-time telemetry observation and calibration parameter tuning over CAN.
    """

    def __init__(self, initial_map: Optional[CalibrationMemoryMap] = None) -> None:
        self.is_connected = False
        self.current_mta = 0x00000000
        self.cal_map = initial_map or CalibrationMemoryMap()
        self.audit_trace: list[str] = []

    # =========================================================================
    # Address Resolution Helpers
    # =========================================================================

    def _read_memory(self, addr: int, length: int) -> Tuple[bool, bytes]:
        if addr == 0x1000 and length == 4:
            return True, struct.pack("<I", self.cal_map.pwm_freq_hz)
        elif addr == 0x1004 and length == 4:
            return True, struct.pack("<f", self.cal_map.pid_kp)
        elif addr == 0x1008 and length == 4:
            return True, struct.pack("<f", self.cal_map.pid_ki)
        elif addr == 0x100C and length == 4:
            return True, struct.pack("<f", self.cal_map.pid_kd)
        elif addr == 0x1010 and length == 4:
            return True, struct.pack("<f", self.cal_map.degraded_power_limit_pct)
        elif addr == 0x1014 and length == 4:
            return True, struct.pack("<I", self.cal_map.fast_restart_interval_ms)
        return False, b""

    def _write_memory(self, addr: int, data: bytes) -> bool:
        if addr == 0x1000 and len(data) == 4:
            self.cal_map.pwm_freq_hz = struct.unpack("<I", data)[0]
            self.audit_trace.append(f"XCP 標定覆寫: pwm_freq_hz = {self.cal_map.pwm_freq_hz} Hz")
            return True
        elif addr == 0x1004 and len(data) == 4:
            self.cal_map.pid_kp = round(struct.unpack("<f", data)[0], 4)
            self.audit_trace.append(f"XCP 標定覆寫: pid_kp = {self.cal_map.pid_kp}")
            return True
        elif addr == 0x1008 and len(data) == 4:
            self.cal_map.pid_ki = round(struct.unpack("<f", data)[0], 4)
            self.audit_trace.append(f"XCP 標定覆寫: pid_ki = {self.cal_map.pid_ki}")
            return True
        elif addr == 0x100C and len(data) == 4:
            self.cal_map.pid_kd = round(struct.unpack("<f", data)[0], 4)
            self.audit_trace.append(f"XCP 標定覆寫: pid_kd = {self.cal_map.pid_kd}")
            return True
        elif addr == 0x1010 and len(data) == 4:
            self.cal_map.degraded_power_limit_pct = round(struct.unpack("<f", data)[0], 2)
            self.audit_trace.append(
                f"XCP 標定覆寫: degraded_power_limit_pct = {self.cal_map.degraded_power_limit_pct}%"
            )
            return True
        elif addr == 0x1014 and len(data) == 4:
            self.cal_map.fast_restart_interval_ms = struct.unpack("<I", data)[0]
            self.audit_trace.append(
                f"XCP 標定覆寫: fast_restart_interval_ms = {self.cal_map.fast_restart_interval_ms} ms"
            )
            return True
        return False

    # =========================================================================
    # XCP Core Command Handlers
    # =========================================================================

    def execute_connect(self) -> Dict[str, Any]:
        """XCP CONNECT (0xFF)."""
        self.is_connected = True
        return {
            "status": "CONNECTED",
            "resource": 0x1F,  # CAL/PAG/DAQ/STIM/PGM supported
            "comm_mode": 0x01, # Byte order: Intel (Little-Endian)
            "max_cto": 8,
            "max_dto": 8,
        }

    def execute_disconnect(self) -> Dict[str, Any]:
        """XCP DISCONNECT (0xFE)."""
        self.is_connected = False
        return {"status": "DISCONNECTED"}

    def set_mta(self, address: int) -> bool:
        """XCP SET_MTA (0xF6)."""
        if not self.is_connected:
            return False
        self.current_mta = address
        return True

    def upload(self, length: int) -> Tuple[bool, bytes]:
        """XCP UPLOAD (0xF5) from current MTA."""
        if not self.is_connected:
            return False, b""
        ok, data = self._read_memory(self.current_mta, length)
        if ok:
            self.current_mta += length
        return ok, data

    def download(self, data: bytes) -> bool:
        """XCP DOWNLOAD (0xF0) to current MTA."""
        if not self.is_connected:
            return False
        ok = self._write_memory(self.current_mta, data)
        if ok:
            self.current_mta += len(data)
        return ok

    def short_download(self, address: int, data: bytes) -> bool:
        """XCP SHORT_DOWNLOAD (0xED). Direct address write."""
        if not self.is_connected:
            return False
        return self._write_memory(address, data)

    def short_upload(self, address: int, length: int) -> Tuple[bool, bytes]:
        """XCP SHORT_UPLOAD (0xF4). Direct address read."""
        if not self.is_connected:
            return False, b""
        return self._read_memory(address, length)
