"""Tests for Third Office Factory."""

from __future__ import annotations

import pytest
from third_office_factory.chaos_tester.verifier import ChaosVerifier, ExamGrade
from third_office_factory.factory import ThirdOfficeFactory
from third_office_factory.media_engine.generator import MediaSynthesisEngine, VideoJobSpec


def test_chaos_verifier_honors_pass() -> None:
    verifier = ChaosVerifier()
    res = verifier.evaluate_curriculum_challenge("EXAM-01", "TestEngine", 1.0)
    assert res.is_graduated is True
    assert res.grade == ExamGrade.HONORS_PASS
    assert res.scenarios_passed == 20
    assert "CERT-PHANTOM" in res.certificate_id


def test_chaos_verifier_partial_pass() -> None:
    verifier = ChaosVerifier()
    res = verifier.evaluate_curriculum_challenge("EXAM-02", "TestEngine", 0.85)
    assert res.is_graduated is True
    assert res.grade == ExamGrade.PASS
    assert res.jitter_resilience_score == 85.0


def test_media_template_generation(tmp_path: pytest.TempPathFactory) -> None:
    engine = MediaSynthesisEngine()
    spec = VideoJobSpec(
        job_id="V1",
        project_title="Test Project",
        tagline="A test tagline",
        script_text="Hello world",
        output_filename="test.mp4",
    )
    target = f"{tmp_path}/test_frame.html"
    engine.render_html_template(spec, target)
    with open(target, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Test Project" in content
    assert "PHANTOM GRID" in content


def test_third_office_factory_graduation() -> None:
    factory = ThirdOfficeFactory()
    res = factory.process_graduation_and_delivery(
        module_name="BobFlow_DFMesh_Unified",
        challenge_title="Autonomous Multi-Agent Curriculum Exam",
        tagline="Autonomous edge orchestration",
        script="Verification completed",
    )
    assert "CERT-PHANTOM" in res["certificate_id"]
    assert res["grade"] == "HONORS_PASS"
