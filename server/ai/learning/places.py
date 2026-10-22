"""足迹 and 事件: places from her timeline, and the library's own automatic event albums.

Places merge by point of interest: "深圳市 · 尚云花园" and a bare "尚云花园" are one
place, its city taken from the members that name one (or from the same days).
Raw "GPS_lat_lon" names never become a place name: those items join the place
visited that day and lend it coordinates. Event members are filtered to what her
timeline shows, so an album never exposes items outside the family's view; an
old album the library re-made for the same day (with or without a place) is merged.
"""
from __future__ import annotations

from collections import Counter

from .online_timeline import family_story, gps_place, place_city, poi, quality, short_place, unsuitable
from .store import valid_day

MAX_IDS = 60
MIN_EVENT_ITEMS = 3
OVERLAP = 0.8  # same-day albums sharing this much of the smaller one are versions of one event
HOME_SHARE = 0.6  # places visited on at least this share of the top place's days are home too


def _cover_key(row):
    return (quality(row), row["day"], row["item"]["file_id"])


def _card_url(row):
    """A ~900px cover for list cards (the 1600px large preview is for full-screen)."""
    item = row["item"]
    return "/learning/api/online-timeline/%s/preview?size=card&revision=%s" % (item["file_id"], item["content_hash"])


class Places:
    def __init__(self, timeline):
        self.timeline = timeline

    def places(self, scope):
        self.timeline.authorize(scope)
        groups, gps, day_places, day_cities = {}, [], {}, {}
        for row in self.timeline.snapshot()["rows"]:
            if not row["day"]:
                continue
            found = poi(row["place"])
            if found is None:
                if gps_place(row["place"]):
                    gps.append(row)
                continue
            city, short = found
            groups.setdefault(short, []).append(row)
            day_places.setdefault(row["day"], Counter())[short] += 1
            if city:
                day_cities.setdefault(row["day"], Counter())[city] += 1
        coords = {}
        for row in gps:
            # A raw coordinate joins the place she was at that day; alone it is not a place name.
            nearby = day_places.get(row["day"])
            if nearby:
                short = nearby.most_common(1)[0][0]
                groups[short].append(row)
                coords.setdefault(short, []).append(gps_place(row["place"]))
        items = []
        for short, rows in groups.items():
            rows.sort(key=lambda r: (r["stamp"] or "", r["item"]["file_id"]), reverse=True)
            cities = Counter(place_city(r["place"]) for r in rows if place_city(r["place"]))
            if not cities:  # bare names: the city of the same days
                for r in rows:
                    cities.update(day_cities.get(r["day"], Counter()))
            city = cities.most_common(1)[0][0] if cities else None
            cover = max(rows, key=_cover_key)
            points = coords.get(short) or []
            items.append({"name": "%s·%s" % (city, short) if city and city != short else short, "short": short,
                          "city": city, "count": len(rows),
                          "cover_url": self.timeline.public(cover)["preview_url"],
                          "item_ids": [r["item"]["file_id"] for r in rows[:MAX_IDS]],
                          "first_day": min(r["day"] for r in rows), "last_day": max(r["day"] for r in rows),
                          # Coordinates only when the library recorded raw GPS for this place; the app geocodes otherwise.
                          "lat": round(sum(p[0] for p in points) / len(points), 5) if points else None,
                          "lon": round(sum(p[1] for p in points) / len(points), 5) if points else None,
                          "days": len({r["day"] for r in rows}), "home": False})
        if items:
            top = max(p["days"] for p in items)
            for place in items:
                place["home"] = top >= 30 and place["days"] >= top * HOME_SHARE
        items.sort(key=lambda p: (-p["count"], p["name"]))
        return {"items": items}

    @staticmethod
    def _merge(albums):
        """Same-day versions of one event: keep the one with a place (else the larger) and union the members."""
        albums = sorted(albums, key=lambda a: (bool(a["place"]), len(a["visible"]), a["id"]), reverse=True)
        kept = []
        for album in albums:
            mine = set(album["visible"])
            twin = next((k for k in kept if k["day"] == album["day"]
                         and len(mine & set(k["visible"])) >= OVERLAP * min(len(mine), len(k["visible"]))), None)
            if twin is None:
                kept.append(album)
            else:
                twin["visible"] += [fid for fid in album["visible"] if fid not in twin["visible"]]
        return kept

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
        labels = snapshot.get("labels") or {}
        albums = []
        for album in snapshot.get("events") or []:
            visible = [fid for fid in dict.fromkeys(album.get("file_ids") or []) if fid in rows]
            if len(visible) < MIN_EVENT_ITEMS:
                continue
            day = album.get("day") if isinstance(album.get("day"), str) and len(album["day"]) == 10 else None
            day = day or max((rows[fid]["day"] for fid in visible if rows[fid]["day"]), default=None)
            if not day:
                continue
            albums.append({**album, "day": day, "visible": visible, "place": short_place(album.get("place"))})
        items = []
        for album in self._merge(albums):
            day, visible = album["day"], album["visible"]
            if (start and day < start) or (end and day > end):
                continue
            cover_id = album.get("cover_id")
            if cover_id not in visible or unsuitable(rows[cover_id]):
                cover_id = max(visible, key=lambda fid: (quality(rows[fid]), fid))
            items.append({"id": album["id"], "title": family_story(album.get("title") or "", labels),
                          "story": family_story(album.get("story") or "", labels),
                          "day": day, "place": album["place"], "count": len(visible),
                          "cover_url": self.timeline.public(rows[cover_id])["large_url"],
                          "card_url": _card_url(rows[cover_id]), "item_ids": visible})
        items.sort(key=lambda e: (e["day"], e["id"]), reverse=True)
        return {"items": items}
