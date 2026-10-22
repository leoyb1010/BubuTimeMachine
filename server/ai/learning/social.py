"""家人互动: comments and hearts on timeline items, kept in learning.sqlite only.

Any signed-in family member may comment or heart; only the author deletes a comment.
The second brain is never written. An optional ntfy topic hears that a comment
arrived (who, not what was written).
"""
from __future__ import annotations

from datetime import datetime, timezone
import logging
import os
from pathlib import Path
import re
import threading
import time
import uuid

import httpx

from .store import Missing

log = logging.getLogger("bubu.learning.social")
DEFAULT_AUTHOR = "家人"


def _iso(value):
    return datetime.fromtimestamp(value, timezone.utc).isoformat()


def author(scope):
    return (getattr(scope, "display_name", "") or "").strip() or DEFAULT_AUTHOR


def notify(name):
    """Fire-and-forget push; silently skipped unless BUBU_SOCIAL_NTFY_URL is configured."""
    url = os.environ.get("BUBU_SOCIAL_NTFY_URL", "").strip()
    if not url:
        return None
    token = os.environ.get("BUBU_SOCIAL_NTFY_TOKEN", "").strip()
    token_file = os.environ.get("BUBU_SOCIAL_NTFY_TOKEN_FILE", "").strip()
    if not token and token_file:
        try:
            token = Path(token_file).read_text().strip()
        except OSError:
            token = ""

    def send():
        headers = {"Title": "布布时光机", "Tags": "speech_balloon"}
        if token:
            headers["Authorization"] = "Bearer " + token
        try:
            with httpx.Client(timeout=5, trust_env=False) as client:
                client.post(url, content=("%s评论了布布的一条时光" % name).encode(), headers=headers)
        except Exception as exc:
            log.warning("social push failed error=%s", type(exc).__name__)

    thread = threading.Thread(target=send, name="social-ntfy", daemon=True)
    thread.start()
    return thread


class Social:
    def __init__(self, timeline):
        self.timeline, self.store, self.family = timeline, timeline.store, timeline.family
        with self.store.db() as db:
            db.execute("CREATE TABLE IF NOT EXISTS social_comments (id TEXT PRIMARY KEY, family_id TEXT NOT NULL, "
                       "item_id TEXT NOT NULL, user_id TEXT NOT NULL, author TEXT NOT NULL, text TEXT NOT NULL, "
                       "created_at REAL NOT NULL)")
            db.execute("CREATE INDEX IF NOT EXISTS social_comment_item ON social_comments(family_id,item_id,created_at)")
            db.execute("CREATE TABLE IF NOT EXISTS social_hearts (family_id TEXT NOT NULL, item_id TEXT NOT NULL, "
                       "user_id TEXT NOT NULL, author TEXT NOT NULL, created_at REAL NOT NULL, "
                       "PRIMARY KEY(family_id,item_id,user_id))")

    def _item(self, scope, fid):
        self.timeline.authorize(scope)
        if not isinstance(fid, str) or not re.fullmatch(r"[a-f0-9]{24}", fid) \
                or fid not in self.timeline.snapshot()["rows_by_id"]:
            raise Missing("素材不存在")
        return fid

    @staticmethod
    def _comment(row, user):
        return {"id": row["id"], "author": row["author"], "text": row["text"], "created_at": _iso(row["created_at"]),
                "mine": row["user_id"] == user}

    def _hearts(self, db, fid, user):
        rows = db.execute("SELECT user_id FROM social_hearts WHERE family_id=? AND item_id=?", (self.family, fid)).fetchall()
        return {"hearts": len(rows), "hearted": any(r["user_id"] == user for r in rows)}

    def social(self, scope, fid):
        fid = self._item(scope, fid)
        with self.store.db() as db:
            comments = db.execute("SELECT * FROM social_comments WHERE family_id=? AND item_id=? ORDER BY created_at,id",
                                  (self.family, fid)).fetchall()
            return {"comments": [self._comment(r, scope.user_id) for r in comments], **self._hearts(db, fid, scope.user_id)}

    def comment(self, scope, fid, text):
        fid = self._item(scope, fid)
        text = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", str(text or "")).strip()
        if not 1 <= len(text) <= 300:
            raise ValueError("评论长度无效")
        row = {"id": uuid.uuid4().hex, "family_id": self.family, "item_id": fid, "user_id": scope.user_id,
               "author": author(scope), "text": text, "created_at": time.time()}
        with self.store.db() as db:
            db.execute("INSERT INTO social_comments VALUES(:id,:family_id,:item_id,:user_id,:author,:text,:created_at)", row)
        notify(row["author"])
        return self._comment(row, scope.user_id)

    def delete_comment(self, scope, fid, cid):
        fid = self._item(scope, fid)
        with self.store.db() as db:
            row = db.execute("SELECT user_id FROM social_comments WHERE id=? AND family_id=? AND item_id=?",
                             (str(cid), self.family, fid)).fetchone()
            if row is None or row["user_id"] != scope.user_id:
                raise Missing("评论不存在")
            db.execute("DELETE FROM social_comments WHERE id=?", (str(cid),))

    def heart(self, scope, fid, on):
        fid = self._item(scope, fid)
        with self.store.db() as db:
            if on:
                db.execute("INSERT OR IGNORE INTO social_hearts VALUES(?,?,?,?,?)",
                           (self.family, fid, scope.user_id, author(scope), time.time()))
            else:
                db.execute("DELETE FROM social_hearts WHERE family_id=? AND item_id=? AND user_id=?",
                           (self.family, fid, scope.user_id))
            return self._hearts(db, fid, scope.user_id)

    def recent(self, scope, limit=20):
        self.timeline.authorize(scope)
        if type(limit) is not int or not 1 <= limit <= 100:
            raise ValueError("数量无效")
        rows = self.timeline.snapshot()["rows_by_id"]
        with self.store.db() as db:
            events = db.execute(
                "SELECT item_id,author,text,'comment' AS kind,created_at FROM social_comments WHERE family_id=? "
                "UNION ALL SELECT item_id,author,NULL,'heart',created_at FROM social_hearts WHERE family_id=? "
                "ORDER BY created_at DESC LIMIT ?", (self.family, self.family, limit * 3)).fetchall()
        items = [{"item_id": e["item_id"], "author": e["author"], "text": e["text"], "kind": e["kind"],
                  "created_at": _iso(e["created_at"]), "preview_url": self.timeline.public(rows[e["item_id"]])["preview_url"]}
                 for e in events if e["item_id"] in rows]
        return {"items": items[:limit]}
