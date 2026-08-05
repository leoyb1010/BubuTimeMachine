from __future__ import annotations

import shutil
import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import sound_render  # noqa: E402


class FakeStore:
    def __init__(self, sources):
        self.sources = sources
        self.uploaded = None
        self.updated = None
        self.records = {
            record_id: {
                "familyId": "family", "localId": record_id.removeprefix("record"),
                "isDeleted": False,
                "file": "%s.m4a" % record_id.removeprefix("record"),
                "updated": "2026-08-06T08:00:00Z",
            }
            for record_id in sources
        }
        self.downloads = 0

    def download_record_file(self, _collection, record_id, _file_name, destination):
        self.downloads += 1
        shutil.copyfile(self.sources[record_id], destination)

    def get_record(self, collection, record_id):
        assert collection == "voicememos"
        return self.records[record_id]

    def upload_artifact_file(self, artifact_id, file_path, file_name):
        self.uploaded = (artifact_id, Path(file_path).read_bytes(), file_name)

    def update_artifact(self, artifact_id, changes):
        self.updated = (artifact_id, changes)
        return dict(changes, id=artifact_id)


def test_render_writes_timeline_uploads_then_cleans_temp(monkeypatch, tmp_path):
    source_a = tmp_path / "a.raw"
    source_b = tmp_path / "b.raw"
    source_a.write_bytes(b"a")
    source_b.write_bytes(b"b")
    store = FakeStore({"recorda": source_a, "recordb": source_b})

    workdir = tmp_path / "work"
    workdir.mkdir()
    monkeypatch.setattr(sound_render, "available", lambda: True)
    monkeypatch.setattr(sound_render.tempfile, "mkdtemp", lambda **_kwargs: str(workdir))
    monkeypatch.setattr(sound_render, "_make_silence", lambda path, _seconds: path.write_bytes(b"s"))
    monkeypatch.setattr(sound_render, "_make_bridge", lambda path, _text: path.write_bytes(b"b"))
    monkeypatch.setattr(sound_render, "_normalize", lambda _src, dst, _seconds: dst.write_bytes(b"n"))

    def fake_duration(path):
        if path.suffix == ".m4a":
            return 184.0
        if path.name.startswith("bridge"):
            return 2.0
        if path.name.startswith("clip"):
            return 90.0
        return 0.45

    monkeypatch.setattr(sound_render, "_duration", fake_duration)

    def fake_run(command, label, timeout=600):
        del timeout
        if label == "concat":
            Path(command[-1]).write_bytes(b"rendered-audio")

    monkeypatch.setattr(sound_render, "_run", fake_run)
    artifact = {
        "id": "artifact123",
        "familyId": "family",
        "title": "布布的声音年轮",
        "payload": {
            "clips": [
                {"sourceId": "voicememos:a", "recordId": "recorda", "fileName": "a.m4a",
                 "sourceUpdatedAt": "2026-08-06T08:00:00Z",
                 "ageYears": 0, "durationSeconds": 90},
                {"sourceId": "voicememos:b", "recordId": "recordb", "fileName": "b.m4a",
                 "sourceUpdatedAt": "2026-08-06T08:00:00Z",
                 "ageYears": 1, "durationSeconds": 90},
            ],
            "timeline": [], "attempts": 1,
        },
    }

    result = sound_render.render_artifact_now(store, artifact)
    assert result["status"] == "ready"
    assert store.uploaded[0] == "artifact123"
    assert store.uploaded[1] == b"rendered-audio"
    assert store.updated[1]["payload"]["timeline"] == [
        {"sourceId": "voicememos:a", "startSeconds": 2.45, "endSeconds": 92.45},
        {"sourceId": "voicememos:b", "startSeconds": 95.35, "endSeconds": 185.35},
    ]
    assert not workdir.exists()


def test_source_deleted_during_render_never_uploads_or_becomes_ready(monkeypatch, tmp_path):
    source_a = tmp_path / "a.raw"
    source_b = tmp_path / "b.raw"
    source_a.write_bytes(b"a")
    source_b.write_bytes(b"b")
    store = FakeStore({"recorda": source_a, "recordb": source_b})
    monkeypatch.setattr(sound_render, "available", lambda: True)
    monkeypatch.setattr(sound_render, "_make_silence", lambda path, _seconds: path.write_bytes(b"s"))
    monkeypatch.setattr(sound_render, "_make_bridge", lambda path, _text: path.write_bytes(b"b"))
    monkeypatch.setattr(sound_render, "_normalize", lambda _src, dst, _seconds: dst.write_bytes(b"n"))
    monkeypatch.setattr(sound_render, "_duration", lambda path: 184.0 if path.suffix == ".m4a" else (90.0 if path.name.startswith("clip") else 0.45))

    def fake_run(command, label, timeout=600):
        del timeout
        if label == "concat":
            Path(command[-1]).write_bytes(b"rendered-audio")
            store.records["recorda"]["isDeleted"] = True

    monkeypatch.setattr(sound_render, "_run", fake_run)
    artifact = {
        "id": "artifact123", "familyId": "family", "title": "声音年轮",
        "payload": {"clips": [
            {"sourceId": "voicememos:a", "recordId": "recorda", "fileName": "a.m4a",
             "sourceUpdatedAt": "2026-08-06T08:00:00Z", "ageYears": 0, "durationSeconds": 90},
            {"sourceId": "voicememos:b", "recordId": "recordb", "fileName": "b.m4a",
             "sourceUpdatedAt": "2026-08-06T08:00:00Z", "ageYears": 1, "durationSeconds": 90},
        ]},
    }
    try:
        sound_render.render_artifact_now(store, artifact)
        raise AssertionError("渲染期间删除原声不得发布")
    except Exception as exc:
        assert "重新整理" in str(exc)
    assert store.uploaded is None
    assert store.updated is None


def test_submit_failure_releases_inflight_slot(monkeypatch):
    monkeypatch.setattr(sound_render._executor, "submit", lambda *_: (_ for _ in ()).throw(RuntimeError("closed")))
    try:
        sound_render.submit_artifact_render("artifact123", "family", "generation")
        raise AssertionError("submit 失败应向上抛出")
    except RuntimeError:
        pass
    assert "artifact123" not in sound_render._inflight


def test_only_current_render_generation_can_publish():
    current = {
        "status": "rendering",
        "payload": {"renderGeneration": "new-generation"},
    }
    try:
        sound_render._validate_generation(current, "old-generation")
        raise AssertionError("旧制作任务不得发布")
    except RuntimeError as exc:
        assert "旧任务" in str(exc)
    sound_render._validate_generation(current, "new-generation")
