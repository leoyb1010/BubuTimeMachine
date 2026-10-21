"""Automatic timeline sync: isolated SQLite and a fake PocketBase transport."""
import copy
from email.parser import BytesParser
from email.policy import default
import hashlib
import json
from pathlib import Path
import re
import sys

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning.brain_bridge import BrainUnavailable
from learning.brain_sync import BrainSyncService, PocketBaseTimelineWriter, TimelineWriteError
from learning.store import LearningStore
from memory_query import PocketBaseMemoryStore


def item(tmp_path, n=1):
    path = tmp_path / f"photo-{n}.jpg"
    path.write_bytes(f"synthetic photo {n}".encode())
    return {
        "file_id": f"{n:024x}", "content_hash": hashlib.sha256(path.read_bytes()).hexdigest(),
        "captured_at": "2026-10-20T10:30:00+08:00", "media_type": "photo", "name": path.name,
        "source_revision": f"revision-{n}", "provenance": "manual", "confidence": 1.0,
        "analysis": {"description": "正在画画", "tags": ["画画"], "ocr": "", "segments": [],
                     "provider": "second-brain-gemini", "model_version": "legacy-unversioned", "warnings": []},
        "local_path": str(path),
    }


class Bridge:
    def __init__(self, items):
        self.snapshot = {"complete": True, "snapshot_id": "snapshot-1", "items": items, "excluded": {}}

    def subject_snapshot(self, subject_id):
        assert subject_id == "subject-a"
        return copy.deepcopy(self.snapshot)


class Writer:
    def __init__(self):
        self.calls = []
        self.fail = set()

    def upsert(self, value):
        self.calls.append(value["content_hash"])
        if value["content_hash"] in self.fail:
            raise RuntimeError("SECRET /private/path")
        suffix = value["content_hash"][:8]
        return {"status": "synced", "action": "created", "media_id": "m" + suffix,
                "entry_id": "e" + suffix, "media_local_id": "local-m" + suffix,
                "entry_local_id": "local-e" + suffix, "owned": True}


def service(tmp_path, values):
    bridge = Bridge(values)
    writer = Writer()
    store = LearningStore(tmp_path / "learning")
    return BrainSyncService(bridge, store, writer, "family-a", "child-a", "subject-a"), bridge, writer, store


def test_bounded_backfill_never_skips_remainder_of_complete_snapshot(tmp_path):
    values = [item(tmp_path, n) for n in range(1, 6)]
    sync, _, writer, _ = service(tmp_path, values)
    assert sync.run_once(limit=2)["pending"] == 3
    assert sync.run_once(limit=2)["pending"] == 1
    assert sync.run_once(limit=2)["pending"] == 0
    assert len(writer.calls) == 5
    sync.run_once(limit=2)
    assert len(writer.calls) == 5
    assert len(sync.registry()["items"]) == 5
    assert "local_path" not in json.dumps(sync.registry())


def test_dry_run_and_exclusion_do_not_create_or_reimport_photos(tmp_path):
    first, second = item(tmp_path), item(tmp_path, 2)
    sync, bridge, writer, store = service(tmp_path, [first, second])
    report = sync.run_once(dry_run=True, limit=1)
    assert report["planned"] == 1
    assert not writer.calls
    with store.db() as db:
        assert db.execute("SELECT count(*) FROM cursors").fetchone()[0] == 0
    sync.exclude(first["content_hash"])
    sync.run_once()
    first["source_revision"] = "changed"
    bridge.snapshot["items"] = [first, second]
    sync.run_once()
    assert writer.calls == [second["content_hash"]]
    assert sync.registry()["items"][first["content_hash"]]["status"] == "hidden"


def test_metadata_revision_updates_native_analysis_mapping(tmp_path):
    first = item(tmp_path)
    sync, bridge, _, _ = service(tmp_path, [first])
    sync.run_once()
    mapping = sync.registry()["items"][first["content_hash"]]
    first["source_revision"] = "corrected"
    first["analysis"]["description"] = "修正为搭积木"
    bridge.snapshot["items"] = [first]
    sync.run_once()
    assert sync.media_analysis(mapping["media_id"])["analysis"]["description"] == "修正为搭积木"
    assert sync.media_analysis("another-media") is None


def test_failed_snapshot_never_marks_existing_records_missing(tmp_path):
    sync, bridge, writer, _ = service(tmp_path, [item(tmp_path)])
    sync.run_once()
    before = sync.registry()
    bridge.snapshot = {"complete": False, "snapshot_id": "failed", "items": []}
    with pytest.raises(BrainUnavailable):
        sync.run_once()
    assert sync.registry() == before
    assert len(writer.calls) == 1


def test_missing_item_is_recheck_not_automatic_deletion(tmp_path):
    first = item(tmp_path)
    sync, bridge, writer, _ = service(tmp_path, [first])
    sync.run_once()
    bridge.snapshot["items"] = []
    report = sync.run_once()
    saved = sync.registry()["items"][first["content_hash"]]
    assert report["needs_recheck"] == 1
    assert saved["status"] == "needs_recheck"
    assert saved["media_id"]
    assert len(writer.calls) == 1


def test_duplicate_hash_redirect_does_not_create_a_second_moment(tmp_path):
    first = item(tmp_path)
    duplicate = dict(first, file_id="f" * 24)
    sync, bridge, writer, _ = service(tmp_path, [first, duplicate])
    sync.run_once()
    assert len(writer.calls) == 1
    bridge.snapshot["items"] = [duplicate]
    sync.run_once()
    assert len(writer.calls) == 1
    assert sync.registry()["items"][first["content_hash"]]["brain_file_ids"] == [duplicate["file_id"]]


def test_failed_item_is_retryable_and_error_report_has_no_private_text(tmp_path):
    first, second = item(tmp_path), item(tmp_path, 2)
    sync, _, writer, _ = service(tmp_path, [first, second])
    writer.fail.add(first["content_hash"])
    report = sync.run_once(limit=2)
    assert report["failed"] == 1 and report["pending"] == 1
    assert "SECRET" not in json.dumps(report) + json.dumps(sync.registry())
    writer.fail.clear()
    assert sync.run_once()["pending"] == 0
    assert writer.calls.count(second["content_hash"]) == 1


def test_high_confidence_auto_identity_is_candidate_until_manually_confirmed(tmp_path):
    first = item(tmp_path)
    first.update(provenance="gemini_two_pass", confidence=0.99)
    sync, bridge, writer, _ = service(tmp_path, [first])
    report = sync.run_once()
    assert report["pending_identity"] == 1 and not writer.calls
    assert sync.registry()["items"][first["content_hash"]]["status"] == "pending_identity"
    first["provenance"] = "manual"
    bridge.snapshot["items"] = [first]
    assert sync.run_once()["pending_identity"] == 0
    assert writer.calls == [first["content_hash"]]


def test_a_failed_photo_does_not_starve_the_backfill_tail(tmp_path):
    values = [item(tmp_path, n) for n in range(1, 5)]
    sync, _, writer, _ = service(tmp_path, values)
    writer.fail.add(values[0]["content_hash"])
    for _ in range(4):
        sync.run_once(limit=1)
    assert set(writer.calls) == {value["content_hash"] for value in values}
    assert len(writer.calls) == 4


class PocketBase:
    def __init__(self):
        self.records = {"entries": {}, "media": {}}
        self.requests = []
        self.uploads = []
        self.author_family = "family-a"
        self.lose_media_response = False
        self.delete_new_media = False

    def handle(self, request):
        self.requests.append((request.method, request.url.path))
        pieces = request.url.path.split("/")
        collection = pieces[3]
        if collection == "users":
            return httpx.Response(200, json={"id": "authora", "familyId": self.author_family})
        rows = self.records[collection]
        if request.method == "GET":
            if len(pieces) == 6:
                row = rows.get(pieces[-1])
                return httpx.Response(200 if row else 404, json=row or {})
            clauses = re.findall(r"(\w+)='([^']*)'", request.url.params.get("filter", ""))
            matches = [r for r in rows.values() if all(str(r.get(k, "")) == value for k, value in clauses)]
            return httpx.Response(200, json={"items": matches, "totalPages": 1})
        if request.method == "POST" and "multipart/form-data" in request.headers.get("content-type", ""):
            message = BytesParser(policy=default).parsebytes(
                b"Content-Type: " + request.headers["content-type"].encode() + b"\r\n\r\n" + request.read())
            body = {}
            for part in message.iter_parts():
                key = part.get_param("name", header="content-disposition")
                if key == "file":
                    body[key] = part.get_filename()
                    self.uploads.append(part.get_payload(decode=True))
                else:
                    value = part.get_payload(decode=True).decode()
                    body[key] = {"true": True, "false": False}.get(value, value)
        else:
            body = json.loads(request.content)
        if request.method == "POST":
            if any(r["localId"] == body["localId"] for r in rows.values()):
                return httpx.Response(400, json={"error": "duplicate localId"})
            rid = collection[0] + str(len(rows) + 1)
            rows[rid] = {"id": rid, **body}
            if collection == "media" and self.delete_new_media:
                rows[rid]["isDeleted"] = True
            if collection == "media" and self.lose_media_response:
                self.lose_media_response = False
                raise httpx.ReadTimeout("response lost", request=request)
            return httpx.Response(200, json=rows[rid])
        assert request.method == "PATCH"
        rows[pieces[-1]].update(body)
        return httpx.Response(200, json=rows[pieces[-1]])


@pytest.fixture
def timeline_writer(monkeypatch):
    monkeypatch.setenv("PB_WORKER_TOKEN", "isolated-test-token")
    db = PocketBase()
    memory = PocketBaseMemoryStore()
    memory._client.close()
    memory._client = httpx.Client(base_url="http://pb.invalid", transport=httpx.MockTransport(db.handle))
    writer = PocketBaseTimelineWriter("family-a", "authora", "爸爸", store=memory)
    yield writer, db
    memory.close()


def test_new_photo_is_display_media_and_hash_verified_before_upload(tmp_path, timeline_writer):
    writer, db = timeline_writer
    source = item(tmp_path)
    saved = writer.upsert(source)
    assert saved["media_id"] and saved["entry_id"]
    assert saved["content_hash"] == source["content_hash"] and saved["analysis"] == source["analysis"]
    media = db.records["media"][saved["media_id"]]
    entry = db.records["entries"][saved["entry_id"]]
    assert media["resourceRole"] == "display"
    assert media["contentHash"] == source["content_hash"]
    assert entry["isArchived"] is False and entry["sourceRaw"] == "second-brain-auto"
    assert media["authorUserId"] == "authora" and media["familyId"] == "family-a"
    assert db.uploads == [Path(source["local_path"]).read_bytes()]
    assert writer.upsert(source)["media_id"] == saved["media_id"]
    assert len(db.uploads) == 1


def test_user_edits_survive_later_analysis_revisions(tmp_path, timeline_writer):
    writer, db = timeline_writer
    source = item(tmp_path)
    saved = writer.upsert(source)
    db.records["entries"][saved["entry_id"]].update(note="家人手写的正文", editedAt="2026-10-21")
    source["analysis"]["description"] = "模型更正了画面"
    before = copy.deepcopy(db.records["entries"])
    request_count = len(db.requests)
    assert writer.upsert(source)["media_id"] == saved["media_id"]
    assert before == db.records["entries"]
    assert all(method == "GET" for method, _ in db.requests[request_count:])


@pytest.mark.parametrize("deleted_collection", ["entries", "media"])
def test_same_hash_tombstone_is_never_resurrected(tmp_path, timeline_writer, deleted_collection):
    writer, db = timeline_writer
    source = item(tmp_path)
    saved = writer.upsert(source)
    key = "entry_id" if deleted_collection == "entries" else "media_id"
    db.records[deleted_collection][saved[key]]["isDeleted"] = True
    count = len(db.requests)
    assert writer.upsert(source)["status"] == "tombstoned"
    assert all(method == "GET" for method, _ in db.requests[count:])
    assert len(db.uploads) == 1


def test_upload_response_loss_resumes_without_duplicate_entry_or_file(tmp_path, timeline_writer):
    writer, db = timeline_writer
    source = item(tmp_path)
    db.lose_media_response = True
    with pytest.raises(httpx.ReadTimeout):
        writer.upsert(source)
    assert next(iter(db.records["entries"].values()))["isArchived"] is True
    saved = writer.upsert(source)
    assert saved["status"] == "synced"
    assert len(db.records["entries"]) == len(db.records["media"]) == len(db.uploads) == 1
    assert db.records["entries"][saved["entry_id"]]["isArchived"] is False


def test_changed_source_is_rejected_before_any_mutation(tmp_path, timeline_writer):
    writer, db = timeline_writer
    source = item(tmp_path)
    Path(source["local_path"]).write_bytes(b"changed after bridge snapshot")
    with pytest.raises(TimelineWriteError):
        writer.upsert(source)
    assert all(method == "GET" for method, _ in db.requests)
    assert not db.uploads


def test_author_must_belong_to_configured_family(tmp_path, timeline_writer):
    writer, db = timeline_writer
    db.author_family = "other-family"
    with pytest.raises(TimelineWriteError):
        writer.upsert(item(tmp_path))
    assert not db.records["entries"] and not db.records["media"]


def test_writer_cannot_bypass_manual_identity_gate(tmp_path, timeline_writer):
    writer, db = timeline_writer
    source = item(tmp_path)
    source.update(provenance="gemini_two_pass", confidence=0.99)
    with pytest.raises(TimelineWriteError):
        writer.upsert(source)
    assert not db.requests


def test_manual_same_hash_is_reused_without_any_modification(tmp_path, timeline_writer):
    writer, db = timeline_writer
    source = item(tmp_path)
    db.records["entries"]["existingentry"] = {"id": "existingentry", "localId": "manual-entry",
                                               "familyId": "family-a", "note": "妈妈写的正文"}
    db.records["media"]["existingmedia"] = {"id": "existingmedia", "localId": "manual-media",
                                            "entryLocalId": "manual-entry", "familyId": "family-a",
                                            "contentHash": source["content_hash"], "file": "photo.jpg"}
    before = copy.deepcopy(db.records)
    saved = writer.upsert(source)
    assert saved["media_id"] == "existingmedia" and saved["owned"] is False
    assert before == db.records and not db.uploads


def test_same_hash_in_another_family_is_not_reused(tmp_path, timeline_writer):
    writer, db = timeline_writer
    source = item(tmp_path)
    db.records["media"]["foreignmedia"] = {"id": "foreignmedia", "localId": "foreign-media",
                                           "familyId": "family-b", "contentHash": source["content_hash"]}
    saved = writer.upsert(source)
    assert saved["media_id"] != "foreignmedia"
    assert db.records["media"][saved["media_id"]]["familyId"] == "family-a"


@pytest.mark.parametrize("change", [{"resourceRole": "original"}, {"file": ""}])
def test_invisible_or_incomplete_existing_media_is_not_reported_as_synced(tmp_path, timeline_writer, change):
    writer, db = timeline_writer
    source = item(tmp_path)
    saved = writer.upsert(source)
    db.records["media"][saved["media_id"]].update(change)
    count = len(db.requests)
    assert writer.upsert(source)["status"] == "needs_recheck"
    assert all(method == "GET" for method, _ in db.requests[count:])


def test_pending_moment_stays_hidden_if_media_was_deleted_during_upload(tmp_path, timeline_writer):
    writer, db = timeline_writer
    db.delete_new_media = True
    result = writer.upsert(item(tmp_path))
    assert result["status"] == "tombstoned"
    assert next(iter(db.records["entries"].values()))["isArchived"] is True
