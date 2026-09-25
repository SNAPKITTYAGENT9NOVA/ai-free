from pathlib import Path


def test_environment_sanity():
    """Verify test pipeline and execution environment."""
    assert True


def test_project_modules():
    """Verify core directories exist."""
    root = Path(__file__).resolve().parent.parent
    assert (root / "ai").exists() or (root / "src" / "ai").exists()
    assert (root / "bridge").exists() or (root / "src").exists()
