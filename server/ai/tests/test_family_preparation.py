import importlib.util
import sqlite3
from pathlib import Path

import pytest


spec = importlib.util.spec_from_file_location("family_preparation", Path(__file__).resolve().parents[2] / "ops/prepare_family_ownership.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture(path):
    with sqlite3.connect(path) as db:
        db.execute("CREATE TABLE families(id TEXT PRIMARY KEY, name TEXT NOT NULL)")
        db.execute("CREATE TABLE users(id TEXT PRIMARY KEY, familyId TEXT, password TEXT)")
        db.execute("CREATE TABLE entries(id TEXT PRIMARY KEY, familyId TEXT, note TEXT, updated TEXT)")
        db.execute("INSERT INTO users VALUES ('user-a', '', 'untouched-password-hash')")
        db.execute("INSERT INTO entries VALUES ('entry-a', 'legacy', 'keep this note', 'original-time')")
        db.execute("INSERT INTO entries VALUES ('entry-b', '', 'also keep', 'original-time')")


def test_preview_and_apply_preserve_every_nonownership_field(tmp_path):
    path = tmp_path / "data.db"
    fixture(path)
    before = module.prepare(path, "legacy", 1)
    assert not before["applied"]
    result = module.prepare(path, "legacy", 1, True, tmp_path / "backup.db", before["protected_sha256"])
    assert result["applied"]
    assert result["protected_sha256"] == before["protected_sha256"]
    with sqlite3.connect(path) as db:
        assert db.execute("SELECT count(distinct familyId) FROM entries").fetchone() == (1,)
        assert db.execute("SELECT password FROM users").fetchone() == ("untouched-password-hash",)
        assert db.execute("SELECT familyId FROM users").fetchone() == (result["family_id"],)
    with sqlite3.connect(tmp_path / "backup.db") as db:
        assert db.execute("SELECT count(*) FROM families").fetchone() == (0,)
    # Repeating against the canonical family is idempotent and creates no extra family.
    preview = module.prepare(path, "legacy", 1)
    again = module.prepare(path, "legacy", 1, True, tmp_path / "second.db", preview["protected_sha256"])
    assert again["family_id"] == result["family_id"]


def test_unexpected_owner_or_multiple_families_refuse_without_writing(tmp_path):
    path = tmp_path / "data.db"
    fixture(path)
    with pytest.raises(ValueError, match="unexpected"):
        module.prepare(path, "wrong-owner", 1)
    with sqlite3.connect(path) as db:
        db.executemany("INSERT INTO families VALUES (?,?)", [("aaaaaaaaaaaaaaa", "A"), ("bbbbbbbbbbbbbbb", "B")])
    with pytest.raises(ValueError, match="multiple families"):
        module.prepare(path, "legacy", 1)


def test_stale_preview_and_backup_reuse_refuse(tmp_path):
    path = tmp_path / "data.db"
    fixture(path)
    preview = module.prepare(path, "legacy", 1)
    with sqlite3.connect(path) as db:
        db.execute("UPDATE entries SET note='new edit' WHERE id='entry-a'")
    with pytest.raises(ValueError, match="facts changed"):
        module.prepare(path, "legacy", 1, True, tmp_path / "backup.db", preview["protected_sha256"])
    preview = module.prepare(path, "legacy", 1)
    backup = tmp_path / "backup.db"
    backup.write_bytes(b"preserve")
    with pytest.raises(ValueError, match="fresh separate"):
        module.prepare(path, "legacy", 1, True, backup, preview["protected_sha256"])
    assert backup.read_bytes() == b"preserve"


def test_sidecar_keeps_pending_upload_payload_and_embeddings(tmp_path):
    for table in ("batches", "semantic_assets"):
        path = tmp_path / (table + ".db")
        with sqlite3.connect(path) as db:
            db.execute(f"CREATE TABLE {table}(id TEXT, family_id TEXT, payload BLOB)")
            db.execute(f"INSERT INTO {table} VALUES ('item','legacy',?)", (b"keep-original-payload",))
        result = module.prepare_sidecar(path, table, "legacy", "canonical", tmp_path / (table + "-before.db"))
        assert result == {"rows": 1, "content_preserved": True}
        with sqlite3.connect(path) as db:
            assert db.execute(f"SELECT family_id,payload FROM {table}").fetchone() == ("canonical", b"keep-original-payload")
