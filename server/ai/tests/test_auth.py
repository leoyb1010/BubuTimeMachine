from __future__ import annotations

import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main  # noqa: E402
from fastapi import HTTPException  # noqa: E402
import pytest  # noqa: E402


class FakeResponse:
    status_code = 200

    @staticmethod
    def json():
        return {"record": {"id": "family-user"}}


class FakeClient:
    def __init__(self, **kwargs):
        assert kwargs["trust_env"] is False

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return None

    def post(self, url, headers):
        assert url.endswith("/api/collections/users/auth-refresh")
        assert headers == {"Authorization": "Bearer valid-token"}
        return FakeResponse()


def test_pocketbase_user_token_is_accepted_without_persisting_the_raw_token(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
    main._pb_auth_cache.clear()

    principal = main._pocketbase_principal("Bearer valid-token")

    assert principal == "pb:family-user"
    assert all("valid-token" not in key for key in main._pb_auth_cache)


def test_pocketbase_user_must_match_configured_allowlist(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "another-user,second-user")
    main._pb_auth_cache.clear()

    assert main._pocketbase_principal("Bearer valid-token") is None
    assert main._pb_auth_cache == {}


def test_missing_or_malformed_bearer_is_rejected():
    assert main._pocketbase_principal(None) is None
    assert main._pocketbase_principal("Bearer ") is None
    assert main._pocketbase_principal("Basic abc") is None


def test_missing_allowlist_fails_closed(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.delenv("AI_ALLOWED_PB_USER_IDS", raising=False)
    main._pb_auth_cache.clear()
    assert main._pocketbase_principal("Bearer valid-token") is None


class RejectingResponse:
    status_code = 401


class RejectingClient(FakeClient):
    def post(self, url, headers):
        return RejectingResponse()


def test_uncached_invalid_bearers_are_limited_before_pocketbase(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", RejectingClient)
    monkeypatch.setattr(main, "_PREAUTH_RATE_LIMIT", 1)
    main._pb_auth_cache.clear()
    main._rate_buckets.clear()

    assert main._pocketbase_principal("Bearer first", "preauth:test") is None
    with pytest.raises(HTTPException) as caught:
        main._pocketbase_principal("Bearer second", "preauth:test")
    assert caught.value.status_code == 429


class FakeRequest:
    class Client:
        host = "127.0.0.1"
    client = Client()

    class URL:
        path = "/intake/candidates"
    url = URL()


def test_intake_requires_explicit_family_user_and_rejects_service_key(monkeypatch):
    monkeypatch.delenv("INTAKE_ALLOWED_PB_USER_IDS", raising=False)
    with pytest.raises(HTTPException) as missing:
        main.require_intake_family_user(FakeRequest(), None, None)
    assert missing.value.status_code == 503

    monkeypatch.setenv("INTAKE_ALLOWED_PB_USER_IDS", "family-user")
    monkeypatch.setattr(main, "require_api_key", lambda *_: "service:legacy-key")
    with pytest.raises(HTTPException) as service:
        main.require_intake_family_user(FakeRequest(), "legacy", None)
    assert service.value.status_code == 403

    monkeypatch.setattr(main, "require_api_key", lambda *_: "pb:family-user")
    assert main.require_intake_family_user(FakeRequest(), None, "Bearer token") == "pb:family-user"
