from __future__ import annotations

import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from artifact_workflow import ArtifactUnavailable, ArtifactWorkflow  # noqa: E402


class FakeStore:
    def __init__(self):
        self.records = {}

    def find_artifact(self, key):
        return self.records.get(key)

    def create_artifact(self, payload):
        record = dict(payload, id="artifact123")
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


def test_workflow_is_idempotent_and_family_scoped():
    store = FakeStore()
    flow = ArtifactWorkflow(store, "sound_ring")
    payload = {
        "artifactKey": "sound_ring:family:one",
        "familyId": "family",
        "kind": "sound_ring",
        "status": "draft",
    }
    first = flow.create_idempotent(payload)
    second = flow.create_idempotent(dict(payload, status="ready"))
    assert first is second
    assert second["status"] == "draft"

    try:
        flow.owned("other-family", "artifact123")
        raise AssertionError("不能跨家庭读取派生作品")
    except ArtifactUnavailable:
        pass


def test_archive_guard_does_not_touch_unready_artifact():
    store = FakeStore()
    flow = ArtifactWorkflow(store, "sound_ring")
    record = flow.create_idempotent({
        "artifactKey": "sound_ring:family:one",
        "familyId": "family",
        "kind": "sound_ring",
        "status": "rendering",
    })
    try:
        flow.archive("family", record["id"], allowed=lambda item: item["status"] == "ready")
        raise AssertionError("未完成作品不能归档")
    except ArtifactUnavailable:
        pass
    assert record["status"] == "rendering"
