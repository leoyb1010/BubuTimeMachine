from __future__ import annotations

import hashlib
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from intake_staging import IntakeStagingStore
from ssd_intake import SSDIntakeScanner


def test_ssd_scanner_is_read_only_idempotent_and_waits_for_phone_confirmation(tmp_path: Path):
    source = tmp_path / "Bubu Inbox"
    source.mkdir()
    photo = source / "IMG_0001.jpg"
    video = source / "VID_0002.mov"
    photo.write_bytes(b"photo-original")
    video.write_bytes(b"video-original")
    before = {
        path.name: (path.read_bytes(), path.stat().st_mtime_ns)
        for path in (photo, video)
    }

    store = IntakeStagingStore(tmp_path / "staging")
    scanner = SSDIntakeScanner(source, store)
    first = scanner.stage_candidates("family-bubu")
    second = scanner.stage_candidates("family-bubu")

    assert len(first) == 1
    assert second == []
    persisted = store.batch(first[0]["id"])
    assert persisted["state"] == "awaiting_confirmation"
    assert all(item["state"] == "staged" for item in persisted["items"])
    assert all(item["resource_role"] == "display" for item in persisted["items"])
    assert len(persisted["items"]) == 2
    assert {
        path.name: (path.read_bytes(), path.stat().st_mtime_ns)
        for path in (photo, video)
    } == before
    assert (store.root / "manifests" / "latest-scan.json").is_file()

    confirmed = store.confirm(first[0]["id"], "family-bubu", "pb:family-user")
    assert confirmed["state"] == "staged"
    assert store.begin_commit(first[0]["id"], "pb:family-user")["state"] == "committing"


def test_existing_content_hash_is_not_staged_again(tmp_path: Path):
    source = tmp_path / "Bubu Inbox"
    source.mkdir()
    duplicate = source / "already-in-phone.heic"
    duplicate.write_bytes(b"same-content")
    digest = hashlib.sha256(b"same-content").hexdigest()

    store = IntakeStagingStore(tmp_path / "staging")
    scanner = SSDIntakeScanner(source, store)
    assert scanner.stage_candidates("family-bubu", existing_hashes=[digest]) == []
    scan = scanner.scan(existing_hashes=[digest])
    assert scan[0].status == "duplicate"


def test_incremental_scan_does_not_restage_old_files_when_group_changes(tmp_path: Path):
    source = tmp_path / "Bubu Inbox"
    source.mkdir()
    old = source / "old.jpg"
    old.write_bytes(b"old")
    store = IntakeStagingStore(tmp_path / "staging")
    scanner = SSDIntakeScanner(source, store)
    first = scanner.stage_candidates("family-bubu")
    assert len(first) == 1

    new = source / "new.jpg"
    new.write_bytes(b"new")
    second = scanner.stage_candidates("family-bubu")
    assert len(second) == 1
    assert [item["file_name"] for item in second[0]["items"]] == ["new.jpg"]


def test_unsupported_and_symlink_files_are_ignored(tmp_path: Path):
    source = tmp_path / "Bubu Inbox"
    source.mkdir()
    (source / "notes.txt").write_text("not media", encoding="utf-8")
    outside = tmp_path / "outside.jpg"
    outside.write_bytes(b"outside")
    (source / "linked.jpg").symlink_to(outside)

    scanner = SSDIntakeScanner(source, IntakeStagingStore(tmp_path / "staging"))
    assert scanner.scan() == []


def test_ssd_scan_obeys_copy_budget_without_touching_source(tmp_path: Path, monkeypatch):
    source = tmp_path / "Bubu Inbox"
    source.mkdir()
    photo = source / "large.jpg"
    photo.write_bytes(b"original")
    monkeypatch.setenv("INTAKE_SSD_SCAN_BUDGET_BYTES", "1")

    scanner = SSDIntakeScanner(source, IntakeStagingStore(tmp_path / "staging"))
    assert scanner.stage_candidates("family-bubu") == []
    assert photo.read_bytes() == b"original"


def test_oversized_first_file_does_not_starve_later_small_file(tmp_path: Path, monkeypatch):
    source = tmp_path / "Bubu Inbox"
    source.mkdir()
    too_large = source / "00-large.mov"
    later = source / "01-small.jpg"
    too_large.write_bytes(b"123456")
    later.write_bytes(b"x")
    monkeypatch.setenv("INTAKE_SSD_SCAN_BUDGET_BYTES", "5")
    monkeypatch.setenv("INTAKE_MIN_FREE_BYTES", "0")

    store = IntakeStagingStore(tmp_path / "staging")
    batches = SSDIntakeScanner(source, store).stage_candidates("family-bubu")

    assert len(batches) == 1
    assert [item["file_name"] for item in batches[0]["items"]] == ["01-small.jpg"]
    manifest = (store.root / "manifests" / "latest-scan.json").read_text(encoding="utf-8")
    assert '"relative_path": "00-large.mov"' in manifest
    assert '"status": "deferred"' in manifest
    assert '"error": "scan_budget_exhausted"' in manifest


def test_large_event_is_split_at_server_item_limit(tmp_path: Path, monkeypatch):
    source = tmp_path / "Bubu Inbox"
    source.mkdir()
    for index in range(501):
        (source / f"IMG_{index:04d}.jpg").write_bytes(f"photo-{index}".encode())
    monkeypatch.setenv("INTAKE_MIN_FREE_BYTES", "0")

    batches = SSDIntakeScanner(
        source, IntakeStagingStore(tmp_path / "staging")
    ).stage_candidates("family-bubu")

    assert sorted(len(batch["items"]) for batch in batches) == [1, 500]


def test_ignored_hash_survives_cleanup_and_never_reappears(tmp_path: Path):
    source = tmp_path / "Bubu Inbox"
    source.mkdir()
    photo = source / "ignored.jpg"
    photo.write_bytes(b"ignore-me")
    store = IntakeStagingStore(tmp_path / "staging")
    scanner = SSDIntakeScanner(source, store)
    batch = scanner.stage_candidates("family-bubu")[0]
    store.cancel(batch["id"], "family-bubu")
    with sqlite3.connect(store.db_path) as db:
        db.execute(
            "UPDATE batches SET updated_at=? WHERE id=?", (time.time() - 7200, batch["id"])
        )
    store.cleanup(older_than_seconds=3600)
    assert store.batch(batch["id"])["state"] == "cancelled"
    assert scanner.stage_candidates("family-bubu") == []
