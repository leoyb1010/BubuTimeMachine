from __future__ import annotations

import hashlib
import os
import sqlite3
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from intake_staging import (
    IntakeConflict,
    IntakeError,
    IntakeItem,
    IntakeStagingStore,
    issue_upload_token,
    verify_upload_token,
)


def item(size: int) -> IntakeItem:
    return IntakeItem(
        asset_key="asset-key-0001",
        file_name="IMG_0001.HEIC",
        media_type="photo",
        captured_at="2026-08-06T00:00:00Z",
        expected_size=size,
        expected_mime="image/heic",
    )


def create(store: IntakeStagingStore, size: int = 5):
    return store.create_batch(
        "batch-id-0001",
        "pb:family-user",
        "family-bubu",
        {
            "local_id": "entry-id-0001",
            "happened_at": "2026-08-06T00:00:00Z",
            "author_role": "爸爸",
        },
        [item(size)],
    )


def temporary(root: Path, data: bytes) -> Path:
    path = root / ("upload-" + hashlib.sha256(data).hexdigest()[:8] + ".part")
    path.write_bytes(data)
    return path


def test_batch_creation_is_idempotent_but_content_change_conflicts(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    first = create(store)
    second = create(store)
    assert first["id"] == second["id"]
    assert second["state"] == "accepted"

    with pytest.raises(IntakeConflict):
        store.create_batch(
            "batch-id-0001", "pb:family-user", "family-bubu",
            {"local_id": "different-entry"}, [item(5)],
        )


def test_verified_upload_converges_and_entire_batch_becomes_staged(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    data = b"bubu!"
    create(store, len(data))
    store.mark_uploading("batch-id-0001", "asset-key-0001")
    digest = hashlib.sha256(data).hexdigest()

    result = store.stage_file(
        "batch-id-0001", "asset-key-0001", temporary(tmp_path, data), digest, len(data)
    )
    assert result["state"] == "staged"
    assert result["items"][0]["content_hash"] == digest

    # A repeated system callback with the same bytes is a no-op, not a second item.
    repeated = store.stage_file(
        "batch-id-0001", "asset-key-0001", temporary(tmp_path, data), digest, len(data)
    )
    assert repeated["state"] == "staged"
    assert len(repeated["items"]) == 1


def test_wrong_size_never_reaches_staged_state(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    create(store, 8)
    data = b"short"
    with pytest.raises(IntakeConflict):
        store.stage_file(
            "batch-id-0001", "asset-key-0001", temporary(tmp_path, data),
            hashlib.sha256(data).hexdigest(), len(data),
        )
    assert store.batch("batch-id-0001")["state"] == "failed"


def test_only_fully_staged_batch_can_commit_and_retry_is_idempotent(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    data = b"bubu!"
    create(store, len(data))
    with pytest.raises(IntakeConflict):
        store.begin_commit("batch-id-0001", "pb:family-user")

    digest = hashlib.sha256(data).hexdigest()
    store.stage_file(
        "batch-id-0001", "asset-key-0001", temporary(tmp_path, data), digest, len(data)
    )
    manifest = store.begin_commit("batch-id-0001", "pb:family-user")
    assert manifest["state"] == "committing"
    assert Path(manifest["items"][0]["stored_path"]).read_bytes() == data

    done = store.finish_commit("batch-id-0001", "pb:family-user", "pb-entry-id")
    assert done["state"] == "committed"
    assert not (store.files / "batch-id-0001").exists()
    assert store.begin_commit("batch-id-0001", "pb:family-user")["committed_entry_id"] == "pb-entry-id"


def test_upload_capability_is_bound_to_batch_asset_owner_and_expiry(monkeypatch):
    monkeypatch.setenv("INTAKE_UPLOAD_SECRET", "x" * 64)
    token = issue_upload_token("batch-id-0001", "asset-key-0001", "pb:family-user")
    assert verify_upload_token(token, "batch-id-0001", "asset-key-0001", "pb:family-user")
    assert not verify_upload_token(token, "batch-id-0002", "asset-key-0001", "pb:family-user")
    assert not verify_upload_token(token, "batch-id-0001", "asset-key-0002", "pb:family-user")
    assert not verify_upload_token(token, "batch-id-0001", "asset-key-0001", "pb:other-user")

    expires, signature = token.split(".", 1)
    expired = f"{int(time.time()) - 1}.{signature}"
    assert not verify_upload_token(expired, "batch-id-0001", "asset-key-0001", "pb:family-user")


def test_staging_permissions_are_private(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    create(store)
    assert oct(store.root.stat().st_mode & 0o777) == "0o700"
    assert oct(store.db_path.stat().st_mode & 0o777) == "0o600"
    wal = Path(str(store.db_path) + "-wal")
    if wal.exists():
        assert oct(wal.stat().st_mode & 0o777) == "0o600"


def test_staged_item_cannot_be_downgraded_by_conflicting_retry(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    data = b"bubu!"
    create(store, len(data))
    digest = hashlib.sha256(data).hexdigest()
    store.stage_file(
        "batch-id-0001", "asset-key-0001", temporary(tmp_path, data), digest, len(data)
    )
    store.fail_item("batch-id-0001", "asset-key-0001", "late_conflict")
    result = store.batch("batch-id-0001")
    assert result["state"] == "staged"
    assert result["items"][0]["state"] == "staged"


def test_commit_revalidates_hash_size_and_rejects_symlink(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    data = b"bubu!"
    create(store, len(data))
    digest = hashlib.sha256(data).hexdigest()
    store.stage_file(
        "batch-id-0001", "asset-key-0001", temporary(tmp_path, data), digest, len(data)
    )
    path = next((store.files / "batch-id-0001").iterdir())
    path.write_bytes(b"other")
    with pytest.raises(IntakeConflict):
        store.begin_commit("batch-id-0001", "pb:family-user")

    # reset the state left by begin_commit, then prove symlink escape is rejected too.
    store.reset_commit("batch-id-0001", "pb:family-user", "test")
    path.unlink()
    outside = tmp_path / "outside.heic"
    outside.write_bytes(data)
    path.symlink_to(outside)
    with pytest.raises(IntakeConflict):
        store.begin_commit("batch-id-0001", "pb:family-user")


def test_stale_committing_batch_is_recoverable_and_retry_safe(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    data = b"bubu!"
    create(store, len(data))
    store.stage_file(
        "batch-id-0001", "asset-key-0001", temporary(tmp_path, data),
        hashlib.sha256(data).hexdigest(), len(data),
    )
    store.begin_commit("batch-id-0001", "pb:family-user")
    with sqlite3.connect(store.db_path) as db:
        db.execute(
            "UPDATE batches SET updated_at=? WHERE id=?",
            (time.time() - 600, "batch-id-0001"),
        )
    assert store.recover_stale_commits(older_than_seconds=60) == 1
    assert store.batch("batch-id-0001")["state"] == "staged"


def test_pending_ssd_candidate_time_can_be_edited_or_cancelled(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    store.create_batch(
        "batch-id-0001", "service:ssd", "family-bubu",
        {"local_id": "entry-id-0001", "happened_at": "2026-01-01T00:00:00Z",
         "source": "ssd-bubu-inbox"},
        [item(5)], confirmed=False,
    )
    data = b"bubu!"
    store.stage_file(
        "batch-id-0001", "asset-key-0001", temporary(tmp_path, data),
        hashlib.sha256(data).hexdigest(), len(data),
    )
    updated = store.update_candidate_time(
        "batch-id-0001", "family-bubu", "2025-05-22T08:00:00Z"
    )
    assert updated["entry"]["happened_at"] == "2025-05-22T08:00:00Z"
    store.confirm("batch-id-0001", "family-bubu", "pb:family-user")
    store.begin_commit("batch-id-0001", "pb:family-user")
    store.reset_candidate_confirmation("batch-id-0001", "family-bubu")
    assert store.batch("batch-id-0001")["state"] == "awaiting_confirmation"
    assert store.cancel("batch-id-0001", "family-bubu")["state"] == "cancelled"


def test_cancelled_batch_rejects_late_upload_with_still_valid_token(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    create(store, 5)
    store.cancel("batch-id-0001", "family-bubu")
    with pytest.raises(IntakeConflict):
        store.mark_uploading("batch-id-0001", "asset-key-0001")
    data = b"bubu!"
    late = temporary(tmp_path, data)
    with pytest.raises(IntakeConflict):
        store.stage_file(
            "batch-id-0001", "asset-key-0001", late,
            hashlib.sha256(data).hexdigest(), len(data),
        )
    late.unlink(missing_ok=True)
    assert store.batch("batch-id-0001")["state"] == "cancelled"


def test_unstaged_ssd_candidate_is_hidden_and_cannot_be_confirmed(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    store.create_batch(
        "batch-id-0001", "service:ssd", "family-bubu",
        {"local_id": "entry-id-0001", "happened_at": "2026-01-01T00:00:00Z",
         "source": "ssd-bubu-inbox"},
        [item(5)], confirmed=False,
    )
    assert store.ready_family_candidates("family-bubu") == []
    with pytest.raises(IntakeConflict):
        store.confirm("batch-id-0001", "family-bubu", "pb:family-user")


def test_partial_ssd_copy_can_be_abandoned_and_retried(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    second = IntakeItem(
        asset_key="asset-key-0002", file_name="IMG_0002.HEIC", media_type="photo",
        captured_at="2026-08-06T00:01:00Z", expected_size=5, expected_mime="image/heic",
    )
    store.create_batch(
        "batch-id-0001", "service:ssd-inbox", "family-bubu",
        {"local_id": "entry-id-0001", "happened_at": "2026-08-06T00:00:00Z",
         "source": "ssd-bubu-inbox"},
        [item(5), second], confirmed=False,
    )
    data = b"bubu!"
    store.stage_file(
        "batch-id-0001", "asset-key-0001", temporary(tmp_path, data),
        hashlib.sha256(data).hexdigest(), len(data),
    )

    assert store.known_hashes("family-bubu") == set()
    store.abandon_unconfirmed("batch-id-0001", "family-bubu")
    with pytest.raises(IntakeError, match="batch not found"):
        store.batch("batch-id-0001")
    assert not (store.files / "batch-id-0001").exists()
