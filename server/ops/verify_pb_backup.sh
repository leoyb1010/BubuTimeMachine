#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${1:?用法：verify_pb_backup.sh /path/to/pb_data_mirror}"

[[ -f "$BACKUP_DIR/data.db" ]] || { echo "缺少 data.db" >&2; exit 1; }
[[ -d "$BACKUP_DIR/storage" ]] || { echo "缺少 storage" >&2; exit 1; }
[[ -f "$BACKUP_DIR/backup-manifest.json" ]] || { echo "缺少 backup-manifest.json" >&2; exit 1; }

python3 - "$BACKUP_DIR" <<'PY'
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

root = Path(sys.argv[1])
manifest = json.loads((root / "backup-manifest.json").read_text(encoding="utf-8"))
for name, expected in manifest["databases"].items():
    path = root / name
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    if digest != expected["sha256"]:
        raise SystemExit(f"{name} SHA-256 不一致")
    with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as db:
        result = db.execute("PRAGMA integrity_check").fetchone()
        if result is None or result[0] != "ok":
            raise SystemExit(f"{name} integrity_check 失败：{result}")
print("备份校验通过")
PY
