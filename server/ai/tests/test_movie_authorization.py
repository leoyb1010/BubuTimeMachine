"""Movie access regressions against a disposable, real PocketBase database."""
import io
import shutil
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "server/ai"))
from server.pocketbase.tests import test_family_isolation as pb_tests
import main
import movie_render


@pytest.fixture
def movie_api(monkeypatch, tmp_path):
    database = pb_tests.FamilyIsolationIntegrationTests()
    try:
        database.setUp()
        monkeypatch.setenv("PB_BASE_URL", database.base)
        monkeypatch.setenv("PB_WORKER_TOKEN", database.admin)
        monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", database.user_a["id"])
        main._pb_auth_cache.clear()
        main._rate_buckets.clear()
        monkeypatch.setattr(movie_render, "_jobs", {})
        monkeypatch.setattr(movie_render, "MOVIES_DIR", str(tmp_path))
        monkeypatch.setattr(movie_render, "ffmpeg_available", lambda: True)

        class InlineExecutor:
            def submit(self, function, *args):
                function(*args)

        def clip(source, destination, *args, **kwargs):
            shutil.copyfile(source, destination)
            return True

        monkeypatch.setattr(movie_render, "_executor", InlineExecutor())
        monkeypatch.setattr(movie_render, "_kenburns_clip", clip)
        encoded = io.BytesIO()
        Image.new("RGB", (4, 4), "blue").save(encoded, "JPEG")
        files = {}
        for suffix, family in [("a", database.family_a), ("b", database.family_b)]:
            status, media = database.multipart(
                "/api/collections/media/records",
                {"localId": "movie-media-" + suffix, "familyId": family,
                 "entryLocalId": suffix, "mediaType": "photo"},
                "file", "photo.jpg", encoded.getvalue(), database.admin,
            )
            assert status == 200, media
            files[suffix] = media
        yield TestClient(main.app), database, files, encoded.getvalue()
    finally:
        database.doCleanups()


def render(client, token, media, **changes):
    payload = {"year": 2026, "photos": [{"url": (
        "https://public.example/api/files/media/" + media["id"] + "/" + media["file"]
    )}]}
    payload.update(changes)
    return client.post("/movie/render", headers={"Authorization": "Bearer " + token}, json=payload)


def test_movie_rejects_cross_family_source_before_worker_download(movie_api):
    client, database, files, _ = movie_api
    status, _ = database.call("GET", "/api/collections/media/records/" + files["b"]["id"], token=database.token_a)
    assert status == 404
    response = render(client, database.token_a, files["b"])
    assert response.status_code == 403
    assert movie_render._jobs == {}


def test_same_family_movie_works_but_other_principals_cannot_read_job(movie_api, monkeypatch):
    client, database, files, data = movie_api
    response = render(client, database.token_a, files["a"])
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "ready"
    job_id = response.json()["job_id"]
    own = {"Authorization": "Bearer " + database.token_a}
    assert client.get("/movie/file/" + job_id, headers=own).content == data
    other, token = database.user("other", database.family_b)
    monkeypatch.setenv("AI_ALLOWED_PB_USER_IDS", database.user_a["id"] + "," + other["id"])
    for route in ("status", "file"):
        assert client.get("/movie/" + route + "/" + job_id,
                          headers={"Authorization": "Bearer " + token}).status_code == 404
    monkeypatch.setattr(main, "_API_KEY", "maintenance-test-key")
    assert client.get("/movie/file/" + job_id,
                      headers={"X-API-Key": "maintenance-test-key"}).status_code == 404


@pytest.mark.parametrize("source", ["deleted_media", "deleted_entry", "wrong_file", "invalid_path"])
def test_movie_rejects_unavailable_or_invalid_source(movie_api, source):
    client, database, files, _ = movie_api
    media = dict(files["a"])
    changes = {}
    if source in {"deleted_media", "deleted_entry"}:
        collection, record_id = (("media", media["id"]) if source == "deleted_media"
                                 else ("entries", database.entry_a["id"]))
        assert database.call("PATCH", "/api/collections/" + collection + "/records/" + record_id,
                             {"isDeleted": True}, database.admin)[0] == 200
    elif source == "wrong_file":
        media["file"] = "other.jpg"
    else:
        changes["photos"] = [{"url": "http://127.0.0.1:8090/api/health"}]
    assert render(client, database.token_a, media, **changes).status_code in {403, 422}
    assert movie_render._jobs == {}


def test_maintenance_key_cannot_authorize_family_movie_sources(movie_api, monkeypatch):
    client, _, files, _ = movie_api
    monkeypatch.setattr(main, "_API_KEY", "maintenance-test-key")
    response = client.post("/movie/render", headers={"X-API-Key": "maintenance-test-key"},
                           json={"photos": [{"url": "https://public.example/api/files/media/"
                                             + files["a"]["id"] + "/" + files["a"]["file"]}]})
    assert response.status_code == 403


def test_movie_filesystem_failure_reaches_failed_terminal_state(monkeypatch):
    job = movie_render.RenderJob("synthetic", 2026, "synthetic")
    monkeypatch.setattr(movie_render, "ffmpeg_available", lambda: True)
    monkeypatch.setattr(movie_render, "_download", lambda *args: True)
    monkeypatch.setattr(movie_render, "_source_still_authorized", lambda *args: True)
    monkeypatch.setattr(movie_render, "_kenburns_clip", lambda *args, **kwargs: True)
    def no_space(*args):
        raise OSError(28, "synthetic private path and secret")
    monkeypatch.setattr(movie_render.shutil, "copyfile", no_space)
    movie_render._run_render(job, "documentary", [movie_render.RenderPhoto("synthetic")], "")
    assert job.status == "failed"
    assert "private" not in job.error and "secret" not in job.error


@pytest.mark.parametrize("change", ["deleted", "membership"])
def test_queued_movie_rechecks_sources_before_service_download(movie_api, monkeypatch, change):
    client, database, files, _ = movie_api
    pending = []
    class DeferredExecutor:
        def submit(self, function, *args):
            pending.append((function, args))
    monkeypatch.setattr(movie_render, "_executor", DeferredExecutor())
    response = render(client, database.token_a, files["a"])
    assert response.status_code == 200
    if change == "deleted":
        path, body = "/api/collections/media/records/" + files["a"]["id"], {"isDeleted": True}
    else:
        path, body = "/api/collections/users/records/" + database.user_a["id"], {"familyId": database.family_b}
    assert database.call("PATCH", path, body, database.admin)[0] == 200
    monkeypatch.setattr(movie_render, "_download", lambda *args: pytest.fail("revoked source downloaded"))
    function, args = pending[0]
    function(*args)
    assert movie_render.get_job(response.json()["job_id"]).status == "failed"
