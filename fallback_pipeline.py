"""Fallback Pipeline — 動態降級與路由備援模組.

主路徑異常處理：主代理連續 2 次未響應 → 切斷 → 自動切換本機輕量模型/備用規則引擎
降級安全輸出：僅輸出防護型核心數據，背景生成異常診斷日誌，管線不卡死
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine

logger = logging.getLogger(__name__)

# ── 常數 ─────────────────────────────────────────────
MAX_CONSECUTIVE_FAILURES: int = 2   # 連續失敗次數門檻
FALLBACK_TIMEOUT_S: float = 5.0     # 主路徑逾時門檻


class PipelineMode(Enum):
    """管線運行模式."""

    PRIMARY = "PRIMARY"             # 主路徑正常
    DEGRADED = "DEGRADED"           # 降級：備援引擎接管
    RECOVERING = "RECOVERING"       # 恢復中：嘗試切回主路徑


@dataclass
class DiagnosticEntry:
    """異常診斷日誌條目."""

    timestamp: float
    service_id: str
    error_type: str
    detail: str
    mode_at_failure: PipelineMode

    def to_dict(self) -> dict[str, Any]:
        """轉換為字典."""
        return {
            "timestamp": self.timestamp,
            "service_id": self.service_id,
            "error_type": self.error_type,
            "detail": self.detail,
            "mode": self.mode_at_failure.value,
        }


@dataclass
class SafeOutput:
    """降級安全輸出：僅包含防護型核心數據."""

    is_degraded: bool
    source: str                    # "primary" | "fallback" | "rule_engine"
    core_data: dict[str, Any]      # 防護型核心數據
    diagnostics_pending: int = 0   # 背景待處理的診斷日誌數


# 服務呼叫型別
ServiceCall = Callable[..., Coroutine[Any, Any, dict[str, Any]]]


class FallbackPipeline:
    """動態降級與路由備援管線.

    Example
    -------
    >>> pipe = FallbackPipeline(
    ...     primary=cloud_api_call,
    ...     fallback=local_model_call,
    ... )
    >>> result = await pipe.execute(prompt="status check")
    >>> result.source  # "primary" or "fallback"
    """

    def __init__(
        self,
        primary: ServiceCall,
        fallback: ServiceCall,
        *,
        max_failures: int = MAX_CONSECUTIVE_FAILURES,
        timeout: float = FALLBACK_TIMEOUT_S,
        on_degraded: Callable[[], None] | None = None,
        on_recovered: Callable[[], None] | None = None,
    ) -> None:
        self._primary = primary
        self._fallback = fallback
        self._max_failures = max_failures
        self._timeout = timeout
        self._on_degraded = on_degraded
        self._on_recovered = on_recovered

        self._mode = PipelineMode.PRIMARY
        self._consecutive_failures: int = 0
        self._diagnostics: list[DiagnosticEntry] = []

    # ── 狀態查詢 ─────────────────────────────────────

    @property
    def mode(self) -> PipelineMode:
        """目前管線模式."""
        return self._mode

    @property
    def consecutive_failures(self) -> int:
        """連續失敗次數."""
        return self._consecutive_failures

    @property
    def diagnostics(self) -> list[DiagnosticEntry]:
        """異常診斷日誌."""
        return list(self._diagnostics)

    # ── 診斷日誌 ─────────────────────────────────────

    def _log_diagnostic(
        self,
        service_id: str,
        error_type: str,
        detail: str,
    ) -> None:
        """背景生成異常診斷日誌."""
        entry = DiagnosticEntry(
            timestamp=time.time(),
            service_id=service_id,
            error_type=error_type,
            detail=detail,
            mode_at_failure=self._mode,
        )
        self._diagnostics.append(entry)
        logger.warning(
            "FallbackPipeline 診斷: [%s] %s — %s",
            error_type,
            service_id,
            detail,
        )

    # ── 主執行邏輯 ───────────────────────────────────

    async def execute(self, **kwargs: Any) -> SafeOutput:
        """執行管線：主路徑優先，失敗自動降級.

        Parameters
        ----------
        **kwargs
            傳遞給 primary / fallback 服務的參數。

        Returns
        -------
        SafeOutput
            包含來源標記與核心數據的安全輸出。
        """
        # ── 主路徑模式 ───────────────────────────────
        if self._mode == PipelineMode.PRIMARY:
            return await self._try_primary(**kwargs)

        # ── 降級模式：直接走備援 ─────────────────────
        return await self._run_fallback(**kwargs)

    async def _try_primary(self, **kwargs: Any) -> SafeOutput:
        """嘗試主路徑呼叫."""
        try:
            result = await asyncio.wait_for(
                self._primary(**kwargs),
                timeout=self._timeout,
            )
            # ✅ 成功：重置計數器
            self._consecutive_failures = 0
            if self._mode == PipelineMode.RECOVERING:
                self._mode = PipelineMode.PRIMARY
                logger.info("FallbackPipeline: 主路徑恢復正常")
                if self._on_recovered:
                    self._on_recovered()

            return SafeOutput(
                is_degraded=False,
                source="primary",
                core_data=result,
                diagnostics_pending=len(self._diagnostics),
            )

        except (asyncio.TimeoutError, Exception) as exc:
            self._consecutive_failures += 1
            error_type = (
                "TIMEOUT" if isinstance(exc, asyncio.TimeoutError)
                else type(exc).__name__
            )
            self._log_diagnostic(
                "primary",
                error_type,
                f"連續第 {self._consecutive_failures} 次失敗: {exc!s}",
            )

            # 達到門檻 → 切斷主路徑，降級
            if self._consecutive_failures >= self._max_failures:
                self._mode = PipelineMode.DEGRADED
                logger.error(
                    "FallbackPipeline: 主路徑連續 %d 次失敗，"
                    "切斷連線，降級至備援引擎",
                    self._consecutive_failures,
                )
                if self._on_degraded:
                    self._on_degraded()
                return await self._run_fallback(**kwargs)

            # 未達門檻 → 再嘗試一次主路徑
            return await self._try_primary(**kwargs)

    async def _run_fallback(self, **kwargs: Any) -> SafeOutput:
        """執行備援引擎（本機輕量模型/規則引擎）."""
        try:
            result = await self._fallback(**kwargs)
            return SafeOutput(
                is_degraded=True,
                source="fallback",
                core_data=result,
                diagnostics_pending=len(self._diagnostics),
            )
        except Exception as exc:
            # 備援也失敗 → 輸出最小防護型核心數據
            self._log_diagnostic(
                "fallback",
                type(exc).__name__,
                f"備援引擎也失敗: {exc!s}",
            )
            return SafeOutput(
                is_degraded=True,
                source="rule_engine",
                core_data={"status": "SAFE_MODE", "message": "管線降級防護中"},
                diagnostics_pending=len(self._diagnostics),
            )

    # ── 手動恢復 ─────────────────────────────────────

    async def try_recover(self, **kwargs: Any) -> SafeOutput:
        """手動嘗試恢復主路徑."""
        self._mode = PipelineMode.RECOVERING
        self._consecutive_failures = 0
        logger.info("FallbackPipeline: 嘗試恢復主路徑...")
        return await self._try_primary(**kwargs)

    def force_degraded(self) -> None:
        """強制降級（供外部觸發）."""
        self._mode = PipelineMode.DEGRADED
        logger.warning("FallbackPipeline: 外部強制降級")

    def reset(self) -> None:
        """完全重置管線狀態."""
        self._mode = PipelineMode.PRIMARY
        self._consecutive_failures = 0
        self._diagnostics.clear()
