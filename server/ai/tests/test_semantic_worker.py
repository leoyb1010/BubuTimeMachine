from pathlib import Path

import httpx

from semantic_index import SemanticIndex
from semantic_worker import (
    ClaimedJob,
    SemanticWorker,
    retry_delay_seconds,
    safe_error_summary,
)


class FakeEncoder:
    model_version = "fake-v1"

    def encode_image(self, path):
        assert Path(path).read_bytes() == b"image"
        return [1.0, 0.0]


class FakeClient:
    def __init__(self, jobs, current_deleted=False):
        self.jobs = list(jobs)
        self.current_deleted = current_deleted
        self.completed = []
        self.failed = []

    def claim(self, limit=2):
        result, self.jobs = self.jobs[:limit], self.jobs[limit:]
        return result

    def complete(self, job, model_version):
        self.completed.append((job.id, model_version))

    def fail(self, job, error):
        self.failed.append((job.id, type(error).__name__))

    def fetch_media(self, record_id):
        return {
            "id": record_id,
            "entryLocalId": "entry-1",
            "mediaType": "photo",
            "file": "photo.jpg",
            "aiTags": ["公园", "秋千"],
            "familyId": "family-a",
            "created": "2026-08-05T12:00:00Z",
            "isDeleted": self.current_deleted,
        }

    def fetch_entry(self, local_id):
        return {
            "localId": local_id,
            "title": "第一次玩秋千",
            "note": "笑得很开心",
            "happenedAt": "2026-08-05T11:00:00Z",
        }

    def download_media(self, media, destination):
        Path(destination).write_bytes(b"image")

    def public_file_url(self, media):
        return "http://127.0.0.1:8090/photo.jpg"


def job(kind="semantic_media_upsert"):
    return ClaimedJob(
        id="job-1",
        kind=kind,
        source_record_id="media-1",
        source_local_id="local-media-1",
        family_id="family-a",
        attempts=0,
    )


def test_worker_indexes_photo_and_marks_job_done(tmp_path: Path):
    client = FakeClient([job()])
    index = SemanticIndex(tmp_path / "memory.sqlite", "fake-v1")
    worker = SemanticWorker(client, index, FakeEncoder())

    assert worker.run_once() == 1
    assert client.completed == [("job-1", "fake-v1")]
    assert client.failed == []
    hit = index.search("秋千", [1, 0])[0]
    assert hit.entry_local_id == "entry-1"
    assert hit.media_record_id == "media-1"


def test_legacy_empty_family_uses_configured_logical_family(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("SEMANTIC_FAMILY_ID", "bubu-logical-family")
    current = job()
    current = ClaimedJob(
        id=current.id, kind=current.kind,
        source_record_id=current.source_record_id,
        source_local_id=current.source_local_id,
        family_id="", attempts=current.attempts,
    )

    class LegacyClient(FakeClient):
        def fetch_media(self, record_id):
            value = super().fetch_media(record_id)
            value["familyId"] = ""
            return value

    client = LegacyClient([current])
    index = SemanticIndex(tmp_path / "memory.sqlite", "fake-v1")
    worker = SemanticWorker(client, index, FakeEncoder())
    assert worker.run_once() == 1
    assert len(index.search("秋千", [1, 0], family_id="bubu-logical-family")) == 1
    assert index.search("秋千", [1, 0], family_id="another-family") == []


def test_worker_delete_is_idempotent(tmp_path: Path):
    client = FakeClient([job("semantic_media_delete")], current_deleted=True)
    index = SemanticIndex(tmp_path / "memory.sqlite", "fake-v1")
    worker = SemanticWorker(client, index, FakeEncoder())

    assert worker.run_once() == 1
    assert index.count() == 0
    assert client.completed == [("job-1", "fake-v1")]


def test_stale_delete_rebuilds_when_current_media_was_restored(tmp_path: Path):
    client = FakeClient([job("semantic_media_delete")], current_deleted=False)
    index = SemanticIndex(tmp_path / "memory.sqlite", "fake-v1")
    worker = SemanticWorker(client, index, FakeEncoder())

    assert worker.run_once() == 1
    assert index.active_count() == 1


def test_unknown_job_fails_without_poisoning_worker(tmp_path: Path):
    client = FakeClient([job("unknown")])
    index = SemanticIndex(tmp_path / "memory.sqlite", "fake-v1")
    worker = SemanticWorker(client, index, FakeEncoder())

    assert worker.run_once() == 1
    assert client.completed == []
    assert client.failed == [("job-1", "RuntimeError")]


def test_retry_backoff_is_bounded():
    assert retry_delay_seconds(1) == 60
    assert retry_delay_seconds(2) == 120
    assert retry_delay_seconds(3) == 240
    assert retry_delay_seconds(99) == 3600


def test_http_error_summary_never_contains_protected_file_token():
    request = httpx.Request("GET", "http://127.0.0.1/file.jpg?token=secret-value")
    response = httpx.Response(403, request=request)
    error = httpx.HTTPStatusError("forbidden", request=request, response=response)

    summary = safe_error_summary(error)

    assert summary == "HTTPStatusError: status=403"
    assert "secret-value" not in summary
