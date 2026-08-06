from __future__ import annotations

import sys
from pathlib import Path

import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main  # noqa: E402


def test_semantic_threshold_defaults_to_production_calibration(monkeypatch):
    monkeypatch.delenv("SEMANTIC_MIN_SCORE", raising=False)

    assert main._semantic_min_score() == 0.50


def test_semantic_threshold_accepts_an_explicit_valid_value(monkeypatch):
    monkeypatch.setenv("SEMANTIC_MIN_SCORE", "0.57")

    assert main._semantic_min_score() == 0.57


@pytest.mark.parametrize("value", ["", "not-a-number", "nan", "inf", "-0.1", "1.1"])
def test_semantic_threshold_fails_safe_for_invalid_operator_config(monkeypatch, value):
    monkeypatch.setenv("SEMANTIC_MIN_SCORE", value)

    assert main._semantic_min_score() == 0.50
