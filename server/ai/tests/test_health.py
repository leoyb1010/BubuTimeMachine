"""/health answers from the event loop; /health/deep is loopback-only and bounded."""
from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
import learning.status as status  # noqa: E402


def test_health_is_async_and_needs_no_thread():
    import inspect
    assert inspect.iscoroutinefunction(main.health) and inspect.iscoroutinefunction(main.health_deep)
    with TestClient(main.app) as client:
        assert client.get("/health").json() == {"ok": True, "auth": False}


def test_health_deep_is_loopback_only_and_reports_probe(monkeypatch):
    calls = []

    def fake_probe(state_dir=None, brain_root=None, timeout=5.0):
        calls.append(timeout)
        return {"learning_store": True, "brain_library": False, "heartbeat": {"at": time.time() - 30}, "backup": None}
    monkeypatch.setattr(status, "probe", fake_probe)
    with TestClient(main.app) as remote:
        assert remote.get("/health/deep").status_code == 404
    with TestClient(main.app, client=("127.0.0.1", 50000)) as local:
        assert local.get("/health/deep", headers={"CF-Connecting-IP": "203.0.113.9"}).status_code == 404
        assert local.get("/health/deep", headers={"X-Forwarded-For": "203.0.113.9"}).status_code == 404
        body = local.get("/health/deep").json()
    assert set(body) == {"ok", "learning_store", "brain_library", "worker_heartbeat_age_s", "snapshot_age_s"}
    assert body["ok"] is False and body["learning_store"] is True and 25 <= body["worker_heartbeat_age_s"] <= 60
    assert calls == [5.0]
