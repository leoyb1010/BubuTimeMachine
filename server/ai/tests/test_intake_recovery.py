"""Restart/lease regressions using only a synthetic local staging database."""
import hashlib
import time
import subprocess
import sys
from pathlib import Path
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main
from intake_staging import IntakeConflict, IntakeStagingStore
from test_intake_staging import create, temporary


def staged_store(tmp_path):
    store = IntakeStagingStore(tmp_path / "staging")
    create(store)
    data = b"bubu!"
    store.stage_file("batch-id-0001", "asset-key-0001", temporary(tmp_path, data),
                     hashlib.sha256(data).hexdigest(), len(data))
    return store


def test_immediate_restart_eventually_recovers_commit_and_can_retry(monkeypatch, tmp_path):
    store = staged_store(tmp_path)
    store.begin_commit("batch-id-0001", "pb:family-user")
    started = time.time()
    monkeypatch.setattr(main, "_intake_store", None)
    monkeypatch.setattr(main, "IntakeStagingStore", lambda: store)
    monkeypatch.setattr("intake_staging.time.time", lambda: started + 1)
    assert main._intake_components().batch("batch-id-0001")["state"] == "committing"
    monkeypatch.setattr("intake_staging.time.time", lambda: started + 601)
    recovered = main._intake_components()
    assert recovered.batch("batch-id-0001")["state"] == "staged"
    assert recovered.begin_commit("batch-id-0001", "pb:family-user")["state"] == "committing"


def test_live_slow_commit_is_not_recovered_by_another_store(monkeypatch, tmp_path):
    store = staged_store(tmp_path)
    other_process_store = IntakeStagingStore(store.root)
    started = time.time()
    monkeypatch.setenv("INTAKE_COMMIT_KEY", "synthetic-test-key-00000000000000000")

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, *args, **kwargs):
            monkeypatch.setattr("intake_staging.time.time", lambda: started + 601)
            assert other_process_store.recover_stale_commits() == 0
            assert other_process_store.batch("batch-id-0001")["state"] == "committing"
            class Response:
                status_code = 201
                def json(self):
                    return {"entry_id": "synthetic-entry"}
            return Response()

    monkeypatch.setattr(main.httpx, "Client", Client)
    assert main._commit_staged_batch(store, "batch-id-0001", "pb:family-user")["state"] == "committed"


def test_commit_lock_survives_live_process_and_is_released_on_exit(monkeypatch, tmp_path):
    store = staged_store(tmp_path)
    program = """
import sys
from intake_staging import IntakeStagingStore
from pathlib import Path
store = IntakeStagingStore(Path(sys.argv[1]))
with store.commit_lock('batch-id-0001'):
    store.begin_commit('batch-id-0001', 'pb:family-user')
    print('locked', flush=True)
    sys.stdin.read()
"""
    process = subprocess.Popen([sys.executable, "-c", program, str(store.root)],
                               cwd=Path(main.__file__).parent,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        assert process.stdout.readline().strip() == "locked"
        future = time.time() + 601
        monkeypatch.setattr("intake_staging.time.time", lambda: future)
        assert store.recover_stale_commits() == 0
        process.terminate()
        process.wait(timeout=5)
        assert store.recover_stale_commits() == 1
        assert store.batch("batch-id-0001")["state"] == "staged"
    finally:
        if process.poll() is None:
            process.kill()
        process.communicate(timeout=5)


def test_candidate_confirmation_conflict_does_not_reset_live_commit(monkeypatch, tmp_path):
    store = staged_store(tmp_path)
    confirmed = store.batch("batch-id-0001")
    store.begin_commit("batch-id-0001", "pb:family-user")
    monkeypatch.setattr(main, "_intake_components", lambda: store)
    monkeypatch.setattr(main, "_intake_family_id", lambda: "family-bubu")
    # This request confirmed just before another request acquired the commit lock.
    monkeypatch.setattr(store, "confirm", lambda *args: confirmed)
    def already_running(*args):
        raise IntakeConflict("batch commit is already running")
    monkeypatch.setattr(main, "_commit_staged_batch", already_running)
    with pytest.raises(main.HTTPException) as caught:
        main.intake_confirm(main.IntakeBatchCommitReq(batch_id="batch-id-0001"), "pb:family-user")
    assert caught.value.status_code == 409
    assert store.batch("batch-id-0001")["state"] == "committing"


@pytest.mark.parametrize("other_is_committing", [False, True])
def test_stale_confirmation_failure_cannot_demote_another_owner(monkeypatch, tmp_path, other_is_committing):
    store = staged_store(tmp_path)
    confirmed = store.confirm("batch-id-0001", "family-bubu", "pb:family-user")
    store.confirm("batch-id-0001", "family-bubu", "pb:other-user")
    actual_commit = main._commit_staged_batch
    held = []
    def failure_after_owner_changed(*args):
        try:
            return actual_commit(*args)
        except main.IntakeError:
            if other_is_committing:
                lock = store.commit_lock("batch-id-0001")
                lock.__enter__()
                held.append(lock)
                store.begin_commit("batch-id-0001", "pb:other-user")
            raise
    monkeypatch.setattr(main, "_intake_components", lambda: store)
    monkeypatch.setattr(main, "_intake_family_id", lambda: "family-bubu")
    monkeypatch.setattr(store, "confirm", lambda *args: confirmed)
    monkeypatch.setattr(main, "_commit_staged_batch", failure_after_owner_changed)
    try:
        with pytest.raises(main.HTTPException) as caught:
            main.intake_confirm(main.IntakeBatchCommitReq(batch_id="batch-id-0001"), "pb:family-user")
        assert caught.value.status_code == 503
        row = store.batch("batch-id-0001")
        assert row["owner"] == "pb:other-user"
        assert row["state"] == ("committing" if other_is_committing else "staged")
    finally:
        for lock in held:
            lock.__exit__(None, None, None)


def test_old_failure_cleanup_cannot_reset_same_owner_live_retry(tmp_path):
    store = staged_store(tmp_path)
    store.begin_commit("batch-id-0001", "pb:family-user")
    with store.commit_lock("batch-id-0001"):
        store.reset_commit("batch-id-0001", "pb:family-user", "old-network-failure")
        assert store.batch("batch-id-0001")["state"] == "committing"


def test_manifest_failure_inside_commit_lock_still_resets_and_releases(tmp_path):
    store = staged_store(tmp_path)
    for path in (store.files / "batch-id-0001").iterdir():
        path.write_bytes(b"wrong")
    with pytest.raises(IntakeConflict):
        main._commit_staged_batch(store, "batch-id-0001", "pb:family-user")
    assert store.batch("batch-id-0001")["state"] == "failed"
    with store.commit_lock("batch-id-0001"):
        pass
