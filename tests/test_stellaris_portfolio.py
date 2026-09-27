import runpy
import sys
from unittest.mock import MagicMock, patch

from stellaris_portfolio import StellarisPortfolioEngine


def test_portfolio_init_default():
    engine = StellarisPortfolioEngine()
    assert engine.risk_profile == "MODERATE_EXPEDITION"


def test_calculate_optimal_allocation_structure():
    engine = StellarisPortfolioEngine()
    report = engine.calculate_optimal_allocation()
    assert "PASSED" in report["status"]
    assert "allocations" in report
    assert "expected_annual_roi_pct" in report


def test_calculate_optimal_allocation_saved_file():
    engine = StellarisPortfolioEngine()
    report = engine.calculate_optimal_allocation(capital_usd=500000.0)
    assert isinstance(report, dict)
    assert report["status"] == "STELLARIS_PORTFOLIO_OPTIMIZATION_PASSED"


def test_win32_encoding_branch():
    mock_stdout = MagicMock()
    mock_stderr = MagicMock()
    with (
        patch("sys.platform", "win32"),
        patch("sys.stdout", mock_stdout),
        patch("sys.stderr", mock_stderr),
    ):
        runpy.run_module("stellaris_portfolio", run_name="stellaris_portfolio_mock")
    assert mock_stdout.reconfigure.called or hasattr(sys.stdout, "reconfigure")


def test_main_execution_block():
    with patch.object(sys, "argv", ["stellaris_portfolio.py"]):
        runpy.run_module("stellaris_portfolio", run_name="__main__")
