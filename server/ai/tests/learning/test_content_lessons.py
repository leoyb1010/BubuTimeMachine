"""2.28: lessons are built from the uploaded video's content and the parent's note, with narrator audio."""
import copy
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning import speech
from learning.auth import FamilyScope
from learning.brain_bridge import BrainBlocked, BrainUnavailable
from learning.processing import CONTENT_PIPELINE_VERSION, MediaProcessor, ProcessingUnavailable
from learning.service import LearningService
from learning.store import Conflict, LearningStore
from learning.worker import LearningWorker

F, C, DAY = "fam", "child", "2026-10-22"
VIDEO = b"the autumn nursery rhyme video"


def scope(review=True):
    return FamilyScope("parent", F, [{"id": C, "name": "布布"}], review)


class Bridge:
    def __init__(self, *replies):
        self.replies, self.calls = list(replies), []
        self.root = Path("/unused")

    def complete_json(self, system, content, schema, *, effort="high"):
        self.calls.append((effort, content))
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
        if isinstance(reply, Exception):
            raise reply
        return copy.deepcopy(reply)


def spoken(text, target):
    target.write_bytes(("tts:" + text).encode())
    return True


def analysis(processor, frames=8, **overrides):
    resources = [processor._save(F, _tmp_bytes(processor, b"frame %d" % i), ".jpg")[0] for i in range(frames)]
    payload = {
        "material_kind": "song", "duration": 217.17, "pipeline_version": "bubu-learning-evidence-1",
        "description": "这是一段以秋天（Autumn）为主题的幼儿英语儿歌动画视频。画面展示了秋季落叶、多云天气、雨伞、保暖帽、"
                       "树林动物（如松鼠、狐狸、刺猬、猫头鹰）以及装有苹果的篮子等卡通插图。",
        "ocr": "Autumn; a big umbrella and my hat; it's autumn again; Leaves are falling; One more",
        "tags": ["儿歌", "秋天主题"],
        "frames": [{"time": round(30.94 * i, 2), "resource": r} for i, r in enumerate(resources)],
        "segments": [{"id": "seg-0001", "start": 9.72, "end": 12.48, "text": "yellow, red and brown."},
                     {"id": "seg-0002", "start": 12.72, "end": 15.78, "text": "Leaves are falling on the ground."},
                     {"id": "seg-0003", "start": 15.9, "end": 22.02, "text": "Apples in the basket, pumpkins in the box."}],
        "warnings": [],
    }
    payload.update(overrides)
    return payload


def _tmp_bytes(processor, content):
    path = processor.store.root / "tmp-frame"
    path.write_bytes(content)
    return path


def activity(**fields):
    base = {"id": "a1", "kind": "listen_choice", "title": "找苹果", "concept": "apple", "instruction": "听一听，苹果在哪里？",
            "prompt_text": "Where is the apple? 苹果在哪里？", "answer_text": "Yes! Apple! 是苹果！",
            "grounding": "Apples in the basket",
            "choices": [{"id": "apple", "label": "apple", "image_frame": 3}, {"id": "umbrella", "label": "umbrella", "emoji": "☂️"},
                        {"id": "leaf", "label": "leaf", "emoji": "🍂"}],
            "correct_choice": "apple"}
    base.update(fields)
    return base


AUTUMN = {"title": "秋天的儿歌", "intro": "今天学了秋天的英文儿歌，陪布布找一找苹果和雨伞。", "summary": "重点词 leaf、apple、umbrella。",
          "key_words": ["leaf", "apple", "umbrella", "Apple"], "warnings": [],
          "activities": [
              activity(),
              activity(id="a2", kind="color_choice", title="落叶的颜色", concept="yellow", instruction="树叶是什么颜色？",
                       prompt_text="Leaves are yellow. Find yellow!", answer_text="Yellow! 黄色！", grounding="yellow, red and brown",
                       choices=[{"id": "y", "label": "yellow"}, {"id": "b", "label": "blue"}], correct_choice="y"),
              activity(id="a3", kind="sort", title="放进篮子", concept="basket", instruction="把苹果放进篮子",
                       prompt_text="Put the apple in the basket!", answer_text="In the basket! 放进篮子啦！",
                       grounding="Apples in the basket, pumpkins in the box",
                       choices=[{"id": "basket", "label": "basket", "emoji": "🧺"}, {"id": "box", "label": "box", "emoji": "📦"}],
                       correct_choice="basket"),
              activity(id="a4", kind="speak", title="说雨伞", concept="umbrella", instruction="跟着说 umbrella",
                       prompt_text="Can you say umbrella?", answer_text="Umbrella", grounding="a big umbrella and my hat",
                       choices=[], correct_choice=None),
              activity(id="a5", kind="music", title="一起唱", concept="leaves", instruction="一起唱落叶歌",
                       prompt_text="Leaves are falling on the ground.", answer_text=None, grounding="Leaves are falling",
                       segment_ref="m1/seg-0002", choices=[], correct_choice=None),
              # Dropped: not from this lesson / picture that doesn't exist / colour feedback mismatched.
              activity(id="bad1", grounding="Elephants dance on the moon"),
              activity(id="bad2", choices=[{"id": "apple", "label": "apple", "image_frame": 99}, {"id": "x", "label": "hat"}]),
              activity(id="bad3", kind="color_choice", answer_text="Blue!", grounding="yellow, red and brown",
                       choices=[{"id": "y", "label": "yellow"}, {"id": "b", "label": "blue"}], correct_choice="y"),
          ]}


@pytest.fixture
def lesson(tmp_path, monkeypatch):
    store = LearningStore(tmp_path / "state")

    def build(reply=AUTUMN, note="", payload=None, tts=spoken, files=(VIDEO, VIDEO)):
        bridge = Bridge(*(reply if isinstance(reply, list) else [reply]))
        processor = MediaProcessor(store, bridge, tts=tts)
        # Cutting the real song line: ffmpeg writes its output file.
        monkeypatch.setattr(processor, "_run", lambda args, timeout=120: Path(args[-1]).write_bytes(b"song " + args[4].encode()) or "")
        course = store.create_course(F, C, DAY, "10.22", "teaching", "en-US", "parent", len(files), note)
        for index, content in enumerate(files):
            store.add_source(F, C, DAY, "course:%s:%d" % (course["id"], index), "upload-%d.mp4" % index, content, "video/mp4",
                             kind="teaching", course_id=course["id"])
        aid = store.sources(F, C, DAY, course_id=course["id"])[0]["asset_id"]
        store.set_analysis(F, aid, analysis(processor) if payload is None else payload)
        with store.db() as db:
            db.execute("UPDATE jobs SET state='done' WHERE kind='analyze'")
        worker = LearningWorker(store, bridge, processor, family=F, child=C)
        return store, bridge, processor, worker, store.course(F, course["id"])
    return build


def drain(worker):
    while worker.process_one():
        pass


def current_pack(store, course):
    return next(p for p in store.packs(F, C, DAY, course_id=course["id"]) if p["status"] in {"draft", "published", "no_lesson"})


def test_song_video_without_teacher_questions_becomes_a_playful_draft_lesson(lesson):
    store, bridge, processor, worker, course = lesson()
    drain(worker)
    pack = current_pack(store, course)
    payload = pack["payload"]
    assert pack["status"] == "draft" and payload["pipeline_version"] == CONTENT_PIPELINE_VERSION
    assert [a["id"] for a in payload["activities"]] == ["a1", "a2", "a3", "a4", "a5"]
    assert payload["key_words"] == ["leaf", "apple", "umbrella"] and payload["intro"].startswith("今天学了")
    # Duplicate uploads share one asset: the model reads one material; the pack keeps both source ids.
    brief = json.loads(bridge.calls[0][1][0]["text"])
    assert len(brief["materials"]) == 1 and brief["child_age"].startswith("2岁5个月")
    assert len(pack["source_ids"]) == 2 and payload["duplicate_files"] == 1
    assert bridge.calls[0][0] == "medium"
    listen, color, sort, speak, music = payload["activities"]
    frames = [f["resource"] for f in store.analysis(F, store.sources(F, C, DAY)[0]["asset_id"])["payload"]["frames"]]
    assert listen["prompt"]["role"] == "cue" and listen["prompt"]["origin"] == "tts"
    assert processor.resource_path(F, listen["prompt"]["audio_resource"]).read_bytes() == b"tts:Where is the apple? \xe8\x8b\xb9\xe6\x9e\x9c\xe5\x9c\xa8\xe5\x93\xaa\xe9\x87\x8c\xef\xbc\x9f"
    assert listen["answer"]["role"] == "answer" and listen["answer"]["audio_resource"].endswith(".m4a")
    assert listen["choices"][0]["image_resource"] == frames[3] and listen["choices"][1]["label"] == "☂️ umbrella"
    assert color["choices"][0]["colors"] == ["#F5CF39"]
    assert speak["prompt"]["role"] == "question" and speak["answer"]["text"] == "Umbrella"
    assert music["prompt"]["role"] == "context" and music["prompt"]["origin"] == "source"
    assert music["prompt"]["segment_id"] == "seg-0002" and music["prompt"]["start"] == 12.72
    assert music["answer"] is None


def test_content_lesson_publishes_and_tampering_is_refused(lesson):
    store, _, processor, worker, course = lesson()
    drain(worker)
    service = LearningService(store, processor)
    detail = service.course(scope(), course["id"])
    assert detail["state"] == "draft" and detail["activity_count"] == 5
    public = detail["pack"]
    assert public["payload"]["key_words"] == ["leaf", "apple", "umbrella"]
    assert public["payload"]["activities"][0]["prompt"]["audio_url"].startswith("/learning/api/packs/")
    assert public["payload"]["activities"][0]["choices"][0]["image_url"]
    path, mime = service.resource(scope(), public["id"], public["payload"]["activities"][4]["prompt"]["audio_url"].rsplit("/", 1)[1])
    assert mime == "audio/mp4" and path.read_bytes().startswith(b"song ")
    receipts = [{**r, "verified": True} for r in public["confirmations"]]
    published = service.publish(scope(), public["id"], public["revision"], receipts, True)
    assert published["status"] == "published"
    # A pack whose picture is not one of this course's sampled frames cannot be published.
    raw = store.pack(F, public["id"])
    tampered = copy.deepcopy(raw["payload"])
    tampered["activities"][0]["choices"][0]["image_resource"] = "c" * 64 + ".jpg"
    tampered["generation_nonce"] = "tampered"
    other = store.create_pack(F, C, DAY, tampered, raw["source_ids"], course_id=course["id"])
    with pytest.raises(Conflict):
        service.publish(scope(), other["id"], other["revision"],
                        [{**r, "verified": True} for r in service.pack(scope(), other["id"])["confirmations"]], True)


def test_invalid_reply_gets_one_repair_and_then_fails_visibly(lesson):
    nothing = {"title": "x", "activities": [activity(grounding="not in this lesson at all")]}
    store, bridge, _, worker, course = lesson(reply=nothing)
    assert worker.process_one()
    assert len(bridge.calls) == 2 and "grounding" in bridge.calls[1][1][-1]["text"]
    assert [p for p in store.packs(F, C, DAY) if p["status"] != "superseded"] == []
    assert store.compose_job_state(F, C, DAY, course["id"]) == "queued"  # retried with backoff, then 'failed'


def test_medium_timeout_falls_back_to_low_and_safety_block_drops_pictures(lesson, tmp_path):
    store, bridge, _, worker, course = lesson(reply=[BrainUnavailable("busy"), AUTUMN])
    drain(worker)
    assert [effort for effort, _ in bridge.calls] == ["medium", "low"]
    assert current_pack(store, course)["status"] == "draft"


def test_blocked_request_retries_gentler_without_images_and_ignores_frame_numbers(lesson):
    store, bridge, _, worker, course = lesson(reply=[BrainBlocked("filter"), BrainBlocked("filter"), AUTUMN])
    drain(worker)
    efforts = [effort for effort, _ in bridge.calls]
    assert efforts == ["medium", "low", "medium"]
    assert any(p["type"] == "image_url" for p in bridge.calls[0][1])
    assert not any(p["type"] == "image_url" for p in bridge.calls[2][1])
    payload = current_pack(store, course)["payload"]
    # Frame indexes are meaningless when the model saw no pictures: those activities are dropped.
    assert "a1" not in [a["id"] for a in payload["activities"]] and payload["activities"]


def test_every_variant_blocked_raises_for_retry(tmp_path):
    store = LearningStore(tmp_path / "state")
    processor = MediaProcessor(store, Bridge(BrainBlocked("filter")))
    with pytest.raises(BrainBlocked):
        processor._ask_content([[{"type": "text", "text": "a"}], [{"type": "text", "text": "b"}]])
    assert len(processor.bridge.calls) == 4


def test_no_usable_content_and_no_note_is_no_lesson_without_a_model_call(lesson):
    empty = {"material_kind": "uncertain", "duration": 10, "description": "", "ocr": "", "segments": [], "frames": []}
    store, bridge, _, worker, course = lesson(payload=empty, files=(VIDEO,))
    drain(worker)
    assert bridge.calls == [] and current_pack(store, course)["status"] == "no_lesson"


def test_parent_note_alone_is_enough_and_grounds_activities(lesson):
    empty = {"material_kind": "uncertain", "duration": 10, "description": "", "ocr": "", "segments": [], "frames": []}
    from_note = {"title": "x", "activities": [activity(grounding="重点词 leaf, apple, umbrella", choices=[
        {"id": "apple", "label": "apple", "emoji": "🍎"}, {"id": "leaf", "label": "leaf", "emoji": "🍂"}])]}
    store, bridge, _, worker, course = lesson(reply=from_note, payload=empty, files=(VIDEO,),
                                               note="今天学了秋天的英文儿歌，重点词 leaf, apple, umbrella")
    drain(worker)
    brief = json.loads(bridge.calls[0][1][0]["text"])
    assert brief["parent_note"].startswith("今天学了秋天") and brief["frames"] == []
    pack = current_pack(store, course)
    assert pack["status"] == "draft" and pack["payload"]["note"].startswith("今天学了")
    assert pack["payload"]["activities"][0]["choices"][0]["label"] == "🍎 apple"


def test_without_a_voice_prompts_are_text_only_and_still_publishable(lesson):
    store, _, processor, worker, course = lesson(tts=lambda text, target: False)
    drain(worker)
    payload = current_pack(store, course)["payload"]
    listen = payload["activities"][0]
    assert "audio_resource" not in listen["prompt"] and listen["prompt"]["text"].startswith("Where is the apple")
    assert any("朗读声音" in w for w in payload["warnings"])
    service = LearningService(store, processor)
    public = service.course(scope(), course["id"])["pack"]
    assert public["payload"]["activities"][0]["prompt"]["audio_url"] is None
    assert service.publish(scope(), public["id"], public["revision"],
                           [{**r, "verified": True} for r in public["confirmations"]], True)["status"] == "published"


def test_patch_note_saves_requeues_and_supersedes_only_this_course(lesson):
    store, bridge, processor, worker, course = lesson()
    drain(worker)
    first = current_pack(store, course)
    service = LearningService(store, processor)
    with pytest.raises(Exception):
        service.update_course(scope(review=False), course["id"], "x")
    with pytest.raises(ValueError):
        service.update_course(scope(), course["id"], "字" * 2001)
    detail = service.update_course(scope(), course["id"], "  今天学了秋天的英文儿歌，\n 重点词 leaf, apple  ")
    assert detail["note"] == "今天学了秋天的英文儿歌，\n重点词 leaf, apple"
    assert detail["state"] == "processing"
    assert store.compose_job_state(F, C, DAY, course["id"]) == "queued"
    assert service.courses(scope(), C, DAY, DAY)["items"][0]["note"].startswith("今天学了")
    drain(worker)
    second = current_pack(store, course)
    assert second["id"] != first["id"] and second["payload"]["note"].endswith("leaf, apple")
    assert store.pack(F, first["id"])["status"] == "superseded"
    assert json.loads(bridge.calls[-1][1][0]["text"])["parent_note"].endswith("leaf, apple")


def test_course_created_with_note_returns_it(tmp_path):
    service = LearningService(LearningStore(tmp_path / "state"), processor=None)
    path = tmp_path / "v.mp4"; path.write_bytes(b"v")
    course = service.create_course(scope(), C, DAY, "秋天", "song", "en-US", [("v.mp4", path, "video/mp4")], 0, "重点词 leaf")
    assert course["note"] == "重点词 leaf"
    with pytest.raises(ValueError):
        service.create_course(scope(), C, DAY, "秋天", "song", "en-US", [("v.mp4", path, "video/mp4")], 0, "字" * 2001)


def test_voice_detection_parses_localized_say_listing(monkeypatch):
    listing = {"Tingting": "zh_CN", "Meijia": "zh_TW", "Samantha": "en_US", "Karen": "en_AU"}
    assert speech.pick_voice("zh", listing) == "Tingting" and speech.pick_voice("en", listing) == "Samantha"
    assert speech.pick_voice("zh", {"Meijia": "zh_TW"}) == "Meijia" and speech.pick_voice("en", {"Albert": "en_US"}) is None
    assert speech.language_of("Where is the apple? 苹果在哪里？") == "zh" and speech.language_of("Umbrella") == "en"

    class Result:
        stdout = ("Tingting (中文（中国大陆）) zh_CN    # 你好！我叫婷婷。\n"
                  "Samantha            en_US    # Hello! My name is Samantha.\n"
                  "Eddy (英语（美国）)       en_US    # Hello! My name is Eddy.\n")
    monkeypatch.setattr(speech.subprocess, "run", lambda *a, **k: Result())
    speech.installed_voices.cache_clear()
    try:
        assert speech.installed_voices() == {"Tingting": "zh_CN", "Samantha": "en_US", "Eddy": "en_US"}
    finally:
        speech.installed_voices.cache_clear()


def test_synthesize_without_voice_is_text_only(monkeypatch, tmp_path):
    monkeypatch.setattr(speech, "pick_voice", lambda language: None)
    assert speech.synthesize("Apple", tmp_path / "a.m4a") is False
