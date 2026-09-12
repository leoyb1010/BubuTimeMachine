"""PocketBase 服务账户 token 过期后必须自动重新认证，不能让常驻进程崩溃。

线上事实：superuser token 24 小时过期，PocketBase 对过期 token 不回 401，
而是当匿名请求评估规则，superuser-only 集合返回 403。
"""
import base64
import json
import time

import httpx
import pytest

import memory_query
import semantic_worker


def _jwt(exp: float) -> str:
    payload = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
    return "h." + payload + ".s"


def _mounted(monkeypatch, module, cls, handler):
    monkeypatch.setenv("PB_WORKER_EMAIL", "ops@example.com")
    monkeypatch.setenv("PB_WORKER_PASSWORD", "secret")
    monkeypatch.delenv("PB_WORKER_TOKEN", raising=False)
    client = cls()
    client._client = httpx.Client(
        base_url="http://pb.test", transport=httpx.MockTransport(handler)
    )
    return client


@pytest.mark.parametrize("status", [401, 403])
@pytest.mark.parametrize(
    "module,cls,method",
    [
        (semantic_worker, semantic_worker.PocketBaseWorkerClient, "_request"),
        (memory_query, memory_query.PocketBaseMemoryStore, "request"),
    ],
)
def test_expired_token_reauthenticates_once_on_401_or_403(monkeypatch, status, module, cls, method):
    logins = []
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/auth-with-password"):
            logins.append(1)
            return httpx.Response(200, json={"token": _jwt(time.time() + 86400)})
        calls.append(request.headers.get("Authorization"))
        if len(calls) == 1:
            return httpx.Response(status, json={"message": "Only superusers can perform this action."})
        return httpx.Response(200, json={"items": []})

    client = _mounted(monkeypatch, module, cls, handler)
    client._token = _jwt(time.time() + 3600)  # 本地以为还有效，服务端已判失效
    response = getattr(client, method)("GET", "/api/collections/automation_jobs/records")
    assert response.status_code == 200
    assert len(logins) == 1
    assert len(calls) == 2 and calls[0] != calls[1]


def test_token_near_expiry_is_refreshed_before_use(monkeypatch):
    logins = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/auth-with-password"):
            logins.append(1)
            return httpx.Response(200, json={"token": _jwt(time.time() + 86400)})
        return httpx.Response(200, json={"items": []})

    client = _mounted(monkeypatch, semantic_worker, semantic_worker.PocketBaseWorkerClient, handler)
    client._token = _jwt(time.time() + 60)
    client._request("GET", "/api/collections/automation_jobs/records")
    assert logins == [1]
    assert semantic_worker.token_expires_at(client._token) > time.time() + 80000


def test_static_api_token_is_never_refreshed_but_error_is_clear(monkeypatch):
    monkeypatch.setenv("PB_WORKER_TOKEN", "static-token")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(403, json={})

    client = semantic_worker.PocketBaseWorkerClient()
    client._client = httpx.Client(base_url="http://pb.test", transport=httpx.MockTransport(handler))
    with pytest.raises(RuntimeError, match="PB_WORKER_TOKEN"):
        client._request("GET", "/api/collections/automation_jobs/records")


def test_token_expires_at_tolerates_garbage():
    assert semantic_worker.token_expires_at("") == 0.0
    assert semantic_worker.token_expires_at("not-a-jwt") == 0.0
    assert memory_query.token_expires_at("a.b.c") == 0.0
