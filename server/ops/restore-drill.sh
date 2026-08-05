#!/usr/bin/env bash
set -euo pipefail

# 在隔离临时目录恢复 PocketBase 快照：校验数据库、所有文件引用、媒体抽检，
# 再用独立端口启动真实 PocketBase。绝不接触或覆盖生产 pb_data。

BACKUP_DIR="${1:?用法：restore-drill.sh /path/to/pb_data_mirror}"
POCKETBASE_BIN="${POCKETBASE_BIN:?请设置 POCKETBASE_BIN}"
RESTORE_DRILL_PORT="${RESTORE_DRILL_PORT:-18092}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

[[ -x "$POCKETBASE_BIN" ]] || { echo "PocketBase 二进制不可执行" >&2; exit 1; }
[[ "$RESTORE_DRILL_PORT" =~ ^[0-9]+$ ]] || { echo "隔离端口无效" >&2; exit 1; }
if command -v lsof >/dev/null 2>&1 && \
    lsof -nP -iTCP:"$RESTORE_DRILL_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "隔离端口已被占用" >&2
  exit 1
fi

"$SCRIPT_DIR/verify_pb_backup.sh" "$BACKUP_DIR" >/dev/null

restore_dir="$(mktemp -d "${TMPDIR:-/tmp}/bubu-restore-drill.XXXXXX")"
pb_pid=""
cleanup() {
  local status="$?"
  if [[ -n "$pb_pid" ]]; then
    kill "$pb_pid" 2>/dev/null || true
    wait "$pb_pid" 2>/dev/null || true
  fi
  case "$restore_dir" in
    "${TMPDIR:-/tmp}"/bubu-restore-drill.*) rm -rf "$restore_dir" ;;
  esac
  return "$status"
}
trap cleanup EXIT INT TERM

mkdir -p "$restore_dir/empty_migrations" "$restore_dir/empty_hooks"
rsync -a "$BACKUP_DIR/data.db" "$restore_dir/data.db"
if [[ -f "$BACKUP_DIR/auxiliary.db" ]]; then
  rsync -a "$BACKUP_DIR/auxiliary.db" "$restore_dir/auxiliary.db"
fi
ln -s "$BACKUP_DIR/storage" "$restore_dir/storage"

validation_summary="$(python3 - "$restore_dir/data.db" "$BACKUP_DIR/storage" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys

database = Path(sys.argv[1])
storage = Path(sys.argv[2]).resolve()
identifier = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def quoted(name: str) -> str:
    if not identifier.fullmatch(name):
        raise RuntimeError("invalid SQLite identifier")
    return f'"{name}"'


def file_names(raw: object) -> list[str]:
    if not isinstance(raw, str) or not raw:
        return []
    if raw.startswith("["):
        decoded = json.loads(raw)
        return [item for item in decoded if isinstance(item, str) and item]
    return [raw]


with sqlite3.connect(f"file:{database}?mode=rw", uri=True) as db:
    if db.execute("PRAGMA integrity_check").fetchone() != ("ok",):
        raise RuntimeError("data.db integrity_check failed")
    collections = db.execute(
        "SELECT id, name, fields FROM _collections WHERE system = 0"
    ).fetchall()
    names = {row[1] for row in collections}
    required = {"entries", "media", "growthmeasurements", "healthrecords"}
    missing_collections = required - names
    if missing_collections:
        raise RuntimeError("required collections missing")

    fact_records = 0
    tombstones = 0
    referenced: list[Path] = []
    for collection_id, table, fields_raw in collections:
        table_q = quoted(table)
        columns = {
            row[1] for row in db.execute(f"PRAGMA table_info({table_q})").fetchall()
        }
        fact_records += db.execute(f"SELECT count(*) FROM {table_q}").fetchone()[0]
        if "isDeleted" in columns:
            tombstones += db.execute(
                f"SELECT count(*) FROM {table_q} WHERE isDeleted = 1"
            ).fetchone()[0]
        for field in json.loads(fields_raw or "[]"):
            if field.get("type") != "file":
                continue
            field_name = field.get("name", "")
            if field_name not in columns:
                raise RuntimeError("file field missing from collection table")
            field_q = quoted(field_name)
            for record_id, raw in db.execute(
                f"SELECT id, {field_q} FROM {table_q} WHERE {field_q} <> ''"
            ):
                for name in file_names(raw):
                    candidate = (storage / collection_id / record_id / name).resolve()
                    if os.path.commonpath((storage, candidate)) != str(storage):
                        raise RuntimeError("file reference escaped storage root")
                    referenced.append(candidate)

    if fact_records <= 0:
        raise RuntimeError("backup contains no fact records")
    missing_files = sum(1 for path in referenced if not path.is_file())
    if missing_files:
        raise RuntimeError(f"referenced files missing: {missing_files}")

    # 固定抽检首尾最多 24 个文件，读取头尾字节；不输出文件名或内容。
    ordered = sorted(set(referenced), key=lambda item: str(item))
    samples = ordered[:12] + ordered[-12:] if len(ordered) > 24 else ordered
    digest = hashlib.sha256()
    for path in samples:
        with path.open("rb") as handle:
            head = handle.read(64 * 1024)
            handle.seek(max(0, path.stat().st_size - 64 * 1024))
            tail = handle.read(64 * 1024)
        digest.update(head)
        digest.update(tail)

print(
    f"collections={len(collections)} facts={fact_records} "
    f"tombstones={tombstones} files={len(referenced)} samples={len(samples)}"
)
PY
)"

NO_PROXY=127.0.0.1,localhost "$POCKETBASE_BIN" serve \
  --http="127.0.0.1:$RESTORE_DRILL_PORT" \
  --dir="$restore_dir" \
  --migrationsDir="$restore_dir/empty_migrations" \
  --hooksDir="$restore_dir/empty_hooks" \
  >"$restore_dir/pocketbase.log" 2>&1 &
pb_pid="$!"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl --noproxy '*' -fsS --max-time 2 \
      "http://127.0.0.1:$RESTORE_DRILL_PORT/api/health" >/dev/null 2>&1; then
    printf 'RESTORE_DRILL_OK %s\n' "$validation_summary"
    exit 0
  fi
  sleep 1
done

sed -n '1,120p' "$restore_dir/pocketbase.log" >&2
exit 1
