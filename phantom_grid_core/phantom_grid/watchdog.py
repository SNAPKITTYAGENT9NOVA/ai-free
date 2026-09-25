# -*- coding: utf-8 -*-
"""
PHANTOM GRID Core - Safety Watchdog
安全狀態機與微觀降級機制 (SafetyWatchdog)
即時監控節點心跳與硬體/律法異常，
當遭遇因果悖論或硬體暴衝時在毫秒級切入 Fail-Silent / Fail-Operational / SAFE_STATE_FAIL_SILENT 安全狀態，
鎖定底層硬體防止暴衝。
"""

from __future__ import annotations

import enum
import threading
import time
from typing import Dict, Optional, Tuple


class SafetyWatchdogState(enum.Enum):
    NORMAL = "NORMAL"                                     # 正常運作
    FAIL_OPERATIONAL = "FAIL_OPERATIONAL"                 # 故障維持 (降額至 50% 或開環維持)
    FAIL_SILENT = "FAIL_SILENT"                           # 故障靜默 (立即切斷 PWM / 0% 輸出)
    SAFE_STATE_FAIL_SILENT = "SAFE_STATE_FAIL_SILENT"     # 靜默安全模式 (鎖定硬體防止暴衝)


class SafetyWatchdog:
    """
    安全狀態機與微觀降級機制：
    即時監控節點心跳與硬體/律法異常，
    當遭遇因果悖論或硬體暴衝時在毫秒級切入 SAFE_STATE_FAIL_SILENT 安全狀態。
    """

    def __init__(self, heartbeat_timeout_sec: float = 0.050):
        self.heartbeat_timeout = heartbeat_timeout_sec
        self.state = SafetyWatchdogState.NORMAL
        self._last_heartbeats: Dict[str, float] = {}
        self._lock = threading.RLock()
        self.pwm_duty_pct = 100.0
        self.power_limit_pct = 100.0

    def feed_heartbeat(self, node_id: str, timestamp: Optional[float] = None) -> None:
        """餵狗：記錄節點心跳"""
        with self._lock:
            ts = timestamp or time.time()
            self._last_heartbeats[node_id] = ts

    def inspect(self, now: Optional[float] = None) -> Tuple[SafetyWatchdogState, str]:
        """巡檢心跳是否超時"""
        with self._lock:
            t = now or time.time()
            for node_id, last_ts in self._last_heartbeats.items():
                if (t - last_ts) > self.heartbeat_timeout:
                    # 超時觸發降級
                    return self.trigger_transition(
                        target_state=SafetyWatchdogState.FAIL_OPERATIONAL,
                        reason=f"節點心跳超時: {node_id} (間隔: {(t - last_ts)*1000:.1f}ms > {self.heartbeat_timeout*1000:.1f}ms)",
                    )
            return self.state, "ALL_NODES_HEALTHY"

    def trigger_transition(
        self,
        target_state: SafetyWatchdogState,
        reason: str,
    ) -> Tuple[SafetyWatchdogState, str]:
        """執行毫秒級狀態機跳轉"""
        with self._lock:
            self.state = target_state

            if target_state in (SafetyWatchdogState.FAIL_SILENT, SafetyWatchdogState.SAFE_STATE_FAIL_SILENT):
                # 0ms 斷開 PWM，徹底防止硬體暴衝
                self.pwm_duty_pct = 0.0
                self.power_limit_pct = 0.0
                action = f"緊急觸發 SAFE_STATE_FAIL_SILENT: PWM 0ms 立即切斷 (0% Duty) | 原因: {reason}"
            elif target_state == SafetyWatchdogState.FAIL_OPERATIONAL:
                # 降額至 50% 或開環保底
                self.power_limit_pct = 50.0
                self.pwm_duty_pct = 50.0
                action = f"安全降級 FAIL_OPERATIONAL: 功率限制壓制在 50% | 原因: {reason}"
            else:
                self.pwm_duty_pct = 100.0
                self.power_limit_pct = 100.0
                action = f"恢復正常 NORMAL: 100% 全功率 | 原因: {reason}"

            return self.state, action
