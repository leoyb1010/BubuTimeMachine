from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from memory_query import MemoryEvidence, MemoryQuery  # noqa: E402
from llm import LLMError  # noqa: E402
from weekly_report import (  # noqa: E402
    WeeklyReportService,
    WeeklyReportUnavailable,
    previous_complete_week,
)


UTC = timezone.utc


def evidence(kind: str, suffix: str) -> MemoryEvidence:
    if kind == "voice":
        collection = "voicememos"
    elif kind == "growth":
        collection = "growthmeasurements"
    elif kind == "milestone":
        collection = "milestones"
    else:
        collection = "entries"
    return MemoryEvidence(
        source_id="%s:%s" % (collection, suffix),
        collection=collection,
        record_id="record%s" % suffix,
        local_id=suffix,
        happened_at="2026-07-28T08:00:00Z",
        title="小事%s" % suffix,
        excerpt="真实记录%s" % suffix,
        kind=kind,
    )


class FakeQuery:
    def __init__(self, items):
        self.items = items

    def weekly_evidence(self, *_):
        return self.items


class FakeStore:
    def __init__(self):
        self.records = {}
        self.created = 0

    def find_artifact(self, key):
        return self.records.get(key)

    def create_artifact(self, payload):
        self.created += 1
        record = dict(payload, id="artifact123", created="2026-08-03T01:00:00Z")
        self.records[payload["artifactKey"]] = record
        return record

    def get_artifact(self, artifact_id):
        return next(item for item in self.records.values() if item["id"] == artifact_id)

    def latest_artifact(self, family_id, kind):
        matches = [item for item in self.records.values()
                   if item.get("familyId") == family_id and item.get("kind") == kind]
        return matches[-1] if matches else None

    def recent_artifacts(self, family_id, kind, limit=52):
        matches = [item for item in self.records.values()
                   if item.get("familyId") == family_id and item.get("kind") == kind]
        return list(reversed(matches))[:limit]

    def archive_artifact(self, artifact_id):
        record = next(item for item in self.records.values() if item["id"] == artifact_id)
        record["status"] = "archived"
        return record


class FakeLLM:
    model = "test-model"

    def __init__(self, items):
        self.items = items

    def complete_json(self, *_args, **_kwargs):
        source_ids = [item.source_id for item in self.items]
        growth_id = next(item.source_id for item in self.items
                         if item.kind in {"growth", "milestone"})
        voice_id = next(item.source_id for item in self.items if item.kind == "voice")
        return {"sections": [
            {"kind": "small_things", "text": "伪造的三件事", "source_ids": source_ids[:3]},
            {"kind": "growth", "text": "伪造的成长数字", "source_ids": [growth_id]},
            {"kind": "voice", "text": "伪造的原声", "source_ids": [voice_id]},
            {"kind": "family_question", "text": "伪造的问题", "source_ids": [source_ids[0]]},
            {"kind": "gentle_suggestion", "text": "伪造的建议", "source_ids": [voice_id]},
        ]}


def service_with(items):
    store = FakeStore()
    service = WeeklyReportService(store, FakeLLM(items))
    service.query = FakeQuery(items)
    return service, store


def complete_evidence():
    return [
        evidence("moment", "one"),
        evidence("moment", "two"),
        evidence("growth", "growth"),
        evidence("voice", "voice"),
    ]


def test_previous_complete_week_is_stable_on_monday(monkeypatch):
    monkeypatch.setenv("WEEKLY_REPORT_TIMEZONE", "Asia/Shanghai")
    window = previous_complete_week(datetime(2026, 8, 3, 12, tzinfo=UTC))
    assert window.start.isoformat() == "2026-07-26T16:00:00+00:00"
    assert window.end.isoformat() == "2026-08-02T16:00:00+00:00"
    assert window.key == "2026-07-27"


def test_sunday_evening_does_not_freeze_an_incomplete_week(monkeypatch):
    monkeypatch.setenv("WEEKLY_REPORT_TIMEZONE", "Asia/Shanghai")
    window = previous_complete_week(datetime(2026, 8, 2, 12, 30, tzinfo=UTC))
    assert window.start.isoformat() == "2026-07-19T16:00:00+00:00"
    assert window.end.isoformat() == "2026-07-26T16:00:00+00:00"


def test_no_evidence_means_no_artifact():
    service, store = service_with([])
    try:
        service.generate("family", "布布")
        raise AssertionError("空证据不应生成周报")
    except WeeklyReportUnavailable:
        pass
    assert store.created == 0


def test_voice_evidence_is_required():
    service, store = service_with([evidence("moment", "one")])
    try:
        service.generate("family", "布布")
        raise AssertionError("没有真实原声不应生成五段周报")
    except WeeklyReportUnavailable:
        pass
    assert store.created == 0


def test_generate_is_idempotent_and_sources_are_preserved():
    items = complete_evidence()
    service, store = service_with(items)
    first = service.generate("family", "布布")
    second = service.generate("family", "布布")
    assert first["id"] == second["id"] == "artifact123"
    assert store.created == 1
    assert len(first["sections"]) == 5
    assert first["sections"][2]["sourceIds"] == ["voicememos:voice"]
    assert first["sections"][2]["text"] == "“真实记录voice”"
    assert "伪造" not in "".join(section["text"] for section in first["sections"])
    assert {item["source_id"] for item in first["source_refs"]} == {
        "entries:one", "entries:two", "growthmeasurements:growth", "voicememos:voice"
    }
    assert first["model_version"] == "test-model"


def test_llm_failure_falls_back_to_traceable_deterministic_report():
    class FailingLLM:
        model = "unavailable-model"

        def complete_json(self, *_args, **_kwargs):
            raise LLMError("LLM 401")

    items = complete_evidence()
    store = FakeStore()
    service = WeeklyReportService(store, FailingLLM())
    service.query = FakeQuery(items)

    report = service.generate("family", "布布")

    assert report["model_version"] == "deterministic-evidence-v1"
    assert len(report["sections"]) == 5
    assert report["sections"][2]["text"] == "“真实记录voice”"
    assert {item["source_id"] for item in report["source_refs"]} == {
        "entries:one", "entries:two", "growthmeasurements:growth", "voicememos:voice"
    }


def test_malformed_llm_output_also_falls_back_instead_of_silently_skipping():
    class MalformedLLM:
        model = "malformed-model"

        def complete_json(self, *_args, **_kwargs):
            return {"unexpected": []}

    items = complete_evidence()
    store = FakeStore()
    service = WeeklyReportService(store, MalformedLLM())
    service.query = FakeQuery(items)

    report = service.generate("family", "布布")

    assert report["model_version"] == "deterministic-evidence-v1"
    assert len(report["sections"]) == 5


def test_archive_only_updates_derived_artifact():
    items = complete_evidence()
    service, _ = service_with(items)
    report = service.generate("family", "布布")
    archived = service.archive("family", report["id"])
    assert archived["status"] == "archived"
    assert service.history("family")[0]["id"] == report["id"]


def test_archive_accepts_an_older_report_but_rejects_another_family():
    service, store = service_with(complete_evidence())
    old = {
        "id": "oldartifact123", "artifactKey": "weekly_report:family:2026-07-20",
        "familyId": "family", "kind": "weekly_report", "status": "ready",
        "payload": {}, "sourceRefs": [],
    }
    foreign = dict(old, id="foreign123", artifactKey="weekly_report:other:2026-07-20",
                   familyId="other")
    store.records[old["artifactKey"]] = old
    store.records[foreign["artifactKey"]] = foreign

    assert service.archive("family", old["id"])["status"] == "archived"
    try:
        service.archive("family", foreign["id"])
        raise AssertionError("不能归档其他家庭的周报")
    except WeeklyReportUnavailable:
        pass


def test_uncited_family_records_are_not_copied_into_artifact():
    items = complete_evidence() + [evidence("moment", "unused")]
    service, _ = service_with(items)
    report = service.generate("family", "布布")
    assert {item["source_id"] for item in report["source_refs"]} == {
        "entries:one", "entries:two", "growthmeasurements:growth", "voicememos:voice"
    }


class RecordingMemoryStore:
    def __init__(self):
        self.calls = []

    def list_records(self, collection, *, filter_value, sort, per_page=200):
        self.calls.append((collection, filter_value, sort, per_page))
        fixtures = {
            "entries": [{
                "id": "entryrecord", "localId": "entry-local", "title": "第一次认真闻桂花",
                "note": "布布停下来闻了很久", "firstPersonNote": "", "happenedAt": "2026-07-28T08:00:00Z",
            }],
            "healthrecords": [],
            "growthmeasurements": [{
                "id": "growthrecord", "localId": "growth-local", "measuredAt": "2026-07-29T08:00:00Z",
                "heightCm": 92, "weightKg": 13.5, "headCircumferenceCm": None,
            }],
            "milestones": [],
            "voicememos": [{
                "id": "voicerecord", "localId": "voice-local", "recordedAt": "2026-07-30T08:00:00Z",
                "title": "午后的原声", "transcript": "妈妈你看，小鸟回家了。",
            }],
        }
        return fixtures[collection]


def test_memory_query_keeps_family_window_and_traceable_sources():
    store = RecordingMemoryStore()
    result = MemoryQuery(store).weekly_evidence(
        "family'quoted",
        datetime(2026, 7, 27, tzinfo=UTC),
        datetime(2026, 8, 3, tzinfo=UTC),
    )

    assert [item.source_id for item in result] == [
        "entries:entry-local", "growthmeasurements:growth-local", "voicememos:voice-local"
    ]
    assert result[-1].excerpt == "妈妈你看，小鸟回家了。"
    assert {call[0] for call in store.calls} == {
        "entries", "healthrecords", "growthmeasurements", "milestones", "voicememos"
    }
    for _, filter_value, _, _ in store.calls:
        assert "familyId='family\\'quoted'" in filter_value
        assert "isDeleted=false" in filter_value
        assert ">='2026-07-27T00:00:00+00:00'" in filter_value
        assert "<'2026-08-03T00:00:00+00:00'" in filter_value


def test_legacy_single_family_reads_empty_fact_family_without_rewriting(monkeypatch):
    monkeypatch.setenv("FACTS_LEGACY_EMPTY_FAMILY", "true")
    store = RecordingMemoryStore()
    MemoryQuery(store).weekly_evidence(
        "bubu-logical-family",
        datetime(2026, 7, 27, tzinfo=UTC),
        datetime(2026, 8, 3, tzinfo=UTC),
    )
    assert store.calls
    for _, filter_value, _, _ in store.calls:
        assert "familyId=''" in filter_value
        assert "bubu-logical-family" not in filter_value
