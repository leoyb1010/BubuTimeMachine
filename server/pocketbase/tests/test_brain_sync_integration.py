"""Timeline writer against disposable PocketBase 0.39; synthetic pixels only.

Reuses the repository's initialized temporary-database fixture. No production
database, personal photo library, Gemini, or external service is contacted.
"""
import hashlib
from pathlib import Path
import sys

from PIL import Image
import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "server/ai"))

from server.pocketbase.tests import test_family_isolation as pb_tests
from learning.brain_sync import PocketBaseTimelineWriter, TimelineWriteError
from memory_query import PocketBaseMemoryStore


@pytest.fixture
def timeline_database(monkeypatch, tmp_path):
    # All credentials below are created in this test's disposable PB directory.
    monkeypatch.delenv("BUBU_NTFY_URL", raising=False)
    monkeypatch.delenv("BUBU_NTFY_TOKEN", raising=False)
    monkeypatch.delenv("PB_WORKER_EMAIL", raising=False)
    monkeypatch.delenv("PB_WORKER_PASSWORD", raising=False)
    database = pb_tests.FamilyIsolationIntegrationTests()
    memory = None
    try:
        database.setUp()
        monkeypatch.setenv("PB_BASE_URL", database.base)
        monkeypatch.setenv("PB_WORKER_TOKEN", database.admin)
        memory = PocketBaseMemoryStore()
        writer = PocketBaseTimelineWriter(database.family_a, database.user_a["id"], "爸爸", store=memory)
        original = tmp_path / "synthetic-confirmed-photo.jpg"
        Image.new("RGB", (16, 16), (90, 130, 170)).save(original, "JPEG")
        source = {
            "file_id": "1" * 24,
            "content_hash": hashlib.sha256(original.read_bytes()).hexdigest(),
            "captured_at": "2026-10-20T10:30:00+08:00",
            "media_type": "photo", "name": original.name,
            "source_revision": "synthetic-confirmed-revision",
            "provenance": "manual", "confidence": 1.0,
            "analysis": {"description": "合成色块，用于隔离写入验收。", "tags": ["合成测试"],
                         "provider": "second-brain-gemini", "model_version": "test-only"},
            "local_path": str(original),
        }
        yield database, memory, writer, source
    finally:
        if memory:
            memory.close()
        database.doCleanups()


def imported_rows(memory, family, sha):
    return memory.list_records("media", filter_value="familyId='%s' && contentHash='%s'" % (family, sha), sort="id")


def test_real_pb_creates_visible_photo_and_reuses_it_idempotently(timeline_database, tmp_path, monkeypatch):
    database, memory, writer, source = timeline_database
    request = memory.request
    created_states = []
    def observe(method, path, **kwargs):
        response = request(method, path, **kwargs)
        if method == "POST" and path == "/api/collections/entries/records":
            created = response.json()
            created_states.append((created["isArchived"], created["sourceRaw"]))
        return response
    monkeypatch.setattr(memory, "request", observe)
    saved = writer.upsert(source)
    assert saved["status"] == "synced" and saved["owned"] is True
    entry = memory.get_record("entries", saved["entry_id"])
    media = memory.get_record("media", saved["media_id"])
    assert entry["sourceRaw"] == "second-brain-auto"
    assert entry["isArchived"] is False and entry["isDeleted"] is False
    assert entry["authorUserId"] == database.user_a["id"]
    assert entry["familyId"] == media["familyId"] == database.family_a
    assert media["resourceRole"] == "display" and media["file"]
    assert media["entryLocalId"] == saved["entry_local_id"] == entry["localId"]
    assert media["localId"] == saved["media_local_id"]
    assert media["contentHash"] == source["content_hash"]
    assert entry["happenedAt"].startswith("2026-10-20 02:30:00")

    # The exact multipart-uploaded bytes are available through protected files.
    downloaded = tmp_path / "downloaded.jpg"
    memory.download_record_file("media", media["id"], media["file"], str(downloaded))
    assert hashlib.sha256(downloaded.read_bytes()).hexdigest() == source["content_hash"]

    again = writer.upsert(source)
    assert again["media_id"] == saved["media_id"] and again["entry_id"] == saved["entry_id"]
    assert created_states == [(True, "second-brain-pending")]
    assert len(imported_rows(memory, database.family_a, source["content_hash"])) == 1
    entries = memory.list_records("entries", filter_value="familyId='%s' && localId='%s'" %
                                  (database.family_a, saved["entry_local_id"]), sort="id")
    assert len(entries) == 1
    status, _ = database.call("GET", "/api/collections/entries/records/" + entry["id"], token=database.token_a)
    assert status == 200
    status, _ = database.call("GET", "/api/collections/media/records/" + media["id"], token=database.token_b)
    assert status == 404


@pytest.mark.parametrize("collection,changes", [
    ("media", {"isDeleted": True}),
    ("entries", {"isDeleted": True}),
    ("entries", {"isArchived": True}),
])
def test_real_family_delete_or_archive_is_never_undone(timeline_database, collection, changes):
    database, memory, writer, source = timeline_database
    saved = writer.upsert(source)
    rid = saved["media_id"] if collection == "media" else saved["entry_id"]
    status, _ = database.call("PATCH", "/api/collections/" + collection + "/records/" + rid,
                              changes, database.token_a)
    assert status == 200
    before = memory.get_record(collection, rid)
    rejected = writer.upsert(source)
    after = memory.get_record(collection, rid)
    assert rejected["status"] == "tombstoned"
    assert before == after
    assert len(imported_rows(memory, database.family_a, source["content_hash"])) == 1
    entries = memory.list_records("entries", filter_value="familyId='%s' && localId='%s'" %
                                  (database.family_a, saved["entry_local_id"]), sort="id")
    assert len(entries) == 1


def test_real_pb_rejects_author_from_another_family_without_creating_facts(timeline_database):
    database, memory, _, source = timeline_database
    foreign, _ = database.user("foreign-writer", database.family_b)
    writer = PocketBaseTimelineWriter(database.family_a, foreign["id"], "爸爸", store=memory)
    entries_before = memory.list_records("entries", filter_value="familyId='%s'" % database.family_a, sort="id")
    with pytest.raises(TimelineWriteError, match="author_family_mismatch"):
        writer.upsert(source)
    assert imported_rows(memory, database.family_a, source["content_hash"]) == []
    assert memory.list_records("entries", filter_value="familyId='%s'" % database.family_a, sort="id") == entries_before
