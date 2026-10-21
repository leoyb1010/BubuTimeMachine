from __future__ import annotations

import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main  # noqa: E402
from fastapi import HTTPException  # noqa: E402
import pytest  # noqa: E402


FAMILY_SETTINGS = (
    "INTAKE_FAMILY_ID", "SEMANTIC_FAMILY_ID", "WEEKLY_REPORT_FAMILY_ID", "SOUND_RING_FAMILY_ID",
)


@pytest.fixture(autouse=True)
def isolated_auth_state(monkeypatch):
    for setting in FAMILY_SETTINGS:
        monkeypatch.delenv(setting, raising=False)
    main._pb_auth_cache.clear()
    main._rate_buckets.clear()
    yield
    main._pb_auth_cache.clear()
    main._rate_buckets.clear()


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


@pytest.mark.parametrize("setting", FAMILY_SETTINGS)
@pytest.mark.parametrize("returned_family", ["another-family", ""])
def test_family_bound_service_rejects_other_or_unassigned_family(monkeypatch, setting, returned_family):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
    monkeypatch.setenv(setting, "expected-family")
    monkeypatch.setattr(FakeResponse, "json", staticmethod(lambda: {
        "record": {"id": "family-user", "familyId": returned_family},
    }))
    assert main._pocketbase_principal("Bearer valid-token") is None


def test_family_change_revokes_access_even_with_same_cached_token(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
    monkeypatch.setenv("WEEKLY_REPORT_FAMILY_ID", "expected-family")
    record = {"id": "family-user", "familyId": "expected-family"}
    monkeypatch.setattr(FakeResponse, "json", staticmethod(lambda: {"record": record}))
    assert main._pocketbase_principal("Bearer valid-token") == "pb:family-user"
    record["familyId"] = "another-family"
    assert main._pocketbase_principal("Bearer valid-token") is None


def test_consistent_family_bindings_accept_member_but_recheck_revoked_token(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
    for setting in FAMILY_SETTINGS:
        monkeypatch.setenv(setting, "expected-family")
    monkeypatch.setattr(FakeResponse, "json", staticmethod(lambda: {
        "record": {"id": "family-user", "familyId": "expected-family"},
    }))
    assert main._pocketbase_principal("Bearer valid-token") == "pb:family-user"
    monkeypatch.setattr(main.httpx, "Client", RejectingClient)
    assert main._pocketbase_principal("Bearer valid-token") is None


def test_generic_ai_without_family_binding_keeps_identity_cache(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
    assert main._pocketbase_principal("Bearer valid-token") == "pb:family-user"
    monkeypatch.setattr(main.httpx, "Client", lambda **kwargs: pytest.fail("unexpected PB refresh"))
    assert main._pocketbase_principal("Bearer valid-token") == "pb:family-user"


def test_allowlist_removal_revokes_cached_generic_identity(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
    assert main._pocketbase_principal("Bearer valid-token") == "pb:family-user"
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "another-user")
    assert main._pocketbase_principal("Bearer valid-token") is None
    assert not main._pb_auth_cache


def test_enabling_family_binding_does_not_reuse_generic_identity_cache(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
    assert main._pocketbase_principal("Bearer valid-token") == "pb:family-user"
    monkeypatch.setenv("SEMANTIC_FAMILY_ID", "expected-family")
    assert main._pocketbase_principal("Bearer valid-token") is None


def test_conflicting_family_configuration_fails_closed(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", FakeClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
    monkeypatch.setenv("INTAKE_FAMILY_ID", "family-a")
    monkeypatch.setenv("WEEKLY_REPORT_FAMILY_ID", "family-b")
    with pytest.raises(HTTPException) as caught:
        main._pocketbase_principal("Bearer valid-token")
    assert caught.value.status_code == 503


@pytest.mark.parametrize("path", ["/weekly-report/latest", "/sound-ring/latest", "/semantic/search", "/intake/candidates"])
def test_family_routes_require_a_bound_family_after_authentication(monkeypatch, path):
    from starlette.requests import Request
    monkeypatch.setattr(main, "_authorized_principal", lambda *args: "pb:family-user")
    request = Request({"type": "http", "method": "GET", "path": path})
    with pytest.raises(HTTPException) as caught:
        main.require_api_key(request, None, "Bearer valid-token")
    assert caught.value.status_code == 503


class RejectingResponse:
    status_code = 401


class RejectingClient(FakeClient):
    def post(self, url, headers):
        return RejectingResponse()


def test_uncached_invalid_bearers_are_limited_before_pocketbase(monkeypatch):
    monkeypatch.setattr(main.httpx, "Client", RejectingClient)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", "family-user")
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
