"""Online Bubu timeline: direct second-brain reads, never local Entries."""
from pathlib import Path
import sys

from fastapi import HTTPException
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning.auth import FamilyScope
from learning.brain_bridge import BrainUnavailable
from learning.online_timeline import OnlineTimeline
from learning.store import LearningStore, Missing

FAMILY, CHILD = "family-a", "child-a"


def scope(family=FAMILY, child=CHILD):
    return FamilyScope("user-a", family, [{"id": child, "name": "布布"}], True)


def row(tmp, n, kind="photo", day="2026-10-20T10:00:00+08:00", description="布布在画画", tags=(), segments=(), provenance="gemini_two_pass"):
    path = tmp / ("%02d.%s" % (n, "jpg" if kind == "photo" else "mp4"))
    path.write_bytes(b"x" * (n + 1))
    return {"file_id": "%024x" % n, "content_hash": "%064x" % n, "media_type": kind, "captured_at": day,
            "name": path.name, "local_path": str(path), "provenance": provenance,
            "analysis": {"description": description, "ocr": "", "tags": list(tags), "segments": list(segments)}}


class Bridge:
    def __init__(self, items):
        self.items, self.calls, self.fail = items, 0, False

    def subject_snapshot(self, subject):
        self.calls += 1
        if self.fail:
            raise BrainUnavailable("down")
        return {"complete": True, "snapshot_id": "s%d" % len(self.items), "items": self.items}


class Processor:
    ffmpeg = "ffmpeg"

    def __init__(self):
        self.commands = []

    def _run(self, args, timeout=120):
        self.commands.append(args)
        out = args[args.index("--out") + 1] if "--out" in args else args[-1]
        Path(out).write_bytes(b"jpeg")


@pytest.fixture
def timeline(tmp_path):
    items = [row(tmp_path, 1, day="2026-10-18T09:00:00+08:00", description="布布吃南瓜", tags=["南瓜"]),
             row(tmp_path, 2, kind="video", day="2026-10-20T21:00:00+08:00", description="唱儿歌",
                 segments=[{"id": "s1", "start": 0, "end": 2, "text": "我们一起唱 pumpkin"}], provenance="video_analysis_mention"),
             row(tmp_path, 3, day="2026-10-19T23:30:00+08:00", description="画画"),
             row(tmp_path, 4, description="", tags=[])]  # unparsed: never shown
    bridge, processor = Bridge(items), Processor()
    return OnlineTimeline(bridge, processor, LearningStore(tmp_path / "state"), FAMILY, CHILD, "subject"), bridge, processor


def test_feed_is_newest_first_and_counts_only_parsed_items(timeline):
    service, _, _ = timeline
    feed = service.feed(scope())
    assert [i["id"][-1] for i in feed["items"]] == ["2", "3", "1"]
    assert (feed["total"], feed["photos"], feed["videos"]) == (3, 2, 1)
    assert "local_path" not in repr(feed) and "/" not in feed["items"][0]["id"]
    assert feed["items"][0]["label_provenance_text"] == "第二大脑视频解析提到布布"
    assert feed["items"][0]["media_url"].startswith("/learning/api/online-timeline/")


def test_filters_search_order_and_pages(timeline):
    service, _, _ = timeline
    assert [i["kind"] for i in service.feed(scope(), kind="video")["items"]] == ["video"]
    assert [i["id"][-1] for i in service.feed(scope(), query="南瓜")["items"]] == ["1"]
    assert [i["id"][-1] for i in service.feed(scope(), query="PUMPKIN")["items"]] == ["2"]
    # Days are Shanghai local dates, not UTC dates.
    assert [i["id"][-1] for i in service.feed(scope(), start="2026-10-19", end="2026-10-19")["items"]] == ["3"]
    assert [i["id"][-1] for i in service.feed(scope(), order="asc")["items"]] == ["1", "3", "2"]
    first = service.feed(scope(), page=1, limit=2)
    second = service.feed(scope(), page=2, limit=2)
    assert first["has_more"] and not second["has_more"]
    assert [i["id"] for i in first["items"] + second["items"]] == [i["id"] for i in service.feed(scope())["items"]]
    with pytest.raises(ValueError):
        service.feed(scope(), start="2026-10-20", end="2026-10-01")


def test_other_family_or_child_cannot_read_feed_or_media(timeline):
    service, _, _ = timeline
    with pytest.raises(Missing):
        service.feed(scope(family="family-b"))
    with pytest.raises(HTTPException):
        service.feed(scope(child="other"))
    with pytest.raises(Missing):
        service.media(scope(family="family-b"), "%024x" % 1)


def test_media_previews_are_cached_and_unknown_ids_are_missing(timeline):
    service, _, processor = timeline
    path, mime = service.media(scope(), "%024x" % 1, "thumb")
    assert mime == "image/jpeg" and path.read_bytes() == b"jpeg"
    service.media(scope(), "%024x" % 1, "thumb")
    assert len(processor.commands) == 1 and processor.commands[0][0] == "/usr/bin/sips"
    service.media(scope(), "%024x" % 2, "large")
    assert processor.commands[1][0] == "ffmpeg"
    original, mime = service.media(scope(), "%024x" % 2, "original")
    assert original.name == "02.mp4" and mime == "video/mp4"
    for bad in ("%024x" % 4, "%024x" % 99, "../etc"):
        with pytest.raises(Missing):
            service.media(scope(), bad)


def test_library_failure_is_503_not_an_empty_timeline(timeline):
    service, bridge, _ = timeline
    bridge.fail = True
    with pytest.raises(HTTPException) as error:
        service.feed(scope())
    assert error.value.status_code == 503


def test_family_wording_replaces_description_but_search_keeps_both(timeline):
    service, _, _ = timeline
    fid = "%024x" % 3
    with service.store.db() as db:
        from learning.store import digest
        db.execute("INSERT INTO timeline_captions VALUES(?,?,?,?,?,?)", (fid, "family-a", digest("画画"), "布布（袁晨希）在画画", 1, 0))
    service.cached = None
    row = next(i for i in service.feed(scope())["items"] if i["id"] == fid)
    assert row["description"] == "布布（袁晨希）在画画" and row["description_adjusted"] is True
    assert [i["id"] for i in service.feed(scope(), query="袁晨希")["items"]] == [fid]
    assert fid in [i["id"] for i in service.feed(scope(), query="画画")["items"]]


def test_nothing_before_birth_is_shown(tmp_path):
    items = [row(tmp_path, 1, day="2024-05-21T23:00:00+08:00", description="一二布布动画"),
             row(tmp_path, 2, day="2024-05-22T08:00:00+08:00", description="布布出生第一天"),
             row(tmp_path, 3, day="2023-12-01T10:00:00+08:00", description="别的孩子")]
    service = OnlineTimeline(Bridge(items), Processor(), LearningStore(tmp_path / "state"), FAMILY, CHILD, "s", born="2024-05-22")
    feed = service.feed(scope())
    assert [i["id"][-1] for i in feed["items"]] == ["2"] and feed["total"] == 1
    import pytest as _pytest
    with _pytest.raises(Missing):
        service.media(scope(), "%024x" % 1)


def test_chinese_phrase_tolerates_a_short_gap(tmp_path):
    items = [row(tmp_path, 1, description="布布（袁晨希）坐在桌边吃着西瓜"),
             row(tmp_path, 2, description="吃完饭后去买西瓜和葡萄回家"),
             row(tmp_path, 3, description="布布在画画")]
    service = OnlineTimeline(Bridge(items), Processor(), LearningStore(tmp_path / "state"), FAMILY, CHILD, "s")
    assert [i["id"][-1] for i in service.feed(scope(), query="吃西瓜")["items"]] == ["1"]
