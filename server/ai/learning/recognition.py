"""认一认: families confirm or reject uncertain library photos of the child.

Candidates are photos the second brain judged uncertain for her (state='checked',
confidence >= 0.5) or filed under her folder without any judgement. Decisions
live only in learning.sqlite; the library is never written. 'yes' adds the
photo to the online timeline (provenance family_confirmed); 'no' removes it.
"""
from __future__ import annotations

from datetime import datetime, timezone
import re
import threading
import time

from .store import Missing

READY: set[str] = set()


def _ensure(store) -> None:
    key = str(store.db_path)
    if key in READY:
        return
    with store.db() as db:
        db.execute("CREATE TABLE IF NOT EXISTS recognition_decisions (family_id TEXT NOT NULL, file_id TEXT NOT NULL, "
                   "decision TEXT NOT NULL, decided_by TEXT NOT NULL, decided_at REAL NOT NULL, "
                   "PRIMARY KEY(family_id,file_id))")
    READY.add(key)


def decisions(store, family: str) -> dict[str, str]:
    _ensure(store)
    with store.db() as db:
        return {r["file_id"]: r["decision"] for r in db.execute(
            "SELECT file_id,decision FROM recognition_decisions WHERE family_id=?", (family,))}


class Recognition:
    def __init__(self, bridge, timeline, *, ttl=600):
        self.bridge, self.timeline, self.ttl = bridge, timeline, ttl
        self.store, self.family = timeline.store, timeline.family
        self.lock = threading.Lock()
        self.cached, self.cached_at = None, 0.0
        _ensure(self.store)

    def _candidates(self) -> list[dict]:
        with self.lock:
            if self.cached is None or time.monotonic() - self.cached_at > self.ttl:
                self.cached = self.bridge.recognition_candidates(self.timeline.subject)
                self.cached_at = time.monotonic()
            return self.cached

    def _open(self) -> list[dict]:
        decided = decisions(self.store, self.family)
        born = self.timeline.born
        result = []
        for item in self._candidates():
            if item["file_id"] in decided:
                continue
            stamp = self.timeline.stamp(item.get("captured_at"))
            if born and (not stamp or stamp[:10] < born):
                continue
            result.append({**item, "stamp": stamp})
        return result

    def candidates(self, scope, limit=20):
        self.timeline.authorize(scope)
        if type(limit) is not int or not 1 <= limit <= 100:
            raise ValueError("数量无效")
        rows = self._open()
        items = [{"id": r["file_id"], "preview_url": "/learning/api/recognition/%s/preview" % r["file_id"],
                  "captured_at": r["stamp"], "confidence": r.get("confidence"),
                  "description": str((r.get("analysis") or {}).get("description") or "")} for r in rows[:limit]]
        return {"items": items, "remaining": max(0, len(rows) - len(items))}

    def _item(self, fid: str) -> dict | None:
        if not isinstance(fid, str) or not re.fullmatch(r"[a-f0-9]{24}", fid):
            return None
        hit = next((i for i in self._candidates() if i["file_id"] == fid), None)
        if hit:
            return hit
        hit = self.timeline.snapshot()["by_id"].get(fid)
        if hit:
            return hit
        if fid in decisions(self.store, self.family):
            found = self.bridge.items_by_ids([fid], self.timeline.subject)
            return found[0] if found else None
        return None

    def preview(self, scope, fid):
        self.timeline.authorize(scope)
        item = self._item(fid)
        if item is None:
            raise Missing("素材不存在")
        return self.timeline.render_preview(item, "thumb")

    def decide(self, scope, fid, decision):
        self.timeline.authorize(scope)
        scope.require_review()
        if decision not in {"yes", "no", "undo"}:
            raise ValueError("决定无效")
        if decision == "undo":
            # Back to the second brain's own judgement; an unknown id is simply a no-op.
            if not isinstance(fid, str) or not re.fullmatch(r"[a-f0-9]{24}", fid):
                raise Missing("素材不存在")
            with self.store.db() as db:
                db.execute("DELETE FROM recognition_decisions WHERE family_id=? AND file_id=?", (self.family, fid))
            self.timeline.invalidate()
            return {"id": fid, "decision": "undo"}
        if self._item(fid) is None:
            raise Missing("素材不存在")
        self._save([(fid, decision)], scope.user_id)
        return {"id": fid, "decision": decision}

    def _save(self, pairs, user):
        now = time.time()
        with self.store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            for fid, decision in pairs:
                db.execute("INSERT INTO recognition_decisions VALUES(?,?,?,?,?) ON CONFLICT(family_id,file_id) DO UPDATE SET "
                           "decision=excluded.decision,decided_by=excluded.decided_by,decided_at=excluded.decided_at",
                           (self.family, fid, decision, user, now))
            db.execute("COMMIT")
        self.timeline.invalidate()

    def batch(self, scope, decisions_):
        """Up to 50 yes/no answers at once; ids the family can no longer see are skipped."""
        self.timeline.authorize(scope)
        scope.require_review()
        if not isinstance(decisions_, list) or not 1 <= len(decisions_) <= 50:
            raise ValueError("一次最多50条")
        pairs = {}
        for entry in decisions_:
            fid, decision = entry.get("id"), entry.get("decision")
            if decision not in {"yes", "no"}:
                raise ValueError("决定无效")
            pairs[fid] = decision
        known = {i["file_id"] for i in self._candidates()} | set(self.timeline.snapshot()["by_id"]) | set(decisions(self.store, self.family))
        pairs = [(fid, d) for fid, d in pairs.items() if isinstance(fid, str) and fid in known]
        if pairs:
            self._save(pairs, scope.user_id)
        return {"applied": len(pairs)}

    def history(self, scope, limit=50):
        self.timeline.authorize(scope)
        if type(limit) is not int or not 1 <= limit <= 200:
            raise ValueError("数量无效")
        _ensure(self.store)
        with self.store.db() as db:
            rows = db.execute("SELECT file_id,decision,decided_at FROM recognition_decisions WHERE family_id=? "
                              "ORDER BY decided_at DESC,file_id LIMIT ?", (self.family, limit)).fetchall()
        return {"items": [{"id": r["file_id"], "decision": r["decision"],
                           "decided_at": datetime.fromtimestamp(r["decided_at"], timezone.utc).isoformat(),
                           "preview_url": "/learning/api/recognition/%s/preview" % r["file_id"]} for r in rows]}
