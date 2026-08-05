"""声音年轮：从真实原声生成可回查、可重试、可归档的音频章。"""
from __future__ import annotations

import hashlib
import json
import os
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from threading import Lock
from typing import Any, Callable, Optional

from artifact_workflow import ArtifactUnavailable, ArtifactWorkflow
from memory_query import (
    MemoryEvidence, MemoryQuery, PocketBaseMemoryStore, SoundRingMaterial,
    fact_record_belongs_to_family, sound_source_revision,
)


UTC = timezone.utc
MIN_ORIGINAL_SECONDS = 180.0
MAX_ORIGINAL_SECONDS = 400.0
MAX_CLIPS = 24
MAX_SINGLE_CLIP_SECONDS = 120.0
_artifact_locks_guard = Lock()
_artifact_locks: dict[str, Lock] = {}


@contextmanager
def _artifact_edit_lock(artifact_id: str):
    """单进程 launchd 服务内把草稿编辑与 draft→rendering 转换串行化。"""
    with _artifact_locks_guard:
        lock = _artifact_locks.setdefault(artifact_id, Lock())
    with lock:
        yield


class SoundRingUnavailable(RuntimeError):
    pass


class SoundSourceChanged(SoundRingUnavailable):
    """草稿引用的事实已经变化，旧草稿不得继续生成。"""


def validate_sound_sources(
    store: Any, family_id: str, clips: list[dict[str, Any]]
) -> None:
    """重新读取每条原声，防止删除、换家庭或替换文件后仍发布旧事实。"""
    for clip in clips:
        record_id = str(clip.get("recordId") or "")
        expected_local_id = str(clip.get("sourceId") or "").removeprefix("voicememos:")
        expected_file = str(clip.get("fileName") or "")
        expected_revision = str(clip.get("sourceUpdatedAt") or "")
        if not record_id or not expected_local_id or not expected_file or not expected_revision:
            raise SoundSourceChanged("原声素材版本不完整，请重新整理一圈声音。")
        try:
            record = store.get_record("voicememos", record_id)
        except Exception:
            raise SoundSourceChanged("有一段原声已不可用，请重新整理一圈声音。") from None
        current_file = _single_file_name(record.get("file"))
        current_revision = sound_source_revision(record)
        if (
            not fact_record_belongs_to_family(record, family_id)
            or _truthy(record.get("isDeleted"))
            or str(record.get("localId") or "") != expected_local_id
            or current_file != expected_file
            or current_revision != expected_revision
        ):
            raise SoundSourceChanged("原声素材在确认后发生了变化，请重新整理一圈声音。")


class SoundRingService:
    def __init__(
        self,
        store: PocketBaseMemoryStore,
        submitter: Optional[Callable[[str, str, str], None]] = None,
    ) -> None:
        self.store = store
        self.query = MemoryQuery(store)
        self.workflow = ArtifactWorkflow(store, "sound_ring")
        if submitter is None:
            from sound_render import submit_artifact_render
            submitter = submit_artifact_render
        self.submitter = submitter

    def latest(self, family_id: str) -> Optional[dict[str, Any]]:
        artifact = self.workflow.latest(family_id)
        if artifact is not None:
            artifact = self._recover_stale(family_id, artifact)
        return public_artifact(artifact) if artifact else None

    def history(self, family_id: str, limit: int = 24) -> list[dict[str, Any]]:
        return [
            public_artifact(self._recover_stale(family_id, item))
            for item in self.workflow.history(family_id, limit)
        ]

    def get(self, family_id: str, artifact_id: str) -> dict[str, Any]:
        try:
            current = self.workflow.owned(family_id, artifact_id)
            return public_artifact(self._recover_stale(family_id, current))
        except ArtifactUnavailable as exc:
            raise SoundRingUnavailable(str(exc)) from exc

    def draft(self, family_id: str, child_name: str) -> dict[str, Any]:
        selected = select_materials(self.query.sound_ring_materials(family_id))
        if not selected:
            raise SoundRingUnavailable("还没有可用于声音年轮的原声。")
        signature = [
            {
                "source": item.voice.source_id,
                "file": item.file_name,
                "updated": item.source_updated_at,
                "duration": round(duration, 3),
            }
            for item, duration in selected
        ]
        digest = hashlib.sha256(
            json.dumps(signature, sort_keys=True, ensure_ascii=False).encode("utf-8")
        ).hexdigest()[:20]
        artifact_key = "sound_ring:%s:%s" % (family_id, digest)
        existing = self.store.find_artifact(artifact_key)
        if existing is not None:
            return public_artifact(existing)

        ages = sorted({item.age_years for item, _ in selected})
        clip_payload = []
        refs: list[MemoryEvidence] = []
        for item, duration in sorted(selected, key=lambda pair: pair[0].voice.happened_at):
            refs.append(item.voice)
            if item.related_entry is not None:
                refs.append(item.related_entry)
            clip_payload.append({
                "sourceId": item.voice.source_id,
                "recordId": item.voice.record_id,
                "fileName": item.file_name,
                "sourceUpdatedAt": item.source_updated_at,
                "durationSeconds": round(duration, 3),
                "originalDurationSeconds": round(item.duration_seconds, 3),
                "ageYears": item.age_years,
                "kind": item.kind,
                "title": item.voice.title,
                "recordedAt": item.voice.happened_at,
                "transcript": item.voice.excerpt if item.voice.excerpt != "原声未转写" else "",
                "photoSourceId": (
                    item.related_entry.source_id if item.related_entry is not None else ""
                ),
            })
        unique_refs = _unique_evidence(refs)
        original_seconds = sum(duration for _, duration in selected)
        title = "%s的声音年轮 · %s" % (child_name, _age_span(ages))
        payload = {
            "version": 1,
            "childName": child_name,
            "clips": clip_payload,
            "timeline": [],
            "originalDurationSeconds": round(original_seconds, 3),
            "renderedDurationSeconds": 0,
            "attempts": 0,
            "error": "",
            "narrator": "Apple 系统中性旁白",
            "voiceCloning": False,
        }
        record = self.workflow.create_idempotent({
            "artifactKey": artifact_key,
            "kind": "sound_ring",
            "familyId": family_id,
            "status": "draft",
            "title": title,
            "summary": "%d 段真实原声 · %s" % (len(selected), _duration_text(original_seconds)),
            "sourceRefs": [item.public() for item in unique_refs],
            "payload": payload,
            "generatedAt": datetime.now(UTC).isoformat(),
            "modelVersion": "sound-ring-v1-original-first",
        })
        return public_artifact(record)

    def render(self, family_id: str, artifact_id: str) -> dict[str, Any]:
        with _artifact_edit_lock(artifact_id):
            return self._render_locked(family_id, artifact_id)

    def _render_locked(self, family_id: str, artifact_id: str) -> dict[str, Any]:
        try:
            current = self.workflow.owned(family_id, artifact_id)
        except ArtifactUnavailable as exc:
            raise SoundRingUnavailable(str(exc)) from exc
        current = self._recover_stale(family_id, current)
        status = str(current.get("status") or "")
        if status in {"ready", "archived", "rendering"}:
            return public_artifact(current)
        if status not in {"draft", "failed"}:
            raise SoundRingUnavailable("这份声音年轮当前不能制作。")
        payload = _payload(current)
        clips = payload.get("clips") if isinstance(payload.get("clips"), list) else []
        try:
            validate_sound_sources(
                self.store, family_id, [item for item in clips if isinstance(item, dict)]
            )
        except SoundSourceChanged as exc:
            payload["error"] = str(exc)
            self.workflow.update(
                family_id, artifact_id, {"status": "failed", "payload": payload}
            )
            raise
        payload["attempts"] = int(payload.get("attempts") or 0) + 1
        payload["error"] = ""
        payload["timeline"] = []
        payload["renderStartedAt"] = datetime.now(UTC).isoformat()
        generation = uuid.uuid4().hex
        payload["renderGeneration"] = generation
        updated = self.workflow.update(
            family_id, artifact_id, {"status": "rendering", "payload": payload}
        )
        try:
            self.submitter(artifact_id, family_id, generation)
        except Exception:
            payload["error"] = "制作任务暂时没有启动，原声仍然安全，可以稍后重试。"
            self.workflow.update(
                family_id, artifact_id, {"status": "failed", "payload": payload}
            )
            raise SoundRingUnavailable(payload["error"]) from None
        return public_artifact(updated)

    def remove_clip(
        self, family_id: str, artifact_id: str, source_id: str
    ) -> dict[str, Any]:
        """从草稿清单移除一段，绝不修改 voicememos 事实记录。"""
        with _artifact_edit_lock(artifact_id):
            return self._remove_clip_locked(family_id, artifact_id, source_id)

    def _remove_clip_locked(
        self, family_id: str, artifact_id: str, source_id: str
    ) -> dict[str, Any]:
        try:
            current = self.workflow.owned(family_id, artifact_id)
        except ArtifactUnavailable as exc:
            raise SoundRingUnavailable(str(exc)) from exc
        if str(current.get("status") or "") != "draft":
            raise SoundRingUnavailable("只有等待确认的素材清单可以调整。")
        payload = _payload(current)
        raw_clips = payload.get("clips")
        clips = [item for item in raw_clips if isinstance(item, dict)] \
            if isinstance(raw_clips, list) else []
        kept = [item for item in clips if str(item.get("sourceId") or "") != source_id]
        if len(kept) == len(clips):
            raise SoundRingUnavailable("这段原声已经不在当前清单里。")
        remaining_seconds = sum(float(item.get("durationSeconds") or 0) for item in kept)
        if remaining_seconds < MIN_ORIGINAL_SECONDS:
            raise SoundRingUnavailable(
                "移除后真实原声不足 3 分钟；可以先继续录几段，再重新整理。"
            )
        payload["clips"] = kept
        payload["originalDurationSeconds"] = round(remaining_seconds, 3)
        payload["timeline"] = []
        payload["renderedDurationSeconds"] = 0
        payload["error"] = ""

        kept_source_ids = {
            str(item.get("sourceId") or "") for item in kept
        } | {
            str(item.get("photoSourceId") or "") for item in kept
        }
        refs = current.get("sourceRefs")
        source_refs = [
            item for item in refs
            if isinstance(item, dict)
            and str(item.get("source_id") or item.get("sourceId") or "") in kept_source_ids
        ] if isinstance(refs, list) else []
        summary = "%d 段真实原声 · %s" % (len(kept), _duration_text(remaining_seconds))
        updated = self.workflow.update(
            family_id,
            artifact_id,
            {"status": "draft", "summary": summary,
             "sourceRefs": source_refs, "payload": payload},
        )
        return public_artifact(updated)

    def archive(self, family_id: str, artifact_id: str) -> dict[str, Any]:
        try:
            record = self.workflow.archive(
                family_id,
                artifact_id,
                allowed=lambda item: str(item.get("status") or "") in {"ready", "archived"},
            )
        except ArtifactUnavailable as exc:
            raise SoundRingUnavailable(str(exc)) from exc
        return public_artifact(record)

    def _recover_stale(
        self, family_id: str, record: dict[str, Any]
    ) -> dict[str, Any]:
        if str(record.get("status") or "") != "rendering":
            return record
        payload = _payload(record)
        started = _parse_datetime(payload.get("renderStartedAt"))
        timeout = max(300, int(os.environ.get("SOUND_RING_STALE_SECONDS", "1200")))
        if started is not None and (datetime.now(UTC) - started).total_seconds() < timeout:
            return record
        payload["error"] = "上次制作因服务重启或超时中断，原声仍然安全，可以继续制作。"
        return self.workflow.update(
            family_id, str(record.get("id") or ""),
            {"status": "failed", "payload": payload},
        )


def select_materials(
    materials: list[SoundRingMaterial],
) -> list[tuple[SoundRingMaterial, float]]:
    """确定性、跨年龄、布布原声优先地挑 3—8 分钟素材。"""
    usable = [item for item in materials if item.duration_seconds >= 1.5]
    if not usable:
        return []

    by_age: dict[int, list[SoundRingMaterial]] = {}
    for item in sorted(usable, key=lambda value: value.voice.happened_at):
        by_age.setdefault(item.age_years, []).append(item)

    priority: list[SoundRingMaterial] = []
    # 先让每一圈至少有一段布布原声；没有时才用家人原声占位。
    for age in sorted(by_age):
        group = by_age[age]
        first = next((item for item in group if item.kind == "childVoice"), group[0])
        priority.append(first)
    priority.extend(
        item for item in sorted(usable, key=lambda value: value.voice.happened_at)
        if item.kind == "childVoice" and item not in priority
    )
    priority.extend(
        item for item in sorted(usable, key=lambda value: value.voice.happened_at)
        if item.kind != "childVoice" and item not in priority
    )

    selected: list[tuple[SoundRingMaterial, float]] = []
    total = 0.0
    for item in priority:
        if len(selected) >= MAX_CLIPS or total >= MAX_ORIGINAL_SECONDS:
            break
        available = min(item.duration_seconds, MAX_SINGLE_CLIP_SECONDS)
        duration = min(available, MAX_ORIGINAL_SECONDS - total)
        if duration < 1.5:
            continue
        selected.append((item, duration))
        total += duration
    if total < MIN_ORIGINAL_SECONDS:
        raise SoundRingUnavailable(
            "声音年轮至少需要约 3 分钟真实原声；当前可用原声还不够，可以先继续录几段。"
        )
    return selected


def public_artifact(record: dict[str, Any]) -> dict[str, Any]:
    payload = _payload(record)
    clips = payload.get("clips") if isinstance(payload.get("clips"), list) else []
    timeline = payload.get("timeline") if isinstance(payload.get("timeline"), list) else []
    timing = {
        str(item.get("sourceId") or ""): item
        for item in timeline if isinstance(item, dict)
    }
    public_clips = []
    for raw in clips:
        if not isinstance(raw, dict):
            continue
        source_id = str(raw.get("sourceId") or "")
        times = timing.get(source_id, {})
        public_clips.append({
            "source_id": source_id,
            "photo_source_id": str(raw.get("photoSourceId") or ""),
            "age_years": max(0, int(raw.get("ageYears") or 0)),
            "kind": str(raw.get("kind") or "childVoice"),
            "title": str(raw.get("title") or "一段原声"),
            "recorded_at": str(raw.get("recordedAt") or ""),
            "transcript": str(raw.get("transcript") or ""),
            "duration_seconds": float(raw.get("durationSeconds") or 0),
            "start_seconds": float(times.get("startSeconds") or 0),
            "end_seconds": float(times.get("endSeconds") or 0),
        })
    refs = record.get("sourceRefs") if isinstance(record.get("sourceRefs"), list) else []
    status = str(record.get("status") or "")
    return {
        "id": str(record.get("id") or ""),
        "artifact_key": str(record.get("artifactKey") or ""),
        "status": status,
        "title": str(record.get("title") or ""),
        "summary": str(record.get("summary") or ""),
        "generated_at": str(record.get("generatedAt") or record.get("created") or ""),
        "model_version": str(record.get("modelVersion") or ""),
        "original_duration_seconds": float(payload.get("originalDurationSeconds") or 0),
        "rendered_duration_seconds": float(payload.get("renderedDurationSeconds") or 0),
        "attempts": int(payload.get("attempts") or 0),
        "error": str(payload.get("error") or ""),
        "narrator": str(payload.get("narrator") or ""),
        "voice_cloning": bool(payload.get("voiceCloning") or False),
        "has_audio": status in {"ready", "archived"} and bool(record.get("file")),
        "clips": public_clips,
        "source_refs": refs,
        "content_hash": _content_hash(payload, refs),
    }


def _payload(record: dict[str, Any]) -> dict[str, Any]:
    value = record.get("payload")
    return dict(value) if isinstance(value, dict) else {}


def _single_file_name(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list) and len(value) == 1 and isinstance(value[0], str):
        return value[0]
    return ""


def _truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes"}


def _unique_evidence(items: list[MemoryEvidence]) -> list[MemoryEvidence]:
    result = []
    seen = set()
    for item in items:
        if item.source_id in seen:
            continue
        seen.add(item.source_id)
        result.append(item)
    return result


def _age_span(ages: list[int]) -> str:
    if not ages:
        return "这一段时光"
    if len(ages) == 1:
        return "%d岁" % ages[0]
    return "%d—%d岁" % (ages[0], ages[-1])


def _duration_text(seconds: float) -> str:
    total = max(0, int(round(seconds)))
    minutes, remainder = divmod(total, 60)
    return "%d分%02d秒" % (minutes, remainder)


def _content_hash(payload: dict[str, Any], refs: list[Any]) -> str:
    # 私有文件名不是客户端内容；仍纳入 hash，重传源文件会产生新作品版本。
    body = json.dumps({"payload": payload, "refs": refs}, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(body.encode("utf-8")).hexdigest()[:20]


def _parse_datetime(value: Any) -> Optional[datetime]:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=UTC)
