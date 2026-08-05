from __future__ import annotations

import sys
from pathlib import Path

import httpx


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from memory_query import (  # noqa: E402
    MemoryEvidence, MemoryQuery, PocketBaseMemoryStore, SoundRingMaterial,
    sound_source_revision,
)
from sound_ring import (  # noqa: E402
    SoundRingService,
    SoundSourceChanged,
    SoundRingUnavailable,
    public_artifact,
    select_materials,
)
from main import SoundRingArtifactReq, SoundRingResp, app  # noqa: E402


def material(
    suffix: str,
    *,
    age: int,
    duration: float,
    kind: str = "childVoice",
    photo: bool = False,
) -> SoundRingMaterial:
    voice = MemoryEvidence(
        source_id="voicememos:%s" % suffix,
        collection="voicememos",
        record_id="record%s" % suffix,
        local_id=suffix,
        happened_at="202%d-05-22T08:00:00Z" % (4 + age),
        title="布布的声音" if kind == "childVoice" else "家人对她说",
        excerpt="真实原声%s" % suffix,
        kind="voice",
    )
    related = None
    if photo:
        related = MemoryEvidence(
            source_id="entries:photo%s" % suffix,
            collection="entries",
            record_id="entry%s" % suffix,
            local_id="photo%s" % suffix,
            happened_at=voice.happened_at,
            title="同一天的照片",
            excerpt="公园散步",
            kind="photo_moment",
        )
    return SoundRingMaterial(
        voice=voice,
        file_name="%s.m4a" % suffix,
        duration_seconds=duration,
        age_years=age,
        kind=kind,
        source_updated_at="2026-08-06T08:00:00Z",
        related_entry=related,
    )


class FakeQuery:
    def __init__(self, items):
        self.items = items

    def sound_ring_materials(self, _family_id):
        return self.items


class FakeStore:
    def __init__(self):
        self.records = {}
        self.sources = {}

    def find_artifact(self, key):
        return self.records.get(key)

    def create_artifact(self, payload):
        record = dict(payload, id="soundartifact123", file="")
        self.records[payload["artifactKey"]] = record
        return record

    def latest_artifact(self, family_id, kind):
        matches = [item for item in self.records.values()
                   if item.get("familyId") == family_id and item.get("kind") == kind]
        return matches[-1] if matches else None

    def recent_artifacts(self, family_id, kind, limit):
        return [item for item in self.records.values()
                if item.get("familyId") == family_id and item.get("kind") == kind][:limit]

    def get_artifact(self, artifact_id):
        return next(item for item in self.records.values() if item["id"] == artifact_id)

    def update_artifact(self, artifact_id, changes):
        record = self.get_artifact(artifact_id)
        record.update(changes)
        return record

    def archive_artifact(self, artifact_id):
        return self.update_artifact(artifact_id, {"status": "archived"})

    def get_record(self, collection, record_id):
        assert collection == "voicememos"
        if record_id in self.sources:
            return self.sources[record_id]
        suffix = record_id.removeprefix("record")
        return {
            "id": record_id, "familyId": "family", "localId": suffix,
            "isDeleted": False, "file": "%s.m4a" % suffix,
            "updated": "2026-08-06T08:00:00Z",
        }


def test_selection_is_original_first_cross_age_and_capped():
    items = [
        material("family0", age=0, duration=80, kind="familyVoice"),
        material("child0", age=0, duration=100),
        material("child1", age=1, duration=100),
        material("family1", age=1, duration=100, kind="familyVoice"),
    ]
    selected = select_materials(items)
    assert selected[0][0].voice.source_id == "voicememos:child0"
    assert selected[1][0].voice.source_id == "voicememos:child1"
    assert sum(duration for _, duration in selected) <= 400
    assert sum(duration for _, duration in selected) >= 180


def test_selection_refuses_to_pad_missing_original_audio():
    try:
        select_materials([material("short", age=0, duration=40)])
        raise AssertionError("不应用静音或 AI 旁白凑够三分钟")
    except SoundRingUnavailable as exc:
        assert "3 分钟真实原声" in str(exc)


def test_materials_keep_each_voice_own_revision():
    class QueryStore:
        def list_records(self, collection, **_kwargs):
            if collection == "voicememos":
                return [
                    {"id": "recorda", "localId": "a", "file": "a.m4a",
                     "recordedAt": "2024-05-22T08:00:00Z", "durationSeconds": 90,
                     "ageYears": 0, "kind": "childVoice", "updated": "revision-a"},
                    {"id": "recordb", "localId": "b", "file": "b.m4a",
                     "recordedAt": "2025-05-22T08:00:00Z", "durationSeconds": 90,
                     "ageYears": 1, "kind": "childVoice", "updated": "revision-b"},
                ]
            return []

    values = MemoryQuery(QueryStore()).sound_ring_materials("family")
    assert [item.source_updated_at for item in values] == ["revision-a", "revision-b"]


def test_legacy_voice_without_timestamps_uses_stable_content_revision():
    record = {
        "familyId": "family", "localId": "voice", "isDeleted": False,
        "file": "voice.m4a", "durationSeconds": 60, "recordedAt": "2024-05-22",
        "kind": "childVoice", "transcript": "妈妈",
    }
    first = sound_source_revision(record)
    assert first.startswith("fallback:")
    assert sound_source_revision(dict(record)) == first
    assert sound_source_revision(dict(record, file="replaced.m4a")) != first


def test_draft_render_retry_archive_and_public_privacy():
    store = FakeStore()
    submitted = []
    service = SoundRingService(store, submitter=lambda artifact_id, family_id, generation: submitted.append(
        (artifact_id, family_id, generation)
    ))
    service.query = FakeQuery([
        material("zero", age=0, duration=100, photo=True),
        material("one", age=1, duration=100),
    ])

    draft = service.draft("family", "布布")
    assert draft["status"] == "draft"
    assert draft["voice_cloning"] is False
    assert {item["source_id"] for item in draft["source_refs"]} == {
        "voicememos:zero", "entries:photozero", "voicememos:one"
    }
    assert "fileName" not in repr(draft)
    assert "recordId" not in repr(draft)

    rendering = service.render("family", draft["id"])
    assert rendering["status"] == "rendering"
    assert rendering["attempts"] == 1
    assert len(submitted) == 1
    assert submitted[0][:2] == (draft["id"], "family")
    assert len(submitted[0][2]) == 32

    record = store.get_artifact(draft["id"])
    record["status"] = "failed"
    record["payload"]["error"] = "第一次失败"
    retried = service.render("family", draft["id"])
    assert retried["attempts"] == 2
    assert retried["error"] == ""

    record["status"] = "ready"
    record["file"] = "ring.m4a"
    archived = service.archive("family", draft["id"])
    assert archived["status"] == "archived"
    assert public_artifact(record)["has_audio"] is True


def test_deleted_source_after_draft_is_failed_and_never_submitted():
    store = FakeStore()
    submitted = []
    service = SoundRingService(store, submitter=lambda *args: submitted.append(args))
    service.query = FakeQuery([
        material("zero", age=0, duration=100),
        material("one", age=1, duration=100),
    ])
    draft = service.draft("family", "布布")
    store.sources["recordzero"] = {
        "familyId": "family", "localId": "zero", "isDeleted": True,
        "file": "zero.m4a", "updated": "2026-08-06T08:00:00Z",
    }

    try:
        service.render("family", draft["id"])
        raise AssertionError("已删除原声不得提交渲染")
    except SoundSourceChanged as exc:
        assert "重新整理" in str(exc)
    assert submitted == []
    assert store.get_artifact(draft["id"])["status"] == "failed"


def test_replaced_source_revision_after_draft_is_rejected():
    store = FakeStore()
    service = SoundRingService(store, submitter=lambda *_: None)
    service.query = FakeQuery([
        material("zero", age=0, duration=100),
        material("one", age=1, duration=100),
    ])
    draft = service.draft("family", "布布")
    store.sources["recordone"] = {
        "familyId": "family", "localId": "one", "isDeleted": False,
        "file": "one-replaced.m4a", "updated": "2026-08-06T09:00:00Z",
    }
    try:
        service.render("family", draft["id"])
        raise AssertionError("被替换的原声不得继续渲染")
    except SoundSourceChanged:
        pass
    assert store.get_artifact(draft["id"])["status"] == "failed"


def test_source_moved_to_another_family_after_draft_is_rejected():
    store = FakeStore()
    service = SoundRingService(store, submitter=lambda *_: None)
    service.query = FakeQuery([
        material("zero", age=0, duration=100),
        material("one", age=1, duration=100),
    ])
    draft = service.draft("family", "布布")
    store.sources["recordzero"] = {
        "familyId": "another-family", "localId": "zero", "isDeleted": False,
        "file": "zero.m4a", "updated": "2026-08-06T08:00:00Z",
    }
    try:
        service.render("family", draft["id"])
        raise AssertionError("换家庭后的原声不得继续渲染")
    except SoundSourceChanged:
        pass
    assert store.get_artifact(draft["id"])["status"] == "failed"


def test_http_contract_keeps_family_server_bound_and_routes_complete():
    assert set(SoundRingArtifactReq.model_fields) == {"artifact_id"}
    paths = {route.path for route in app.routes}
    assert {
        "/sound-ring/latest", "/sound-ring/history", "/sound-ring/draft",
        "/sound-ring/render", "/sound-ring/status/{artifact_id}",
        "/sound-ring/archive", "/sound-ring/file/{artifact_id}",
    }.issubset(paths)

    payload = {
        "id": "artifact123", "artifact_key": "sound_ring:family:one",
        "status": "draft", "title": "声音年轮", "summary": "3 段真实原声",
        "generated_at": "2026-08-06T00:00:00Z", "model_version": "v1",
        "original_duration_seconds": 180, "rendered_duration_seconds": 0,
        "attempts": 0, "error": "", "narrator": "Apple 系统中性旁白",
        "voice_cloning": False, "has_audio": False, "clips": [],
        "source_refs": [], "content_hash": "hash",
    }
    assert SoundRingResp(**payload).voice_cloning is False


def test_protected_file_token_is_cached_for_one_render(monkeypatch):
    store = PocketBaseMemoryStore()
    calls = []

    class Response:
        def json(self):
            return {"token": "short-lived-file-token"}

    monkeypatch.setattr(store, "request", lambda method, path, **_kwargs: (
        calls.append((method, path)) or Response()
    ))
    try:
        assert store.protected_file_token() == "short-lived-file-token"
        assert store.protected_file_token() == "short-lived-file-token"
        assert calls == [("POST", "/api/files/token")]
    finally:
        store.close()


def test_stale_render_becomes_retryable_after_service_restart():
    store = FakeStore()
    record = store.create_artifact({
        "artifactKey": "sound_ring:family:stale",
        "familyId": "family",
        "kind": "sound_ring",
        "status": "rendering",
        "payload": {"renderStartedAt": "2020-01-01T00:00:00Z", "attempts": 1},
        "sourceRefs": [],
    })
    service = SoundRingService(store, submitter=lambda *_: None)
    recovered = service.get("family", record["id"])
    assert recovered["status"] == "failed"
    assert "服务重启或超时" in recovered["error"]


def test_protected_file_failure_never_exposes_signed_token(monkeypatch):
    store = PocketBaseMemoryStore()
    store._file_token_value = "secret-first-token"

    class TokenResponse:
        def json(self):
            return {"token": "secret-second-token"}

    def fake_request(method, path, **kwargs):
        if method == "POST":
            return TokenResponse()
        token = kwargs["params"]["token"]
        request = httpx.Request("GET", "http://pb.local/file?token=%s" % token)
        response = httpx.Response(404, request=request)
        raise httpx.HTTPStatusError("signed URL failed", request=request, response=response)

    monkeypatch.setattr(store, "request", fake_request)
    try:
        try:
            store._protected_file_response("/api/files/one")
            raise AssertionError("两次 404 应返回脱敏错误")
        except RuntimeError as exc:
            assert "secret-first-token" not in str(exc)
            assert "secret-second-token" not in str(exc)
            assert "404" in str(exc)
    finally:
        store.close()
