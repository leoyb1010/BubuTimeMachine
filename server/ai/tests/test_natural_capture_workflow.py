"""Synthetic AI-review boundary regressions: no provider, family, or production calls."""
from datetime import datetime, timezone

from fastapi.testclient import TestClient
import pytest

import main


def request_body():
    return {"text": "测试宝宝今天喝水120ml", "childName": "测试宝宝", "timezone": "UTC",
            "referenceDate": datetime(2026, 10, 2, tzinfo=timezone.utc).isoformat()}


@pytest.fixture
def client(monkeypatch):
    main.app.dependency_overrides[main.require_api_key] = lambda: "synthetic-audit"
    with TestClient(main.app, raise_server_exceptions=False) as value:
        yield value
    main.app.dependency_overrides.pop(main.require_api_key, None)


@pytest.mark.parametrize("output", [
    {"warnings": None, "items": []},
    {"warnings": 42, "items": []},
    {"warnings": "date_inferred", "items": None},
    {"items": 7},
    {"items": {"domain": "water"}},
    {"items": [{"domain": [], "tags": 7}]},
    {"items": [{"domain": {}, "tags": None}]},
    {"items": [{"domain": "water", "tags": 7}]},
])
def test_malformed_model_containers_return_reviewable_response(client, monkeypatch, output):
    monkeypatch.setattr(main.llm, "complete_json", lambda *a, **kw: output)
    response = client.post("/parse-natural-capture", json=request_body())
    assert response.status_code == 200
    payload = response.json()
    assert isinstance(payload["items"], list)
    assert isinstance(payload["warnings"], list)
    assert all(isinstance(w, str) for w in payload["warnings"])
    for item in payload["items"]:
        assert item["source_text"] == request_body()["text"]
        assert isinstance(item["tags"], list)


@pytest.mark.parametrize("confidence", [float("nan"), float("inf"), -float("inf"), -1, 2, "NaN", "Infinity", "1e999", True, False])
def test_invalid_confidence_fails_closed_and_stays_json_serializable(client, monkeypatch, confidence):
    monkeypatch.setattr(main.llm, "complete_json", lambda *a, **kw: {
        "confidence": confidence,
        "items": [{"domain": "water", "title": "喝水", "fields": {"amount_ml": 120},
                   "confidence": confidence, "needs_confirmation": False}],
    })
    response = client.post("/parse-natural-capture", json=request_body())
    assert response.status_code == 200
    payload = response.json()
    assert payload["confidence"] == 0
    assert payload["items"][0]["confidence"] == 0
    assert payload["items"][0]["needs_confirmation"] is True
    assert payload["items"][0]["fields"]["amount_ml"] == 120


def test_invalid_nested_numbers_do_not_break_the_entire_review(client, monkeypatch):
    monkeypatch.setattr(main.llm, "complete_json", lambda *a, **kw: {
        "items": [{"domain": "water", "title": "喝水", "confidence": .95,
                   "needs_confirmation": False, "tags": "not-an-array",
                   "fields": {"amount_ml": float("inf"), "other": [1, float("nan")],
                              "nested": {"bad": -float("inf"), "good": "original"}}}],
    })
    response = client.post("/parse-natural-capture", json=request_body())
    assert response.status_code == 200
    item = response.json()["items"][0]
    assert item["fields"] == {"amount_ml": None, "other": [1, None], "nested": {"bad": None, "good": "original"}}
    assert item["tags"] == []
    assert item["needs_confirmation"] is True
    assert "item_fields_sanitized" in response.json()["warnings"]


def test_valid_multi_record_output_and_false_confirmation_are_preserved(client, monkeypatch):
    monkeypatch.setattr(main.llm, "complete_json", lambda *a, **kw: {
        "confidence": .9, "warnings": ["date_inferred", 12],
        "items": [{"domain": "water", "title": "喝水", "fields": {"amount_ml": 120},
                   "confidence": .9, "needs_confirmation": False, "tags": ["饮水"]},
                  {"domain": "vaccine", "title": "疫苗", "confidence": .99,
                   "needs_confirmation": False}],
    })
    payload = client.post("/parse-natural-capture", json=request_body()).json()
    assert len(payload["items"]) == 2
    assert payload["items"][0]["needs_confirmation"] is False
    assert payload["items"][0]["fields"] == {"amount_ml": 120}
    assert payload["items"][1]["needs_confirmation"] is True
    assert payload["warnings"] == ["date_inferred"]


@pytest.mark.parametrize("number", [10 ** 400, -(10 ** 400)])
def test_integer_outside_native_double_range_requires_repair(client, monkeypatch, number):
    monkeypatch.setattr(main.llm, "complete_json", lambda *a, **kw: {
        "items": [{"domain": "water", "title": "喝水", "confidence": .95,
                   "needs_confirmation": False, "fields": {"amount_ml": number}}],
    })
    payload = client.post("/parse-natural-capture", json=request_body()).json()
    assert payload["items"][0]["fields"]["amount_ml"] is None
    assert payload["items"][0]["needs_confirmation"] is True


def test_finite_representable_numbers_are_not_rewritten_to_invented_ranges(client, monkeypatch):
    monkeypatch.setattr(main.llm, "complete_json", lambda *a, **kw: {
        "items": [{"domain": "water", "title": "喝水", "fields": {"amount_ml": 1e100}}],
    })
    payload = client.post("/parse-natural-capture", json=request_body()).json()
    assert payload["items"][0]["fields"]["amount_ml"] == 1e100
    assert payload["items"][0]["needs_confirmation"] is True


def test_bad_record_does_not_discard_following_valid_record_or_poison_retry(client, monkeypatch):
    outputs = iter([
        {"items": [{"domain": [], "tags": 7}, {"domain": "water", "fields": {"amount_ml": 120}}]},
        {"items": [{"domain": "water", "fields": {"amount_ml": 150}}]},
    ])
    monkeypatch.setattr(main.llm, "complete_json", lambda *a, **kw: next(outputs))
    first = client.post("/parse-natural-capture", json=request_body()).json()
    second = client.post("/parse-natural-capture", json=request_body()).json()
    assert [item["domain"] for item in first["items"]] == ["unknown", "water"]
    assert first["items"][1]["fields"]["amount_ml"] == 120
    assert len(second["items"]) == 1 and second["items"][0]["fields"]["amount_ml"] == 150
    assert "domain_coerced_unknown" not in second["warnings"]
