#!/usr/bin/env python3
"""Prepare one explicitly selected legacy family without changing any family facts.

Default is read-only. Apply during the service maintenance window, after a media
backup/restore drill. A fresh SQLite snapshot and exact protected-field fingerprint
are required before the only allowed writes: families + familyId ownership fields.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import secrets
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


TABLES = (
    "users", "entries", "media", "comments", "voicenotes", "milestones", "firsttimes",
    "voicememos", "members", "childprofile", "healthrecords", "timecapsules", "feed_events",
    "vaccinerecords", "growthmeasurements", "automation_jobs", "derived_artifacts",
)


def inspect(db):
    counts, identifiers = {}, set()
    digest = hashlib.sha256()
    existing = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for table in TABLES:
        if table not in existing:
            continue
        columns = [r[1] for r in db.execute(f'PRAGMA table_info("{table}")')]
        if "familyId" not in columns:
            raise ValueError(f"missing familyId: {table}")
        protected = [name for name in columns if name != "familyId"]
        select = ",".join('"' + name.replace('"', '""') + '"' for name in protected)
        rows = db.execute(f'SELECT {select} FROM "{table}" ORDER BY id').fetchall()
        counts[table] = len(rows)
        digest.update(table.encode())
        for row in rows:
            values = [value.hex() if isinstance(value, bytes) else value for value in row]
            digest.update(json.dumps(values, ensure_ascii=False, separators=(",", ":")).encode())
            digest.update(b"\n")
        identifiers.update(r[0] for r in db.execute(f'SELECT DISTINCT familyId FROM "{table}"') if r[0])
    families = db.execute("SELECT id FROM families ORDER BY id").fetchall()
    return {"counts": counts, "protected_sha256": digest.hexdigest(),
            "families": [r[0] for r in families], "ownership_ids": sorted(identifiers)}


def prepare(database, legacy_id, expected_users, apply=False, backup=None, expected_sha=None):
    database = Path(database).resolve(strict=True)
    # Do not create a missing database by accident.
    mode = "rw" if apply else "ro"
    with sqlite3.connect(database.as_uri() + "?mode=" + mode, uri=True, timeout=10) as db:
        before = inspect(db)
        if before["counts"].get("users") != expected_users:
            raise ValueError("user count changed; inspect again before assigning ownership")
        if len(before["families"]) > 1:
            raise ValueError("multiple families require explicit per-record assignment")
        canonical = before["families"][0] if before["families"] else secrets.token_hex(8)[:15]
        if not re.fullmatch(r"[a-z0-9]{15}", canonical):
            raise ValueError("canonical family id is not a valid PocketBase record id")
        if set(before["ownership_ids"]) - {legacy_id, canonical}:
            raise ValueError("unexpected family ownership; no records changed")
        result = {"counts": before["counts"], "protected_sha256": before["protected_sha256"],
                  "existing_families": len(before["families"]), "applied": False}
        if not apply:
            return result
        if not expected_sha or expected_sha != before["protected_sha256"]:
            raise ValueError("facts changed since preview; no records changed")
        if backup is None:
            raise ValueError("a new SQLite backup path is required")
        backup = Path(backup).resolve()
        if backup.exists() or backup == database:
            raise ValueError("backup must be a fresh separate file")
        backup.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Reserve the path without replacing an earlier safety snapshot.
        with backup.open("xb"):
            pass
        backup.chmod(0o600)
        with sqlite3.connect(backup) as copy:
            db.backup(copy)
            if copy.execute("PRAGMA integrity_check").fetchone() != ("ok",):
                raise ValueError("backup integrity check failed")
            if inspect(copy) != before:
                raise ValueError("backup differs from preview")
        db.execute("BEGIN IMMEDIATE")
        if inspect(db) != before:
            raise ValueError("database changed before write lock; retry from preview")
        if not before["families"]:
            fields = {r[1] for r in db.execute("PRAGMA table_info(families)")}
            payload = {"id": canonical, "name": "布布的家"}
            for field in ("created", "updated"):
                if field in fields:
                    payload[field] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.000Z")
            names = ",".join('"' + name + '"' for name in payload)
            db.execute(f"INSERT INTO families ({names}) VALUES ({','.join('?' for _ in payload)})", list(payload.values()))
        for table in before["counts"]:
            db.execute(f'UPDATE "{table}" SET familyId=? WHERE familyId IS NULL OR familyId IN (?,?)',
                       (canonical, "", legacy_id))
        after = inspect(db)
        if after["counts"] != before["counts"] or after["protected_sha256"] != before["protected_sha256"]:
            raise ValueError("protected facts changed; transaction rolled back")
        if set(after["ownership_ids"]) - {canonical}:
            raise ValueError("ownership remains inconsistent; transaction rolled back")
        db.commit()
        result.update({"applied": True, "family_id": canonical, "backup": str(backup)})
        return result


def prepare_sidecar(database, table, legacy_id, canonical_id, backup):
    """Move derived search/upload ownership while keeping embeddings, payloads and files intact."""
    if table not in {"semantic_assets", "batches"}:
        raise ValueError("unsupported sidecar table")
    database = Path(database).resolve(strict=True)
    backup = Path(backup).resolve()
    if backup.exists() or backup == database:
        raise ValueError("sidecar backup must be a fresh separate file")
    with sqlite3.connect(database.as_uri() + "?mode=rw", uri=True, timeout=10) as db:
        fields = [r[1] for r in db.execute(f'PRAGMA table_info("{table}")')]
        if "family_id" not in fields:
            raise ValueError("sidecar has no family_id")
        names = ",".join('"' + name + '"' for name in fields if name != "family_id")
        before = db.execute(f'SELECT {names} FROM "{table}" ORDER BY rowid').fetchall()
        owners = {r[0] for r in db.execute(f'SELECT DISTINCT family_id FROM "{table}"') if r[0]}
        if owners - {legacy_id, canonical_id}:
            raise ValueError("unexpected sidecar ownership")
        backup.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with backup.open("xb"):
            pass
        backup.chmod(0o600)
        with sqlite3.connect(backup) as destination:
            db.backup(destination)
            if destination.execute("PRAGMA integrity_check").fetchone() != ("ok",):
                raise ValueError("sidecar snapshot failed integrity check")
        db.execute("BEGIN IMMEDIATE")
        if before != db.execute(f'SELECT {names} FROM "{table}" ORDER BY rowid').fetchall():
            raise ValueError("sidecar changed before lock")
        db.execute(f'UPDATE "{table}" SET family_id=? WHERE family_id IN (?,?) OR family_id IS NULL',
                   (canonical_id, "", legacy_id))
        if before != db.execute(f'SELECT {names} FROM "{table}" ORDER BY rowid').fetchall():
            raise ValueError("sidecar content changed; rolled back")
        db.commit()
        return {"rows": len(before), "content_preserved": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("--legacy-family-id", required=True)
    parser.add_argument("--expected-users", type=int, required=True)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--backup", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    result = prepare(args.database, args.legacy_family_id, args.expected_users, args.apply,
                     args.backup, args.expected_sha256)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
