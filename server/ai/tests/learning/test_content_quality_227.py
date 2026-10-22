"""2.27 content quality (T9): ask, words, events, places, firsts, picks, wording, search, aspect, bursts, backup.

Fakes only: no library, disk or model.
"""
from datetime import date, datetime
import io
import json
import logging
import os
from pathlib import Path
import sqlite3
import sys
import time

from PIL import Image
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_family_features import Bridge, Processor, build, item, scope, FAMILY, CHILD  # noqa: E402
from learning.ask import Ask, time_window  # noqa: E402
from learning.auth import FamilyScope  # noqa: E402
from learning.brain_bridge import BrainBlocked, BrainBridge, BrainUnavailable  # noqa: E402
from learning.firsts import Firsts  # noqa: E402
from learning.memories import Memories  # noqa: E402
from learning.monthly import Monthly  # noqa: E402
from learning.online_timeline import familiar, family_story, search_terms, unsuitable  # noqa: E402
from learning.places import Places  # noqa: E402
from learning.service import LearningService  # noqa: E402
from learning.status import Status, probe  # noqa: E402
from learning.store import LearningStore  # noqa: E402
from learning.voices import Voices  # noqa: E402
from learning.words import Words, key, tokens  # noqa: E402

TODAY = date(2026, 10, 22)
LABELS = {"袁博": "爸爸", "张云": "妈妈", "郑德兰": "姥姥"}


class AskBridge(Bridge):
    def __init__(self, items, replies=()):
        super().__init__(items)
        self.replies, self.asked = list(replies), []

    def subject_snapshot(self, subject):
        return {**super().subject_snapshot(subject), "people_labels": LABELS}

    def complete_json(self, system, user, schema, *, effort="high", timeout=None):
        self.asked.append(json.loads(user))
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply


# ---------- ask: time words, 第一次, relevance, failure reasons ----------

def test_time_window_understands_family_time_words():
    assert time_window("去年冬天我们去了哪里玩？", TODAY)[:2] == (date(2025, 12, 1), date(2026, 2, 28))
    assert time_window("上个月布布在幼儿园做了什么", TODAY)[:2] == (date(2026, 9, 1), date(2026, 9, 30))
    assert time_window("三月份去哪了", TODAY)[:2] == (date(2026, 3, 1), date(2026, 3, 31))
    assert time_window("去年12月", TODAY)[:2] == (date(2025, 12, 1), date(2025, 12, 31))
    assert time_window("最近她喜欢玩什么", TODAY)[:2] == (date(2026, 9, 7), TODAY)
    assert time_window("两岁生日怎么过的", TODAY, "2024-05-22")[:2] == (date(2026, 5, 7), date(2026, 6, 6))
    assert time_window("一岁的时候", TODAY, "2024-05-22")[:2] == (date(2025, 5, 22), date(2026, 5, 21))
    assert time_window("她最喜欢玩什么", TODAY) == (None, None, [])


def test_ask_filters_by_time_ranks_newest_on_ties_and_pins_the_first_card(tmp_path):
    items = [item(tmp_path, 1, day="2024-06-10T10:00:00+08:00", description="布布在家里"),
             item(tmp_path, 2, day="2025-02-15T10:00:00+08:00", description="布布在深圳湾面朝大海"),
             item(tmp_path, 3, day="2026-06-19T10:00:00+08:00", description="布布在沙滩上看海狮"),
             item(tmp_path, 4, day="2025-12-20T10:00:00+08:00", description="布布在公园滑滑梯", place="中国 · 深圳市 · 莲花山"),
             item(tmp_path, 5, day="2026-01-10T10:00:00+08:00", description="布布在商场", place="中国 · 深圳市 · 万象天地"),
             item(tmp_path, 6, day="2025-06-01T10:00:00+08:00", description="布布在公园滑滑梯")]
    bridge = AskBridge(items)
    timeline, _ = build(tmp_path, items, bridge=bridge)
    firsts = Firsts(timeline)
    firsts.compute()
    ask = Ask(timeline, bridge, firsts, today=lambda: TODAY)
    snapshot = timeline.snapshot()
    rows, _ = ask.retrieve("布布第一次看海是什么时候？", snapshot)
    assert [r["item"]["file_id"][-1] for r in rows][:2] == ["2", "3"]  # earliest relevant, synonyms 大海/沙滩
    winter, _ = ask.retrieve("去年冬天我们去了哪里玩？", snapshot)
    assert {r["item"]["file_id"][-1] for r in winter} == {"4", "5"}  # only that winter, filled by place
    slides, _ = ask.retrieve("她喜欢玩滑梯吗", snapshot)
    assert [r["item"]["file_id"][-1] for r in slides][:2] == ["4", "6"]  # same score: newer first


def test_ask_logs_and_retries_a_blocked_model_once_with_gentle_records(tmp_path, caplog):
    items = [item(tmp_path, 1, description="布布洗澡后吃西瓜", people=["张云"]),
             item(tmp_path, 2, description="布布和袁博吃西瓜", people=["袁博"])]
    bridge = AskBridge(items, [BrainBlocked("x"), {"answer": "吃西瓜[1]", "citations": [{"id": "%024x" % 2, "note": "西瓜"}]}])
    timeline, _ = build(tmp_path, items, bridge=bridge)
    ask = Ask(timeline, bridge, today=lambda: TODAY)
    with caplog.at_level(logging.WARNING):
        result = ask.ask(scope(), "布布最喜欢吃什么水果？")
    assert "ask model failed attempt=1 error=BrainBlocked" in caplog.text
    assert result["model_used"] and result["reason"] is None and result["answer"] == "吃西瓜[1]"
    first, second = bridge.asked
    assert "people" in first["records"][0] and all("people" not in r for r in second["records"])
    assert [r["id"][-1] for r in second["records"]] == ["2"]  # the bath scene is left out of the retry
    assert "爸爸" in json.dumps(first, ensure_ascii=False) and "袁博" not in json.dumps(first, ensure_ascii=False)
    bridge.replies = [BrainUnavailable("down"), BrainUnavailable("down")]
    assert ask.ask(scope(), "西瓜")["reason"] == "unavailable"
    bridge.replies = [BrainBlocked("x"), BrainBlocked("x")]
    assert ask.ask(scope(), "西瓜")["reason"] == "blocked"
    assert ask.ask(scope(), "火星")["reason"] == "no_items"
    bridge.replies = [{"answer": "", "citations": []}]
    assert ask.ask(scope(), "西瓜")["reason"] == "empty"
    ask.busy.acquire(), ask.busy.acquire()
    started = time.monotonic()
    assert ask.ask(scope(), "西瓜")["reason"] == "busy" and time.monotonic() - started < 5


# ---------- words ----------

def test_words_segment_by_dictionary_without_fragments_or_her_name():
    assert tokens("姥姥对不起我不是故意哒") == ["姥姥", "对不起", "不是", "故意"]
    assert tokens("唱游戏上游机在爸爸爬滑梯好滑滑梯") == ["唱", "爸爸", "爬", "滑梯", "好"]  # 滑滑梯 ≈ 滑梯
    assert tokens("布布的照片") == ["照片"]
    assert tokens("妞妞妞妞") == ["妞妞"] and tokens("大宝") == ["大宝"]
    assert tokens("你身上呢") == [] and tokens("说我笨了") == []
    assert key("滑滑梯") == key("滑梯") and key("奶奶") != key("奶") and key("哎哟") == key("哎呦")


def test_words_report_incomplete_while_the_backlog_is_large(tmp_path):
    items = [item(tmp_path, 1, kind="video", day="2026-03-01T10:00:00+08:00")]
    bridge = Bridge(items)
    timeline, _ = build(tmp_path, items, bridge=bridge)
    voices = Voices(timeline, bridge, Processor())
    with timeline.store.db() as db:
        db.execute("INSERT INTO voices VALUES(?,?,?,?,1,2,'',?,?,0,0)", ("a" * 16, FAMILY, "%024x" % 1,
                                                                        "2026-03-01T02:00:00+00:00", "滑滑梯 滑梯", "ready"))
        for n in range(3):
            db.execute("INSERT INTO voices VALUES(?,?,?,?,1,2,'',?,?,0,0)", ("%016x" % n, FAMILY, "%024x" % 1,
                                                                            "2025-0%d-01T02:00:00+00:00" % (n + 3), "", "pending"))
    result = Words(timeline, voices).words(scope())
    assert result["months"] == [{"month": "2026-03", "new_words": ["滑滑梯"], "total": 1}]
    assert result["incomplete"] is True and result["pending_since"] == "2025-03-01T02:00:00+00:00"


def test_voices_process_oldest_first_and_stop_on_an_outage(tmp_path):
    speech = [{"id": "a", "start": 10.0, "end": 11.5, "text": "爸爸抱"}]
    items = [item(tmp_path, n, kind="video", day="2026-0%d-01T10:00:00+08:00" % n, segments=speech) for n in (3, 4, 5)]
    bridge = Bridge(items)
    seen = []

    def reply(user):
        seen.append(user[0]["text"])
        raise BrainUnavailable("down")
    bridge.reply = reply
    timeline, _ = build(tmp_path, items, bridge=bridge)
    voices = Voices(timeline, bridge, Processor())
    voices.sync_candidates()
    assert voices.process(20) == {"ready": 0, "rejected": 0, "failed": 1} and len(seen) == 1
    with timeline.store.db() as db:
        touched = db.execute("SELECT item_id FROM voices WHERE attempts=1").fetchall()
    assert [r[0] for r in touched] == ["%024x" % 3]  # the oldest clip, and only it
    bridge.reply = lambda user: {"child_speaks": True, "heard": "爸爸"}
    assert voices.process(20, budget=0)["ready"] == 1  # a spent budget still handles one clip


# ---------- events and places ----------

def test_events_merge_old_and_new_album_versions_and_use_family_wording(tmp_path):
    items = [item(tmp_path, n, day="2026-08-03T10:00:00+08:00") for n in range(1, 8)]
    items += [item(tmp_path, n, day="2026-08-05T10:00:00+08:00") for n in range(8, 12)]
    bridge = Bridge(items)
    ids = ["%024x" % n for n in range(1, 12)]
    bridge.auto_events = lambda: [
        {"id": "old", "title": "戏水", "story": "女童在水边玩", "day": "2026-08-03", "place": "", "cover_id": None, "file_ids": ids[:5]},
        {"id": "new", "title": "洱海戏水", "story": "袁晨希和袁博在洱海边，女童笑了", "day": "2026-08-03",
         "place": "中国 · 大理白族自治州 · 洱海", "cover_id": None, "file_ids": ids[1:7]},
        {"id": "other", "title": "古城", "story": "", "day": "2026-08-05", "place": "", "cover_id": None, "file_ids": ids[7:]}]
    timeline, _ = build(tmp_path, items, bridge=bridge)
    events = {e["id"]: e for e in Places(timeline).events(scope())["items"]}
    assert set(events) == {"new", "other"}
    assert events["new"]["count"] == 7 and set(events["new"]["item_ids"]) == set(ids[:7])  # members united
    assert events["new"]["story"] == "布布和爸爸在洱海边，布布笑了"
    assert "/preview?size=card&revision=" in events["new"]["card_url"]
    assert family_story("两名女童在玩", LABELS) == "两名女童在玩"  # several children: no guessing


def test_places_merge_by_point_of_interest_and_turn_gps_names_into_coordinates(tmp_path):
    items = [item(tmp_path, 1, day="2026-01-01T10:00:00+08:00", place="中国 · 深圳市 · 尚云花园"),
             item(tmp_path, 2, day="2026-01-02T10:00:00+08:00", place="尚云花园"),
             item(tmp_path, 3, day="2026-01-03T10:00:00+08:00", place="民治"),
             item(tmp_path, 4, day="2026-01-03T11:00:00+08:00", place="中国 · 深圳市 · 万象天地"),
             item(tmp_path, 5, day="2026-01-03T12:00:00+08:00", place="GPS_22.657_114.183"),
             item(tmp_path, 6, day="2026-01-09T12:00:00+08:00", place="GPS_28.582_115.788")]
    timeline, _ = build(tmp_path, items)
    places = {p["short"]: p for p in Places(timeline).places(scope())["items"]}
    assert set(places) == {"尚云花园", "民治", "万象天地"}  # no GPS_ names, home not split
    assert places["尚云花园"]["count"] == 2 and places["尚云花园"]["name"] == "深圳市·尚云花园"
    assert places["民治"]["city"] == "深圳市"  # inherited from the same day
    gps_place = next(p for p in places.values() if p["lat"] is not None)
    assert (gps_place["lat"], gps_place["lon"]) == (22.657, 114.183) and gps_place["count"] == 2
    assert all(p["home"] is False for p in places.values())  # too little history to call anything home


# ---------- firsts ----------

def test_firsts_need_her_as_the_subject_and_a_plausible_age(tmp_path):
    items = [item(tmp_path, 1, day="2024-08-25T10:00:00+08:00", description="袁博和张云跳舞，拍摄者呼唤布布快看爸妈跳舞"),
             item(tmp_path, 2, day="2024-08-31T10:00:00+08:00", description="女子抱着布布站起来"),
             item(tmp_path, 3, day="2025-05-03T10:00:00+08:00", description="父母一边哼唱一边引导她前行"),
             item(tmp_path, 4, day="2025-05-17T10:00:00+08:00", description="布布在生日背景前合影"),
             item(tmp_path, 5, day="2026-05-17T10:00:00+08:00", description="布布站在一辆儿童自行车后"),
             item(tmp_path, 6, day="2024-07-01T10:00:00+08:00", description="布布在地上爬行"),  # 6 weeks old
             item(tmp_path, 7, day="2025-03-01T10:00:00+08:00", description="布布扶着沙发站起来"),
             item(tmp_path, 8, day="2025-12-24T10:00:00+08:00", description="布布转过身来拍手跳舞"),
             item(tmp_path, 9, day="2026-07-10T10:00:00+08:00", description="布布骑车，男孩子们在骑车")]
    timeline, _ = build(tmp_path, items)
    firsts = Firsts(timeline)
    firsts.compute()
    found = {i["kind"]: i["item_id"][-1] for i in firsts.list(scope())["items"]}
    assert found == {"standing": "7", "dancing": "8", "bike": "9"}


# ---------- daily picks, memory covers, wording ----------

def test_picks_skip_screenshots_label_only_the_exact_day_and_carry_a_short_caption(tmp_path):
    items = [item(tmp_path, 1, day="2025-10-22T10:00:00+08:00", description="手机截屏界面，显示一款证件照制作软件",
                  tags=["手机截图"]),
             item(tmp_path, 2, day="2025-10-22T11:00:00+08:00", description="布布在海边", people=["袁博", "张云"],
                  place="中国 · 深圳市 · 深圳湾公园"),
             item(tmp_path, 3, day="2024-10-20T10:00:00+08:00", description="布布在家"),
             item(tmp_path, 4, day="2026-10-20T10:00:00+08:00", description="布布画画"),
             item(tmp_path, 5, day="2026-10-20T10:00:10+08:00", description="布布画画"),  # same burst
             item(tmp_path, 6, day="2026-10-19T10:00:00+08:00", description="正面特写，背景为纯白抠图底")]
    timeline, _ = build(tmp_path, items, bridge=AskBridge(items))
    result = timeline.highlights(scope(), "2026-10-22")
    ids = [i["id"][-1] for i in result["items"]]
    assert "1" not in ids and "6" not in ids and ids[0] == "2"
    assert result["reason_by_id"]["%024x" % 2] == "那年今天" and result["reason_by_id"]["%024x" % 3] == "那年这几天"
    assert len({"4", "5"} & set(ids)) == 1  # one per burst
    assert result["caption_by_id"]["%024x" % 2] == "和爸爸妈妈在深圳湾公园"
    assert result["caption_by_id"]["%024x" % 3] is None


def test_memory_cover_avoids_screenshots_and_adult_close_ups(tmp_path):
    items = [item(tmp_path, 1, day="2025-10-22T10:00:00+08:00", description="手机截屏，证件照软件", tags=["截图"]),
             item(tmp_path, 2, day="2025-10-22T10:01:00+08:00", description="成年男子面部特写自拍，布布在左下角"),
             item(tmp_path, 3, day="2025-10-22T10:30:00+08:00", description="布布在草地上笑"),
             item(tmp_path, 4, day="2025-10-22T11:00:00+08:00", description="布布吃饭"),
             item(tmp_path, 5, day="2025-10-22T12:00:00+08:00", description="布布睡觉")]
    timeline, _ = build(tmp_path, items)
    card = Memories(timeline).memories(scope(), "2026-10-22")["items"][0]
    assert card["title"] == "1年前的今天" and card["cover_id"] == "%024x" % 3
    assert card["card_url"] == "/learning/api/online-timeline/%024x/preview?size=card&revision=%064x" % (3, 3)


def test_descriptions_and_reports_use_family_roles(tmp_path):
    assert familiar("爸爸袁博抱着布布，张云在旁边", LABELS) == "爸爸抱着布布，妈妈在旁边"
    assert familiar("一名成年男子抱着布布", LABELS, ["袁博"]) == "爸爸抱着布布"
    assert familiar("两名成年男子", LABELS, ["袁博"]) == "两名成年男子"
    assert familiar("一名成年男子和一名中年女性", LABELS, ["袁博", "郑德兰"]) == "爸爸和姥姥"
    items = [item(tmp_path, n, day="2026-09-%02dT10:00:00+08:00" % n, description="袁博抱着布布", people=["袁博"],
                  place="GPS_22.1_114.1" if n == 1 else "中国 · 珠海市 · 横琴" if n % 2 else "横琴")
             for n in range(1, 6)]
    bridge = AskBridge(items)
    timeline, _ = build(tmp_path, items, bridge=bridge)
    assert timeline.feed(scope())["items"][0]["description"] == "爸爸抱着布布"
    assert timeline.feed(scope(), query="袁博")["total"] == 5  # names still find them
    with timeline.store.db() as db:
        Monthly(timeline, bridge)
        db.execute("INSERT INTO monthly_reports VALUES(?,?,?,?,?,?)",
                   (FAMILY, "2026-09", "和张云的九月", "她与袁博、张云出游", "[]", "2026-10-01"))
    report = Monthly(timeline, bridge).list(scope())["items"][0]
    assert report["title"] == "和妈妈的九月" and report["summary"] == "她与爸爸、妈妈出游"
    assert report["places"] == ["横琴"]


# ---------- search, aspect, bursts ----------

def test_search_understands_natural_phrasing(tmp_path):
    assert search_terms("第一次骑车") == ["骑车"] and search_terms("在海边") == ["海边"]
    assert search_terms("去年") == ["去年"]
    items = [item(tmp_path, 1, description="布布骑着粉色自行车"), item(tmp_path, 2, description="布布在洱海边戏水",
                                                                      place="中国 · 大理白族自治州 · 洱海")]
    timeline, _ = build(tmp_path, items)
    assert timeline.feed(scope(), query="第一次骑车")["total"] == 1
    assert [i["id"][-1] for i in timeline.feed(scope(), query="在大理玩水")["items"]] == ["2"]


def test_aspect_comes_from_library_size_and_bursts_collapse(tmp_path):
    items = [item(tmp_path, n, day="2026-10-20T10:00:%02d+08:00" % (n * 5), description="布布坐在小椅子上吃水果")
             for n in range(1, 4)]
    items.append(item(tmp_path, 4, day="2026-10-20T09:00:00+08:00", description="布布在公园"))
    for entry in items:
        entry.update(width=1080, height=1920)
    items[3].update(width=0, height=0)
    timeline, _ = build(tmp_path, items)
    feed = timeline.feed(scope())["items"]
    assert [i["aspect"] for i in feed] == [0.5625, 0.5625, 0.5625, 1.0]
    assert [i["burst_count"] for i in feed] == [3, 3, 3, 1] and len({i["burst_id"] for i in feed[:3]}) == 1
    assert feed[3]["burst_id"] is None
    collapsed = timeline.feed(scope(), collapse_bursts=True)
    assert collapsed["total"] == 2 and collapsed["items"][0]["burst_count"] == 3
    assert timeline.feed(scope(), query="公园", collapse_bursts=True)["total"] == 1


def test_bridge_reads_display_size_from_the_library_thumbnail(tmp_path):
    bridge = BrainBridge(tmp_path)
    thumbs = tmp_path / "data/media/thumbs"
    thumbs.mkdir(parents=True)
    buffer = io.BytesIO()
    Image.new("RGB", (270, 480)).save(buffer, "JPEG")
    (thumbs / ("a" * 24 + ".jpg")).write_bytes(buffer.getvalue())
    raw = {"width": 1920, "height": 1080}  # rotated video: raw sensor size is landscape

    class Asset(dict):
        def keys(self):
            return super().keys()
    assert bridge._display_size("a" * 24, "1" * 64, Asset(raw)) == {"width": 270, "height": 480}
    assert bridge._display_size("b" * 24, "1" * 64, Asset(raw)) == {"width": 1920, "height": 1080}
    assert unsuitable({"item": {"media_type": "photo", "width": 400, "height": 900}, "tags": [], "description": "布布"})


# ---------- status backup marker, attempts window ----------

def test_status_backup_at_reads_the_nightly_mirror_marker(tmp_path, monkeypatch):
    store = LearningStore(tmp_path / "state")
    mirror = tmp_path / "mirror/learning"
    mirror.mkdir(parents=True)
    (mirror / "manifest.json").write_text("{}")
    stamp = time.time() - 3600
    os.utime(mirror / "manifest.json", (stamp, stamp))
    result = probe(str(store.root), "", marker=str(mirror))
    assert abs(result["backup_marker"]["at"] - stamp) < 2 and result["backup"] is None
    monkeypatch.setenv("LEARNING_BACKUP_MARKER", str(mirror / "manifest.json"))
    assert abs(probe(str(store.root), "")["backup_marker"]["at"] - stamp) < 2
    assert probe(str(store.root), "", marker=str(tmp_path / "missing"))["backup_marker"] is None
    timeline, _ = build(tmp_path, [item(tmp_path, 1)])
    status = Status(timeline, lambda *a: {"learning_store": True, "brain_library": True, "heartbeat": None,
                                          "backup": {"at": stamp - 86400}, "backup_marker": {"at": stamp}})
    value = status.status(scope())
    assert value["backup_at"] == datetime.fromtimestamp(stamp).astimezone().astimezone(
        __import__("zoneinfo").ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds")


def test_attempts_can_be_limited_to_a_date_window(tmp_path):
    store = LearningStore(tmp_path / "state")
    service = LearningService(store, None)
    with store.db() as db:
        for n, when in enumerate(("2026-10-12T23:30:00+08:00", "2026-10-13T00:10:00+08:00", "2026-10-19T23:59:00+08:00",
                                  "2026-10-20T00:01:00+08:00")):
            db.execute("INSERT INTO attempts VALUES(?,?,?,?,?,?,?)", ("a%d" % n, FAMILY, CHILD, "p", "x",
                       json.dumps({"kind": "choice"}), datetime.fromisoformat(when).timestamp()))
    me = FamilyScope("mom", FAMILY, [{"id": CHILD, "name": "布布"}], True)
    assert len(service.attempts(me, CHILD)["items"]) == 4
    assert {i["id"] for i in service.attempts(me, CHILD, "2026-10-13", "2026-10-19")["items"]} == {"a1", "a2"}
    assert {i["id"] for i in service.attempts(me, CHILD, "2026-10-20")["items"]} == {"a3"}
    with pytest.raises(ValueError):
        service.attempts(me, CHILD, "2026-10-20", "2026-10-13")
