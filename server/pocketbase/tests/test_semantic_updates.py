"""Real PocketBase hooks + worker + SQLite index, with only the image encoder faked."""
import io
import sys
from pathlib import Path

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "server/ai"))
from server.pocketbase.tests import test_family_isolation as pb_tests
from semantic_index import SemanticIndex
from semantic_worker import PocketBaseWorkerClient, SemanticWorker


@pytest.fixture
def semantic_pipeline(monkeypatch, tmp_path):
    database = pb_tests.FamilyIsolationIntegrationTests()
    worker_client = None
    try:
        database.setUp()
        monkeypatch.setenv("PB_BASE_URL", database.base)
        monkeypatch.setenv("PB_WORKER_TOKEN", database.admin)
        monkeypatch.setenv("SEMANTIC_FAMILY_ID", database.family_a)
        worker_client = PocketBaseWorkerClient()
        class Encoder:
            model_version = "synthetic-v1"
            def encode_image(self, path):
                assert Path(path).is_file()
                return [1.0, 0.0]
        index = SemanticIndex(tmp_path / "index.sqlite", Encoder.model_version)
        worker = SemanticWorker(worker_client, index, Encoder())
        encoded = io.BytesIO()
        Image.new("RGB", (4, 4), "blue").save(encoded, "JPEG")
        media = {}
        for suffix, family in [("a", database.family_a), ("b", database.family_b)]:
            status, media[suffix] = database.multipart(
                "/api/collections/media/records",
                {"localId": "semantic-" + suffix, "familyId": family,
                 "entryLocalId": suffix, "mediaType": "photo"},
                "file", "photo.jpg", encoded.getvalue(), database.admin,
            )
            assert status == 200
        yield database, media, worker, index
    finally:
        if worker_client:
            worker_client.close()
        database.doCleanups()


def drain(database, worker):
    for _ in range(30):
        if worker.run_once() == 0:
            break
    else:
        pytest.fail("semantic queue did not converge")
    status, result = database.call("GET", "/api/collections/automation_jobs/records?perPage=200", token=database.admin)
    assert status == 200
    assert all(job["state"] == "done" for job in result["items"]), [job["state"] for job in result["items"]]


def update(database, collection, record_id, changes, token=None):
    status, result = database.call("PATCH", "/api/collections/" + collection + "/records/" + record_id,
                                   changes, token or database.token_a)
    assert status == 200, result


def test_metadata_corrections_rebuild_without_sync_touch_churn(semantic_pipeline):
    database, media, worker, index = semantic_pipeline
    drain(database, worker)
    initial = len(database.jobs_for(media["a"]["id"]))
    assert initial == 1
    update(database, "entries", database.entry_a["id"],
           {"note": "海边散步", "title": "第一次看海", "locationName": "沙滩",
            "happenedAt": "2026-09-09 00:00:00.000Z"})
    update(database, "media", media["a"]["id"], {"aiTags": ["贝壳", "海浪"]})
    drain(database, worker)
    hit = index.search("海边", [1, 0], family_id=database.family_a)[0]
    assert "海边散步" in hit.caption
    assert "沙滩" in hit.caption
    assert hit.captured_at.startswith("2026-09-09")
    assert hit.tags == ("贝壳", "海浪")
    revised = len(database.jobs_for(media["a"]["id"]))
    assert revised == initial + 2
    for changes in ({"width": 100}, {"height": 200}, {"clientUpdatedAt": "2026-09-12 00:00:00.000Z"},
                    {"aiTags": ["贝壳", "海浪"]}):
        update(database, "media", media["a"]["id"], changes)
    for changes in ({"authorRole": "妈妈"}, {"clientUpdatedAt": "2026-09-12 00:00:00.000Z"},
                    {"note": "海边散步"}):
        update(database, "entries", database.entry_a["id"], changes)
    assert len(database.jobs_for(media["a"]["id"])) == revised
    assert worker.run_once() == 0


def test_entry_deletion_and_restore_refresh_only_its_family(semantic_pipeline):
    database, media, worker, index = semantic_pipeline
    drain(database, worker)
    other_jobs = database.jobs_for(media["b"]["id"])
    update(database, "entries", database.entry_a["id"], {"isDeleted": True})
    drain(database, worker)
    assert index.search("synthetic", [1, 0], family_id=database.family_a) == []
    assert len(index.search("synthetic", [1, 0], family_id=database.family_b)) == 1
    assert database.jobs_for(media["b"]["id"]) == other_jobs
    # Ordinary users still cannot undelete/transfer facts. Admin restore wakes the old signature.
    status, _ = database.call("PATCH", "/api/collections/entries/records/" + database.entry_a["id"],
                              {"isDeleted": False}, database.token_a)
    assert status >= 400
    update(database, "entries", database.entry_a["id"], {"isDeleted": False}, database.admin)
    drain(database, worker)
    assert len(index.search("synthetic", [1, 0], family_id=database.family_a)) == 1
    assert len(database.jobs_for(media["a"]["id"])) == 2


def test_correction_while_old_job_is_running_eventually_wins(semantic_pipeline):
    database, media, worker, index = semantic_pipeline
    original_encode = worker.encoder.encode_image
    changed = False
    def encode_after_correction(path):
        nonlocal changed
        if not changed:
            changed = True
            update(database, "entries", database.entry_a["id"], {"note": "更正后的文字"})
        return original_encode(path)
    worker.encoder.encode_image = encode_after_correction
    drain(database, worker)
    hit = index.search("更正", [1, 0], family_id=database.family_a)[0]
    assert "更正后的文字" in hit.caption
    assert len(database.jobs_for(media["a"]["id"])) == 2


@pytest.mark.parametrize("changes", [{"resourceRole": "original"}, {"mediaType": "audio"}])
def test_no_longer_searchable_media_is_removed(semantic_pipeline, changes):
    database, media, worker, index = semantic_pipeline
    drain(database, worker)
    update(database, "media", media["a"]["id"], changes)
    drain(database, worker)
    assert index.search("synthetic", [1, 0], family_id=database.family_a) == []
    assert len(index.search("synthetic", [1, 0], family_id=database.family_b)) == 1


def test_late_entry_creation_wakes_its_preexisting_media(semantic_pipeline):
    database, media, worker, index = semantic_pipeline
    drain(database, worker)
    update(database, "media", media["a"]["id"], {"entryLocalId": "late-entry"})
    drain(database, worker)
    assert index.search("synthetic", [1, 0], family_id=database.family_a) == []
    database.create("entries", {**database.entry("late-entry", database.family_a), "note": "迟到的关联记录"})
    drain(database, worker)
    assert "迟到的关联记录" in index.search("迟到", [1, 0], family_id=database.family_a)[0].caption


def test_entry_membership_change_removes_old_family_index(semantic_pipeline):
    database, media, worker, index = semantic_pipeline
    drain(database, worker)
    update(database, "entries", database.entry_a["id"], {"familyId": database.family_b}, database.admin)
    drain(database, worker)
    assert index.search("synthetic", [1, 0], family_id=database.family_a) == []
    hits = index.search("synthetic", [1, 0], family_id=database.family_b)
    assert [hit.media_record_id for hit in hits] == [media["b"]["id"]]


def test_new_audio_and_original_only_media_do_not_queue(semantic_pipeline):
    database, _, worker, _ = semantic_pipeline
    drain(database, worker)
    for suffix, changes in [("audio", {"mediaType": "audio"}),
                            ("original", {"mediaType": "photo", "resourceRole": "original"})]:
        media = database.create("media", {"localId": "ignored-" + suffix, "entryLocalId": "a",
                                          "familyId": database.family_a, **changes})
        assert database.jobs_for(media["id"]) == []
    assert worker.run_once() == 0
