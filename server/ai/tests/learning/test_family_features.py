"""2.25 family features over the online timeline: fakes only, no library or model."""
from datetime import date, datetime
import io
from pathlib import Path
import sys

from fastapi import HTTPException
from PIL import Image
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning import fsrs
from learning.auth import FamilyScope
from learning.brain_bridge_runner import validate_request
from learning.firsts import Firsts
from learning.memories import Memories
from learning.monthly import Monthly, pick_highlights
from learning.online_timeline import OnlineTimeline, jpeg_size, plausible_segment
from learning.recognition import Recognition
from learning.store import LearningStore, Missing
from learning.voices import Voices
from learning.worker import LearningWorker

FAMILY, CHILD = "family-a", "child-a"


def scope(review=True):
    return FamilyScope("mom", FAMILY, [{"id": CHILD, "name": "布布"}], review)


def item(tmp, n, *, kind="photo", day="2026-10-20T10:00:00+08:00", description="布布在画画", people=(), place="",
         tags=(), event="", segments=()):
    path = tmp / ("%03d.%s" % (n, "jpg" if kind == "photo" else "mp4"))
    path.write_bytes(b"x" * (n + 1))
    return {"file_id": "%024x" % n, "content_hash": "%064x" % n, "media_type": kind, "captured_at": day, "name": path.name,
            "local_path": str(path), "provenance": "gemini_two_pass", "people": list(people), "place": place, "event": event,
            "analysis": {"description": description, "ocr": "", "tags": list(tags), "segments": list(segments)}}


class Bridge:
    def __init__(self, items, extra=(), candidates=()):
        self.items, self.extra, self.candidates = items, list(extra), list(candidates)
        self.calls = []

    def subject_snapshot(self, subject):
        return {"complete": True, "items": [dict(i) for i in self.items], "people_labels": {"郑德兰": "姥姥", "袁博": "爸爸"}}

    def items_by_ids(self, ids, subject=""):
        return [dict(i) for i in self.items + self.extra + self.candidates if i["file_id"] in ids]

    def recognition_candidates(self, subject):
        return [dict(i) for i in self.candidates]

    def complete_json(self, system, user, schema, *, effort="high"):
        self.calls.append((system, user, effort))
        validate_request(system, user, schema)
        return self.reply(user) if callable(self.reply) else self.reply


class Processor:
    ffmpeg = "ffmpeg"

    def __init__(self):
        self.commands = []

    def _run(self, args, timeout=120):
        self.commands.append(args)
        out = args[args.index("--out") + 1] if "--out" in args else args[-1]
        Path(out).write_bytes(b"\x00\x00\x00\x18ftypmp42" + b"0" * 32)


class Gateway:
    def __init__(self, scores):
        self.value, self.queries = scores, []

    def scores(self, query):
        self.queries.append(query)
        if isinstance(self.value, Exception):
            raise self.value
        return self.value


def build(tmp, items, **kwargs):
    bridge = kwargs.pop("bridge", None) or Bridge(items)
    store = LearningStore(tmp / "state")
    timeline = OnlineTimeline(bridge, Processor(), store, FAMILY, CHILD, "s" * 16, born="2024-05-22", **kwargs)
    return timeline, bridge


def test_transcript_filter_drops_zh_asr_gibberish_but_keeps_real_speech():
    for junk in ["Bu bu goob wasin boplea bubun the", "H", "you", "。", "Mommy goodabobody", "tely Good joble walklin the"]:
        assert not plausible_segment(junk, 0, 3)
    assert not plausible_segment("有", 6.5, 13.3)  # one character stretched over seconds
    assert not plausible_segment("字幕由Amara.org社区提供", 0, 3)
    for real in ["我喜欢小", "妈妈", "好了下一个流程梳头", "我们来唱 ABC song", "二"]:
        assert plausible_segment(real, 0, 2)


def test_jpeg_header_gives_aspect_and_feed_reports_extended_fields(tmp_path):
    items = [item(tmp_path, 1, people=["郑德兰"], place="中国 · 深圳市 · 尚云花园",
                  segments=[{"id": "a", "start": 0, "end": 2, "text": "妈妈抱"}, {"id": "b", "start": 2, "end": 4, "text": "H"}]),
             item(tmp_path, 2, day="2026-09-01T10:00:00+08:00")]
    timeline, _ = build(tmp_path, items)
    buffer = io.BytesIO()
    Image.new("RGB", (300, 200)).save(buffer, "JPEG", progressive=True)
    previews = timeline.store.root / "online-previews"
    previews.mkdir()
    (previews / ("%064x-thumb.jpg" % 1)).write_bytes(buffer.getvalue())
    assert jpeg_size(previews / ("%064x-thumb.jpg" % 1)) == (300, 200)
    feed = timeline.feed(scope())
    first, second = feed["items"]
    assert first["aspect"] == 1.5 and second["aspect"] == 1.0
    assert first["people"] == ["姥姥"] and first["place"] == "深圳市 · 尚云花园"
    assert [s["text"] for s in first["segments"]] == ["妈妈抱"] and first["transcript_hidden"] == 1
    assert first["confirmed_by_family"] is False
    assert feed["months"] == [{"month": "2026-10", "count": 1}, {"month": "2026-09", "count": 1}]
    assert "months" not in timeline.feed(scope(), page=2, limit=1)
    # Person filter accepts the name or the kinship label; search also finds people and places.
    assert [i["id"] for i in timeline.feed(scope(), person="姥姥")["items"]] == ["%024x" % 1]
    assert [i["id"] for i in timeline.feed(scope(), person="郑德兰")["items"]] == ["%024x" % 1]
    assert timeline.feed(scope(), query="尚云花园")["total"] == 1
    assert timeline.people(scope())["items"] == [{"name": "郑德兰", "label": "姥姥", "count": 1}]


def test_semantic_hits_rank_first_then_keywords_and_gateway_failure_falls_back(tmp_path):
    items = [item(tmp_path, 1, description="布布在海边玩沙子", day="2026-10-01T10:00:00+08:00"),
             item(tmp_path, 2, description="布布在沙坑里", day="2026-10-02T10:00:00+08:00"),
             item(tmp_path, 3, description="吃饭", day="2026-10-03T10:00:00+08:00"),
             item(tmp_path, 4, description="海边日落", day="2026-10-04T10:00:00+08:00")]
    gateway = Gateway({"%024x" % 2: 0.72, "%024x" % 1: 0.70, "%024x" % 3: 0.55, "f" * 24: 0.99})
    timeline, _ = build(tmp_path, items, semantic=gateway)
    feed = timeline.feed(scope(), query="海边")
    assert [i["id"][-1] for i in feed["items"]] == ["2", "1", "4"] and feed["semantic"] is True
    gateway.value = RuntimeError("down")
    assert [i["id"][-1] for i in timeline.feed(scope(), query="海边")["items"]] == ["4", "1"]
    gateway.value = None
    assert timeline.feed(scope(), query="海边")["total"] == 2
    assert timeline.feed(scope())["total"] == 4 and len(gateway.queries) == 3  # no gateway call without query


def test_items_by_ids_and_highlights_prefer_on_this_day(tmp_path):
    items = [item(tmp_path, 1, day="2025-10-21T10:00:00+08:00"), item(tmp_path, 2, day="2025-10-21T11:00:00+08:00"),
             item(tmp_path, 3, day="2024-10-25T10:00:00+08:00"), item(tmp_path, 4, day="2026-10-20T10:00:00+08:00"),
             item(tmp_path, 5, day="2026-10-23T10:00:00+08:00"), item(tmp_path, 6, day="2025-06-01T10:00:00+08:00")]
    timeline, _ = build(tmp_path, items)
    ids = ",".join(["%024x" % 4, "nope", "%024x" % 1])
    assert [i["id"][-1] for i in timeline.items(scope(), ids)["items"]] == ["4", "1"]
    with pytest.raises(ValueError):
        timeline.items(scope(), ",".join(["%024x" % n for n in range(61)]))
    result = timeline.highlights(scope(), "2026-10-22")
    ids = [i["id"][-1] for i in result["items"]]
    assert ids[:2] in (["1", "3"], ["2", "3"]) and "5" not in ids and "6" not in ids
    assert result["reason_by_id"]["%024x" % 4] == "最近精选"
    assert result["reason_by_id"]["%024x" % 3] == "那年这几天"  # ±3 days is never labelled 今天
    assert len(ids) <= 6 and len(set(ids)) == len(ids)


def test_recognition_queue_decisions_flow_into_timeline(tmp_path):
    shown = item(tmp_path, 1)
    candidate = item(tmp_path, 7, day="2026-08-01T10:00:00+08:00", description="一个小女孩")
    old = item(tmp_path, 8, day="2023-01-01T10:00:00+08:00")
    newest = item(tmp_path, 9, day="2026-09-01T10:00:00+08:00")
    for c, confidence in ((newest, 0.8), (candidate, None), (old, 0.9)):
        c["confidence"] = confidence
    bridge = Bridge([shown], candidates=[newest, candidate, old])
    timeline, _ = build(tmp_path, [shown], bridge=bridge)
    recognition = Recognition(bridge, timeline)
    queue = recognition.candidates(scope(), 1)
    assert [i["id"] for i in queue["items"]] == [newest["file_id"]] and queue["remaining"] == 1
    assert queue["items"][0]["preview_url"].endswith("/recognition/%s/preview" % newest["file_id"])
    with pytest.raises(HTTPException):
        recognition.decide(scope(review=False), candidate["file_id"], "yes")
    with pytest.raises(Missing):
        recognition.decide(scope(), "%024x" % 99, "yes")
    with pytest.raises(Missing):
        recognition.preview(scope(), "%024x" % 99)
    assert recognition.preview(scope(), candidate["file_id"])[1] == "image/jpeg"
    assert recognition.decide(scope(), candidate["file_id"], "yes") == {"id": candidate["file_id"], "decision": "yes"}
    feed = timeline.feed(scope())
    added = next(i for i in feed["items"] if i["id"] == candidate["file_id"])
    assert added["label_provenance"] == "family_confirmed" and added["confirmed_by_family"] is True
    assert recognition.candidates(scope())["items"][0]["id"] == newest["file_id"]
    # “不是布布” from the details page removes an existing timeline item.
    recognition.decide(scope(), shown["file_id"], "no")
    assert shown["file_id"] not in [i["id"] for i in timeline.feed(scope())["items"]]
    assert recognition.preview(scope(), shown["file_id"])[1] == "image/jpeg"  # decided ids keep a preview


def memory_items(tmp):
    items, n = [], 0
    for year in (2025, 2026):
        for day in range(18, 25):
            n += 1
            items.append(item(tmp, n, day="%d-10-%02dT10:00:00+08:00" % (year, day), people=["郑德兰"] if n % 2 else ["袁博"],
                              place="中国 · 深圳市 · 家", description="布布吃饭" if n % 3 else "布布画画"))
    for day in range(1, 7):
        n += 1
        items.append(item(tmp, n, day="2025-08-%02dT10:00:00+08:00" % day, place="中国 · 三亚市 · 海边", people=["郑德兰"],
                          description="布布在沙滩"))
    return items


def test_memories_are_deterministic_bounded_and_rotate(tmp_path):
    timeline, _ = build(tmp_path, memory_items(tmp_path))
    memories = Memories(timeline)
    first = memories.memories(scope(), "2026-10-22")["items"]
    assert first == Memories(timeline).memories(scope(), "2026-10-22")["items"]
    assert 1 <= len(first) <= 6 and all(c["count"] >= 5 and c["count"] == len(c["item_ids"]) for c in first)
    kinds = [c["kind"] for c in first]
    assert kinds[0] == "on_this_day" and first[0]["title"] == "1年前的这几天"  # the exact day alone is too thin
    assert {"family", "trip", "theme"} <= set(kinds)
    assert next(c for c in first if c["kind"] == "trip")["title"] == "三亚之旅"
    assert first[0]["cover_url"].startswith("/learning/api/online-timeline/%s/preview" % first[0]["cover_id"])
    family = {c["title"] for c in first if c["kind"] == "family"}
    assert family <= {"和姥姥在一起", "和爸爸在一起"}
    themes = {d: [c["title"] for c in Memories(timeline).memories(scope(), d)["items"] if c["kind"] == "theme"]
              for d in ("2026-10-22", "2026-10-23")}
    assert themes["2026-10-22"] != themes["2026-10-23"]  # rotation: no same theme two days running
    with pytest.raises(ValueError):
        memories.memories(scope(), "2026-13-01")


def test_firsts_pick_earliest_and_dismiss_proposes_next(tmp_path):
    items = [item(tmp_path, 1, day="2024-05-10T10:00:00+08:00", description="别人吃西瓜"),  # before birth
             item(tmp_path, 2, day="2025-07-01T10:00:00+08:00", description="布布第一次吃西瓜"),
             item(tmp_path, 3, day="2025-08-01T10:00:00+08:00", description="", tags=["西瓜"]),
             item(tmp_path, 5, day="2025-07-15T10:00:00+08:00", description="妈妈切西瓜，布布在旁边看动画", tags=["西瓜"]),
             item(tmp_path, 6, day="2025-07-20T10:00:00+08:00", description="布布拉着西瓜球玩"),
             item(tmp_path, 4, day="2025-09-01T10:00:00+08:00", description="布布在幼儿园门口")]
    timeline, _ = build(tmp_path, items)
    firsts = Firsts(timeline)
    assert firsts.compute()["candidates"] == 2
    listed = {i["concept"]: i for i in firsts.list(scope())["items"]}
    assert listed["watermelon"]["item_id"] == "%024x" % 2 and listed["watermelon"]["title"] == "第一次吃西瓜"
    assert listed["kindergarten"]["date"] == "2025-09-01" and listed["kindergarten"]["preview_url"]
    with pytest.raises(HTTPException):
        firsts.dismiss(scope(review=False), listed["watermelon"]["id"])
    assert firsts.dismiss(scope(), listed["watermelon"]["id"])["status"] == "dismissed"
    nxt = next(i for i in firsts.list(scope())["items"] if i["concept"] == "watermelon")
    assert nxt["item_id"] == "%024x" % 3
    confirmed = firsts.confirm(scope(), nxt["id"])
    assert confirmed["status"] == "confirmed"
    firsts.compute()
    assert [i["concept"] for i in firsts.list(scope(), "confirmed")["items"]] == ["watermelon"]
    assert {i["concept"] for i in firsts.list(scope(), "all")["items"]} == {"watermelon", "kindergarten"}
    assert firsts.confirmed_in_month("2025-08") == ["第一次吃西瓜"]
    with pytest.raises(Missing):
        firsts.confirm(scope(), "missing")
    with pytest.raises(ValueError):
        firsts.list(scope(), "dismissed")


def test_monthly_report_is_validated_and_generated_once(tmp_path):
    items = [item(tmp_path, n, day="2026-09-%02dT10:00:00+08:00" % n, description="布布在公园玩" if n % 2 else "布布吃饭",
                  people=["郑德兰"] if n == 1 else [], place="中国 · 深圳市 · 公园", event="游玩" if n % 2 else "用餐")
             for n in range(1, 9)]
    bridge = Bridge(items)
    bridge.reply = {"title": "九月的公园时光", "summary": "布布在公园玩，也认真吃饭。" * 3}
    timeline, _ = build(tmp_path, items, bridge=bridge)
    firsts = Firsts(timeline)
    monthly = Monthly(timeline, bridge, firsts)
    report = monthly.generate("2026-09")
    assert report["title"] == "九月的公园时光" and report["summary"].startswith("布布（袁晨希）")
    assert len(report["summary"]) <= 160 and bridge.calls[0][2] == "medium"
    assert "姥姥" in bridge.calls[0][1] and "布布在公园玩" in bridge.calls[0][1]
    assert monthly.generate("2026-09") == report and len(bridge.calls) == 1
    assert monthly.generate("2026-08") is None
    listed = monthly.list(scope())["items"]
    assert listed[0]["month"] == "2026-09" and listed[0]["photos"] == 8 and listed[0]["places"] == ["公园"]
    assert 1 <= len(listed[0]["highlight_ids"]) <= 6
    # Too long twice: clipped, and her full name still appears.
    bridge.reply = {"title": "一" * 30, "summary": "她" * 300}
    forced = monthly.generate("2026-09", force=True)
    assert len(forced["title"]) == 20 and len(forced["summary"]) <= 160 and "布布（袁晨希）" in forced["summary"]
    assert monthly.months(date(2024, 8, 3)) == ["2024-05", "2024-06", "2024-07"]


def test_highlights_are_diverse():
    rows = [{"item": {"file_id": "%024x" % n, "media_type": "photo"}, "adjusted": True, "description": "x" * 50,
             "event": "吃饭" if n < 5 else "画画", "day": "2026-09-0%d" % (1 + n % 3), "people": [], "stamp": str(n)}
            for n in range(8)]
    chosen = pick_highlights(rows, 3)
    assert len(chosen) == 3 and len({(r["event"], r["day"]) for r in chosen}) == 3
    assert {r["event"] for r in chosen} == {"吃饭", "画画"}


def test_voice_candidates_clip_and_model_reply(tmp_path):
    speech = [{"id": "a", "start": 10.0, "end": 11.5, "text": "爸爸抱"}, {"id": "b", "start": 20.0, "end": 30.0, "text": "好了下一个流程梳头吧我们走"},
              {"id": "c", "start": 40.0, "end": 41.0, "text": "啊呀"}]
    items = [item(tmp_path, 1, kind="video", day="2026-03-01T10:00:00+08:00", segments=speech),
             item(tmp_path, 2, kind="video", day="2024-08-01T10:00:00+08:00", segments=speech)]  # too young to talk
    bridge = Bridge(items)
    bridge.reply = lambda user: {"child_speaks": "爸爸抱" in user[0]["text"], "heard": "爸爸抱抱"}
    timeline, _ = build(tmp_path, items, bridge=bridge)
    processor = Processor()
    voices = Voices(timeline, bridge, processor)
    assert voices.sync_candidates() == 2 and voices.sync_candidates() == 0
    assert voices.process(5) == {"ready": 1, "rejected": 1, "failed": 0}
    assert all(call[2] == "low" for call in bridge.calls)
    cut = processor.commands[0]
    assert cut[cut.index("-ss") + 1] == "8.50" and cut[cut.index("-t") + 1] == "4.50"
    listed = voices.list(scope())["items"]
    assert [(v["text"], v["heard"]) for v in listed] == [("爸爸抱", "爸爸抱抱")]
    path, mime = voices.audio(scope(), listed[0]["id"])
    assert mime == "audio/mp4" and path.is_file()
    with pytest.raises(Missing):
        voices.audio(scope(), "0" * 16)


def test_fsrs_two_ratings_schedule():
    d = date(2026, 10, 1)
    assert fsrs.due([], d) is None
    is_due, recall, last = fsrs.due([(d, fsrs.AGAIN)], date(2026, 10, 2))
    assert is_due and last == fsrs.AGAIN
    assert not fsrs.due([(d, fsrs.GOOD)], date(2026, 10, 3))[0]
    good = [(date(2026, 10, 1), fsrs.GOOD), (date(2026, 10, 7), fsrs.GOOD)]
    stability = fsrs.schedule(good)[0]
    assert stability > fsrs.schedule(good[:1])[0] and fsrs.interval(stability) > 6
    # A same-day failure makes the whole day Again.
    assert fsrs.schedule([(d, fsrs.GOOD), (d, fsrs.AGAIN)])[0] == fsrs.W[0]
    assert fsrs.schedule([(date(2026, 10, 1), fsrs.GOOD), (date(2026, 10, 5), fsrs.AGAIN)])[0] < fsrs.W[2]


def test_worker_periodic_steps_are_guarded_and_never_raise(tmp_path):
    calls = []

    class Step:
        def __init__(self, name, fail=False, result=None):
            self.name, self.fail, self.result = name, fail, result

        def __getattr__(self, method):
            def run(*args):
                calls.append((self.name, method))
                if self.fail:
                    raise RuntimeError("boom")
                return self.result
            return run

    store = LearningStore(tmp_path / "state")
    worker = LearningWorker(store, None, None, family="f1", child="c1",
                            features={"firsts": Step("firsts"), "monthly": Step("monthly", fail=True), "voices": Step("voices")})
    worker.periodic(now=0, today=date(2026, 10, 22))
    assert calls == [("firsts", "compute"), ("monthly", "generate_due"), ("voices", "sync_candidates"), ("voices", "process")]
    worker.periodic(now=60, today=date(2026, 10, 22))
    assert len(calls) == 4
    worker.periodic(now=4000, today=date(2026, 10, 22))
    assert ("firsts", "compute") not in calls[4:] and ("voices", "process") in calls[4:]
    worker.features["monthly"] = Step("monthly", result={"month": "2026-09"})
    worker.periodic(now=8000, today=date(2026, 10, 23))
    assert calls[-1] == ("monthly", "generate_due")  # a model call ends the pass


def test_semantic_gateway_reads_local_token_and_fails_soft(tmp_path, monkeypatch):
    import httpx
    from learning import online_timeline
    seen = []

    def handler(request):
        seen.append((request.url.path, request.url.params["q"], request.headers["authorization"]))
        return httpx.Response(200, json={"available": True, "scores": {"a" * 24: 0.7}})
    real = httpx.Client
    monkeypatch.setattr(online_timeline.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))
    gateway = online_timeline.SemanticGateway(tmp_path / "token.json")
    assert gateway.scores("海边") is None  # no token file: keywords only
    (tmp_path / "token.json").write_text('{"token": "t"}')
    assert gateway.scores("海边") == {"a" * 24: 0.7}
    assert gateway.scores("海边") == {"a" * 24: 0.7} and len(seen) == 1  # cached
    assert seen[0] == ("/v1/media/semantic", "海边", "Bearer t")
    monkeypatch.setattr(online_timeline.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(
        lambda r: (_ for _ in ()).throw(httpx.ConnectError("down"))), **kw))
    assert gateway.scores("沙滩") is None
