"""2.29: clean narrator audio (no clipping) and more interactive content lessons."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning import speech
from learning.models import ContentActivity
from learning.processing import content_schema
from learning.service import LearningService
from learning.store import Conflict
from test_content_lessons import AUTUMN, DAY, F, C, activity, current_pack, drain, lesson, scope  # noqa: F401

FFMPEG = shutil.which("ffmpeg") and shutil.which("ffprobe")
needs_ffmpeg = pytest.mark.skipif(not FFMPEG, reason="ffmpeg/ffprobe not installed")


def loud_source(calls):
    """A deliberately clipping source at a non-44.1k native rate (24 kHz, peaks at 0 dBFS)."""
    def source(text, language, workdir):
        calls.append(text)
        raw = workdir / "fake.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=24000:duration=1.5",
                        "-af", "volume=30dB", "-c:a", "pcm_s16le", "-y", str(raw)], check=True)
        return raw
    return source


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels,bit_rate",
                          "-of", "json", str(path)], capture_output=True, text=True, check=True).stdout
    return json.loads(out)["streams"][0]


@needs_ffmpeg
def test_clipping_source_is_normalised_without_clipping(tmp_path):
    calls = []
    raw = loud_source([])("x", "en", tmp_path)
    assert speech.volume(raw)[0] >= -0.1  # the fake really clips
    target = tmp_path / "out.m4a"
    assert speech.synthesize("Where is the apple?", target, sources=[("fake", loud_source(calls))]) is True
    peak, mean = speech.volume(target)
    assert peak < -1.0 and mean > -40
    stream = probe(target)
    assert stream["codec_name"] == "aac" and stream["sample_rate"] == "44100" and stream["channels"] == 1
    assert 96_000 <= int(stream["bit_rate"]) <= 160_000
    # Fade-in: the first 10 ms are much quieter than the clip.
    head = tmp_path / "head.wav"
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(target), "-t", "0.01", "-y", str(head)], check=True)
    assert speech.volume(head)[0] < peak - 6


@needs_ffmpeg
def test_sources_fall_back_in_order_and_finished_clips_are_cached(tmp_path):
    calls = []
    order = []
    unavailable = lambda text, language, workdir: order.append("best") or None
    sources = [("best", unavailable), ("fake", loud_source(calls))]
    cache = tmp_path / "cache"
    assert speech.synthesize("Yes! Apple! 太棒啦！", tmp_path / "a.m4a", cache_dir=cache, sources=sources)
    assert order == ["best"] and calls == ["Yes! Apple! 太棒啦！"]
    assert speech.synthesize("Yes!  Apple! 太棒啦！", tmp_path / "b.m4a", cache_dir=cache, sources=sources)
    assert calls == ["Yes! Apple! 太棒啦！"]  # same normalised text: served from the cache, not re-rendered
    assert (tmp_path / "a.m4a").read_bytes() == (tmp_path / "b.m4a").read_bytes()
    assert speech.synthesize("Umbrella", tmp_path / "c.m4a", cache_dir=cache, sources=sources) and len(calls) == 2


def test_silent_or_failing_source_is_not_accepted(tmp_path):
    assert speech.synthesize("x", tmp_path / "a.m4a", sources=[("none", lambda *a: None)]) is False
    assert speech.synthesize("", tmp_path / "a.m4a", sources=[("never", lambda *a: pytest.fail("called"))]) is False


@needs_ffmpeg
def test_silence_is_refused(tmp_path):
    def silent(text, language, workdir):
        raw = workdir / "s.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", "1", "-y", str(raw)], check=True)
        return raw
    assert speech.synthesize("x", tmp_path / "a.m4a", sources=[("silent", silent)]) is False


def test_neural_source_needs_the_swift_toolchain(monkeypatch, tmp_path):
    monkeypatch.setenv("LEARNING_TTS_SWIFT", str(tmp_path / "no-swift"))
    assert speech.neural_helper() is None and speech.neural_source("Apple", "en", tmp_path) is None
    assert [name for name, _ in speech.SOURCES] == ["apple-best", "say"]


INTERACTIVE = copy.deepcopy(AUTUMN)
INTERACTIVE.update(greeting="Hi 宝贝！我是星星姐姐，今天我们一起玩秋天的游戏吧！", closing="今天你真棒！leaf, apple, umbrella，明天再玩！")
_extra = {
    "a1": dict(style="find_it", warmup_text="看！篮子里有什么？", praise_text="Yes! Apple! 太棒啦！", retry_hint_text="再看看，红红圆圆的是哪一个？"),
    "a2": dict(style="classic", praise_text="Yellow! 你真会找颜色！", retry_hint_text="像香蕉一样的颜色哦"),
    "a3": dict(style="classic", praise_text="放进去啦！"),
    "a4": dict(style="call_response", warmup_text="我说你说！", praise_text="说得真清楚！", retry_hint_text="跟我慢慢说一遍"),
    "a5": dict(style="sing_along", praise_text="唱得真好听！"),
}
for _a in INTERACTIVE["activities"]:
    _a.update(_extra.get(_a["id"], {}))


def test_interactive_lesson_has_spoken_lines_choice_audio_and_styles(lesson):
    store, _, processor, worker, course = lesson(reply=INTERACTIVE)
    drain(worker)
    payload = current_pack(store, course)["payload"]
    assert payload["greeting"]["text"].startswith("Hi 宝贝") and payload["greeting"]["audio_resource"].endswith(".m4a")
    assert payload["closing"]["audio_resource"]
    listen, color, sort, speak, music = payload["activities"]
    assert listen["style"] == "find_it" and speak["style"] == "call_response" and music["style"] == "sing_along"
    assert listen["warmup"]["text"] == "看！篮子里有什么？"
    assert processor.resource_path(F, listen["praise"]["audio_resource"]).read_bytes() == "tts:Yes! Apple! 太棒啦！".encode()
    assert listen["retry_hint"]["audio_resource"] and sort["retry_hint"] is None and music["retry_hint"] is None
    # Tapping an option speaks the word itself, not the emoji label.
    umbrella = listen["choices"][1]
    assert umbrella["label"] == "☂️ umbrella"
    assert processor.resource_path(F, umbrella["audio_resource"]).read_bytes() == b"tts:umbrella"
    assert umbrella["audio_hash"] == umbrella["audio_resource"][:-4]

    service = LearningService(store, processor)
    public = service.course(scope(), course["id"])["pack"]
    body = public["payload"]
    assert body["greeting"]["audio_url"].startswith("/learning/api/packs/") and set(body["greeting"]) == {"text", "audio_url"}
    first = body["activities"][0]
    assert first["style"] == "find_it" and first["praise"]["audio_url"] and first["retry_hint"]["text"].startswith("再看看")
    assert all(c["audio_url"] for c in first["choices"])
    for url in (first["choices"][0]["audio_url"], body["closing"]["audio_url"], first["warmup"]["audio_url"]):
        path, mime = service.resource(scope(), public["id"], url.rsplit("/", 1)[1])
        assert mime == "audio/mp4" and path.read_bytes().startswith(b"tts:")
    published = service.publish(scope(), public["id"], public["revision"],
                                [{**r, "verified": True} for r in public["confirmations"]], True)
    assert published["status"] == "published"


def test_tampered_lines_or_styles_are_not_publishable(lesson):
    store, _, processor, worker, course = lesson(reply=INTERACTIVE)
    drain(worker)
    service = LearningService(store, processor)
    raw = store.pack(F, current_pack(store, course)["id"])
    for change in (lambda p: p["activities"][0]["praise"].update(audio_resource="d" * 64 + ".m4a"),
                   lambda p: p["activities"][0].update(style="sing_along"),
                   lambda p: p.update(greeting={"text": "hi", "script": "x"}),
                   lambda p: p["activities"][0]["choices"][0].update(audio_hash="e" * 64)):
        tampered = copy.deepcopy(raw["payload"])
        change(tampered)
        tampered["generation_nonce"] = "tampered"
        other = store.create_pack(F, C, DAY, tampered, raw["source_ids"], course_id=course["id"])
        with pytest.raises(Conflict):
            service.publish(scope(), other["id"], other["revision"],
                            [{**r, "verified": True} for r in service.pack(scope(), other["id"])["confirmations"]], True)


def test_older_packs_without_new_fields_still_render_and_publish(lesson):
    store, _, processor, worker, course = lesson()  # AUTUMN has no 2.29 fields
    drain(worker)
    raw = store.pack(F, current_pack(store, course)["id"])
    legacy = copy.deepcopy(raw["payload"])
    for key in ("greeting", "closing"):
        legacy.pop(key, None)
    for a in legacy["activities"]:
        for key in ("style", "warmup", "praise", "retry_hint"):
            a.pop(key, None)
        for c in a["choices"]:
            c.pop("audio_resource", None); c.pop("audio_hash", None)
    legacy["generation_nonce"] = "legacy"
    old = store.create_pack(F, C, DAY, legacy, raw["source_ids"], course_id=course["id"])
    service = LearningService(store, processor)
    public = service.pack(scope(), old["id"])
    assert public["payload"]["greeting"] is None and public["payload"]["closing"] is None
    first = public["payload"]["activities"][0]
    assert first["style"] is None and first["praise"] is None and first["choices"][0]["audio_url"] is None
    assert service.publish(scope(), old["id"], old["revision"],
                           [{**r, "verified": True} for r in public["confirmations"]], True)["status"] == "published"


@pytest.mark.parametrize("fields, error", [
    (dict(style="sing_along"), "玩法"),
    (dict(style="call_response"), "玩法"),
    (dict(style="find_it", choices=[{"id": "apple", "label": "apple"}, {"id": "leaf", "label": "leaf"}]), "画面"),
    (dict(retry_hint_text="是 apple 哦"), "答案"),
])
def test_interactivity_validation_is_strict(fields, error):
    with pytest.raises(ValueError, match=error):
        ContentActivity.model_validate(activity(**fields))


def test_music_has_no_retry_hint_and_counting_fits_speak():
    music = activity(kind="music", choices=[], correct_choice=None, answer_text=None, retry_hint_text="再唱一遍")
    with pytest.raises(ValueError, match="再试"):
        ContentActivity.model_validate(music)
    speak = activity(kind="speak", choices=[], correct_choice=None, answer_text="three leaves", style="counting",
                     praise_text="三片叶子！真棒！", retry_hint_text="我们一起数")
    assert ContentActivity.model_validate(speak).style == "counting"


def test_schema_asks_the_model_for_every_interactive_field():
    schema = content_schema()
    assert {"greeting", "closing"} <= set(schema["required"])
    assert {"style", "warmup_text", "praise_text", "retry_hint_text"} <= set(schema["$defs"]["ContentActivity"]["required"])
