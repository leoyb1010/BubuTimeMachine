"""声音年轮 ffmpeg 音频姊妹管线。

真实原声始终是主体；Apple 系统中性 TTS 只念年龄衔接语，不克隆任何家人声音。
渲染状态与文件都写回受保护的 ``derived_artifacts``，临时文件无论成败都会清理。
"""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Lock
from typing import Any, Optional

from artifact_workflow import ArtifactWorkflow
from memory_query import PocketBaseMemoryStore
from sound_ring import validate_sound_sources


logger = logging.getLogger("bubu.sound_render")
_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="bubu-sound")
_inflight: set[str] = set()
_inflight_lock = Lock()


def _resolve_binary(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    for prefix in ("/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"):
        candidate = os.path.join(prefix, name)
        if os.path.exists(candidate):
            return candidate
    return name


_FFMPEG = _resolve_binary("ffmpeg")
_FFPROBE = _resolve_binary("ffprobe")
_SAY = _resolve_binary("say")


def available() -> bool:
    return shutil.which(_FFMPEG) is not None and shutil.which(_FFPROBE) is not None


def submit_artifact_render(artifact_id: str, family_id: str, generation: str) -> None:
    with _inflight_lock:
        if artifact_id in _inflight:
            return
        _inflight.add(artifact_id)
    try:
        _executor.submit(_render_background, artifact_id, family_id, generation)
    except Exception:
        with _inflight_lock:
            _inflight.discard(artifact_id)
        raise


def _render_background(artifact_id: str, family_id: str, generation: str) -> None:
    try:
        with PocketBaseMemoryStore() as store:
            artifact = ArtifactWorkflow(store, "sound_ring").owned(family_id, artifact_id)
            render_artifact_now(store, artifact, expected_generation=generation)
    except Exception:
        logger.exception("sound ring render crashed id=%s", artifact_id)
        try:
            with PocketBaseMemoryStore() as store:
                current = ArtifactWorkflow(store, "sound_ring").owned(family_id, artifact_id)
                payload = _payload(current)
                if (
                    str(current.get("status") or "") != "rendering"
                    or str(payload.get("renderGeneration") or "") != generation
                ):
                    return
                payload["error"] = "制作没有完成，原声仍然安全，可以稍后重试。"
                store.update_artifact(artifact_id, {"status": "failed", "payload": payload})
        except Exception:
            logger.exception("sound ring failure state update failed id=%s", artifact_id)
    finally:
        with _inflight_lock:
            _inflight.discard(artifact_id)


def render_artifact_now(
    store: Any, artifact: dict[str, Any], expected_generation: Optional[str] = None
) -> dict[str, Any]:
    if not available():
        raise RuntimeError("服务器未安装 ffmpeg / ffprobe")
    artifact_id = str(artifact.get("id") or "")
    if not artifact_id.isalnum():
        raise ValueError("声音年轮 id 非法")
    payload = _payload(artifact)
    if expected_generation is not None:
        _validate_generation(artifact, expected_generation)
    raw_clips = payload.get("clips") if isinstance(payload.get("clips"), list) else []
    clips = [item for item in raw_clips if isinstance(item, dict)]
    if not clips:
        raise RuntimeError("声音年轮没有可渲染片段")
    family_id = str(artifact.get("familyId") or "")
    if not family_id:
        raise RuntimeError("声音年轮缺少家庭归属")
    validate_sound_sources(store, family_id, clips)

    workdir = Path(tempfile.mkdtemp(prefix="bubu_sound_%s_" % artifact_id))
    try:
        sequence: list[Path] = []
        timeline: list[dict[str, Any]] = []
        cursor = 0.0
        current_age: Optional[int] = None
        silence = workdir / "silence.wav"
        _make_silence(silence, 0.45)

        for index, clip in enumerate(clips):
            validate_sound_sources(store, family_id, [clip])
            record_id = str(clip.get("recordId") or "")
            file_name = str(clip.get("fileName") or "")
            source_id = str(clip.get("sourceId") or "")
            age = max(0, int(clip.get("ageYears") or 0))
            target_duration = min(120.0, max(1.5, float(clip.get("durationSeconds") or 0)))
            if age != current_age:
                bridge = workdir / ("bridge_%02d.wav" % index)
                _make_bridge(bridge, "接下来，是布布%d岁的声音。" % age)
                sequence.append(bridge)
                cursor += _duration(bridge)
                sequence.append(silence)
                cursor += 0.45
                current_age = age

            source = workdir / ("source_%02d%s" % (index, Path(file_name).suffix or ".audio"))
            store.download_record_file("voicememos", record_id, file_name, str(source))
            normalized = workdir / ("clip_%02d.wav" % index)
            _normalize(source, normalized, target_duration)
            actual_duration = _duration(normalized)
            start = cursor
            sequence.append(normalized)
            cursor += actual_duration
            timeline.append({
                "sourceId": source_id,
                "startSeconds": round(start, 3),
                "endSeconds": round(cursor, 3),
            })
            sequence.append(silence)
            cursor += 0.45

        concat_file = workdir / "sequence.txt"
        concat_file.write_text(
            "".join("file '%s'\n" % path.as_posix().replace("'", "'\\''") for path in sequence),
            encoding="utf-8",
        )
        output = workdir / ("bubu_sound_ring_%s.m4a" % artifact_id)
        _run([
            _FFMPEG, "-y", "-f", "concat", "-safe", "0", "-i", str(concat_file),
            "-vn", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
            "-metadata", "title=%s" % str(artifact.get("title") or "布布的声音年轮"),
            str(output),
        ], "concat")
        rendered_duration = _duration(output)
        if rendered_duration < 178 or rendered_duration > 490:
            raise RuntimeError("成片时长超出 3—8 分钟安全范围")

        # ffmpeg 可能运行数分钟；发布前必须再核对整批事实，变化即丢弃临时成片。
        validate_sound_sources(store, family_id, clips)
        if expected_generation is not None:
            _validate_generation(store.get_artifact(artifact_id), expected_generation)
        store.upload_artifact_file(artifact_id, str(output), output.name)
        payload["timeline"] = timeline
        payload["renderedDurationSeconds"] = round(rendered_duration, 3)
        payload["error"] = ""
        return store.update_artifact(
            artifact_id, {"status": "ready", "payload": payload}
        )
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def _normalize(source: Path, destination: Path, seconds: float) -> None:
    fade_out = max(0.0, seconds - 0.10)
    filters = (
        "highpass=f=70,lowpass=f=13000,"
        "loudnorm=I=-18:TP=-2:LRA=11,"
        "afade=t=in:st=0:d=0.06,"
        "afade=t=out:st=%.3f:d=0.10" % fade_out
    )
    _run([
        _FFMPEG, "-y", "-i", str(source), "-t", "%.3f" % seconds,
        "-vn", "-af", filters, "-ar", "44100", "-ac", "1",
        "-c:a", "pcm_s16le", str(destination),
    ], "normalize")


def _make_bridge(destination: Path, text: str) -> None:
    configured = os.environ.get("SOUND_RING_NARRATOR_VOICE", "Tingting").strip()
    aiff = destination.with_suffix(".aiff")
    say_cmd = [_SAY]
    if configured:
        say_cmd += ["-v", configured]
    say_cmd += ["-r", "165", "-o", str(aiff), text]
    try:
        _run(say_cmd, "narrator", timeout=30)
        _run([
            _FFMPEG, "-y", "-i", str(aiff), "-af", "loudnorm=I=-20:TP=-3:LRA=7",
            "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", str(destination),
        ], "narrator convert")
    except RuntimeError:
        # 没有可用中文系统声音时，不让旁白阻塞原声作品；退化成极短安静间隔。
        logger.warning("system narrator unavailable; using silence")
        _make_silence(destination, 0.8)
    finally:
        try:
            aiff.unlink()
        except OSError:
            pass


def _make_silence(destination: Path, seconds: float) -> None:
    _run([
        _FFMPEG, "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
        "-t", "%.3f" % seconds, "-c:a", "pcm_s16le", str(destination),
    ], "silence")


def _duration(path: Path) -> float:
    result = subprocess.run(
        [_FFPROBE, "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True,
        timeout=30,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("无法读取音频时长")
    try:
        return float(result.stdout.decode("utf-8", "ignore").strip())
    except ValueError as exc:
        raise RuntimeError("音频时长格式异常") from exc


def _run(command: list[str], label: str, timeout: int = 600) -> None:
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError("%s 执行失败" % label) from exc
    if result.returncode != 0:
        tail = result.stderr.decode("utf-8", "ignore")[-600:]
        logger.error("%s failed rc=%d: %s", label, result.returncode, tail)
        raise RuntimeError("%s 执行失败" % label)


def _payload(record: dict[str, Any]) -> dict[str, Any]:
    value = record.get("payload")
    return dict(value) if isinstance(value, dict) else {}


def _validate_generation(record: dict[str, Any], expected: str) -> None:
    payload = _payload(record)
    if (
        str(record.get("status") or "") != "rendering"
        or str(payload.get("renderGeneration") or "") != expected
    ):
        raise RuntimeError("声音年轮制作任务已被更新，本次旧任务停止发布")
