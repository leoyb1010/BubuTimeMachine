#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${1:?用法：verify_pb_backup.sh /path/to/pb_data_mirror}"

[[ -f "$BACKUP_DIR/data.db" ]] || { echo "缺少 data.db" >&2; exit 1; }
[[ -d "$BACKUP_DIR/storage" ]] || { echo "缺少 storage" >&2; exit 1; }
[[ -f "$BACKUP_DIR/backup-manifest.json" ]] || { echo "缺少 backup-manifest.json" >&2; exit 1; }

for required in python3 rsync; do
  command -v "$required" >/dev/null 2>&1 || { echo "缺少命令：$required" >&2; exit 1; }
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/bubu-backup-verify.XXXXXX")"
cleanup() {
  local status="$?"
  rm -f \
    "$work_dir/data.db" "$work_dir/data.db-shm" "$work_dir/data.db-wal" \
    "$work_dir/auxiliary.db" "$work_dir/auxiliary.db-shm" "$work_dir/auxiliary.db-wal" \
    "$work_dir/backup-manifest.json"
  rmdir "$work_dir" 2>/dev/null || true
  return "$status"
}
trap cleanup EXIT INT TERM

# macOS TCC 可能允许 rsync 访问外置盘、却拒绝 Python/SQLite 直接打开同一路径。
# 先把数据库和清单复制到内置临时目录，再做真实恢复校验。
rsync -a "$BACKUP_DIR/data.db" "$BACKUP_DIR/backup-manifest.json" "$work_dir/"
if [[ -f "$BACKUP_DIR/auxiliary.db" ]]; then
  rsync -a "$BACKUP_DIR/auxiliary.db" "$work_dir/"
fi

python3 - "$work_dir" <<'PY'
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
    # 文件已复制到隔离临时目录。mode=rw 不会创建不存在的数据库，并允许
    # WAL 模式首次打开时建立本地 -shm/-wal；只执行完整性查询，不改业务数据。
    with sqlite3.connect(f"file:{path}?mode=rw", uri=True) as db:
        result = db.execute("PRAGMA integrity_check").fetchone()
        if result is None or result[0] != "ok":
            raise SystemExit(f"{name} integrity_check 失败：{result}")
print("备份校验通过")
PY
