"""Durable learning sources, revisions and attempts; every lookup is family scoped.

Files are content-addressed within a family. A teaching occurrence is a separate
row, so reusing Monday's video on Wednesday never loses Wednesday's lesson.
"""
from __future__ import annotations

from contextlib import contextmanager
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile
import time
import uuid
from typing import Any


class Missing(LookupError):
    pass


class Conflict(ValueError):
    pass


def encoded(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def digest(value: Any) -> str:
    return hashlib.sha256(encoded(value).encode()).hexdigest()


COURSE_KINDS = {"teaching", "practice", "song"}


def compose_key(child: str, day: str, course_id: str = "") -> str:
    return child + ":" + day + (":" + course_id if course_id else "")


def valid_day(value: str) -> str:
    if date.fromisoformat(value).isoformat() != value:
        raise ValueError("日期格式必须为 YYYY-MM-DD")
    return value


class LearningStore:
    def __init__(self, root: Path):
        self.root = Path(root).expanduser().resolve()
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.db_path = self.root / "learning.sqlite"
        with self.db() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS assets (
                    id TEXT PRIMARY KEY, family_id TEXT NOT NULL, hash TEXT NOT NULL,
                    path TEXT NOT NULL, mime TEXT NOT NULL, size INTEGER NOT NULL,
                    media_ref TEXT NOT NULL DEFAULT '{}', created_at REAL NOT NULL,
                    UNIQUE(family_id,hash));
                CREATE TABLE IF NOT EXISTS sources (
                    id TEXT PRIMARY KEY, family_id TEXT NOT NULL, child_id TEXT NOT NULL,
                    school_date TEXT NOT NULL, origin_key TEXT NOT NULL, asset_id TEXT NOT NULL,
                    name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'auto', language TEXT NOT NULL DEFAULT 'en-US',
                    deleted INTEGER NOT NULL DEFAULT 0, date_confirmed INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL,
                    UNIQUE(family_id,child_id,school_date,origin_key),
                    FOREIGN KEY(asset_id) REFERENCES assets(id));
                CREATE INDEX IF NOT EXISTS source_day ON sources(family_id,child_id,school_date,deleted);
                CREATE TABLE IF NOT EXISTS analyses (
                    asset_id TEXT PRIMARY KEY, family_id TEXT NOT NULL, source_hash TEXT NOT NULL,
                    revision INTEGER NOT NULL, state TEXT NOT NULL, payload TEXT NOT NULL,
                    error TEXT NOT NULL DEFAULT '', updated_at REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY, family_id TEXT NOT NULL, kind TEXT NOT NULL,
                    job_key TEXT NOT NULL, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'queued',
                    attempts INTEGER NOT NULL DEFAULT 0, available_at REAL NOT NULL,
                    lease_until REAL, lease_owner TEXT, rerun INTEGER NOT NULL DEFAULT 0,
                    error TEXT NOT NULL DEFAULT '', UNIQUE(family_id,kind,job_key));
                CREATE INDEX IF NOT EXISTS job_claim ON jobs(state,available_at,lease_until);
                CREATE TABLE IF NOT EXISTS packs (
                    id TEXT PRIMARY KEY, family_id TEXT NOT NULL, child_id TEXT NOT NULL,
                    school_date TEXT NOT NULL, revision INTEGER NOT NULL, fingerprint TEXT NOT NULL,
                    status TEXT NOT NULL, payload TEXT NOT NULL, source_ids TEXT NOT NULL,
                    review TEXT NOT NULL DEFAULT '{}', analysis_revisions TEXT NOT NULL DEFAULT '{}', created_at REAL NOT NULL, published_at REAL,
                    UNIQUE(family_id,child_id,school_date,fingerprint));
                CREATE INDEX IF NOT EXISTS pack_day ON packs(family_id,child_id,school_date,revision);
                CREATE TABLE IF NOT EXISTS attempts (
                    id TEXT PRIMARY KEY, family_id TEXT NOT NULL, child_id TEXT NOT NULL,
                    pack_id TEXT NOT NULL, activity_id TEXT NOT NULL, payload TEXT NOT NULL,
                    created_at REAL NOT NULL);
                CREATE INDEX IF NOT EXISTS attempt_child ON attempts(family_id,child_id,created_at);
                CREATE TABLE IF NOT EXISTS analysis_history (
                    asset_id TEXT NOT NULL, family_id TEXT NOT NULL, source_hash TEXT NOT NULL,
                    revision INTEGER NOT NULL, state TEXT NOT NULL, payload TEXT NOT NULL,
                    error TEXT NOT NULL DEFAULT '', updated_at REAL NOT NULL,
                    PRIMARY KEY(asset_id,revision));
                CREATE TABLE IF NOT EXISTS source_moves (
                    source_id TEXT PRIMARY KEY, family_id TEXT NOT NULL, replacement_id TEXT NOT NULL,
                    old_day TEXT NOT NULL, new_day TEXT NOT NULL, moved_at REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS cursors (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS courses (
                    id TEXT PRIMARY KEY, family_id TEXT NOT NULL, child_id TEXT NOT NULL,
                    school_date TEXT NOT NULL, title TEXT NOT NULL, kind TEXT NOT NULL,
                    language TEXT NOT NULL DEFAULT 'en-US', created_by TEXT NOT NULL DEFAULT '',
                    deleted INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL);
                CREATE INDEX IF NOT EXISTS course_day ON courses(family_id,child_id,school_date,deleted);
            """)
            # Additive migration: preserve originals, prior confirmations, and every
            # existing row. Legacy dates are unconfirmed until a parent verifies them.
            db.execute("BEGIN IMMEDIATE")
            if "date_confirmed" not in {r["name"] for r in db.execute("PRAGMA table_info(sources)")}:
                db.execute("ALTER TABLE sources ADD COLUMN date_confirmed INTEGER NOT NULL DEFAULT 0")
            if "analysis_revisions" not in {r["name"] for r in db.execute("PRAGMA table_info(packs)")}:
                db.execute("ALTER TABLE packs ADD COLUMN analysis_revisions TEXT NOT NULL DEFAULT '{}'")
            # One parent upload is one lesson. Legacy automatic candidates keep
            # course_id='' and are no longer shown in the learning views.
            for table in ("sources", "packs"):
                if "course_id" not in {r["name"] for r in db.execute("PRAGMA table_info(" + table + ")")}:
                    db.execute("ALTER TABLE " + table + " ADD COLUMN course_id TEXT NOT NULL DEFAULT ''")
            # Large lessons arrive one file per request (proxies cap request size).
            # A course composes only after every announced file has arrived.
            if "expected_files" not in {r["name"] for r in db.execute("PRAGMA table_info(courses)")}:
                db.execute("ALTER TABLE courses ADD COLUMN expected_files INTEGER NOT NULL DEFAULT 0")
            db.execute("INSERT OR IGNORE INTO analysis_history SELECT * FROM analyses")
            db.execute("COMMIT")

    @contextmanager
    def db(self):
        connection = sqlite3.connect(self.db_path, timeout=20, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA busy_timeout=20000")
        for suffix in ("", "-wal", "-shm"):
            path = Path(str(self.db_path) + suffix)
            if path.exists():
                path.chmod(0o600)
        try:
            yield connection
        finally:
            connection.close()

    def add_source(self, family: str, child: str, day: str, origin: str,
                   name: str, content: bytes | Path, mime: str, *,
                   kind: str = "auto", language: str = "en-US", media_ref: dict | None = None,
                   course_id: str = "") -> dict:
        valid_day(day)
        if not family or not child or not origin or len(origin) > 250:
            raise ValueError("素材缺少家庭、孩子或来源标识")
        if kind not in {"auto", "teaching", "practice", "song", "daily", "care"}:
            raise ValueError("素材类别无效")
        if language not in {"en-US", "zh-CN"}:
            raise ValueError("暂支持中文或英文音轨")
        if mime not in {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif",
                        "video/mp4", "video/quicktime", "audio/mp4", "audio/mpeg", "audio/wav"}:
            raise ValueError("不支持的素材格式")
        name = Path(name.replace("\\", "/")).name[:180] or "素材"
        directory = self.root / "originals" / hashlib.sha256(family.encode()).hexdigest()[:24]
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, tmp = tempfile.mkstemp(dir=directory)
        checksum = hashlib.sha256()
        size = 0
        try:
            with os.fdopen(fd, "wb") as target:
                if isinstance(content, bytes):
                    target.write(content); checksum.update(content); size = len(content)
                else:
                    with Path(content).open("rb") as source:
                        for chunk in iter(lambda: source.read(1024 * 1024), b""):
                            size += len(chunk)
                            if size > 256 * 1024 * 1024:
                                raise ValueError("素材超过 256 MB")
                            checksum.update(chunk); target.write(chunk)
            if not size or size > 256 * 1024 * 1024:
                raise ValueError("素材为空或过大")
            sha = checksum.hexdigest()
            final = directory / sha
            if not final.exists():
                os.replace(tmp, final)
                final.chmod(0o600)
            with self.db() as db:
                db.execute("BEGIN IMMEDIATE")
                prior = db.execute("SELECT s.*,a.hash FROM sources s JOIN assets a ON a.id=s.asset_id "
                                   "WHERE s.family_id=? AND s.child_id=? AND s.school_date=? AND s.origin_key=?",
                                   (family, child, day, origin)).fetchone()
                if prior:
                    if prior["hash"] != sha or prior["deleted"]:
                        raise Conflict("此来源已经归档为不同内容，请创建新的来源记录")
                    db.execute("COMMIT")
                    return self.source(family, prior["id"])
                asset = db.execute("SELECT id FROM assets WHERE family_id=? AND hash=?", (family, sha)).fetchone()
                aid = asset["id"] if asset else uuid.uuid4().hex
                if not asset:
                    db.execute("INSERT INTO assets VALUES(?,?,?,?,?,?,?,?)", (
                        aid, family, sha, str(final.relative_to(self.root)), mime, size,
                        encoded(media_ref or {}), time.time()))
                sid = uuid.uuid4().hex
                if course_id:
                    course = db.execute("SELECT * FROM courses WHERE id=? AND family_id=? AND deleted=0", (course_id, family)).fetchone()
                    if not course or course["child_id"] != child or course["school_date"] != day:
                        raise ValueError("课程与素材的孩子或日期不一致")
                db.execute("INSERT INTO sources(id,family_id,child_id,school_date,origin_key,asset_id,name,kind,language,course_id,created_at) "
                           "VALUES(?,?,?,?,?,?,?,?,?,?,?)", (sid, family, child, day, origin, aid, name, kind, language, course_id, time.time()))
                analyzed = db.execute("SELECT state FROM analyses WHERE asset_id=? AND family_id=?", (aid, family)).fetchone()
                if analyzed and analyzed["state"] == "ready":
                    self._enqueue_compose(db, family, child, day, course_id)
                else:
                    self._enqueue(db, family, "analyze", aid, {"asset_id": aid})
                db.execute("COMMIT")
            return self.source(family, sid)
        finally:
            Path(tmp).unlink(missing_ok=True)

    def asset(self, family: str, aid: str) -> dict:
        with self.db() as db:
            row = db.execute("SELECT * FROM assets WHERE id=? AND family_id=?", (aid, family)).fetchone()
        if not row:
            raise Missing("素材不存在")
        result = dict(row); result["media_ref"] = json.loads(result["media_ref"])
        return result

    def asset_path(self, family: str, aid: str) -> Path:
        path = (self.root / self.asset(family, aid)["path"]).resolve(strict=True)
        if not path.is_relative_to(self.root / "originals"):
            raise Missing("素材路径无效")
        return path

    def source(self, family: str, sid: str) -> dict:
        with self.db() as db:
            row = db.execute("SELECT s.*,a.hash,a.mime,a.size FROM sources s JOIN assets a ON a.id=s.asset_id "
                             "WHERE s.id=? AND s.family_id=? AND s.deleted=0", (sid, family)).fetchone()
        if not row:
            raise Missing("来源不存在")
        return dict(row)

    def sources(self, family: str, child: str, day: str | None = None, *, course_id: str | None = None) -> list[dict]:
        query = "SELECT s.*,a.hash,a.mime,a.size FROM sources s JOIN assets a ON a.id=s.asset_id " \
                "WHERE s.family_id=? AND s.child_id=? AND s.deleted=0"
        values = [family, child]
        if day is not None:
            query += " AND s.school_date=?"; values.append(valid_day(day))
        if course_id is not None:
            query += " AND s.course_id=?"; values.append(course_id)
        with self.db() as db:
            return [dict(r) for r in db.execute(query + " ORDER BY s.school_date DESC,s.created_at", values)]

    def asset_sources(self, family: str, aid: str) -> list[dict]:
        with self.db() as db:
            return [dict(r) for r in db.execute("SELECT * FROM sources WHERE family_id=? AND asset_id=? AND deleted=0", (family, aid))]

    def remove_source(self, family: str, sid: str) -> None:
        self.source(family, sid)
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("UPDATE sources SET deleted=1 WHERE id=? AND family_id=?", (sid, family))
            db.execute("UPDATE packs SET status='revoked' WHERE family_id=? "
                       "AND EXISTS(SELECT 1 FROM json_each(packs.source_ids) WHERE value=?)", (family, sid))
            db.execute("COMMIT")

    @staticmethod
    def _source_in(db, family: str, sid: str):
        row = db.execute("SELECT s.*,a.hash FROM sources s JOIN assets a ON a.id=s.asset_id "
                         "WHERE s.id=? AND s.family_id=? AND s.deleted=0", (sid, family)).fetchone()
        if not row:
            raise Missing("来源不存在")
        return row

    @staticmethod
    def _revoke_source(db, family: str, sid: str) -> None:
        db.execute("UPDATE packs SET status='revoked' WHERE family_id=? AND status IN ('draft','published') "
                   "AND EXISTS(SELECT 1 FROM json_each(packs.source_ids) WHERE value=?)", (family, sid))

    def _set_analysis(self, db, family: str, aid: str, payload: dict, state: str, error: str,
                      expected_revision: int | None = None) -> dict:
        if state not in {"queued", "processing", "ready", "failed", "unavailable"}:
            raise ValueError("解析状态无效")
        asset = db.execute("SELECT hash FROM assets WHERE id=? AND family_id=?", (aid, family)).fetchone()
        if not asset:
            raise Missing("素材不存在")
        old = db.execute("SELECT * FROM analyses WHERE asset_id=? AND family_id=?", (aid, family)).fetchone()
        prior_revision = old["revision"] if old else 0
        if expected_revision is not None and expected_revision != prior_revision:
            raise Conflict("素材解析已经更新，请重新核对")
        if old:
            db.execute("INSERT OR IGNORE INTO analysis_history VALUES(?,?,?,?,?,?,?,?)", tuple(old))
        revision = prior_revision + 1
        values = (aid, family, asset["hash"], revision, state, encoded(payload), error[:250], time.time())
        db.execute("INSERT INTO analyses VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(asset_id) DO UPDATE SET "
                   "revision=excluded.revision,state=excluded.state,payload=excluded.payload,error=excluded.error,updated_at=excluded.updated_at", values)
        db.execute("INSERT INTO analysis_history VALUES(?,?,?,?,?,?,?,?)", values)
        for source in db.execute("SELECT id,child_id,school_date,course_id FROM sources WHERE family_id=? AND asset_id=? AND deleted=0", (family, aid)).fetchall():
            self._revoke_source(db, family, source["id"])
            if state == "ready":
                self._enqueue_compose(db, family, source["child_id"], source["school_date"], source["course_id"])
        return {"asset_id": aid, "family_id": family, "source_hash": asset["hash"], "revision": revision,
                "state": state, "payload": payload, "error": error[:250], "updated_at": values[-1]}

    def set_analysis(self, family: str, aid: str, payload: dict, state: str = "ready", error: str = "", *,
                     expected_revision: int | None = None) -> dict:
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            result = self._set_analysis(db, family, aid, payload, state, error, expected_revision)
            db.execute("COMMIT")
        return result

    def analysis(self, family: str, aid: str) -> dict | None:
        with self.db() as db:
            row = db.execute("SELECT * FROM analyses WHERE family_id=? AND asset_id=?", (family, aid)).fetchone()
        if not row:
            return None
        value = dict(row); value["payload"] = json.loads(value["payload"])
        return value

    def analysis_history(self, family: str, aid: str) -> list[dict]:
        self.asset(family, aid)
        with self.db() as db:
            rows = db.execute("SELECT * FROM analysis_history WHERE family_id=? AND asset_id=? ORDER BY revision", (family, aid)).fetchall()
        return [{**dict(row), "payload": json.loads(row["payload"])} for row in rows]

    def _move_source_date(self, db, family: str, sid: str, day: str, date_confirmed: bool) -> str:
        source = self._source_in(db, family, sid)
        if source["course_id"] and source["school_date"] != day:
            raise ValueError("课程素材的日期由整节课决定")
        if source["school_date"] == day:
            db.execute("UPDATE sources SET date_confirmed=? WHERE id=? AND family_id=?", (int(date_confirmed), sid, family))
            if not date_confirmed:
                self._revoke_source(db, family, sid)
            return sid
        target = db.execute("SELECT * FROM sources WHERE family_id=? AND child_id=? AND school_date=? AND origin_key=?",
                            (family, source["child_id"], day, source["origin_key"])).fetchone()
        if target and target["asset_id"] != source["asset_id"]:
            raise Conflict("目标日期已有不同来源内容，请先核对后再调整日期")
        origin = source["origin_key"]
        if target and target["deleted"]:
            # Moving back to a previously corrected day must not resurrect the
            # historical occurrence (or its old pack). Preserve it and append one.
            origin = origin[:180] + ":correction:" + uuid.uuid4().hex
            target = None
        replacement = target["id"] if target else uuid.uuid4().hex
        if target:
            db.execute("UPDATE sources SET date_confirmed=? WHERE id=? AND family_id=?", (int(date_confirmed), replacement, family))
            if not date_confirmed:
                self._revoke_source(db, family, replacement)
        else:
            db.execute("INSERT INTO sources(id,family_id,child_id,school_date,origin_key,asset_id,name,kind,language,date_confirmed,created_at) "
                       "VALUES(?,?,?,?,?,?,?,?,?,?,?)", (replacement, family, source["child_id"], day, origin,
                       source["asset_id"], source["name"], source["kind"], source["language"], int(date_confirmed), time.time()))
        # Retain the original occurrence and its old day rather than overwriting history.
        db.execute("UPDATE sources SET deleted=1 WHERE id=? AND family_id=?", (sid, family))
        db.execute("INSERT INTO source_moves VALUES(?,?,?,?,?,?)", (sid, family, replacement, source["school_date"], day, time.time()))
        self._revoke_source(db, family, sid)
        child = source["child_id"]
        for changed_day in {source["school_date"], day}:
            self._enqueue_compose(db, family, child, changed_day, "")
        return replacement

    def move_source_date(self, family: str, sid: str, school_date: str, *, date_confirmed: bool = False,
                         expected_day: str | None = None) -> dict:
        valid_day(school_date)
        if type(date_confirmed) is not bool:
            raise ValueError("日期确认格式无效")
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            source = self._source_in(db, family, sid)
            if expected_day is not None and expected_day != source["school_date"]:
                raise Conflict("素材日期已经变化，请重新核对")
            replacement = self._move_source_date(db, family, sid, school_date, date_confirmed)
            db.execute("COMMIT")
        return self.source(family, replacement)

    def update_source_analysis(self, family: str, sid: str, expected_revision: int, payload: dict,
                               school_date: str, date_confirmed: bool) -> dict:
        """Parent correction commits analysis CAS, history, date move and revocation together."""
        valid_day(school_date)
        if type(date_confirmed) is not bool:
            raise ValueError("日期确认格式无效")
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            source = self._source_in(db, family, sid)
            replacement = self._move_source_date(db, family, sid, school_date, date_confirmed)
            self._set_analysis(db, family, source["asset_id"], payload, "ready", "", expected_revision)
            db.execute("COMMIT")
        return self.source(family, replacement)

    @classmethod
    def _enqueue_compose(cls, db, family: str, child: str, day: str, course_id: str = "", nonce: str = "") -> str:
        payload = {"child_id": child, "school_date": day}
        if course_id:
            payload["course_id"] = course_id
        if nonce:
            payload["nonce"] = nonce
        return cls._enqueue(db, family, "compose", compose_key(child, day, course_id), payload, force=True)

    def enqueue_compose(self, family: str, child: str, day: str, course_id: str = "", nonce: str = "") -> str:
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            jid = self._enqueue_compose(db, family, child, day, course_id, nonce)
            db.execute("COMMIT")
        return jid

    # Parent-declared lessons. A course groups exactly the files of one upload.
    def create_course(self, family: str, child: str, day: str, title: str, kind: str,
                      language: str = "en-US", created_by: str = "", expected_files: int = 0) -> dict:
        valid_day(day)
        title = " ".join(str(title).split())[:60]
        if not family or not child or not title:
            raise ValueError("课程缺少名称")
        if kind not in COURSE_KINDS or language not in {"en-US", "zh-CN"}:
            raise ValueError("课程类型或语言无效")
        if type(expected_files) is not int or not 0 <= expected_files <= 8:
            raise ValueError("课程文件数量无效")
        cid = uuid.uuid4().hex
        with self.db() as db:
            db.execute("INSERT INTO courses(id,family_id,child_id,school_date,title,kind,language,created_by,created_at,expected_files) "
                       "VALUES(?,?,?,?,?,?,?,?,?,?)", (cid, family, child, day, title, kind, language, created_by[:100], time.time(), expected_files))
        return self.course(family, cid)

    def course(self, family: str, cid: str) -> dict:
        with self.db() as db:
            row = db.execute("SELECT * FROM courses WHERE id=? AND family_id=? AND deleted=0", (cid, family)).fetchone()
        if not row:
            raise Missing("课程不存在")
        return dict(row)

    def course_file_count(self, family: str, cid: str) -> int:
        with self.db() as db:
            return db.execute("SELECT count(*) FROM sources WHERE family_id=? AND course_id=? AND deleted=0", (family, cid)).fetchone()[0]

    def course_sealed(self, family: str, cid: str) -> bool:
        return self.course_file_count(family, cid) >= self.course(family, cid)["expected_files"]

    def courses(self, family: str, child: str, start: str, end: str) -> list[dict]:
        valid_day(start); valid_day(end)
        with self.db() as db:
            return [dict(r) for r in db.execute(
                "SELECT * FROM courses WHERE family_id=? AND child_id=? AND deleted=0 AND school_date>=? AND school_date<=? "
                "ORDER BY school_date DESC,created_at DESC LIMIT 500", (family, child, start, end))]

    def remove_course(self, family: str, cid: str) -> None:
        self.course(family, cid)
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("UPDATE courses SET deleted=1 WHERE id=? AND family_id=?", (cid, family))
            db.execute("UPDATE sources SET deleted=1 WHERE course_id=? AND family_id=?", (cid, family))
            db.execute("UPDATE packs SET status='revoked' WHERE course_id=? AND family_id=? AND status IN ('draft','published','no_lesson')", (cid, family))
            db.execute("DELETE FROM jobs WHERE family_id=? AND kind='compose' AND state!='running' AND job_key LIKE ?", (family, "%:" + cid))
            db.execute("COMMIT")

    @staticmethod
    def _enqueue(db, family: str, kind: str, key: str, payload: dict, *, force: bool = False) -> str:
        if kind not in {"analyze", "compose"}:
            raise ValueError("不支持的学习任务")
        prior = db.execute("SELECT id,state FROM jobs WHERE family_id=? AND kind=? AND job_key=?", (family, kind, key)).fetchone()
        if prior:
            if force:
                if prior["state"] == "running":
                    db.execute("UPDATE jobs SET rerun=1,payload=? WHERE id=?", (encoded(payload), prior["id"]))
                else:
                    db.execute("UPDATE jobs SET state='queued',payload=?,attempts=0,available_at=?,error='' WHERE id=?", (encoded(payload), time.time(), prior["id"]))
            return prior["id"]
        jid = uuid.uuid4().hex
        db.execute("INSERT INTO jobs(id,family_id,kind,job_key,payload,available_at) VALUES(?,?,?,?,?,?)",
                   (jid, family, kind, key, encoded(payload), time.time()))
        return jid

    def enqueue(self, family: str, kind: str, key: str, payload: dict, *, force: bool = False) -> str:
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            jid = self._enqueue(db, family, kind, key, payload, force=force)
            db.execute("COMMIT")
        return jid

    def claim(self, *, now: float | None = None, lease: float = 600, family: str | None = None) -> dict | None:
        now = time.time() if now is None else now
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            where = "((state='queued' AND available_at<=?) OR (state='running' AND lease_until<=?))"
            parameters = [now, now]
            if family is not None:
                where += " AND family_id=?"
                parameters.append(family)
            row = db.execute("SELECT * FROM jobs WHERE " + where + " ORDER BY available_at LIMIT 1", parameters).fetchone()
            if not row:
                db.execute("COMMIT"); return None
            owner = uuid.uuid4().hex
            db.execute("UPDATE jobs SET state='running',lease_until=?,lease_owner=?,attempts=attempts+1,rerun=0 WHERE id=?",
                       (now+lease, owner, row["id"]))
            db.execute("COMMIT")
        result = dict(row); result.update(lease_owner=owner, lease_until=now+lease, attempts=row["attempts"]+1)
        result["payload"] = json.loads(result["payload"])
        return result

    def finish_job(self, job: dict, *, success: bool, error: str = "", defer: bool = False) -> None:
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT rerun,attempts FROM jobs WHERE id=? AND state='running' AND lease_owner=?",
                             (job["id"], job["lease_owner"])).fetchone()
            if not row:
                raise Conflict("任务租约已经变化")
            repeat = row["rerun"] or defer
            state = "queued" if repeat else "done" if success else "failed" if row["attempts"] >= 3 else "queued"
            delay = 5 if defer else 0 if repeat or success else min(3600, 60*2**(row["attempts"]-1))
            db.execute("UPDATE jobs SET state=?,available_at=?,lease_owner=NULL,lease_until=NULL,error=?,attempts=?,rerun=0 WHERE id=?",
                       (state, time.time()+delay, error[:250], 0 if repeat else row["attempts"], job["id"]))
            db.execute("COMMIT")

    def jobs(self, family: str) -> list[dict]:
        with self.db() as db:
            return [dict(r) for r in db.execute("SELECT id,kind,state,attempts,error,available_at FROM jobs WHERE family_id=? ORDER BY available_at DESC LIMIT 100", (family,))]

    def backup_to(self, destination: Path) -> None:
        """Online SQLite snapshot plus immutable originals; WAL is never copied as a database."""
        destination = Path(destination)
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self.db() as source, sqlite3.connect(destination / "learning.sqlite") as target:
            source.backup(target)
        for name in ("originals", "derived"):
            if (self.root / name).exists():
                shutil.copytree(self.root / name, destination / name, dirs_exist_ok=True)

    @staticmethod
    def _pack_row(row) -> dict:
        result = dict(row)
        for key in ("payload", "source_ids", "review", "analysis_revisions"):
            result[key] = json.loads(result[key])
        return result

    def create_pack(self, family: str, child: str, day: str, payload: dict, source_ids: list[str],
                    course_id: str = "") -> dict:
        valid_day(day)
        if not source_ids or len(source_ids) > 100 or len(set(source_ids)) != len(source_ids):
            raise ValueError("课程缺少来源、来源重复或来源过多")
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            revisions, fingerprints = {}, []
            for sid in source_ids:
                source = self._source_in(db, family, sid)
                if source["child_id"] != child or source["school_date"] != day or source["course_id"] != course_id:
                    raise ValueError("课程来源不属于同一个孩子、授课日和课程")
                analysis = db.execute("SELECT revision,state FROM analyses WHERE asset_id=? AND family_id=?",
                                      (source["asset_id"], family)).fetchone()
                if not analysis or analysis["state"] != "ready":
                    raise Conflict("课程来源尚未完成解析")
                revisions[source["asset_id"]] = analysis["revision"]
                fingerprints.append((sid, source["hash"], analysis["revision"]))
            # Worker generation may race with a correction; don't attach old model
            # output to a fresh analysis revision even when the source IDs match.
            if payload.get("source_fingerprint") and payload["source_fingerprint"] != digest(fingerprints):
                raise Conflict("生成期间素材已更新，请重新生成课程")
            fingerprint = digest({"payload": payload, "sources": sorted(source_ids), "analyses": revisions})
            prior = db.execute("SELECT * FROM packs WHERE family_id=? AND child_id=? AND school_date=? AND fingerprint=?",
                               (family, child, day, fingerprint)).fetchone()
            if prior:
                db.execute("COMMIT"); return self._pack_row(prior)
            revision = db.execute("SELECT coalesce(max(revision),0)+1 FROM packs WHERE family_id=? AND child_id=? AND school_date=? AND course_id=?",
                                  (family, child, day, course_id)).fetchone()[0]
            pid = uuid.uuid4().hex
            status = "draft" if payload.get("activities") else "no_lesson"
            db.execute("UPDATE packs SET status='superseded' WHERE family_id=? AND child_id=? AND school_date=? AND course_id=? "
                       "AND status IN ('draft','published','no_lesson')", (family, child, day, course_id))
            db.execute("INSERT INTO packs(id,family_id,child_id,school_date,revision,fingerprint,status,payload,source_ids,analysis_revisions,created_at,course_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                       (pid, family, child, day, revision, fingerprint, status, encoded(payload), encoded(source_ids), encoded(revisions), time.time(), course_id))
            db.execute("COMMIT")
        return self.pack(family, pid)

    def exclude_activity(self, family: str, pid: str, revision: int, activity_id: str) -> dict:
        """Remove a reviewed activity without letting a stale page replace a newer pack."""
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM packs WHERE family_id=? AND id=?", (family, pid)).fetchone()
            if not row:
                raise Missing("课程不存在")
            pack = self._pack_row(row)
            if pack["revision"] != revision or pack["status"] not in {"draft", "published"}:
                raise Conflict("课程内容已经变化，请重新核对")
            self._check_pack_sources(db, family, pack, dates_confirmed=False)
            payload = pack["payload"]
            activities = payload.get("activities", [])
            if activity_id not in {activity["id"] for activity in activities}:
                raise ValueError("活动不属于当前课程")
            payload["activities"] = [activity for activity in activities if activity["id"] != activity_id]
            payload["generation_nonce"] = "excluded:" + uuid.uuid4().hex
            fingerprint = digest({"payload": payload, "sources": sorted(pack["source_ids"]), "analyses": pack["analysis_revisions"]})
            course_id = pack["course_id"]
            new_revision = db.execute("SELECT coalesce(max(revision),0)+1 FROM packs WHERE family_id=? AND child_id=? AND school_date=? AND course_id=?",
                                      (family, pack["child_id"], pack["school_date"], course_id)).fetchone()[0]
            new_id = uuid.uuid4().hex
            status = "draft" if payload["activities"] else "no_lesson"
            db.execute("UPDATE packs SET status='superseded' WHERE family_id=? AND child_id=? AND school_date=? AND course_id=? AND status IN ('draft','published')",
                       (family, pack["child_id"], pack["school_date"], course_id))
            db.execute("INSERT INTO packs(id,family_id,child_id,school_date,revision,fingerprint,status,payload,source_ids,analysis_revisions,created_at,course_id) "
                       "VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", (new_id, family, pack["child_id"], pack["school_date"], new_revision, fingerprint, status,
                        encoded(payload), encoded(pack["source_ids"]), encoded(pack["analysis_revisions"]), time.time(), course_id))
            db.execute("COMMIT")
        return self.pack(family, new_id)

    def _check_pack_sources(self, db, family: str, pack: dict, *, dates_confirmed: bool = True) -> None:
        if not pack["analysis_revisions"]:
            raise Conflict("课程缺少当前解析版本，请重新生成并核对")
        for sid in pack["source_ids"]:
            try:
                source = self._source_in(db, family, sid)
            except Missing as exc:
                raise Conflict("课程来源已撤回") from exc
            if (source["child_id"] != pack["child_id"] or source["school_date"] != pack["school_date"]
                    or source["course_id"] != pack.get("course_id", "")):
                raise Conflict("来源日期或孩子已经变化，请重新生成")
            if dates_confirmed and not source["date_confirmed"]:
                raise Conflict("授课日期尚未确认")
            analysis = db.execute("SELECT revision,state FROM analyses WHERE asset_id=? AND family_id=?", (source["asset_id"], family)).fetchone()
            if not analysis or analysis["state"] != "ready" or pack["analysis_revisions"].get(source["asset_id"]) != analysis["revision"]:
                raise Conflict("素材解析已经变化，请重新核对课程")

    def pack(self, family: str, pid: str, *, require_published: bool = False) -> dict:
        with self.db() as db:
            row = db.execute("SELECT * FROM packs WHERE family_id=? AND id=?", (family, pid)).fetchone()
            if not row:
                raise Missing("课程不存在")
            result = self._pack_row(row)
            if require_published:
                if result["status"] != "published":
                    raise Conflict("课程尚未确认或来源已经更新")
                self._check_pack_sources(db, family, result)
        return result

    def packs(self, family: str, child: str, day: str | None = None, *, published_only: bool = False,
              course_id: str | None = None, courses_only: bool = False) -> list[dict]:
        where = "family_id=? AND child_id=?"
        args = [family, child]
        if day:
            where += " AND school_date=?"; args.append(valid_day(day))
        if course_id is not None:
            where += " AND course_id=?"; args.append(course_id)
        elif courses_only:
            where += " AND course_id!=''"
        if published_only:
            where += " AND status='published'"
        with self.db() as db:
            rows = db.execute("SELECT * FROM packs WHERE " + where + " ORDER BY school_date DESC,revision DESC LIMIT 500", args).fetchall()
        result = []
        for row in rows:
            if published_only:
                try:
                    result.append(self.pack(family, row["id"], require_published=True))
                except Conflict:
                    continue
            else:
                result.append(self._pack_row(row))
        return result

    def publish(self, family: str, pid: str, revision: int, reviewer: str, confirmations: list[dict], *,
                date_confirmed: bool = False) -> dict:
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM packs WHERE family_id=? AND id=?", (family, pid)).fetchone()
            if not row:
                raise Missing("课程不存在")
            pack = self._pack_row(row)
            if pack["revision"] != revision or pack["status"] not in {"draft", "published"}:
                raise Conflict("课程内容已经变化，请重新核对")
            expected = {a["id"]: digest(a) for a in pack["payload"].get("activities", [])}
            actual = {r.get("activity_id"): r.get("digest") for r in confirmations if r.get("verified") is True}
            if not expected or expected != actual or len(confirmations) != len(expected):
                raise Conflict("请逐项核对当前版本的题目原声、答案和图片")
            self._check_pack_sources(db, family, pack, dates_confirmed=date_confirmed is not True)
            if date_confirmed is True:
                for sid in pack["source_ids"]:
                    db.execute("UPDATE sources SET date_confirmed=1 WHERE id=? AND family_id=?", (sid, family))
            db.execute("UPDATE packs SET status='published',review=?,published_at=? WHERE id=? AND family_id=?",
                       (encoded({"reviewer": reviewer, "confirmations": confirmations, "date_confirmed": True}), time.time(), pid, family))
            db.execute("COMMIT")
        return self.pack(family, pid, require_published=True)

    def save_attempt(self, family: str, child: str, pid: str, attempt_id: str, body: dict) -> dict:
        if not attempt_id or len(attempt_id) > 100:
            raise ValueError("互动记录标识无效")
        allowed = {"activity_id", "kind", "choice", "run_id", "assistance", "note", "occurred_at"}
        if set(body) - allowed or len(encoded(body)) > 4000:
            raise ValueError("互动记录格式无效")
        pack = self.pack(family, pid, require_published=True)
        if pack["child_id"] != child:
            raise Missing("课程不属于当前孩子")
        activity = next((a for a in pack["payload"].get("activities", []) if a["id"] == body.get("activity_id")), None)
        if not activity:
            raise ValueError("互动不属于当前课程版本")
        kind = body.get("kind")
        if kind not in {"choice", "replay", "model", "speaking_attempt", "participation", "parent_observation", "skip"}:
            raise ValueError("互动类别无效")
        result = dict(body)
        result["concept"] = activity.get("concept", "")
        result["correct"] = None
        if kind == "choice":
            if body.get("choice") not in {c["id"] for c in activity.get("choices", [])}:
                raise ValueError("选项不属于这道题")
            result["correct"] = body["choice"] == activity.get("correct_choice")
        result["request_digest"] = digest(body)
        with self.db() as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT * FROM attempts WHERE id=?", (attempt_id,)).fetchone()
            if old:
                if old["family_id"] != family or old["child_id"] != child:
                    raise Missing("记录不存在")
                prior = json.loads(old["payload"])
                if old["pack_id"] != pid or prior.get("request_digest") != digest(body):
                    raise Conflict("同一互动标识已保存其他内容")
                db.execute("COMMIT"); return prior
            db.execute("INSERT INTO attempts VALUES(?,?,?,?,?,?,?)", (attempt_id, family, child, pid,
                       body["activity_id"], encoded(result), time.time()))
            db.execute("COMMIT")
        return result

    def attempts(self, family: str, child: str, limit: int = 1000) -> list[dict]:
        with self.db() as db:
            rows = db.execute("SELECT * FROM attempts WHERE family_id=? AND child_id=? ORDER BY created_at DESC LIMIT ?",
                              (family, child, min(max(limit, 1), 5000))).fetchall()
        return [{"id": r["id"], "pack_id": r["pack_id"], "created_at": r["created_at"], **json.loads(r["payload"])} for r in rows]

    def set_cursor(self, key: str, value: Any) -> None:
        with self.db() as db:
            db.execute("INSERT INTO cursors VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, encoded(value)))

    def get_cursor(self, key: str, default=None):
        with self.db() as db:
            row = db.execute("SELECT value FROM cursors WHERE key=?", (key,)).fetchone()
        return json.loads(row[0]) if row else default
