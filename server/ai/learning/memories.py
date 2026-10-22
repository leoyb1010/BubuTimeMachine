"""回忆: deterministic memory cards for one date, built from the online timeline.

No model calls. The same date always yields the same cards; people, trips and
themes rotate by day so the same one is not shown day after day.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date as Date
import random

from .online_timeline import place_city as _city, quality
from .store import digest, valid_day

MIN_ITEMS, MAX_ITEMS, MAX_CARDS = 5, 30, 6
CAPS = {"on_this_day": 2, "family": 2, "trip": 1, "theme": 1}
THEMES = (
    ("food", "布布的美食时光", ("吃饭", "美食", "水果", "零食", "西瓜", "蛋糕", "进餐", "用餐", "喝奶")),
    ("art", "小画家布布", ("画画", "涂鸦", "绘画", "蜡笔", "画笔")),
    ("outdoor", "公园里的布布", ("公园", "草地", "滑梯", "秋千", "户外")),
    ("water", "玩水的布布", ("玩水", "游泳", "泳池", "沙滩", "海边", "戏水")),
    ("animal", "布布和小动物", ("小狗", "小猫", "动物", "鸭子", "金鱼", "兔子")),
    ("music", "唱唱跳跳", ("唱歌", "跳舞", "儿歌", "音乐", "舞蹈")),
    ("book", "布布读绘本", ("绘本", "看书", "读书", "翻书")),
    ("toy", "玩具时间", ("玩具", "积木", "拼图", "玩偶")),
    ("sleep", "睡梦中的布布", ("睡觉", "熟睡", "午睡", "睡着")),
)


def _quality(row):
    return (quality(row), row["item"]["file_id"])


def _month_text(day):
    return "%d年%d月" % (int(day[:4]), int(day[5:7]))


def _span(rows):
    first, last = min(r["day"] for r in rows), max(r["day"] for r in rows)
    if first == last:
        return "%s%d日" % (_month_text(first), int(first[8:]))
    if first[:7] == last[:7]:
        return "%s%d日–%d日" % (_month_text(first), int(first[8:]), int(last[8:]))
    return "%s%d日–%s%d日" % (_month_text(first), int(first[8:]), _month_text(last), int(last[8:]))


def _rotate(values, day, count):
    if not values:
        return []
    start = Date.fromisoformat(day).toordinal() % len(values)
    return (values[start:] + values[:start])[:count]


def build(rows, labels, day):
    """Pure card builder over timeline rows (newest first), for tests and the API."""
    valid_day(day)
    anchor = Date.fromisoformat(day)
    rows = [r for r in rows if r["day"] and r["day"] <= day]
    cards = []

    def card(kind, key, title, chosen, rng_key):
        if len(chosen) < MIN_ITEMS:
            return None
        if len(chosen) > MAX_ITEMS:
            rng = random.Random(digest([day, kind, key, rng_key]))
            best = sorted(chosen, key=_quality, reverse=True)[:MAX_ITEMS // 2]
            taken = {id(r) for r in best}
            rest = [r for r in chosen if id(r) not in taken]
            chosen = best + rng.sample(rest, MAX_ITEMS - len(best))
        chosen = sorted(chosen, key=lambda r: (r["stamp"] or "", r["item"]["file_id"]))
        # Screenshots, ID photos and adult close-ups never cover a card (they may still be inside it).
        cover = max(chosen, key=_quality)["item"]
        return {"id": digest([kind, key, [r["item"]["file_id"] for r in chosen]])[:16], "kind": kind, "title": title,
                "subtitle": "%s · %d个瞬间" % (_span(chosen), len(chosen)), "cover_id": cover["file_id"],
                "cover_url": "/learning/api/online-timeline/%s/preview?size=thumb&revision=%s" % (cover["file_id"], cover["content_hash"]),
                "card_url": "/learning/api/online-timeline/%s/preview?size=card&revision=%s" % (cover["file_id"], cover["content_hash"]),
                "item_ids": [r["item"]["file_id"] for r in chosen], "count": len(chosen)}

    # 那年今天: this exact date in each earlier year, newest year first; when that day alone is too
    # thin, the ±3 days around it, titled as such (never "今天" for another date).
    years, nearby = defaultdict(list), defaultdict(list)
    for row in rows:
        when = Date.fromisoformat(row["day"])
        if when.year >= anchor.year:
            continue
        try:
            same = anchor.replace(year=when.year)
        except ValueError:
            same = anchor.replace(year=when.year, day=28)
        gap = abs((when - same).days)
        if gap == 0:
            years[when.year].append(row)
        if gap <= 3:
            nearby[when.year].append(row)
    found = []
    for y in sorted(nearby, reverse=True):
        if len(years[y]) >= MIN_ITEMS:
            found.append(card("on_this_day", str(y), "%d年前的今天" % (anchor.year - y), years[y], ""))
        else:
            found.append(card("on_this_day", str(y), "%d年前的这几天" % (anchor.year - y), nearby[y], ""))
    cards += [c for c in found if c][:CAPS["on_this_day"]]

    # 家人: one month together with a family member, rotating across people.
    by_person = defaultdict(list)
    for row in rows:
        for name in row["people"]:
            by_person[name].append(row)
    people = sorted(n for n, rs in by_person.items() if len(rs) >= MIN_ITEMS)
    for name in _rotate(people, day, CAPS["family"]):
        months = defaultdict(list)
        for row in by_person[name]:
            months[row["day"][:7]].append(row)
        full = sorted(m for m, rs in months.items() if len(rs) >= MIN_ITEMS)
        if full:
            month = random.Random(digest([day, name])).choice(full)
            chosen = months[month]
        else:
            chosen = by_person[name]
        made = card("family", name, "和%s在一起" % (labels.get(name) or name), chosen, name)
        if made:
            cards.append(made)

    # 旅行: consecutive days in a city other than the usual one.
    cities = Counter(_city(r["place"]) for r in rows if _city(r["place"]))
    home = cities.most_common(1)[0][0] if cities else ""
    trips, current = [], None
    for row in sorted((r for r in rows if _city(r["place"]) and _city(r["place"]) != home), key=lambda r: r["day"]):
        city = _city(row["place"])
        when = Date.fromisoformat(row["day"])
        if current and current["city"] == city and (when - current["last"]).days <= 2:
            current["rows"].append(row)
            current["last"] = when
        else:
            current = {"city": city, "last": when, "rows": [row]}
            trips.append(current)
    trips = [t for t in trips if len(t["rows"]) >= MIN_ITEMS]
    for trip in _rotate(trips, day, CAPS["trip"]):
        made = card("trip", trip["city"] + trip["rows"][0]["day"], "%s之旅" % trip["city"].removesuffix("市"), trip["rows"], "")
        if made:
            cards.append(made)

    # 主题: everyday themes from the descriptions and tags.
    themed = []
    for key, title, words in THEMES:
        matched = [r for r in rows if any(w in r["description"] or w in " ".join(r["tags"]) for w in words)]
        if len(matched) >= MIN_ITEMS:
            themed.append((key, title, matched))
    for key, title, matched in _rotate(themed, day, CAPS["theme"]):
        made = card("theme", key, title, matched, key)
        if made:
            cards.append(made)
    return cards[:MAX_CARDS]


class Memories:
    def __init__(self, timeline):
        self.timeline = timeline
        self.cache = {}

    def memories(self, scope, day):
        self.timeline.authorize(scope)
        valid_day(day)
        snapshot = self.timeline.snapshot()
        key = (day, snapshot["snapshot_id"])
        if key not in self.cache:
            if len(self.cache) > 32:
                self.cache.clear()
            self.cache[key] = build(snapshot["rows"], snapshot.get("labels") or {}, day)
        return {"items": self.cache[key]}
