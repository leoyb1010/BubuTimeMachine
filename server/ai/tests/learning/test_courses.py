"""Parent-uploaded courses: one upload is one lesson; separate from the timeline."""
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning.auth import FamilyScope
from learning.service import LearningService
from learning.store import LearningStore, Missing

FAMILY, CHILD = "family-a", "child-a"


def scope(review=True, family=FAMILY):
    return FamilyScope("parent", family, [{"id": CHILD, "name": "布布"}], review)


@pytest.fixture
def service(tmp_path):
    store = LearningStore(tmp_path / "state")
    return LearningService(store, processor=None)


def files(tmp_path, *items):
    result = []
    for index, (name, mime, content) in enumerate(items):
        path = tmp_path / ("%d-%s" % (index, name))
        path.write_bytes(content)
        result.append((name, path, mime))
    return result


def test_upload_creates_one_course_and_queues_analysis(service, tmp_path):
    course = service.create_course(scope(), CHILD, "2026-10-21", "  Fruit   words ", "teaching", "en-US",
                                   files(tmp_path, ("words.mp4", "video/mp4", b"video"), ("card.jpg", "image/jpeg", b"card")))
    assert course["title"] == "Fruit words" and course["state"] == "processing"
    assert [s["kind"] for s in course["sources"]] == ["teaching", "teaching"]
    assert course["source_count"] == 2 and course["pack"] is None
    jobs = service.store.jobs(FAMILY)
    assert sorted(j["kind"] for j in jobs) == ["analyze", "analyze"]
    listed = service.courses(scope(), CHILD, "2026-10-01", "2026-10-31")["items"]
    assert [c["id"] for c in listed] == [course["id"]]
    assert service.days(scope(), CHILD, "2026-10-01", "2026-10-31")["days"][0]["course_count"] == 1


def test_upload_requires_reviewer_teacher_audio_and_supported_files(service, tmp_path):
    from fastapi import HTTPException
    with pytest.raises(HTTPException):
        service.create_course(scope(review=False), CHILD, "2026-10-21", "A", "teaching", "en-US",
                              files(tmp_path, ("a.mp4", "video/mp4", b"v")))
    with pytest.raises(ValueError):
        service.create_course(scope(), CHILD, "2026-10-21", "A", "teaching", "en-US",
                              files(tmp_path, ("a.jpg", "image/jpeg", b"photo only")))
    with pytest.raises(ValueError):
        service.create_course(scope(), CHILD, "2026-10-21", "A", "teaching", "en-US",
                              files(tmp_path, ("a.mp4", "video/mp4", b"v"), ("x.pdf", "application/pdf", b"pdf")))
    with pytest.raises(ValueError):
        service.create_course(scope(), CHILD, "2026-10-21", "A", "lecture", "en-US",
                              files(tmp_path, ("a.mp4", "video/mp4", b"v")))
    assert service.courses(scope(), CHILD, "2026-10-01", "2026-10-31")["items"] == []


def test_family_member_sees_only_published_courses_and_no_sources(service, tmp_path):
    course = service.create_course(scope(), CHILD, "2026-10-21", "Colors", "song", "en-US",
                                   files(tmp_path, ("song.mp4", "video/mp4", b"song")))
    viewer = service.course(scope(review=False), course["id"])
    assert viewer["state"] == "waiting" and viewer["sources"] == [] and viewer["pack"] is None
    with pytest.raises(Missing):
        service.course(scope(family="family-b"), course["id"])


def test_delete_course_hides_it_and_its_sources(service, tmp_path):
    course = service.create_course(scope(), CHILD, "2026-10-21", "Colors", "practice", "zh-CN",
                                   files(tmp_path, ("a.m4a", "audio/mp4", b"audio")))
    service.delete_course(scope(), course["id"])
    assert service.courses(scope(), CHILD, "2026-10-01", "2026-10-31")["items"] == []
    assert service.store.sources(FAMILY, CHILD) == []
    with pytest.raises(Missing):
        service.course(scope(), course["id"])


def test_announced_files_keep_course_uploading_until_all_arrive(service, tmp_path):
    first = files(tmp_path, ("words.mp4", "video/mp4", b"video"))
    course = service.create_course(scope(), CHILD, "2026-10-21", "Fruit", "teaching", "en-US", first, 3)
    assert course["state"] == "uploading" and course["expected_files"] == 3
    assert not service.store.course_sealed(FAMILY, course["id"])
    service.add_course_file(scope(), course["id"], *files(tmp_path, ("song.m4a", "audio/mp4", b"song"))[0])
    detail = service.add_course_file(scope(), course["id"], *files(tmp_path, ("card.jpg", "image/jpeg", b"card"))[0])
    assert detail["state"] == "processing" and detail["source_count"] == 3
    assert service.store.course_sealed(FAMILY, course["id"])
    from learning.store import Conflict
    with pytest.raises(Conflict):
        service.add_course_file(scope(), course["id"], *files(tmp_path, ("extra.jpg", "image/jpeg", b"extra"))[0])
    with pytest.raises(Exception):
        service.add_course_file(scope(review=False), course["id"], *files(tmp_path, ("x.jpg", "image/jpeg", b"x"))[0])


def test_reupload_after_failed_parse_retries_and_compose_failure_is_visible(service, tmp_path):
    store = service.store
    course = service.create_course(scope(), CHILD, "2026-10-21", "A", "teaching", "en-US", files(tmp_path, ("a.mp4", "video/mp4", b"same")))
    with store.db() as db:
        db.execute("UPDATE jobs SET state='failed' WHERE kind='analyze'")
    aid = store.sources(FAMILY, CHILD)[0]["asset_id"]
    store.set_analysis(FAMILY, aid, {}, state="failed", error="x")
    assert service.course(scope(), course["id"])["state"] == "failed"
    service.delete_course(scope(), course["id"])
    again = service.create_course(scope(), CHILD, "2026-10-21", "A", "teaching", "en-US", files(tmp_path, ("a.mp4", "video/mp4", b"same")))
    assert [j["state"] for j in store.jobs(FAMILY) if j["kind"] == "analyze"] == ["queued"]
    # Analysis ready but the lesson generation failed three times: shown as failed, retry re-queues it.
    store.set_analysis(FAMILY, aid, {"segments": []})
    with store.db() as db:
        db.execute("UPDATE jobs SET state='failed' WHERE kind='compose'")
    assert service.course(scope(), again["id"])["state"] == "failed"
    service.retry_course(scope(), again["id"])
    assert store.compose_job_state(FAMILY, CHILD, "2026-10-21", again["id"]) == "queued"
    assert service.course(scope(), again["id"])["state"] == "processing"


def test_parent_never_sees_internal_source_ids_in_model_notes(service, tmp_path):
    course = service.create_course(scope(), CHILD, "2026-10-21", "A", "teaching", "en-US",
                                   files(tmp_path, ("words.mp4", "video/mp4", b"v"), ("card.jpg", "image/jpeg", b"c")))
    sid = course["sources"][1]["id"]
    pack = {"id": "p", "family_id": FAMILY, "source_ids": [s["id"] for s in course["sources"]]}
    text = service._readable(pack, "材料 %s 缺少切片数据；另有 %s" % (sid, "ab" * 16))
    assert sid not in text and "「card.jpg」" in text and "一份素材" in text
