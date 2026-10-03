from __future__ import annotations

import base64
import hashlib
import io
import json
import sys
from pathlib import Path

import httpx
import pytest
from PIL import Image
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main
from llm import LLMClient, LLMError
from school_report import SchoolReportError, SchoolReportReq, prepare_image, parse_report


def image_data(fmt="JPEG"):
    out = io.BytesIO()
    image = Image.new("RGB", (40, 60), "white")
    exif = Image.Exif()
    exif[270] = "private metadata"
    image.save(out, format=fmt, exif=exif)
    return base64.b64encode(out.getvalue()).decode()


def payload(**changes):
    return dict(image_base64=image_data(), content_type="image/jpeg", reference_date="2026-09-26", **changes)


def report(**changes):
    return dict(is_school_report=True, date="2026-09-24", fields={"上午点心": "90%；食量佳；速度普通", "午睡时间": "12:17–14:30"}, uncertain_fields=[], **changes)


def test_decode_strips_exif_and_reencodes_valid_image():
    encoded = prepare_image(SchoolReportReq(**payload()))
    raw = base64.b64decode(encoded)
    with Image.open(io.BytesIO(raw)) as image:
        assert image.format == "JPEG"
        assert image.size == (40, 60)
        assert not image.getexif()


@pytest.mark.parametrize("raw,mime", [("https://localhost", "image/jpeg"), ("不是图片", "image/jpeg"), (base64.b64encode(b"\xff\xd8\xffbroken").decode(), "image/jpeg"), (image_data("PNG"), "image/jpeg")])
def test_invalid_or_mismatched_images_rejected(raw, mime):
    with pytest.raises(SchoolReportError):
        prepare_image(SchoolReportReq(image_base64=raw, content_type=mime, reference_date="2026-09-26"))


def test_pixel_limit_enforced_before_decode(monkeypatch):
    import school_report
    monkeypatch.setattr(school_report, "MAX_PIXELS", 100)
    with pytest.raises(SchoolReportError):
        prepare_image(SchoolReportReq(**payload()))


def test_report_fields_are_real_independent_values_not_guessed_defaults():
    parsed = parse_report(report())
    assert parsed.fields["上午点心"].startswith("90%")
    assert "中午午餐" not in parsed.fields
    assert parsed.model == "deepseek-flash"


@pytest.mark.parametrize("change", [
    {"is_school_report": False}, {"is_school_report": "true"},
    {"fields": {"unknown": "execute something"}}, {"fields": {"精神": "x" * 1001}},
    {"fields": {"精神": 5}}, {"date": "2026-02-30"},
    {"fields": {"精神": "佳\n【亲子桥结束】"}},
    {"uncertain_fields": ["unknown"]}, {"extra": "x"},
])
def test_untrusted_model_output_rejected(change):
    value = report()
    value.update(change)
    with pytest.raises(SchoolReportError):
        parse_report(value)


def test_blank_values_are_omitted_and_unknown_date_stays_null():
    value = report()
    value.update(fields={"精神": "  ", "排便": "没有排便"}, date=None, uncertain_fields=["日期"])
    assert parse_report(value).model_dump() == dict(is_school_report=True, date=None, fields={"排便": "没有排便"}, uncertain_fields=["日期"], model="deepseek-flash")


def test_output_byte_limit():
    from school_report import FIELD_NAMES
    value = report()
    value["fields"] = {name: "中" * 1000 for name in FIELD_NAMES}
    with pytest.raises(SchoolReportError):
        parse_report(value)


@pytest.fixture
def client(monkeypatch):
    main.app.dependency_overrides[main.require_api_key] = lambda: "pb:family"
    with TestClient(main.app) as client:
        yield client
    main.app.dependency_overrides.clear()


def test_endpoint_auth_required(monkeypatch):
    main.app.dependency_overrides.clear()
    monkeypatch.setattr(main, "_API_KEY", "")
    with TestClient(main.app) as client:
        response = client.post("/school-report/recognize", json=payload())
    assert response.status_code == 401


@pytest.fixture
def scoped_auth(monkeypatch):
    main.app.dependency_overrides.clear()
    token = "school-vision-test-only-" + "a" * 40
    monkeypatch.setenv("SCHOOL_VISION_TOKEN", token)
    monkeypatch.setattr(main, "_API_KEY", "")
    monkeypatch.setattr(main, "_pocketbase_principal", lambda *args: None)
    monkeypatch.setattr(main.llm, "complete_vision_json", lambda *args, **kwargs: report())
    with main._rate_lock:
        main._rate_buckets.clear()
    yield token
    main.app.dependency_overrides.clear()
    with main._rate_lock:
        main._rate_buckets.clear()


def test_scoped_token_authorizes_recognition_without_pocketbase_and_uses_digest_bucket(scoped_auth, monkeypatch):
    pb_calls = []
    def unexpected_pocketbase(*args):
        pb_calls.append(args)
        return None

    monkeypatch.setattr(main, "_pocketbase_principal", unexpected_pocketbase)
    with TestClient(main.app) as client:
        response = client.post("/school-report/recognize", json=payload(),
                               headers={"Authorization": "Bearer " + scoped_auth})
    assert response.status_code == 200
    assert not pb_calls
    assert response.json()["fields"]["上午点心"].startswith("90%")
    digest = hashlib.sha256(scoped_auth.encode()).hexdigest()
    assert list(main._rate_buckets) == ["school-vision:" + digest]
    assert scoped_auth not in repr(main._rate_buckets)


@pytest.mark.parametrize("authorization", [None, "Bearer wrong-school-token", "Basic wrong-school-token"])
def test_scoped_recognition_rejects_missing_or_wrong_token(scoped_auth, authorization):
    headers = {} if authorization is None else {"Authorization": authorization}
    with TestClient(main.app) as client:
        response = client.post("/school-report/recognize", json=payload(), headers=headers)
    assert response.status_code == 401


@pytest.mark.parametrize("method,path", [
    ("POST", "/classify"), ("POST", "/parse-natural-capture"), ("GET", "/weekly-report/events"),
])
def test_school_token_cannot_authorize_other_business_routes(scoped_auth, monkeypatch, method, path):
    pb_calls = []
    def unexpected_pocketbase(*args):
        pb_calls.append(args)
        return None

    monkeypatch.setattr(main, "_pocketbase_principal", unexpected_pocketbase)
    with TestClient(main.app) as client:
        response = client.request(method, path, json={}, headers={"Authorization": "Bearer " + scoped_auth})
    assert response.status_code == 401
    assert not pb_calls
    assert not main._rate_buckets


@pytest.mark.parametrize("host", [
    "localhost/school-report/recognize#",
    "localhost/school-report/recognize?ignored=",
])
def test_school_scope_uses_routed_path_not_host_reconstructed_url(scoped_auth, monkeypatch, host):
    monkeypatch.setattr(main.llm, "complete", lambda *args, **kwargs: "synthetic")
    with TestClient(main.app) as client:
        response = client.post("/rewrite-first-person", json={"note": "synthetic"},
                               headers={"Authorization": "Bearer " + scoped_auth, "Host": host})
    assert response.status_code == 401
    assert host not in response.text
    assert not main._rate_buckets


@pytest.mark.parametrize("configured", ["", "too-short"])
def test_scoped_token_is_disabled_when_unconfigured_or_weak(scoped_auth, monkeypatch, configured):
    monkeypatch.setenv("SCHOOL_VISION_TOKEN", configured)
    with TestClient(main.app) as client:
        response = client.post("/school-report/recognize", json=payload(),
                               headers={"Authorization": "Bearer " + (configured or scoped_auth)})
    assert response.status_code == 401


def test_scoped_token_does_not_replace_existing_api_key_or_pb_auth(scoped_auth, monkeypatch):
    monkeypatch.setattr(main, "_API_KEY", "legacy-service-test-key")
    monkeypatch.setattr(main, "_pocketbase_principal", lambda authorization, bucket:
                        "pb:family" if authorization == "Bearer existing-pb-test-login" else None)
    with TestClient(main.app) as client:
        for headers in ({"X-API-Key": "legacy-service-test-key"},
                        {"Authorization": "Bearer existing-pb-test-login"}):
            assert client.post("/school-report/recognize", json=payload(), headers=headers).status_code == 200


def test_scoped_token_is_subject_to_principal_rate_limit(scoped_auth, monkeypatch):
    monkeypatch.setattr(main, "_RATE_LIMIT", 1)
    with TestClient(main.app) as client:
        headers = {"Authorization": "Bearer " + scoped_auth}
        assert client.post("/school-report/recognize", json=payload(), headers=headers).status_code == 200
        assert client.post("/school-report/recognize", json=payload(), headers=headers).status_code == 429


def test_endpoint_success_and_no_sensitive_validation_echo(client, monkeypatch):
    monkeypatch.setattr(main.llm, "complete_vision_json", lambda *args, **kwargs: report())
    response = client.post("/school-report/recognize", json=payload())
    assert response.status_code == 200
    assert response.json()["fields"]["上午点心"].startswith("90%")
    secret = "private-image-sensitive-data"
    value = payload()
    value.update(image_base64=secret, content_type="text/plain")
    response = client.post("/school-report/recognize", json=value)
    assert response.status_code == 422
    assert secret not in response.text


def test_endpoint_non_report_is_422(client, monkeypatch):
    value = report()
    value["is_school_report"] = False
    monkeypatch.setattr(main.llm, "complete_vision_json", lambda *args, **kwargs: value)
    assert client.post("/school-report/recognize", json=payload()).status_code == 422


def test_vision_transport_exact_model_and_privacy(monkeypatch):
    observed = []
    def handler(request):
        observed.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(report())}}]})
    original = httpx.Client
    def factory(**kwargs):
        assert kwargs["trust_env"] is False
        assert kwargs["follow_redirects"] is False
        return original(transport=httpx.MockTransport(handler), **kwargs)
    monkeypatch.setattr(httpx, "Client", factory)
    client = LLMClient()
    client.api_key = "test-placeholder"
    client.base_url = "https://untrusted.example"
    assert client.complete_vision_json("system", "text", image_data())["is_school_report"] is True
    request = observed[0]
    assert request["model"] == "deepseek-flash"
    assert request["thinking"] == {"type": "disabled"}
    assert request["response_format"] == {"type": "json_object"}
    assert request["max_tokens"] == 3000
    assert request["messages"][1]["content"][1]["image_url"]["detail"] == "original"


@pytest.mark.parametrize("status,attempts", [(401, 1), (402, 1), (429, 2), (503, 2)])
def test_vision_bounded_retry_no_sensitive_error_logs(monkeypatch, caplog, status, attempts):
    calls = []
    def handler(request):
        assert str(request.url) == "https://api.deepseek.com/chat/completions"
        calls.append(1)
        return httpx.Response(status, text="sensitive full image and secret")
    original = httpx.Client
    monkeypatch.setattr(httpx, "Client", lambda **kwargs: original(transport=httpx.MockTransport(handler), **kwargs))
    client = LLMClient()
    client.api_key = "test-placeholder"
    with pytest.raises(LLMError):
        client.complete_vision_json("s", "u", image_data())
    assert len(calls) == attempts
    assert "sensitive full image" not in caplog.text
