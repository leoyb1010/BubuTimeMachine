"""2.25.1 stability and 2.26/2.27 family features: fakes only, no library, disk stalls or model."""
from datetime import date
import json
from pathlib import Path
import sys
import threading
import time

from fastapi import HTTPException
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_family_features import Bridge, Processor, build, item, scope, FAMILY, CHILD  # noqa: E402
from learning import social as social_module, status as status_module  # noqa: E402
from learning.ask import Ask, keywords  # noqa: E402
from learning.auth import FamilyScope  # noqa: E402
from learning.brain_bridge import BrainBlocked, BrainTimeout, BrainUnavailable  # noqa: E402
from learning.firsts import Firsts  # noqa: E402
from learning.online_timeline import OnlineTimeline, UNAVAILABLE  # noqa: E402
from learning.places import Places  # noqa: E402
from learning.recognition import Recognition  # noqa: E402
from learning.social import Social  # noqa: E402
from learning.status import Status, deep_health, probe  # noqa: E402
from learning.store import LearningStore, Missing  # noqa: E402
from learning.timeline_captions import TimelineCaptions  # noqa: E402
from learning.voices import Voices  # noqa: E402
from learning.words import Words, tokens  # noqa: E402
from learning.worker import LearningWorker  # noqa: E402


def member(user="grandma", role="姥姥", review=False):
    return FamilyScope(user, FAMILY, [{"id": CHILD, "name": "布布"}], review, role)


class StuckBridge(Bridge):
    """subject_snapshot blocks until released, like a library on a stalled external disk."""

    def __init__(self, items):
        super().__init__(items)
        self.release = threading.Event()
        self.stuck = False

    def subject_snapshot(self, subject):
        if self.stuck:
            self.release.wait(10)
        return super().subject_snapshot(subject)


# ---------- 2.25.1 snapshot never blocks a request on the library ----------

def test_snapshot_refreshes_in_background_and_stalls_become_503(tmp_path):
    bridge = StuckBridge([item(tmp_path, 1)])
    bridge.stuck = True
    timeline, _ = build(tmp_path, [], bridge=bridge, wait=0.3)
    started = time.monotonic()
    with pytest.raises(HTTPException) as error:
        timeline.feed(scope())
    assert error.value.status_code == 503 and error.value.detail == UNAVAILABLE
    assert time.monotonic() - started < 2
    assert timeline.peek() is None and timeline.snapshot_age() is None
    bridge.release.set()
    deadline = time.monotonic() + 5
    while timeline.peek() is None and time.monotonic() < deadline:
        time.sleep(0.02)
    assert timeline.feed(scope())["total"] == 1 and timeline.snapshot_age() == 0
    # Stalled again after an invalidation: the last good snapshot answers within the wait.
    bridge.release.clear()
    bridge.items.append(item(tmp_path, 2))
    timeline.invalidate()
    started = time.monotonic()
    assert timeline.feed(scope())["total"] == 1 and time.monotonic() - started < 2
    bridge.release.set()
    deadline = time.monotonic() + 5
    while timeline.feed(scope())["total"] != 2 and time.monotonic() < deadline:
        time.sleep(0.02)
    assert timeline.feed(scope())["total"] == 2


def test_stale_snapshot_is_served_while_refreshing_and_failures_keep_last_good(tmp_path):
    bridge = Bridge([item(tmp_path, 1)])
    timeline, _ = build(tmp_path, [], bridge=bridge, ttl=0)
    assert timeline.feed(scope())["total"] == 1
    bridge.subject_snapshot = lambda subject: (_ for _ in ()).throw(BrainUnavailable("down"))
    for _ in range(3):
        assert timeline.feed(scope())["total"] == 1  # age-stale: answered at once
    timeline.invalidate()
    assert timeline.feed(scope())["total"] == 1  # refresh failed: last good snapshot
    assert isinstance(timeline.error, BrainUnavailable)


def test_cached_preview_does_not_touch_the_original(tmp_path):
    timeline, _ = build(tmp_path, [item(tmp_path, 1)])
    path, _ = timeline.media(scope(), "%024x" % 1, "thumb")
    Path(timeline.snapshot()["by_id"]["%024x" % 1]["local_path"]).unlink()
    assert timeline.media(scope(), "%024x" % 1, "thumb")[0] == path
    with pytest.raises(Missing):
        timeline.media(scope(), "%024x" % 1, "original")


# ---------- captions: one poison item no longer blocks the batch ----------

class CaptionBridge:
    def __init__(self, poison=(), outage=False):
        self.poison, self.outage, self.calls = set(poison), outage, []

    def complete_json(self, system, user, schema, *, effort="high"):
        batch = json.loads(user)
        self.calls.append([b["id"] for b in batch])
        if self.outage:
            raise BrainTimeout("slow")
        if any(b["id"] in self.poison for b in batch):
            raise BrainBlocked("filtered")
        return {"items": [{"id": b["id"], "description": "布布（袁晨希）" + b["description"][2:], "changed": True}
                          for b in batch]}


def caption_item(n):
    return {"file_id": "%024x" % n, "analysis": {"description": "女童在画第%d幅画" % n}}


def test_poison_caption_is_retried_alone_then_kept_original(tmp_path):
    captions = TimelineCaptions(LearningStore(tmp_path))
    items = [caption_item(n) for n in range(1, 5)]
    bridge = CaptionBridge(poison={"%024x" % 1})
    report = captions.run(bridge, "fam", items)
    assert report["changed"] == 3 and report["failed"] == 1 and report["given_up"] == 0
    assert [i["file_id"] for i in captions.pending("fam", items)] == ["%024x" % 1]
    for _ in range(2):
        report = captions.run(bridge, "fam", items)
    assert report["given_up"] == 1 and captions.pending("fam", items) == []
    assert captions.overlays("fam", items).get("%024x" % 1) is None  # original wording kept
    assert len(captions.overlays("fam", items)) == 3


def test_caption_outage_is_not_blamed_on_items(tmp_path):
    captions = TimelineCaptions(LearningStore(tmp_path))
    items = [caption_item(n) for n in range(1, 5)]
    bridge = CaptionBridge(outage=True)
    for _ in range(4):
        report = captions.run(bridge, "fam", items)
        assert report["given_up"] == 0
    assert len(bridge.calls) <= 4 * 3  # batch + at most two single probes per pass
    assert len(captions.pending("fam", items)) == 4
    alone = [caption_item(9)]
    for _ in range(4):
        captions.run(bridge, "fam", alone)
    assert captions.pending("fam", alone) == alone
    with captions.store.db() as db:
        assert db.execute("SELECT count(*) FROM timeline_caption_failures").fetchone()[0] == 0


def test_worker_caption_step_logs_exception_class(tmp_path, caplog):
    store = LearningStore(tmp_path / "state")

    class Down:
        def subject_snapshot(self, subject):
            raise BrainUnavailable("disk")
    worker = LearningWorker(store, Down(), None, family="f1", child="c1", subject="s" * 16)
    with caplog.at_level("WARNING"):
        worker.caption_new_timeline_items()
    assert "error=BrainUnavailable" in caplog.text


# ---------- worker heartbeat, voices backlog, daily backup ----------

def test_worker_heartbeat_voices_backlog_and_daily_backup(tmp_path, monkeypatch):
    store = LearningStore(tmp_path / "state")
    store.add_source("f1", "c1", "2026-10-20", "input", "card.jpg", b"evidence", "image/jpeg")
    processed = []

    class VoiceStep:
        def sync_candidates(self):
            return 0

        def process(self, limit):
            processed.append(limit)
    worker = LearningWorker(store, None, None, family="f1", child="c1", features={"voices": VoiceStep()})
    worker.heartbeat()
    beat = store.get_cursor("worker-heartbeat")["at"]
    assert abs(beat - time.time()) < 5
    worker.heartbeat()
    assert store.get_cursor("worker-heartbeat")["at"] == beat  # throttled
    root = tmp_path / "backups"
    monkeypatch.setenv("LEARNING_BACKUP_DIR", str(root))
    worker.periodic(now=0, today=date(2026, 10, 22))
    assert 3 <= processed[0] <= 5
    assert (root / "2026-10-22/learning.sqlite").is_file()
    assert store.get_cursor("learning-backup")["day"] == "2026-10-22"
    worker.periodic(now=10, today=date(2026, 10, 22))
    assert sorted(p.name for p in root.iterdir()) == ["2026-10-22"]  # once a day
    original = next(p for p in (root / "2026-10-22/originals").rglob("*") if p.is_file())
    for day in range(23, 31):
        worker.backup(root, "2026-10-%02d" % day)
    days = sorted(p.name for p in root.iterdir())
    assert days == ["2026-10-%02d" % d for d in range(24, 31)]  # keeps the last seven
    latest = next(p for p in (root / "2026-10-30/originals").rglob("*") if p.is_file())
    assert latest.read_bytes() == b"evidence" and latest.stat().st_nlink >= 2  # unchanged files are hard links
    assert not original.exists()


def test_worker_backup_is_skipped_without_configuration(tmp_path, monkeypatch):
    monkeypatch.delenv("LEARNING_BACKUP_DIR", raising=False)
    store = LearningStore(tmp_path / "state")
    worker = LearningWorker(store, None, None, family="f1", child="c1")
    worker.periodic(now=0, today=date(2026, 10, 22))
    assert store.get_cursor("learning-backup") is None


# ---------- status and deep health ----------

def test_probe_reads_store_and_library_and_times_out(tmp_path, monkeypatch):
    store = LearningStore(tmp_path / "state")
    store.set_cursor("worker-heartbeat", {"at": 1700000000.0})
    brain = tmp_path / "第二 大脑"
    (brain / "data").mkdir(parents=True)
    import sqlite3
    sqlite3.connect(brain / "data/library.sqlite").execute("CREATE TABLE t(x)").connection.close()
    result = probe(str(store.root), str(brain))
    assert result["learning_store"] and result["brain_library"] and result["heartbeat"] == {"at": 1700000000.0}
    assert probe(str(tmp_path / "none"), "")["learning_store"] is False
    monkeypatch.setenv("LEARNING_STATE_DIR", str(store.root))
    monkeypatch.setenv("LEARNING_BRAIN_ROOT", str(brain))
    health = deep_health(12)
    assert health["ok"] and health["snapshot_age_s"] == 12 and health["worker_heartbeat_age_s"] > 1000
    monkeypatch.setattr(status_module, "PROBE", "import time; time.sleep(30)")
    started = time.monotonic()
    assert probe(str(store.root), str(brain), timeout=0.5) == {"learning_store": False, "brain_library": False,
                                                              "heartbeat": None, "backup": None}
    assert time.monotonic() - started < 3


def test_status_fields_are_null_when_unknown_and_never_block(tmp_path):
    timeline, _ = build(tmp_path, [item(tmp_path, 1), item(tmp_path, 2)])
    now = time.time()
    status = Status(timeline, lambda *a: {"learning_store": True, "brain_library": True,
                                          "heartbeat": {"at": now - 10}, "backup": {"at": now - 3600}})
    first = status.status(scope())
    assert first["ok"] and first["worker_alive"] and first["items"] is None and first["snapshot_at"] is None
    assert first["voices_pending"] is None and first["backup_at"].endswith("+08:00")
    deadline = time.monotonic() + 5
    while timeline.peek() is None and time.monotonic() < deadline:
        time.sleep(0.02)
    second = status.status(scope())
    assert second["items"] == 2 and second["captions_pending"] == 2 and second["snapshot_at"]
    assert str(tmp_path) not in json.dumps(second, ensure_ascii=False)
    down = Status(timeline, lambda *a: {"learning_store": False, "brain_library": False, "heartbeat": None, "backup": None})
    result = down.status(scope())
    assert result["ok"] is False and result["worker_alive"] is None and result["worker_heartbeat_at"] is None
    with pytest.raises(Missing):
        status.status(FamilyScope("x", "family-b", [], True))


# ---------- recognition undo / batch / history ----------

def test_recognition_undo_batch_and_history(tmp_path):
    shown = item(tmp_path, 1)
    candidates = [item(tmp_path, n, day="2026-08-0%dT10:00:00+08:00" % n) for n in (2, 3, 4)]
    bridge = Bridge([shown], candidates=candidates)
    timeline, _ = build(tmp_path, [shown], bridge=bridge)
    recognition = Recognition(bridge, timeline)
    batch = [{"id": c["file_id"], "decision": "yes"} for c in candidates[:2]] + [{"id": "%024x" % 99, "decision": "no"}]
    assert recognition.batch(scope(), batch) == {"applied": 2}
    assert {i["id"] for i in timeline.feed(scope())["items"]} == {shown["file_id"], candidates[0]["file_id"], candidates[1]["file_id"]}
    with pytest.raises(HTTPException):
        recognition.batch(scope(review=False), batch)
    with pytest.raises(ValueError):
        recognition.batch(scope(), [{"id": shown["file_id"], "decision": "maybe"}])
    recognition.decide(scope(), shown["file_id"], "no")
    history = recognition.history(scope(), 10)["items"]
    assert history[0]["id"] == shown["file_id"] and history[0]["decision"] == "no"
    assert history[0]["preview_url"] == "/learning/api/recognition/%s/preview" % shown["file_id"]
    assert {h["decision"] for h in history} == {"yes", "no"} and len(history) == 3
    assert recognition.decide(scope(), shown["file_id"], "undo") == {"id": shown["file_id"], "decision": "undo"}
    assert shown["file_id"] in {i["id"] for i in timeline.feed(scope())["items"]}
    recognition.decide(scope(), candidates[0]["file_id"], "undo")
    assert candidates[0]["file_id"] not in {i["id"] for i in timeline.feed(scope())["items"]}
    assert candidates[0]["file_id"] in {i["id"] for i in recognition.candidates(scope())["items"]}
    assert len(recognition.history(scope())["items"]) == 1
    with pytest.raises(Missing):
        recognition.decide(scope(), "../x", "undo")


# ---------- firsts kind and dismissal down-weighting ----------

def test_firsts_kind_and_repeatedly_dismissed_types_need_her_name(tmp_path):
    items = [item(tmp_path, n, day="2025-0%d-01T10:00:00+08:00" % n, description="一个孩子在吃西瓜") for n in range(1, 6)]
    items.append(item(tmp_path, 6, day="2025-08-01T10:00:00+08:00", description="布布在吃西瓜"))
    items.append(item(tmp_path, 7, day="2025-09-15T10:00:00+08:00", description="布布在幼儿园门口"))
    timeline, _ = build(tmp_path, items)
    firsts = Firsts(timeline)
    firsts.compute()
    listed = firsts.list(scope())["items"]
    assert {i["kind"] for i in listed} == {"watermelon", "kindergarten"} and all(i["kind"] == i["concept"] for i in listed)
    for n in range(1, 4):
        current = next(i for i in firsts.list(scope())["items"] if i["kind"] == "watermelon")
        assert current["item_id"] == "%024x" % n
        firsts.dismiss(scope(), current["id"])
    # Three dismissals: generic "孩子" clauses no longer count, so items 4 and 5 are skipped.
    current = firsts.list(scope())["items"]
    assert [i["kind"] for i in current] == ["kindergarten", "watermelon"]  # the weak type is listed last
    assert current[-1]["item_id"] == "%024x" % 6


# ---------- words ----------

def test_word_tokens_use_lexicon_and_stopwords():
    assert tokens("爸爸抱") == ["爸爸", "抱"]
    assert tokens("我要吃苹果呀") == ["我要", "吃", "苹果"]
    assert tokens("Apple, apple! a") == ["apple"]
    assert tokens("啊啊啊") == []


def test_words_timeline_counts_new_words_per_month(tmp_path):
    speech = [{"id": "a", "start": 1.0, "end": 2.0, "text": "爸爸"}]
    items = [item(tmp_path, 1, kind="video", day="2026-03-01T10:00:00+08:00", segments=speech),
             item(tmp_path, 2, kind="video", day="2026-04-01T10:00:00+08:00", segments=speech)]
    bridge = Bridge(items)
    timeline, _ = build(tmp_path, items, bridge=bridge)
    voices = Voices(timeline, bridge, Processor())
    with timeline.store.db() as db:
        for vid, fid, at, heard, state in (("a" * 16, "%024x" % 1, "2026-03-01T02:00:00+00:00", "爸爸抱", "ready"),
                                           ("b" * 16, "%024x" % 2, "2026-03-31T17:00:00+00:00", "爸爸 苹果", "ready"),
                                           ("c" * 16, "%024x" % 2, "2026-04-02T02:00:00+00:00", "妈妈", "pending"),
                                           ("d" * 16, "%024x" % 9, "2026-02-01T02:00:00+00:00", "西瓜", "ready")):
            db.execute("INSERT INTO voices VALUES(?,?,?,?,1,2,'',?,?,0,0)", (vid, FAMILY, fid, at, heard, state))
    result = Words(timeline, voices).words(scope())
    assert result["months"] == [{"month": "2026-03", "new_words": ["爸爸", "抱"], "total": 2},
                                {"month": "2026-04", "new_words": ["苹果"], "total": 3}]  # 17:00Z is April 1st in Shanghai
    first = result["firsts"][0]
    assert first == {"word": "爸爸", "item_id": "%024x" % 1, "voice_id": "a" * 16,
                     "captured_at": "2026-03-01T02:00:00+00:00", "text": "爸爸抱"}
    assert result["source_count"] == 2 and result["pending"] == 1  # item 9 is not in her timeline


# ---------- places and events ----------

def test_places_group_by_full_name_and_events_filter_visible_items(tmp_path):
    items = [item(tmp_path, n, day="2025-07-%02dT10:00:00+08:00" % n, place="中国 · 上海市 · 世纪公园") for n in range(1, 4)]
    items += [item(tmp_path, 4, day="2025-08-01T10:00:00+08:00", place="舟山"), item(tmp_path, 5, place="")]
    bridge = Bridge(items)
    bridge.auto_events = lambda: [
        {"id": "7", "title": "海边的周末", "story": "踩沙子", "day": "2025-07-12", "place": "中国 · 舟山市",
         "cover_id": "%024x" % 2, "file_ids": ["%024x" % n for n in (1, 2, 3, 77)]},
        {"id": "8", "title": "太少", "story": "", "day": None, "place": "", "cover_id": None,
         "file_ids": ["%024x" % 1, "%024x" % 77, "%024x" % 78]},
        {"id": "9", "title": "无日期", "story": "", "day": None, "place": "", "cover_id": "%024x" % 99,
         "file_ids": ["%024x" % n for n in (1, 2, 4)]}]
    timeline, _ = build(tmp_path, items, bridge=bridge)
    places = Places(timeline).places(scope())["items"]
    assert places[0]["name"] == "上海市·世纪公园" and places[0]["short"] == "世纪公园" and places[0]["city"] == "上海市"
    assert places[0]["count"] == 3 and places[0]["item_ids"] == ["%024x" % n for n in (3, 2, 1)]
    assert (places[0]["first_day"], places[0]["last_day"]) == ("2025-07-01", "2025-07-03")
    assert places[0]["cover_url"].startswith("/learning/api/online-timeline/") and "size=thumb" in places[0]["cover_url"]
    assert places[1] == {**places[1], "name": "舟山", "short": "舟山", "city": None, "count": 1}
    events = Places(timeline).events(scope())["items"]
    assert [e["id"] for e in events] == ["9", "7"]  # day desc; the undated one uses its newest item
    sea = events[1]
    assert sea["item_ids"] == ["%024x" % n for n in (1, 2, 3)] and sea["count"] == 3 and sea["place"] == "舟山市"
    assert sea["cover_url"] == "/learning/api/online-timeline/%024x/preview?size=large&revision=%064x" % (2, 2)
    assert events[0]["day"] == "2025-08-01"
    assert [e["id"] for e in Places(timeline).events(scope(), "2025-07-01", "2025-07-31")["items"]] == ["7"]
    with pytest.raises(ValueError):
        Places(timeline).events(scope(), "2025-08-01", "2025-07-01")


# ---------- ask ----------

class AskBridge(Bridge):
    def complete_json(self, system, user, schema, *, effort="high", timeout=None):
        self.calls.append((system, user, effort, timeout))
        if isinstance(self.reply, Exception):
            raise self.reply
        return self.reply


def test_ask_retrieves_cites_only_retrieved_and_falls_back(tmp_path):
    items = [item(tmp_path, 1, day="2025-07-12T10:00:00+08:00", description="布布第一次在海边踩沙子", place="中国 · 舟山市 · 海边"),
             item(tmp_path, 2, day="2025-07-13T10:00:00+08:00", description="布布在海边捡贝壳"),
             item(tmp_path, 3, description="布布在家吃饭")]
    bridge = AskBridge(items)
    bridge.reply = {"answer": "2025年7月12日在舟山的海边[1]，第二天又去捡贝壳[4][4]。[2][3][9]", "citations": [
        {"id": "%024x" % 1, "note": "第一次踩到沙子"}, {"id": "%024x" % 3, "note": "不在检索里"}, {"id": "nope", "note": "x"},
        {"id": "%024x" % 2, "note": "捡贝壳"}]}
    timeline, _ = build(tmp_path, items, bridge=bridge)
    ask = Ask(timeline, bridge)
    assert "海边" in keywords("她第一次去海边是什么时候？") and "什么" not in keywords("她第一次去海边是什么时候？")
    result = ask.ask(scope(), "她第一次去海边是什么时候？")
    assert [i["id"] for i in result["items"]] == ["%024x" % 1, "%024x" % 2]
    assert result["citations"] == [{"id": "%024x" % 1, "note": "第一次踩到沙子"}, {"id": "%024x" % 2, "note": "捡贝壳"}]
    assert result["model_used"] is True and result["answer"] == "2025年7月12日在舟山的海边[1]，第二天又去捡贝壳[2]。"
    system, user, effort, timeout = bridge.calls[-1]
    assert effort in {"low", "medium"} and timeout and timeout <= 120 and "[n]" in system
    assert "local_path" not in user and "base64" not in user and "舟山市 · 海边" in user
    bridge.reply = BrainUnavailable("down")
    fallback = ask.ask(scope(), "海边")
    assert fallback["answer"] is None and fallback["model_used"] is False and len(fallback["items"]) == 2
    calls = len(bridge.calls)
    empty = ask.ask(scope(), "火星旅行")
    assert empty["items"] == [] and empty["answer"] is None and len(bridge.calls) == calls
    with pytest.raises(ValueError):
        ask.ask(scope(), " ")


def test_ask_semantic_hits_rank_first_and_rate_limit(tmp_path):
    from test_family_features import Gateway
    items = [item(tmp_path, n, description="布布在公园%d" % n) for n in range(1, 16)]
    bridge = AskBridge(items)
    bridge.reply = {"answer": "", "citations": []}
    timeline, _ = build(tmp_path, items, bridge=bridge, semantic=Gateway({"%024x" % 9: 0.8}))
    ask = Ask(timeline, bridge)
    result = ask.ask(scope(), "公园")
    assert result["items"][0]["id"] == "%024x" % 9 and len(result["items"]) == 12 and result["semantic"] is True
    assert result["answer"] is None and result["model_used"] is False  # empty answer is no answer
    for _ in range(19):
        ask.ask(scope(), "公园")
    with pytest.raises(HTTPException) as error:
        ask.ask(scope(), "公园")
    assert error.value.status_code == 429


# ---------- social ----------

def test_social_comments_hearts_recent_and_ntfy(tmp_path, monkeypatch):
    items = [item(tmp_path, 1), item(tmp_path, 2)]
    timeline, _ = build(tmp_path, items)
    social = Social(timeline)
    fid = "%024x" % 1
    monkeypatch.delenv("BUBU_SOCIAL_NTFY_URL", raising=False)
    assert social_module.notify("妈妈") is None
    pushed = []
    monkeypatch.setenv("BUBU_SOCIAL_NTFY_URL", "http://127.0.0.1:9/bubu-family")
    token_file = tmp_path / "token"
    token_file.write_text("tk_test\n")
    monkeypatch.setenv("BUBU_SOCIAL_NTFY_TOKEN_FILE", str(token_file))

    class Client:
        def __init__(self, **kwargs):
            assert kwargs["trust_env"] is False

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def post(self, url, content, headers):
            pushed.append((url, content.decode(), headers.get("Authorization")))
    monkeypatch.setattr(social_module.httpx, "Client", Client)
    comment = social.comment(member(), fid, "  好可爱  ")
    assert comment["author"] == "姥姥" and comment["text"] == "好可爱" and comment["mine"] is True
    deadline = time.monotonic() + 3
    while not pushed and time.monotonic() < deadline:
        time.sleep(0.01)
    assert pushed == [("http://127.0.0.1:9/bubu-family", "姥姥评论了布布的一条时光", "Bearer tk_test")]
    social.comment(member("mom", ""), fid, "嗯")
    view = social.social(member("mom", ""), fid)
    assert [(c["author"], c["mine"]) for c in view["comments"]] == [("姥姥", False), ("家人", True)]
    with pytest.raises(Missing):
        social.delete_comment(member("mom", ""), fid, comment["id"])  # only the author deletes
    social.delete_comment(member(), fid, comment["id"])
    assert len(social.social(member(), fid)["comments"]) == 1
    assert social.heart(member(), fid, True) == {"hearts": 1, "hearted": True}
    assert social.heart(member(), fid, True) == {"hearts": 1, "hearted": True}
    assert social.heart(member("mom", ""), fid, True) == {"hearts": 2, "hearted": True}
    assert social.heart(member(), fid, False) == {"hearts": 1, "hearted": False}
    recent = social.recent(member(), 5)["items"]
    assert [r["kind"] for r in recent] == ["heart", "comment"] and recent[0]["text"] is None
    assert recent[1]["text"] == "嗯" and recent[1]["preview_url"].endswith("revision=%064x" % 1)
    for bad in ("", "x" * 301):
        with pytest.raises(ValueError):
            social.comment(member(), fid, bad)
    with pytest.raises(Missing):
        social.comment(member(), "%024x" % 99, "hi")
    with pytest.raises(Missing):
        social.social(FamilyScope("x", "family-b", [], True), fid)
