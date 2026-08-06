#!/usr/bin/env python3
"""Read-only PocketBase fact counts and SHA-256 fingerprint for release gates."""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
from pathlib import Path


FACT_TABLES = (
    "entries", "media", "comments", "voicenotes", "milestones", "firsttimes",
    "voicememos", "members", "childprofile", "healthrecords", "timecapsules",
    "feed_events", "vaccinerecords", "growthmeasurements",
)
ADDITIVE_PROVENANCE_FIELDS = {
    "entries": {"intakeBatchId", "sourceRaw"},
    "media": {
        "intakeBatchId", "sourceAssetKey", "contentHash", "sourceRaw",
        "resourceRole", "assetGroupId",
    },
}


def normalized(value):
    if isinstance(value, bytes):
        return {"bytes_sha256": hashlib.sha256(value).hexdigest(), "size": len(value)}
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    args = parser.parse_args()
    database = args.database.expanduser().resolve()
    aggregate = hashlib.sha256()
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as db:
        db.row_factory = sqlite3.Row
        existing = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        for table in FACT_TABLES:
            if table not in existing:
                continue
            rows = db.execute(f'SELECT * FROM "{table}" ORDER BY id').fetchall()
            digest = hashlib.sha256()
            for row in rows:
                ignored = ADDITIVE_PROVENANCE_FIELDS.get(table, set())
                payload = {
                    key: normalized(row[key]) for key in row.keys()
                    if key not in ignored
                }
                digest.update(json.dumps(
                    payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
                    default=str,
                ).encode("utf-8"))
                digest.update(b"\n")
            line = f"{table}={len(rows)} sha256={digest.hexdigest()}"
            print(line)
            aggregate.update((line + "\n").encode("utf-8"))
    print("FACTS_SHA256=" + aggregate.hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
