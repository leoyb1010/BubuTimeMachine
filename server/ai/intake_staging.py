"""Durable, isolated intake staging for confirmed family photo batches.

The staging database and files are deliberately separate from PocketBase facts.
Uploads may be retried; only a fully verified batch can be handed to the atomic
PocketBase commit hook.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import shutil
import sqlite3
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable, Optional


_ID = re.compile(r"^[A-Za-z0-9_-]{8,128}$")
_STATES = {"awaiting_confirmation", "accepted", "uploading", "staged", "committing", "committed", "failed", "cancelled"}


class IntakeError(RuntimeError):
    pass


class IntakeConflict(IntakeError):
    pass


@dataclass(frozen=True)
class IntakeItem:
    asset_key: str
    file_name: str
    media_type: str
    captured_at: str
    expected_size: int
    expected_mime: str
    resource_role: str = "original"
    asset_group_id: str = ""


class IntakeStagingStore:
    def __init__(self, root: Optional[Path] = None):
        configured = os.environ.get("INTAKE_STAGING_ROOT", "").strip()
        self.root = (root or Path(configured or "./runtime/intake-staging")).expanduser().resolve()
        self.files = self.root / "files"
        self.db_path = self.root / "intake.sqlite"
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.files.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.root, 0o700)
        os.chmod(self.files, 0o700)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.db_path, timeout=20, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA busy_timeout=20000")
        for suffix in ("", "-wal", "-shm"):
            path = Path(str(self.db_path) + suffix)
            if path.exists():
                os.chmod(path, 0o600)
        return db

    def _initialize(self) -> None:
        with self._connect() as db:
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS batches (
                  id TEXT PRIMARY KEY,
                  owner TEXT NOT NULL,
                  family_id TEXT NOT NULL,
                  state TEXT NOT NULL,
                  entry_json TEXT NOT NULL,
                  confirmed INTEGER NOT NULL DEFAULT 1,
                  created_at REAL NOT NULL,
                  updated_at REAL NOT NULL,
                  committed_entry_id TEXT
                );
                CREATE TABLE IF NOT EXISTS items (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  batch_id TEXT NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
                  asset_key TEXT NOT NULL,
                  file_name TEXT NOT NULL,
                  media_type TEXT NOT NULL,
                  captured_at TEXT NOT NULL,
                  expected_size INTEGER NOT NULL,
                  expected_mime TEXT NOT NULL,
                  resource_role TEXT NOT NULL DEFAULT 'original',
                  asset_group_id TEXT NOT NULL DEFAULT '',
                  state TEXT NOT NULL,
                  content_hash TEXT,
                  actual_size INTEGER,
                  stored_path TEXT,
                  last_error TEXT,
                  updated_at REAL NOT NULL,
                  UNIQUE(batch_id, asset_key),
                  UNIQUE(batch_id, content_hash)
                );
                CREATE INDEX IF NOT EXISTS idx_intake_items_batch_state
                  ON items(batch_id, state);
                """
            )
            columns = {row[1] for row in db.execute("PRAGMA table_info(batches)")}
            if "confirmed" not in columns:
                db.execute("ALTER TABLE batches ADD COLUMN confirmed INTEGER NOT NULL DEFAULT 1")
            item_columns = {row[1] for row in db.execute("PRAGMA table_info(items)")}
            if "resource_role" not in item_columns:
                db.execute("ALTER TABLE items ADD COLUMN resource_role TEXT NOT NULL DEFAULT 'original'")
            if "asset_group_id" not in item_columns:
                db.execute("ALTER TABLE items ADD COLUMN asset_group_id TEXT NOT NULL DEFAULT ''")
        os.chmod(self.db_path, 0o600)

    @staticmethod
    def _valid_id(value: str, label: str) -> str:
        value = value.strip()
        if not _ID.fullmatch(value):
            raise IntakeError(f"invalid {label}")
        return value

    @staticmethod
    def _clean_name(value: str) -> str:
        name = Path(value).name.strip()
        if not name or name in {".", ".."} or len(name) > 255:
            raise IntakeError("invalid file name")
        return name

    def create_batch(
        self,
        batch_id: str,
        owner: str,
        family_id: str,
        entry: dict[str, Any],
        items: Iterable[IntakeItem],
        confirmed: bool = True,
    ) -> dict[str, Any]:
        batch_id = self._valid_id(batch_id, "batch id")
        normalized = [
            IntakeItem(
                asset_key=self._valid_id(item.asset_key, "asset key"),
                file_name=self._clean_name(item.file_name),
                media_type=item.media_type if item.media_type in {"photo", "video", "audio"} else "",
                captured_at=item.captured_at.strip(),
                expected_size=int(item.expected_size),
                expected_mime=item.expected_mime.strip().lower(),
                resource_role=(item.resource_role.strip().lower() or "original")[:40],
                asset_group_id=(item.asset_group_id.strip() or item.asset_key)[:128],
            )
            for item in items
        ]
        if not owner or not family_id or not normalized or len(normalized) > 500:
            raise IntakeError("invalid batch")
        if any(not item.media_type or item.expected_size < 0 or item.expected_size > 2_147_483_648
               for item in normalized):
            raise IntakeError("invalid intake item")
        if len({item.asset_key for item in normalized}) != len(normalized):
            raise IntakeError("duplicate asset key")
        entry_json = json.dumps(entry, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        now = time.time()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute("SELECT owner, family_id, entry_json FROM batches WHERE id=?", (batch_id,)).fetchone()
            if existing:
                if existing["owner"] != owner or existing["family_id"] != family_id or existing["entry_json"] != entry_json:
                    db.execute("ROLLBACK")
                    raise IntakeConflict("batch id already belongs to different content")
                current = db.execute("SELECT asset_key, file_name, media_type, captured_at, expected_size, expected_mime, resource_role, asset_group_id FROM items WHERE batch_id=? ORDER BY asset_key", (batch_id,)).fetchall()
                expected = sorted((asdict(item) for item in normalized), key=lambda value: value["asset_key"])
                if [dict(row) for row in current] != expected:
                    db.execute("ROLLBACK")
                    raise IntakeConflict("batch items changed")
                db.execute("COMMIT")
                return self.batch(batch_id, owner)
            db.execute(
                "INSERT INTO batches(id,owner,family_id,state,entry_json,confirmed,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)",
                (batch_id, owner, family_id,
                 "accepted" if confirmed else "awaiting_confirmation",
                 entry_json, 1 if confirmed else 0, now, now),
            )
            db.executemany(
                """INSERT INTO items(batch_id,asset_key,file_name,media_type,captured_at,
                   expected_size,expected_mime,resource_role,asset_group_id,state,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
                [(batch_id, item.asset_key, item.file_name, item.media_type, item.captured_at,
                  item.expected_size, item.expected_mime, item.resource_role, item.asset_group_id,
                  "accepted", now) for item in normalized],
            )
            db.execute("COMMIT")
        return self.batch(batch_id, owner)

    def batch(self, batch_id: str, owner: Optional[str] = None) -> dict[str, Any]:
        batch_id = self._valid_id(batch_id, "batch id")
        with self._connect() as db:
            row = db.execute("SELECT * FROM batches WHERE id=?", (batch_id,)).fetchone()
            if not row or (owner is not None and row["owner"] != owner):
                raise IntakeError("batch not found")
            items = db.execute(
                "SELECT asset_key,file_name,media_type,captured_at,expected_size,expected_mime,resource_role,asset_group_id,state,content_hash,actual_size,last_error FROM items WHERE batch_id=? ORDER BY id",
                (batch_id,),
            ).fetchall()
        result = dict(row)
        result["entry"] = json.loads(result.pop("entry_json"))
        result["items"] = [dict(item) for item in items]
        return result

    def item(self, batch_id: str, asset_key: str) -> sqlite3.Row:
        batch_id = self._valid_id(batch_id, "batch id")
        asset_key = self._valid_id(asset_key, "asset key")
        with self._connect() as db:
            row = db.execute("SELECT * FROM items WHERE batch_id=? AND asset_key=?", (batch_id, asset_key)).fetchone()
        if not row:
            raise IntakeError("item not found")
        return row

    def mark_uploading(self, batch_id: str, asset_key: str) -> sqlite3.Row:
        now = time.time()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM items WHERE batch_id=? AND asset_key=?", (batch_id, asset_key)).fetchone()
            if not row:
                db.execute("ROLLBACK")
                raise IntakeError("item not found")
            batch = db.execute("SELECT confirmed,state FROM batches WHERE id=?", (batch_id,)).fetchone()
            if not batch or batch["state"] in {"committing", "committed", "cancelled"}:
                db.execute("ROLLBACK")
                raise IntakeConflict("batch no longer accepts uploads")
            if row["state"] == "cancelled":
                db.execute("ROLLBACK")
                raise IntakeConflict("item was cancelled")
            if row["state"] == "staged":
                db.execute("COMMIT")
                return row
            db.execute("UPDATE items SET state='uploading',last_error=NULL,updated_at=? WHERE id=?", (now, row["id"]))
            db.execute("UPDATE batches SET state=?,updated_at=? WHERE id=? AND state NOT IN ('committed','cancelled')",
                       ("uploading" if batch and batch["confirmed"] else "awaiting_confirmation", now, batch_id))
            db.execute("COMMIT")
        return self.item(batch_id, asset_key)

    def stage_file(self, batch_id: str, asset_key: str, temporary: Path, digest: str, size: int) -> dict[str, Any]:
        row = self.item(batch_id, asset_key)
        batch = self.batch(batch_id)
        if batch["state"] in {"committing", "committed", "cancelled"}:
            raise IntakeConflict("batch no longer accepts staged files")
        if int(row["expected_size"]) > 0 and int(row["expected_size"]) != size:
            self.fail_item(batch_id, asset_key, "size_mismatch")
            raise IntakeConflict("size mismatch")
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise IntakeError("invalid digest")
        target_dir = self.files / batch_id
        target_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(target_dir, 0o700)
        suffix = Path(row["file_name"]).suffix.lower()[:16]
        target = target_dir / (digest + suffix)
        now = time.time()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            current_batch = db.execute(
                "SELECT state FROM batches WHERE id=?", (batch_id,)
            ).fetchone()
            if not current_batch or current_batch["state"] in {
                "committing", "committed", "cancelled"
            }:
                db.execute("ROLLBACK")
                raise IntakeConflict("batch no longer accepts staged files")
            current = db.execute("SELECT * FROM items WHERE batch_id=? AND asset_key=?", (batch_id, asset_key)).fetchone()
            if current["state"] == "staged":
                if current["content_hash"] != digest or int(current["actual_size"] or 0) != size:
                    db.execute("ROLLBACK")
                    raise IntakeConflict("asset key uploaded with different content")
                db.execute("COMMIT")
                temporary.unlink(missing_ok=True)
                return self.batch(batch_id)
            collision = db.execute(
                "SELECT asset_key FROM items WHERE batch_id=? AND content_hash=? AND asset_key<>?",
                (batch_id, digest, asset_key),
            ).fetchone()
            if collision:
                db.execute("ROLLBACK")
                raise IntakeConflict("duplicate content in batch")
            if target.exists():
                if _sha256(target) != digest or target.stat().st_size != size:
                    db.execute("ROLLBACK")
                    raise IntakeConflict("staging path collision")
                temporary.unlink(missing_ok=True)
            else:
                os.replace(temporary, target)
                os.chmod(target, 0o600)
            db.execute(
                "UPDATE items SET state='staged',content_hash=?,actual_size=?,stored_path=?,last_error=NULL,updated_at=? WHERE id=?",
                (digest, size, str(target), now, current["id"]),
            )
            pending = db.execute("SELECT count(*) FROM items WHERE batch_id=? AND state<>'staged'", (batch_id,)).fetchone()[0]
            confirmed = db.execute("SELECT confirmed FROM batches WHERE id=?", (batch_id,)).fetchone()[0]
            next_state = ("staged" if confirmed else "awaiting_confirmation") if pending == 0 else ("uploading" if confirmed else "awaiting_confirmation")
            updated = db.execute(
                "UPDATE batches SET state=?,updated_at=? WHERE id=? "
                "AND state NOT IN ('committing','committed','cancelled')",
                (next_state, now, batch_id),
            ).rowcount
            if updated != 1:
                db.execute("ROLLBACK")
                raise IntakeConflict("batch state changed during staging")
            db.execute("COMMIT")
        return self.batch(batch_id)

    def fail_item(self, batch_id: str, asset_key: str, reason: str) -> None:
        with self._connect() as db:
            now = time.time()
            # 已完成暂存或正在提交的正确素材不能被并发冲突重放降级。
            changed = db.execute(
                "UPDATE items SET state='failed',last_error=?,updated_at=? "
                "WHERE batch_id=? AND asset_key=? AND state IN ('accepted','uploading','failed')",
                (reason[:200], now, batch_id, asset_key),
            ).rowcount
            if changed:
                db.execute(
                    "UPDATE batches SET state='failed',updated_at=? "
                    "WHERE id=? AND state IN ('accepted','uploading','failed')",
                    (now, batch_id),
                )

    def cancel(self, batch_id: str, family_id: str) -> dict[str, Any]:
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT family_id,state FROM batches WHERE id=?", (batch_id,)
            ).fetchone()
            if not row or row["family_id"] != family_id:
                db.execute("ROLLBACK")
                raise IntakeError("batch not found")
            if row["state"] in {"committing", "committed"}:
                db.execute("ROLLBACK")
                raise IntakeConflict("committed batch cannot be cancelled")
            db.execute(
                "UPDATE batches SET state='cancelled',updated_at=? WHERE id=?",
                (time.time(), batch_id),
            )
            db.execute(
                "UPDATE items SET state='cancelled',updated_at=? WHERE batch_id=?",
                (time.time(), batch_id),
            )
            db.execute("COMMIT")
        shutil.rmtree(self.files / batch_id, ignore_errors=True)
        return self.batch(batch_id)

    def abandon_unconfirmed(self, batch_id: str, family_id: str) -> None:
        """Drop an incomplete SSD copy so the untouched source can be retried.

        This is deliberately different from ``cancel``: cancel is a permanent
        user choice and retains hash tombstones, while abandon is an internal
        copy failure and must not suppress the source on the next scan.
        """
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT family_id,owner,state,confirmed FROM batches WHERE id=?",
                (batch_id,),
            ).fetchone()
            if not row or row["family_id"] != family_id:
                db.execute("ROLLBACK")
                raise IntakeError("batch not found")
            if (row["owner"] != "service:ssd-inbox"
                    or row["state"] != "awaiting_confirmation"
                    or int(row["confirmed"]) != 0):
                db.execute("ROLLBACK")
                raise IntakeConflict("only incomplete SSD candidates can be abandoned")
            db.execute("DELETE FROM batches WHERE id=?", (batch_id,))
            db.execute("COMMIT")
        shutil.rmtree(self.files / batch_id, ignore_errors=True)

    def begin_commit(self, batch_id: str, owner: str) -> dict[str, Any]:
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT owner,state FROM batches WHERE id=?", (batch_id,)).fetchone()
            if not row or row["owner"] != owner:
                db.execute("ROLLBACK")
                raise IntakeError("batch not found")
            if row["state"] == "committed":
                db.execute("COMMIT")
                return self.batch(batch_id, owner)
            if row["state"] != "staged":
                db.execute("ROLLBACK")
                raise IntakeConflict("batch is not fully staged")
            db.execute("UPDATE batches SET state='committing',updated_at=? WHERE id=?", (time.time(), batch_id))
            db.execute("COMMIT")
        return self.commit_manifest(batch_id, owner)

    def family_batches(self, family_id: str, states: Iterable[str]) -> list[dict[str, Any]]:
        wanted = [state for state in states if state in _STATES]
        if not family_id or not wanted:
            return []
        placeholders = ",".join("?" for _ in wanted)
        with self._connect() as db:
            rows = db.execute(
                f"SELECT id FROM batches WHERE family_id=? AND state IN ({placeholders}) ORDER BY created_at DESC LIMIT 100",
                (family_id, *wanted),
            ).fetchall()
        return [self.batch(row["id"]) for row in rows]

    def ready_family_candidates(self, family_id: str) -> list[dict[str, Any]]:
        if not family_id:
            return []
        with self._connect() as db:
            rows = db.execute(
                """
                SELECT b.id FROM batches b
                WHERE b.family_id=? AND b.state='awaiting_confirmation'
                  AND NOT EXISTS(
                    SELECT 1 FROM items i WHERE i.batch_id=b.id AND i.state<>'staged'
                  )
                ORDER BY b.created_at DESC LIMIT 100
                """,
                (family_id,),
            ).fetchall()
        return [self.batch(row["id"]) for row in rows]

    def known_hashes(self, family_id: str) -> set[str]:
        """Hashes already staged or committed for a family across earlier scans."""
        if not family_id:
            return set()
        with self._connect() as db:
            rows = db.execute(
                """
                SELECT DISTINCT i.content_hash
                FROM items i JOIN batches b ON b.id=i.batch_id
                WHERE b.family_id=? AND i.content_hash IS NOT NULL AND i.content_hash<>''
                  AND (
                    b.state='cancelled'
                    OR (
                      i.state='staged'
                      AND NOT EXISTS(
                        SELECT 1 FROM items pending
                        WHERE pending.batch_id=b.id AND pending.state<>'staged'
                      )
                    )
                  )
                """,
                (family_id,),
            ).fetchall()
        return {str(row[0]) for row in rows}

    def confirm(self, batch_id: str, family_id: str, owner: str) -> dict[str, Any]:
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT family_id,state FROM batches WHERE id=?", (batch_id,)).fetchone()
            if not row or row["family_id"] != family_id:
                db.execute("ROLLBACK")
                raise IntakeError("batch not found")
            if row["state"] in {"committing", "committed", "cancelled"}:
                db.execute("COMMIT")
                return self.batch(batch_id)
            pending = db.execute("SELECT count(*) FROM items WHERE batch_id=? AND state<>'staged'", (batch_id,)).fetchone()[0]
            if pending:
                db.execute("ROLLBACK")
                raise IntakeConflict("candidate files are not fully staged")
            next_state = "staged"
            db.execute(
                "UPDATE batches SET owner=?,confirmed=1,state=?,updated_at=? WHERE id=?",
                (owner, next_state, time.time(), batch_id),
            )
            db.execute("COMMIT")
        return self.batch(batch_id, owner)

    def update_candidate_time(
        self, batch_id: str, family_id: str, happened_at: str
    ) -> dict[str, Any]:
        happened_at = happened_at.strip()
        if len(happened_at) < 10 or len(happened_at) > 64:
            raise IntakeError("invalid happened_at")
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT family_id,state,entry_json FROM batches WHERE id=?", (batch_id,)
            ).fetchone()
            if not row or row["family_id"] != family_id:
                db.execute("ROLLBACK")
                raise IntakeError("batch not found")
            if row["state"] != "awaiting_confirmation":
                db.execute("ROLLBACK")
                raise IntakeConflict("only pending candidates can be edited")
            entry = json.loads(row["entry_json"])
            entry["happened_at"] = happened_at
            db.execute(
                "UPDATE batches SET entry_json=?,updated_at=? WHERE id=?",
                (json.dumps(entry, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
                 time.time(), batch_id),
            )
            db.execute("COMMIT")
        return self.batch(batch_id)

    def commit_manifest(self, batch_id: str, owner: str) -> dict[str, Any]:
        result = self.batch(batch_id, owner)
        with self._connect() as db:
            stored = db.execute(
                "SELECT asset_key,file_name,media_type,captured_at,resource_role,asset_group_id,content_hash,actual_size,stored_path FROM items WHERE batch_id=? ORDER BY id",
                (batch_id,),
            ).fetchall()
        verified: list[dict[str, Any]] = []
        allowed = (self.files / batch_id).resolve()
        for item in stored:
            value = dict(item)
            path_text = str(value.get("stored_path") or "")
            path = Path(path_text)
            try:
                if path.is_symlink():
                    raise IntakeConflict("staged file cannot be a symlink")
                canonical = path.resolve(strict=True)
                canonical.relative_to(allowed)
            except (OSError, ValueError) as exc:
                raise IntakeConflict("staged file escaped its batch directory") from exc
            actual_size = canonical.stat().st_size
            actual_hash = _sha256(canonical)
            if (actual_size != int(value.get("actual_size") or -1)
                    or actual_hash != str(value.get("content_hash") or "")):
                raise IntakeConflict("staged file changed before commit")
            value["stored_path"] = str(canonical)
            verified.append(value)
        result["items"] = verified
        return result

    def finish_commit(self, batch_id: str, owner: str, entry_id: str) -> dict[str, Any]:
        with self._connect() as db:
            updated = db.execute(
                "UPDATE batches SET state='committed',committed_entry_id=?,updated_at=? WHERE id=? AND owner=? AND state IN ('committing','committed')",
                (entry_id, time.time(), batch_id, owner),
            ).rowcount
        if not updated:
            raise IntakeConflict("batch commit state changed")
        # PocketBase 已在事务中把文件复制进自己的 storage；隔离中转原片不再保留，
        # 否则持续自动摄取会造成 mini 磁盘无限增长。保留哈希和批次审计记录即可。
        shutil.rmtree(self.files / batch_id, ignore_errors=True)
        with self._connect() as db:
            db.execute(
                "UPDATE items SET stored_path=NULL WHERE batch_id=?",
                (batch_id,),
            )
        return self.batch(batch_id, owner)

    def reset_commit(self, batch_id: str, owner: str, reason: str) -> None:
        with self._connect() as db:
            db.execute(
                "UPDATE batches SET state='staged',updated_at=? WHERE id=? AND owner=? AND state='committing'",
                (time.time(), batch_id, owner),
            )

    def reset_candidate_confirmation(self, batch_id: str, family_id: str) -> None:
        with self._connect() as db:
            db.execute(
                "UPDATE batches SET confirmed=0,state='awaiting_confirmation',updated_at=? "
                "WHERE id=? AND family_id=? AND state IN ('staged','committing')",
                (time.time(), batch_id, family_id),
            )

    def cleanup(self, older_than_seconds: int = 7 * 86400) -> int:
        cutoff = time.time() - max(3600, older_than_seconds)
        with self._connect() as db:
            # ignored/cancelled 的 hash 是永久小墓碑：源 SSD 文件按合同不移动不删除，
            # 若删掉这行元数据，同一批素材会周期性重新冒出来。只清中转文件。
            cancelled = db.execute(
                "SELECT id FROM batches WHERE updated_at<? AND state='cancelled'", (cutoff,)
            ).fetchall()
            for row in cancelled:
                shutil.rmtree(self.files / row["id"], ignore_errors=True)
            rows = db.execute(
                "SELECT id FROM batches WHERE updated_at<? AND state IN "
                "('awaiting_confirmation','accepted','uploading','staged','failed','committed')",
                (cutoff,),
            ).fetchall()
            for row in rows:
                shutil.rmtree(self.files / row["id"], ignore_errors=True)
                db.execute("DELETE FROM batches WHERE id=?", (row["id"],))
        return len(rows)

    def cleanup_temporary_files(self, older_than_seconds: int = 24 * 3600) -> int:
        cutoff = time.time() - max(3600, older_than_seconds)
        removed = 0
        for pattern in ("tmp/upload-*.part", "ssd-*.part"):
            for path in self.root.glob(pattern):
                try:
                    if path.is_file() and path.stat().st_mtime < cutoff:
                        path.unlink()
                        removed += 1
                except OSError:
                    continue
        return removed

    def recover_stale_commits(self, older_than_seconds: int = 5 * 60) -> int:
        """A retry is safe: PocketBase commit is idempotent by intakeBatchId."""
        cutoff = time.time() - max(60, older_than_seconds)
        with self._connect() as db:
            changed = db.execute(
                "UPDATE batches SET "
                "state=CASE WHEN entry_json LIKE '%\"source\":\"ssd-bubu-inbox\"%' "
                "THEN 'awaiting_confirmation' ELSE 'staged' END, "
                "confirmed=CASE WHEN entry_json LIKE '%\"source\":\"ssd-bubu-inbox\"%' "
                "THEN 0 ELSE confirmed END, updated_at=? "
                "WHERE state='committing' AND updated_at<?",
                (time.time(), cutoff),
            ).rowcount
        return int(changed)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def issue_upload_token(batch_id: str, asset_key: str, owner: str, ttl: int = 86400) -> str:
    secret = os.environ.get("INTAKE_UPLOAD_SECRET", "").encode("utf-8")
    if len(secret) < 32:
        raise IntakeError("upload secret is not configured")
    expires = int(time.time()) + max(300, min(ttl, 7 * 86400))
    payload = f"{batch_id}.{asset_key}.{owner}.{expires}"
    signature = hmac.new(secret, payload.encode("utf-8"), hashlib.sha256).hexdigest()
    return f"{expires}.{signature}"


def verify_upload_token(token: str, batch_id: str, asset_key: str, owner: str) -> bool:
    try:
        expires_text, provided = token.strip().split(".", 1)
        expires = int(expires_text)
    except (TypeError, ValueError):
        return False
    if expires < int(time.time()) or expires > int(time.time()) + 7 * 86400 + 60:
        return False
    secret = os.environ.get("INTAKE_UPLOAD_SECRET", "").encode("utf-8")
    if len(secret) < 32:
        return False
    payload = f"{batch_id}.{asset_key}.{owner}.{expires}"
    expected = hmac.new(secret, payload.encode("utf-8"), hashlib.sha256).hexdigest()
    return secrets.compare_digest(provided, expected)
