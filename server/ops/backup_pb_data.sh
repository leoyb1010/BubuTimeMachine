#!/usr/bin/env bash
set -euo pipefail

# PocketBase 2GB+ 数据目录的在线安全备份。
#
# 1. storage 只做增量复制且不删除旧文件，避免把误删同步到唯一副本。
# 2. SQLite 使用在线 backup API，不直接复制 data.db/WAL。
# 3. 可选把镜像交给 restic 生成加密、可追溯的异地快照。

umask 077

PB_DATA_DIR="${PB_DATA_DIR:?请设置 PB_DATA_DIR}"
MIRROR_DIR="${MIRROR_DIR:?请设置 MIRROR_DIR}"
BACKUP_STAMP="${BACKUP_STAMP:-$MIRROR_DIR/.last-success}"
LOCK_DIR="${LOCK_DIR:-${TMPDIR:-/tmp}/bubu-pb-backup.lock}"
WORK_ROOT="${WORK_ROOT:-${TMPDIR:-/tmp}}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
RESTIC_SECONDARY_REPOSITORY="${RESTIC_SECONDARY_REPOSITORY:-}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-}"
REQUIRE_RESTIC_REPOSITORIES="${REQUIRE_RESTIC_REPOSITORIES:-false}"

fail() {
  printf '备份失败：%s\n' "$1" >&2
  exit 1
}

[[ -d "$PB_DATA_DIR" ]] || fail "PocketBase 数据目录不存在"
[[ -f "$PB_DATA_DIR/data.db" ]] || fail "找不到 data.db"
[[ -d "$PB_DATA_DIR/storage" ]] || fail "找不到 storage 目录"
[[ "$PB_DATA_DIR" != "$MIRROR_DIR" ]] || fail "源目录与镜像目录不能相同"
[[ "$MIRROR_DIR" != "/" && "$MIRROR_DIR" != "${HOME:-}" ]] || fail "镜像目录范围过大"
[[ ! -L "$MIRROR_DIR" ]] || fail "镜像目录不能是符号链接"

case "$REQUIRE_RESTIC_REPOSITORIES" in
  1|true|yes|on)
    [[ -n "$RESTIC_REPOSITORY" ]] || fail "安全门要求本地 restic 仓库"
    [[ -n "$RESTIC_SECONDARY_REPOSITORY" ]] || fail "安全门要求异地 restic 仓库"
    [[ "$RESTIC_REPOSITORY" != "$RESTIC_SECONDARY_REPOSITORY" ]] \
      || fail "本地与异地 restic 仓库不能相同"
    ;;
  0|false|no|off) ;;
  *) fail "REQUIRE_RESTIC_REPOSITORIES 只能为 true/false" ;;
esac

for required in python3 rsync; do
  command -v "$required" >/dev/null 2>&1 || fail "缺少命令：$required"
done

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "已有备份任务在运行"
fi

work_dir=""
cleanup() {
  local status="$?"
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    rm -f \
      "$work_dir/data.db" "$work_dir/data.db-shm" "$work_dir/data.db-wal" \
      "$work_dir/auxiliary.db" "$work_dir/auxiliary.db-shm" "$work_dir/auxiliary.db-wal" \
      "$work_dir/backup-manifest.json"
    rmdir "$work_dir" 2>/dev/null || true
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
  return "$status"
}
trap cleanup EXIT INT TERM

# 首次只允许初始化空目录；已有宽目录必须由维护者核对后手工放置 sentinel。
# 这样误把 Desktop、卷根等填成 MIRROR_DIR 时不会覆盖同名 data.db 或整目录送入 restic。
sentinel="$MIRROR_DIR/.bubu-pocketbase-backup-target"
if [[ ! -e "$MIRROR_DIR" ]]; then
  mkdir -p "$MIRROR_DIR"
fi
if [[ ! -f "$sentinel" ]]; then
  if find "$MIRROR_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    fail "镜像目录非空且缺少专用标记，请核对路径后手工初始化"
  fi
  printf 'bubu-pocketbase-backup-v1\n' > "$sentinel"
fi
[[ "$(cat "$sentinel")" == "bubu-pocketbase-backup-v1" ]] || fail "镜像目录专用标记无效"

# 必须真的写入目标目录；只检查父目录 -w 会被 macOS 外置盘 TCC 误导。
source_real="$(cd "$PB_DATA_DIR" && pwd -P)"
mirror_real="$(cd "$MIRROR_DIR" && pwd -P)"
case "$mirror_real/" in
  "$source_real/"*) fail "镜像目录不能位于 PocketBase 数据目录内" ;;
esac

# 本地仓库必须与镜像真正分离。远程 s3/rest/http 仓库没有本机路径，跳过路径判断；
# 绝不能让两个变量指向同一个本地目录，也不能把 restic 仓库嵌进待备份镜像形成递归。
local_repository_real() {
  local repository="$1"
  case "$repository" in
    /*)
      python3 - "$repository" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve(strict=False))
PY
      ;;
    *) return 1 ;;
  esac
}

primary_repo_real="$(local_repository_real "$RESTIC_REPOSITORY" 2>/dev/null || true)"
secondary_repo_real="$(local_repository_real "$RESTIC_SECONDARY_REPOSITORY" 2>/dev/null || true)"
if [[ -n "$primary_repo_real" && -n "$secondary_repo_real" ]]; then
  [[ "$primary_repo_real" != "$secondary_repo_real" ]] \
    || fail "本地与异地 restic 仓库解析后指向同一目录"
fi
for repo_real in "$primary_repo_real" "$secondary_repo_real"; do
  [[ -n "$repo_real" ]] || continue
  case "$repo_real/" in
    "$mirror_real/"*) fail "restic 仓库不能位于镜像目录内" ;;
  esac
  case "$mirror_real/" in
    "$repo_real/"*) fail "镜像目录不能位于 restic 仓库内" ;;
  esac
done

write_probe="$MIRROR_DIR/.write-probe-$$"
if ! (umask 077 && : > "$write_probe"); then
  fail "镜像目录不可写（请检查磁盘挂载与 macOS 完全磁盘访问权限）"
fi
rm -f "$write_probe"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$WORK_ROOT"
work_dir="$WORK_ROOT/bubu-pb-backup-$timestamp-$$"
mkdir -p "$work_dir"

sync_files() {
  rsync -a \
    --exclude '/data.db' \
    --exclude '/data.db-*' \
    --exclude '/auxiliary.db' \
    --exclude '/auxiliary.db-*' \
    --exclude '/backups/' \
    --exclude '/.last-success' \
    --exclude '/.bubu-pocketbase-backup-target' \
    --exclude '/.incomplete-*' \
    "$PB_DATA_DIR/" "$MIRROR_DIR/"
}

backup_sqlite() {
  local source_db="$1"
  local output_db="$2"
  python3 - "$source_db" "$output_db" <<'PY'
import sqlite3
import sys

source, output = sys.argv[1:3]
# mode=rw 保证源必须已存在，同时允许 SQLite 为 WAL 数据库打开共享内存；
# 这里只执行 backup 和 integrity_check，不执行任何写语句。
with sqlite3.connect(f"file:{source}?mode=rw", uri=True, timeout=30) as src:
    with sqlite3.connect(output) as dst:
        src.backup(dst, pages=256, sleep=0.05)
        result = dst.execute("PRAGMA integrity_check").fetchone()
        if result is None or result[0] != "ok":
            raise RuntimeError(f"SQLite integrity_check failed: {result}")
PY
}

# 两次不带 --delete 的 storage 同步夹住数据库快照。PocketBase 文件名不可变，
# 软删除还有保留期，因此数据库快照引用的文件不会被镜像过程主动删掉。
sync_files
backup_sqlite "$PB_DATA_DIR/data.db" "$work_dir/data.db"
if [[ -f "$PB_DATA_DIR/auxiliary.db" ]]; then
  backup_sqlite "$PB_DATA_DIR/auxiliary.db" "$work_dir/auxiliary.db"
fi
sync_files

rsync -a "$work_dir/data.db" "$MIRROR_DIR/.data.db.next"
mv -f "$MIRROR_DIR/.data.db.next" "$MIRROR_DIR/data.db"
if [[ -f "$work_dir/auxiliary.db" ]]; then
  rsync -a "$work_dir/auxiliary.db" "$MIRROR_DIR/.auxiliary.db.next"
  mv -f "$MIRROR_DIR/.auxiliary.db.next" "$MIRROR_DIR/auxiliary.db"
fi

python3 - "$work_dir" "$timestamp" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
payload = {"completedAtUTC": sys.argv[2], "databases": {}}
for name in ("data.db", "auxiliary.db"):
    path = root / name
    if path.exists():
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        payload["databases"][name] = {
            "bytes": path.stat().st_size,
            "sha256": digest.hexdigest(),
        }
(root / "backup-manifest.json").write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
PY
rsync -a "$work_dir/backup-manifest.json" "$MIRROR_DIR/.backup-manifest.json.next"
mv -f "$MIRROR_DIR/.backup-manifest.json.next" "$MIRROR_DIR/backup-manifest.json"

backup_restic_repository() {
  local repository="$1"
  local role="$2"
  [[ -n "$repository" ]] || return 0
  command -v restic >/dev/null 2>&1 || fail "已配置异地仓库但未安装 restic"
  [[ -f "$RESTIC_PASSWORD_FILE" ]] || fail "RESTIC_PASSWORD_FILE 不存在"
  RESTIC_REPOSITORY="$repository"
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
  restic backup "$MIRROR_DIR" --tag bubu-pocketbase --tag "$timestamp"
  restic forget \
    --keep-daily 14 \
    --keep-weekly 8 \
    --keep-monthly 24 \
    --keep-yearly 18
  restic check
  printf 'restic %s仓库完成完整性检查\n' "$role"
}

# 本地第二介质与异地仓库必须分别成功；任一失败都不更新成功时间戳，避免健康检查误报。
backup_restic_repository "$RESTIC_REPOSITORY" "本地"
backup_restic_repository "$RESTIC_SECONDARY_REPOSITORY" "异地"

mkdir -p "$(dirname "$BACKUP_STAMP")"
printf '%s\n' "$timestamp" > "$BACKUP_STAMP"
printf 'PocketBase 备份完成：%s\n' "$timestamp"
