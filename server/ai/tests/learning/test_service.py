"""Real learning state and immutable resources; no model/server/network calls."""
import copy
import hashlib
from pathlib import Path
import sys

from fastapi import HTTPException
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning.auth import FamilyScope
from learning.models import Draft, ground_draft
from learning.processing import ProcessingUnavailable
from learning.service import LearningService
from learning.store import Conflict, LearningStore, Missing, digest


FAMILY, CHILD = "family-a", "child-a"


def scope(*, review=True, family=FAMILY, child=CHILD):
    return FamilyScope("user-a", family, [{"id": child, "name": "布布"}], review)


class Processor:
    def __init__(self, store):
        self.store = store

    def save(self, family, content, extension):
        name = hashlib.sha256(content).hexdigest() + extension
        root = self.store.root / "derived" / hashlib.sha256(family.encode()).hexdigest()[:24]
        root.mkdir(parents=True, exist_ok=True)
        (root / name).write_bytes(content)
        return name

    def resource_path(self, family, name):
        root = self.store.root / "derived" / hashlib.sha256(family.encode()).hexdigest()[:24]
        path = root / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != name.split(".")[0]:
            raise ProcessingUnavailable("test resource changed")
        return path


class PocketBase:
    def __init__(self):
        self.media = {}
        self.entries = {}

    def get_record(self, collection, rid):
        rows = self.media if collection == "media" else self.entries
        if rid not in rows:
            raise Missing("record missing")
        return copy.deepcopy(rows[rid])

    def first_record(self, collection, *, filter_value, sort):
        # Deliberately return by local ID without enforcing family, so service
        # tests prove its explicit checks rather than the fake's filtering.
        import re
        local = re.search(r"localId='([^']*)'", filter_value).group(1)
        return next((copy.deepcopy(row) for row in self.entries.values() if row["localId"] == local), None)

    def list_records(self, collection, **kwargs):
        return copy.deepcopy(list((self.media if collection == "media" else self.entries).values()))


@pytest.fixture
def app(tmp_path):
    store = LearningStore(tmp_path)
    processor = Processor(store)
    pb = PocketBase()
    return store, processor, pb, LearningService(store, processor, pocketbase=pb)


def lesson(app, *, day="2026-10-20", child=CHILD, family=FAMILY):
    store, processor, _, service = app
    course = store.create_course(family, child, day, "Corn and pumpkin", "teaching")
    source = store.add_source(family, child, day, "course:" + course["id"] + ":0", "lesson.mp4", b"teacher original " + day.encode(),
                              "video/mp4", kind="teaching", course_id=course["id"])
    segments = [{"id": "intro", "start": 0, "end": 1, "text": "Hello everyone."},
                {"id": "question", "start": 2, "end": 3, "text": "What is it?"},
                {"id": "corn", "start": 5, "end": 6, "text": "Corn."},
                {"id": "pumpkin", "start": 8, "end": 9, "text": "Pumpkin."},
                {"id": "song", "start": 12, "end": 15, "text": "Pumpkin song."}]
    analysis = store.set_analysis(family, source["asset_id"], {
        "description": "玉米和南瓜的教学", "ocr": "corn pumpkin", "tags": ["英语"], "duration": 20,
        "segments": segments, "material_kind": "teaching", "warnings": [], "provider": "second-brain-gemini",
    })
    def clip(segment, role):
        return {"source_id": source["id"], "segment_id": segment, "role": role}
    draft = Draft.model_validate({"title": "今天的课", "material_kind": "teaching", "activities": [
        {"id": "listen", "kind": "listen_choice", "title": "找玉米", "concept": "corn", "instruction": "听老师的原声",
         "prompt": clip("corn", "cue"), "answer": clip("corn", "answer"),
         "choices": [{"id": "corn", "label": "corn", "evidence": clip("corn", "cue")},
                     {"id": "pumpkin", "label": "pumpkin", "evidence": clip("pumpkin", "cue")}], "correct_choice": "corn"},
        {"id": "speak", "kind": "speak", "title": "说说看", "concept": "corn", "instruction": "试试回应老师",
         "prompt": clip("question", "question"), "answer": clip("corn", "answer")},
        {"id": "music", "kind": "music", "title": "唱儿歌", "concept": "song", "instruction": "一起唱",
         "prompt": clip("song", "context")},
    ]})
    payload = ground_draft(draft, {source["id"]: {**source, "analysis": analysis["payload"]}})
    for activity in payload["activities"]:
        for key in ("prompt", "answer"):
            value = activity.get(key)
            if value:
                name = processor.save(family, value["segment_id"].encode(), ".m4a")
                value.update(audio_resource=name, audio_hash=name[:-4])
                if key == "prompt":
                    value["image_resource"] = processor.save(family, b"frame " + value["segment_id"].encode(), ".jpg")
        for choice in activity["choices"]:
            choice["image_resource"] = processor.save(family, choice["id"].encode(), ".jpg")
    pack = store.create_pack(family, child, day, payload, [source["id"]], course_id=course["id"])
    return source, pack


def publish(service, pack):
    public = service.pack(scope(), pack["id"])
    return service.publish(scope(), pack["id"], pack["revision"],
                           [{**value, "verified": True} for value in public["confirmations"]], True)


def test_drafts_sources_and_resources_are_reviewer_only(app):
    source, pack = lesson(app)
    service = app[3]
    reader = scope(review=False)
    assert service.packs(reader, CHILD, "2026-10-20")["items"] == []
    assert service.sources(reader, CHILD, "2026-10-20")["items"] == []
    with pytest.raises(Missing):
        service.pack(reader, pack["id"])
    with pytest.raises(HTTPException) as original_denied:
        service.source_file(reader, source["id"])
    assert original_denied.value.status_code == 403
    resource = pack["payload"]["activities"][0]["prompt"]["audio_resource"]
    with pytest.raises(Missing):
        service.resource(reader, pack["id"], resource)
    assert service.source_file(scope(), source["id"])[1] == "video/mp4"


def test_pack_public_urls_are_scoped_and_teacher_clip_is_not_instruction(app):
    _, pack = lesson(app)
    public = app[3].pack(scope(), pack["id"])
    activity = public["payload"]["activities"][0]
    assert activity["prompt"]["text"] == "Corn."
    assert activity["prompt"]["start"] == 5
    assert activity["prompt"]["audio_url"].startswith("/learning/api/packs/" + pack["id"] + "/resources/")
    assert "audio_resource" not in repr(public) and "local_path" not in repr(public)
    assert public["confirmations"][0]["digest"] == digest(pack["payload"]["activities"][0])


def test_publication_confirms_dates_and_is_family_child_scoped(app):
    source, pack = lesson(app)
    service = app[3]
    with pytest.raises(HTTPException) as denied:
        service.publish(scope(review=False), pack["id"], pack["revision"], [], True)
    assert denied.value.status_code == 403
    with pytest.raises(Missing):
        service.pack(scope(family="other-family"), pack["id"])
    with pytest.raises(HTTPException):
        service.pack(scope(child="other-child"), pack["id"])
    assert publish(service, pack)["status"] == "published"
    assert app[0].source(FAMILY, source["id"])["date_confirmed"]
    assert service.pack(scope(review=False), pack["id"])["status"] == "published"
    assert service.sources(scope(review=False), CHILD, "2026-10-20") == {"items": []}
    with pytest.raises(HTTPException) as denied:
        service.source_file(scope(review=False), source["id"])
    assert denied.value.status_code == 403
    assert len(service.days(scope(review=False), CHILD, "2026-10-01", "2026-10-31")["days"]) == 1


def test_resource_must_belong_to_this_pack_and_stale_source_revokes_it(app):
    source, pack = lesson(app)
    store, processor, _, service = app
    publish(service, pack)
    unrelated = processor.save(FAMILY, b"unrelated", ".m4a")
    with pytest.raises(Missing):
        service.resource(scope(review=False), pack["id"], unrelated)
    with pytest.raises(Missing):
        service.resource(scope(), pack["id"], "../other.m4a")
    clip = pack["payload"]["activities"][0]["prompt"]["audio_resource"]
    assert service.resource(scope(review=False), pack["id"], clip)[0].is_file()
    store.set_analysis(FAMILY, source["asset_id"], {"description": "changed", "segments": []})
    with pytest.raises((Missing, Conflict)):
        service.resource(scope(review=False), pack["id"], clip)


def test_missing_or_changed_clip_bytes_cannot_be_published(app):
    _, pack = lesson(app)
    resource = pack["payload"]["activities"][0]["prompt"]["audio_resource"]
    app[1].resource_path(FAMILY, resource).write_bytes(b"tampered introduction")
    with pytest.raises(Conflict):
        publish(app[3], pack)
    assert app[0].pack(FAMILY, pack["id"])["status"] == "draft"


def test_exclude_creates_new_draft_and_old_confirmation_cannot_publish_it(app):
    _, pack = lesson(app)
    service = app[3]
    old = service.pack(scope(), pack["id"])
    publish(service, pack)
    new = service.exclude(scope(), pack["id"], pack["revision"], "music")
    assert new["status"] == "draft" and new["revision"] > pack["revision"]
    assert len(new["payload"]["activities"]) == 2
    with pytest.raises(Conflict):
        service.publish(scope(), new["id"], new["revision"], [{**r, "verified": True} for r in old["confirmations"]], True)


def test_exclude_stale_page_cannot_overwrite_a_concurrently_created_pack(app, monkeypatch):
    _, pack = lesson(app)
    store, _, _, service = app
    read = service._pack
    def concurrent_revision(*args, **kwargs):
        old = read(*args, **kwargs)
        store.create_pack(FAMILY, CHILD, pack["school_date"], {**pack["payload"], "title": "并发生成的新课程"}, pack["source_ids"], course_id=pack["course_id"])
        return old
    monkeypatch.setattr(service, "_pack", concurrent_revision)
    with pytest.raises(Conflict):
        service.exclude(scope(), pack["id"], pack["revision"], "music")
    assert store.packs(FAMILY, CHILD)[0]["payload"]["title"] == "并发生成的新课程"


def test_nonempty_invalid_image_reference_cannot_be_silently_published(app):
    _, pack = lesson(app)
    payload = copy.deepcopy(pack["payload"])
    payload["activities"][1]["prompt"]["image_resource"] = "../private.jpg"
    changed = app[0].create_pack(FAMILY, CHILD, pack["school_date"], payload, pack["source_ids"], course_id=pack["course_id"])
    with pytest.raises(Conflict):
        publish(app[3], changed)


def test_segment_correction_uses_revision_cas_and_keeps_course_date(app):
    source, pack = lesson(app)
    store, _, _, service = app
    analysis = store.analysis(FAMILY, source["asset_id"])
    publish(service, pack)
    changed = copy.deepcopy(analysis["payload"]["segments"])
    changed[2]["text"] = "Corn!"
    with pytest.raises(ValueError):
        service.update_segments(scope(), source["id"], analysis["revision"], changed, "2026-10-19", True)
    revised = service.update_segments(scope(), source["id"], analysis["revision"], changed, "2026-10-20", True)
    assert revised["school_date"] == "2026-10-20" and revised["date_confirmed"] is True
    assert store.pack(FAMILY, pack["id"])["status"] == "revoked"
    with pytest.raises(Conflict):
        service.update_segments(scope(), revised["id"], analysis["revision"], changed, "2026-10-20", True)


@pytest.mark.parametrize("activity,kind,choice,event", [
    ("listen", "listen_choice", "pumpkin", "choice"),
    ("speak", "speak", None, "speaking_attempt"),
    ("music", "music", None, "participation"),
])
def test_attempt_kind_is_adapted_and_result_is_server_computed(app, activity, kind, choice, event):
    _, pack = lesson(app)
    service = app[3]
    publish(service, pack)
    body = {"id": "attempt-1", "child_id": CHILD, "pack_id": pack["id"], "activity_id": activity, "kind": kind}
    if choice:
        body["choice"] = choice
    result = service.save_attempt(scope(review=False), body)
    assert result["event_kind"] == event
    assert result["correct"] is (False if choice else None)
    assert service.save_attempt(scope(review=False), body) == result
    assert len(service.attempts(scope(review=False), CHILD)["items"]) == 1
    with pytest.raises(ValueError):
        service.save_attempt(scope(review=False), {**body, "kind": "sort"})


def test_reviews_include_only_published_and_keep_activity_type_separate(app):
    _, published = lesson(app, day="2026-10-19")
    service = app[3]
    publish(service, published)
    lesson(app, day="2026-10-20")
    service.save_attempt(scope(review=False), {"id": "wrong", "child_id": CHILD, "pack_id": published["id"],
        "activity_id": "listen", "kind": "listen_choice", "choice": "pumpkin"})
    review = service.reviews(scope(review=False), CHILD, "week", "2026-10-21")
    assert review["window_start"] == "2026-10-15" and review["window_end"] == "2026-10-21"
    assert {r["pack_id"] for r in review["items"]} == {published["id"]}
    assert {r["activity"]["kind"] for r in review["items"]} >= {"listen_choice", "speak"}
    assert review["items"][0]["activity_id"] == "listen"


def test_reviews_use_fsrs_due_dates_and_cap_five(app):
    from datetime import datetime as _dt
    from zoneinfo import ZoneInfo as _Zone
    store, _, _, service = app
    _, published = lesson(app, day="2026-10-19")
    publish(service, published)
    service.save_attempt(scope(review=False), {"id": "wrong", "child_id": CHILD, "pack_id": published["id"],
        "activity_id": "listen", "kind": "listen_choice", "choice": "pumpkin"})
    at = _dt(2026, 10, 19, 20, 0, tzinfo=_Zone("Asia/Shanghai")).timestamp()
    with store.db() as db:
        db.execute("UPDATE attempts SET created_at=?", (at,))
    same_day = service.reviews(scope(review=False), CHILD, "week", "2026-10-19")
    assert "listen" not in [r["activity_id"] for r in same_day["items"]]  # just practised: not due yet
    next_day = service.reviews(scope(review=False), CHILD, "week", "2026-10-20")
    assert next_day["items"][0]["activity_id"] == "listen"
    assert next_day["items"][0]["reason"] == "上次需要一点提示，再轻松玩一次。"
    assert len(next_day["items"]) <= 5
    # Long after the week window only due cards remain; never-played old ones drop out.
    later = service.reviews(scope(review=False), CHILD, "week", "2026-12-01")
    assert [r["activity_id"] for r in later["items"]] == ["listen"]


def fact(app, *, mid="media1", sha=None, family=FAMILY):
    pb = app[2]
    sha = sha or hashlib.sha256(b"pb original").hexdigest()
    pb.entries["entry" + mid] = {"id": "entry" + mid, "localId": "local-entry-" + mid, "familyId": family,
        "happenedAt": "2026-10-20 02:30:00.000Z", "isDeleted": False, "isArchived": False}
    pb.media[mid] = {"id": mid, "localId": "local-media-" + mid, "entryLocalId": "local-entry-" + mid,
        "familyId": family, "contentHash": sha, "file": "photo.jpg", "mediaType": "photo", "isDeleted": False}
    return pb.media[mid]


def test_media_request_is_scoped_and_never_runs_processing_in_http(app):
    media = fact(app)
    store, _, _, service = app
    first = service.media_analysis(scope(), media["id"], False)
    assert first["state"] == "queued" and first["description"] == "" and first["segments"] == []
    key = "media-analysis-request:" + digest([FAMILY, media["id"], media["contentHash"]])
    request = store.get_cursor(key)
    assert request["family_id"] == FAMILY and request["state"] == "queued"
    with pytest.raises(Missing):
        service.media_analysis(scope(family="other-family"), media["id"], False)


def test_media_cache_rechecks_facts_and_hash_before_returning_text(app):
    media = fact(app)
    store, _, pb, service = app
    source = store.add_source(FAMILY, "__media_analysis__", "2026-10-20", "pb-media", "photo.jpg", b"pb original", "image/jpeg")
    store.set_analysis(FAMILY, source["asset_id"], {"description": "Gemini识别出的画面", "ocr": "文字", "tags": ["画画"],
                                               "segments": [], "provider": "second-brain-gemini"})
    cache_key = "media-analysis:" + digest([FAMILY, media["id"]])
    store.set_cursor(cache_key, {"family_id": FAMILY, "media_id": media["id"], "asset_id": source["asset_id"],
                                "content_hash": media["contentHash"], "state": "ready"})
    assert service.media_analysis(scope(), media["id"], False)["description"] == "Gemini识别出的画面"
    pb.media[media["id"]]["contentHash"] = "f" * 64
    changed = service.media_analysis(scope(), media["id"], False)
    assert changed["state"] == "queued" and changed["description"] == ""
    pb.media[media["id"]]["isDeleted"] = True
    with pytest.raises(Missing):
        service.media_analysis(scope(), media["id"], False)


def test_timeline_search_excludes_auto_candidates_and_stale_or_foreign_facts(app):
    _, _, pb, service = app
    rows = {}
    for n in range(1, 5):
        media = fact(app, mid=f"media{n}", sha=str(n) * 64, family="other-family" if n == 4 else FAMILY)
        rows[media["contentHash"]] = {"status": "synced", "media_id": media["id"], "content_hash": media["contentHash"],
            "provenance": "gemini_two_pass" if n == 2 else "manual", "analysis": {"description": "在幼儿园画画", "ocr": "", "tags": ["画画"]}}
    pb.media["media3"]["isDeleted"] = True
    class Registry:
        def registry(self):
            return {"family_id": FAMILY, "child_id": CHILD, "items": rows}
    service.brain_sync = Registry()
    result = service.timeline_search(scope(), "画画", "photo", "2026-10-20", "2026-10-20", "desc", 50)
    assert [r["media_id"] for r in result["items"]] == ["media1"]
    assert result["items"][0]["identity_status"] == "confirmed"
    assert result["total"] == 1 and result["has_more"] is False


def test_context_reports_pending_jobs_without_paths(app):
    store, _, _, service = app
    store.add_source(FAMILY, CHILD, "2026-10-20", "x", "a.jpg", b"pending", "image/jpeg")
    context = service.context(scope(review=False))
    assert context["source_status"]["pending"] == 1
    assert [k["id"] for k in context["course_kinds"]] == ["teaching", "practice", "song"]
