"""Unit tests for CapCut Bridge Adapter in Third Office."""

from __future__ import annotations

import os
import pytest
from third_office_factory.media_engine.capcut_bridge import CapCutBridgeAdapter


def test_capcut_bridge_package_generation(tmp_path: pytest.TempPathFactory) -> None:
    bridge = CapCutBridgeAdapter(out_dir=str(tmp_path))

    scenes = [
        (5.0, "Welcome to BobFlow powered by IBM Bob 2.0.", "High-tech futuristic title card with blue neon lights."),
        (10.0, "Orchestrator splits technical specs into atomic verified tasks.", "Cyberpunk terminal displaying green automated code tree."),
        (5.0, "Verified with zero hallucinations. Thank you!", "Clean logo reveal with graduation badge."),
    ]

    pkg = bridge.build_project_package("BOBFLOW_CAPCUT_DEMO", "BobFlow Official Pitch", scenes)

    assert pkg.project_id == "BOBFLOW_CAPCUT_DEMO"
    assert len(pkg.scenes) == 3
    assert "https://www.capcut.com" in pkg.workspace_url

    # Verify SRT generation
    srt_file = os.path.join(str(tmp_path), "BOBFLOW_CAPCUT_DEMO.srt")
    assert os.path.exists(srt_file)
    with open(srt_file, "r", encoding="utf-8") as f:
        srt_content = f.read()
    assert "00:00:00,000 --> 00:00:05,000" in srt_content
    assert "Welcome to BobFlow" in srt_content

    # Verify Storyboard JSON
    json_file = os.path.join(str(tmp_path), "BOBFLOW_CAPCUT_DEMO_storyboard.json")
    assert os.path.exists(json_file)
