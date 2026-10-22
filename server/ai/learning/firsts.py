"""第一次: earliest timeline occurrence of curated growth concepts, for parents to confirm.

Titles match the app's preset milestone titles so confirming lights the preset.

Offline keyword matching over (family-adjusted) descriptions, tags and events of
items already in her timeline; no model calls. Candidates and family decisions
live in learning.sqlite. Dismissing a candidate proposes the next occurrence.
"""
from __future__ import annotations

import re
import time

from .store import Missing, digest

# (key, title, words, excluded phrases)
CONCEPTS = (
    ("crawling", "第一次爬行", ("爬行", "匍匐前进", "在地上爬", "学爬"), ("爬行垫", "爬爬垫")),
    ("standing", "第一次扶站", ("扶站", "独自站立", "学站", "站起来", "站立"), ()),
    ("walking", "第一次独立行走", ("学走路", "学步", "蹒跚", "迈步", "独自行走", "自己走路", "扶着走"), ("学步车",)),
    ("running", "第一次小跑", ("奔跑", "跑步", "小跑", "跑来跑去"), ("推着",)),
    ("tricycle", "第一次骑小车", ("三轮车", "滑步车", "平衡车", "扭扭车", "踏板车", "滑板车", "滑行车"), ("推车", "推着")),
    ("bike", "第一次骑自行车", ("自行车", "单车", "骑车"), ("婴儿车", "推车", "儿童座椅")),
    ("watermelon", "第一次吃西瓜", ("西瓜",), ("西瓜球", "弹力球", "西瓜玩具", "西瓜图案", "西瓜造型", "西瓜包", "西瓜帽")),
    ("self_feeding", "第一次自己吃饭", ("自己吃饭", "自主进食", "自己用勺", "握勺", "自己拿勺", "用勺子", "自己进食", "用叉子"), ("喂",)),
    ("brushing_teeth", "第一次自己刷牙", ("刷牙", "牙刷"), ()),
    ("swimming", "第一次游泳", ("游泳", "泳池", "泳圈"), ()),
    ("drawing", "第一次涂鸦", ("画画", "涂鸦", "蜡笔", "绘画", "画笔"), ()),
    ("singing", "第一次唱歌", ("唱歌", "哼唱", "唱儿歌"), ("播放",)),
    ("dancing", "第一次跳舞", ("跳舞", "舞蹈", "随音乐扭动"), ()),
    ("kindergarten", "第一天上幼儿园", ("幼儿园", "入园"), ()),
    ("plane", "第一次坐飞机", ("坐飞机", "飞机上", "机舱", "登机", "航班"), ("玩具飞机", "飞机玩具")),
    ("sea", "第一次看海", ("海边", "沙滩", "大海", "海浪"), ()),
    ("snow", "第一次看雪", ("玩雪", "雪地", "雪人", "下雪", "积雪"), ()),
    ("birthday_cake", "第一次吹生日蜡烛", ("生日蛋糕", "吹蜡烛", "生日"), ()),
    ("haircut", "第一次理发", ("理发", "剪头发", "剃头"), ()),
    ("zoo", "第一次动物园", ("动物园",), ()),
)
# She must be in the same clause as the matched word ("张云拿着勺子喂饭" is not her first).
CHILD_TOKENS = ("布布", "袁晨希", "女婴", "婴儿", "幼童", "幼儿", "女童", "小女孩", "女孩", "宝宝", "她", "孩子")
TITLES = {key: title for key, title, _, _ in CONCEPTS}
STATUSES = {"candidate", "confirmed", "dismissed"}
# A type the family dismissed this often only proposes clauses naming her explicitly, listed last.
DISMISS_LIMIT = 3
NAMES = ("布布", "袁晨希")


def matches(row, words, excluded, strict=False) -> bool:
    """A concept word in a description clause that also names her; tags/events only when there is no description."""
    item = row["item"]
    texts = [str((item.get("analysis") or {}).get("description") or ""), row["description"]]
    tokens = NAMES if strict else CHILD_TOKENS
    for text in texts:
        for clause in re.split(r"[，,。；;！!？?\n]", text):
            if any(w in clause for w in words) and not any(x in clause for x in excluded) \
                    and any(t in clause for t in tokens):
                return True
    if any(texts) or strict:
        return False
    labels = " ".join(row.get("tags") or []) + " " + (row.get("event") or "")
    return any(w in labels for w in words) and not any(x in labels for x in excluded)


class Firsts:
    def __init__(self, timeline):
        self.timeline, self.store, self.family = timeline, timeline.store, timeline.family
        with self.store.db() as db:
            db.execute("CREATE TABLE IF NOT EXISTS firsts (id TEXT PRIMARY KEY, family_id TEXT NOT NULL, concept TEXT NOT NULL, "
                       "item_id TEXT NOT NULL, day TEXT NOT NULL, status TEXT NOT NULL, decided_by TEXT NOT NULL DEFAULT '', "
                       "decided_at REAL, updated_at REAL NOT NULL)")

    def _rows(self):
        with self.store.db() as db:
            return [dict(r) for r in db.execute("SELECT * FROM firsts WHERE family_id=? ORDER BY day,concept", (self.family,))]

    def compute(self) -> dict:
        """One candidate per undecided concept: its earliest not-dismissed occurrence."""
        rows = sorted(self.timeline.snapshot()["rows"], key=lambda r: (r["stamp"] or "", r["item"]["file_id"]))
        stored = self._rows()
        confirmed = {r["concept"] for r in stored if r["status"] == "confirmed"}
        dismissed = {(r["concept"], r["item_id"]) for r in stored if r["status"] == "dismissed"}
        weak = self._weak(stored)
        found = {}
        for key, _, words, excluded in CONCEPTS:
            if key in confirmed:
                continue
            for row in rows:
                if row["day"] and (key, row["item"]["file_id"]) not in dismissed \
                        and matches(row, words, excluded, strict=key in weak):
                    found[key] = row
                    break
        now = time.time()
        with self.store.db() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM firsts WHERE family_id=? AND status='candidate'", (self.family,))
            for key, row in found.items():
                fid = row["item"]["file_id"]
                db.execute("INSERT OR REPLACE INTO firsts VALUES(?,?,?,?,?,?,?,?,?)",
                           (digest([self.family, key, fid])[:16], self.family, key, fid, row["day"], "candidate", "", None, now))
            db.execute("COMMIT")
        return {"candidates": len(found), "confirmed": len(confirmed)}

    @staticmethod
    def _weak(stored):
        counts = {}
        for r in stored:
            if r["status"] == "dismissed":
                counts[r["concept"]] = counts.get(r["concept"], 0) + 1
        return {k for k, n in counts.items() if n >= DISMISS_LIMIT}

    def _public(self, row, by_id):
        item = by_id.get(row["item_id"])
        if item is None:
            return None
        public = self.timeline.public(item)
        return {"id": row["id"], "concept": row["concept"], "kind": row["concept"],
                "title": TITLES.get(row["concept"], row["concept"]),
                "date": row["day"], "item_id": row["item_id"], "preview_url": public["preview_url"],
                "description": public["description"], "status": row["status"]}

    def list(self, scope, status="candidate"):
        self.timeline.authorize(scope)
        if status not in {"candidate", "confirmed", "all"}:
            raise ValueError("状态无效")
        by_id = self.timeline.snapshot()["rows_by_id"]
        stored = self._rows()
        weak = self._weak(stored)
        rows = [r for r in stored if r["status"] != "dismissed" and (status == "all" or r["status"] == status)]
        rows.sort(key=lambda r: r["status"] == "candidate" and r["concept"] in weak)  # stable: keeps day order
        return {"items": [p for p in (self._public(r, by_id) for r in rows) if p]}

    def confirmed_in_month(self, month):
        return [TITLES.get(r["concept"], r["concept"]) for r in self._rows()
                if r["status"] == "confirmed" and r["day"][:7] == month]

    def decide(self, scope, fid, status):
        self.timeline.authorize(scope)
        scope.require_review()
        if status not in {"confirmed", "dismissed"}:
            raise ValueError("状态无效")
        with self.store.db() as db:
            row = db.execute("SELECT * FROM firsts WHERE id=? AND family_id=?", (fid, self.family)).fetchone()
            if row is None:
                raise Missing("记录不存在")
            db.execute("UPDATE firsts SET status=?,decided_by=?,decided_at=?,updated_at=? WHERE id=?",
                       (status, scope.user_id, time.time(), time.time(), fid))
        row = {**dict(row), "status": status}
        if status == "dismissed":
            self.compute()  # propose this concept's next occurrence right away
        return self._public(row, self.timeline.snapshot()["rows_by_id"]) or {
            "id": row["id"], "concept": row["concept"], "kind": row["concept"], "title": TITLES.get(row["concept"], row["concept"]),
            "date": row["day"], "item_id": row["item_id"], "preview_url": None, "description": "", "status": status}

    def confirm(self, scope, fid):
        return self.decide(scope, fid, "confirmed")

    def dismiss(self, scope, fid):
        return self.decide(scope, fid, "dismissed")


if __name__ == "__main__":
    from .runtime import create_features
    print(create_features()["firsts"].compute(), flush=True)
