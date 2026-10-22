"""足迹 and 事件: places from her timeline, and the library's own automatic event albums.

No coordinates exist; the app geocodes `name`. Event members are filtered to what
her timeline shows, so an album never exposes items outside the family's view.
"""
from __future__ import annotations

from .online_timeline import place_city, place_parts, short_place
from .store import valid_day

MAX_IDS = 60
MIN_EVENT_ITEMS = 3


def _quality(row):
    return (row["adjusted"], row["item"]["media_type"] == "photo", min(len(row["description"]), 120))


class Places:
    def __init__(self, timeline):
        self.timeline = timeline

    def places(self, scope):
        self.timeline.authorize(scope)
        groups = {}
        for row in self.timeline.snapshot()["rows"]:
            parts = place_parts(row["place"])
            if parts and parts[0] == "中国":
                parts = parts[1:]
            if not parts or not row["day"]:
                continue
            groups.setdefault("·".join(parts), []).append(row)
        items = []
        for name, rows in groups.items():
            rows.sort(key=lambda r: (r["stamp"] or "", r["item"]["file_id"]), reverse=True)
            cover = max(rows, key=lambda r: (_quality(r), r["day"], r["item"]["file_id"]))
            items.append({"name": name, "short": place_parts(rows[0]["place"])[-1],
                          "city": place_city(rows[0]["place"]) or None, "count": len(rows),
                          "cover_url": self.timeline.public(cover)["preview_url"],
                          "item_ids": [r["item"]["file_id"] for r in rows[:MAX_IDS]],
                          "first_day": min(r["day"] for r in rows), "last_day": max(r["day"] for r in rows)})
        items.sort(key=lambda p: (-p["count"], p["name"]))
        return {"items": items}

    def events(self, scope, start=None, end=None):
        self.timeline.authorize(scope)
        if start:
            valid_day(start)
        if end:
            valid_day(end)
        if start and end and start > end:
            raise ValueError("日期范围无效")
        snapshot = self.timeline.snapshot()
        rows = snapshot["rows_by_id"]
        items = []
        for album in snapshot.get("events") or []:
            visible = [fid for fid in dict.fromkeys(album.get("file_ids") or []) if fid in rows]
            if len(visible) < MIN_EVENT_ITEMS:
                continue
            day = album.get("day") if isinstance(album.get("day"), str) and len(album["day"]) == 10 else None
            day = day or max((rows[fid]["day"] for fid in visible if rows[fid]["day"]), default=None)
            if not day or (start and day < start) or (end and day > end):
                continue
            cover_id = album.get("cover_id") if album.get("cover_id") in visible else \
                max(visible, key=lambda fid: (_quality(rows[fid]), fid))
            items.append({"id": album["id"], "title": album.get("title") or "", "story": album.get("story") or "",
                          "day": day, "place": short_place(album.get("place")), "count": len(visible),
                          "cover_url": self.timeline.public(rows[cover_id])["large_url"], "item_ids": visible})
        items.sort(key=lambda e: (e["day"], e["id"]), reverse=True)
        return {"items": items}
