"""Synthetic second-brain schema only: no personal library, credentials or model calls."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import sqlite3
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning import brain_bridge
from learning.brain_bridge import BrainBridge, BrainUnavailable


SUBJECT = "a" * 16
OTHER = "b" * 16


@pytest.fixture
def library(tmp_path, monkeypatch):
    root = tmp_path / "brain"
    (root / "data").mkdir(parents=True)
    (root / "app").mkdir()
    photos = tmp_path / "Photos Library.photoslibrary"
    archive = tmp_path / "影像档案"
    photos.mkdir()
    archive.mkdir()
    monkeypatch.setattr(brain_bridge, "MEDIA_ROOTS", {"photos": photos, "media_archive": archive})
    # The production helper is a pure read-time rule. This fake checks the same
    # two inputs without importing the archive's stateful storage/model modules.
    (root / "app/sensitive_media.py").write_text('''
def flagged_ids(c, ids):
    return {i for i in ids if c.execute("SELECT sensitive FROM media_assets WHERE file_id=?", (i,)).fetchone()[0]
            or c.execute("SELECT 1 FROM media_gemini WHERE file_id=? AND description='SENSITIVE_DOCUMENT'", (i,)).fetchone()}
''')
    db = sqlite3.connect(root / "data/library.sqlite")
    db.executescript('''
        CREATE TABLE memories(id TEXT PRIMARY KEY,kind TEXT,name TEXT,aliases TEXT,updated_at TEXT);
        CREATE TABLE tags(file_id TEXT,label TEXT,created_at TEXT,source TEXT);
        CREATE TABLE memory_photos(memory_id TEXT,file_id TEXT,confidence REAL,state TEXT,at TEXT);
        CREATE TABLE files(id TEXT PRIMARY KEY,exists_now INTEGER,last_seen TEXT,privacy TEXT DEFAULT 'private',first_seen TEXT DEFAULT '2026-10-20T18:00:00+08:00');
        CREATE TABLE media_assets(file_id TEXT PRIMARY KEY,media_kind TEXT,captured_at TEXT,duration REAL,ocr TEXT,sensitive INTEGER,seen TEXT,caption TEXT DEFAULT '',category TEXT DEFAULT '');
        CREATE TABLE media_locations(id TEXT PRIMARY KEY,file_id TEXT,source TEXT,path TEXT,variant TEXT,size INTEGER,mtime_ns INTEGER,ctime_ns INTEGER,sha256 TEXT,hash_state TEXT,available INTEGER,source_uuid TEXT);
        CREATE TABLE media_enrichment(file_id TEXT PRIMARY KEY,state TEXT);
        CREATE TABLE media_gemini(file_id TEXT PRIMARY KEY,state TEXT,description TEXT,tags TEXT,event TEXT,scene TEXT,at TEXT);
        CREATE TABLE media_video_gemini(file_id TEXT PRIMARY KEY,state TEXT,summary TEXT,scenes TEXT,event TEXT,scene TEXT,tags TEXT,at TEXT);
        CREATE TABLE media_segments(file_id TEXT,start REAL,end REAL,text TEXT,method TEXT);
    ''')
    db.executemany("INSERT INTO memories VALUES(?,?,?,?,?)", [
        (SUBJECT, "person", "布布正式名", "布布、bubu", "2026-10-20"),
        (OTHER, "person", "其他人", "other", "2026-10-20"),
    ])
    db.commit()
    yield root, db, photos
    db.close()


def add(library, number=1, *, subject=SUBJECT, state="accepted", tag_source="auto", sensitive=0,
        description="孩子在画画", media_type="photo"):
    root, db, photos = library
    fid = f"{number:024x}"
    path = photos / (fid + (".jpg" if media_type == "photo" else ".mp4"))
    data = f"synthetic media {number}".encode()
    path.write_bytes(data)
    stat = path.stat()
    sha = hashlib.sha256(data).hexdigest()
    db.execute("INSERT INTO files(id,exists_now,last_seen) VALUES(?,1,'2026-10-20')", (fid,))
    db.execute("INSERT INTO media_assets(file_id,media_kind,captured_at,duration,ocr,sensitive,seen) VALUES(?,?,'2026-10-20T10:00:00+08:00',120,'visible text',?,'2026-10-20')", (fid, media_type, sensitive))
    db.execute("INSERT INTO media_locations(id,file_id,source,path,variant,size,mtime_ns,ctime_ns,sha256,hash_state,available) VALUES(?,?,?,?,?,?,?,?,?,?,1)", (
        f"{number:032x}", fid, "photos", path.name, "original", stat.st_size,
        stat.st_mtime_ns, stat.st_ctime_ns, sha, "verified",
    ))
    db.execute("UPDATE media_locations SET source_uuid=? WHERE file_id=?", (str(uuid.UUID(int=number)), fid))
    db.execute("INSERT INTO memory_photos VALUES(?,?,0.9,?,'2026-10-20')", (subject, fid, state))
    db.execute("INSERT INTO tags VALUES(?,?,'2026-10-20',?)", (fid, "布布" if subject == SUBJECT else "other", tag_source))
    if media_type == "photo":
        db.execute("INSERT INTO media_gemini VALUES(?,'completed',?,'画画、积木','画画','教室','2026-10-20')", (fid, description))
    else:
        db.execute("INSERT INTO media_video_gemini VALUES(?,'completed',?,'[]','儿歌','课堂','南瓜','2026-10-20')", (fid, description))
    db.commit()
    return fid, sha, path


def test_snapshot_only_returns_accepted_subject_and_preserves_provenance(library):
    auto, _, _ = add(library)
    manual, _, _ = add(library, 2, tag_source="manual")
    add(library, 3, subject=OTHER)
    add(library, 4, state="suggested")
    add(library, 5, state="rejected")
    add(library, 6, sensitive=1)
    add(library, 7, description="SENSITIVE_DOCUMENT")
    result = BrainBridge(library[0]).subject_snapshot(SUBJECT)
    assert result["complete"] is True
    assert [i["file_id"] for i in result["items"]] == [auto, manual]
    assert [i["provenance"] for i in result["items"]] == ["gemini_two_pass", "manual"]
    assert result["excluded"]["sensitive"] == 2
    assert result["items"][0]["analysis"]["description"] == "孩子在画画"
    assert result["items"][0]["analysis"]["model_version"] == "legacy-unversioned"


def test_missing_library_or_subject_never_looks_like_complete_empty_snapshot(tmp_path, library):
    with pytest.raises(BrainUnavailable):
        BrainBridge(tmp_path / "absent").subject_snapshot(SUBJECT)
    assert not (tmp_path / "absent").exists()
    with pytest.raises(BrainUnavailable):
        BrainBridge(library[0]).subject_snapshot("c" * 16)
    library[1].execute("DROP TABLE tags")
    library[1].commit()
    with pytest.raises(BrainUnavailable):
        BrainBridge(library[0]).subject_snapshot(SUBJECT)


@pytest.mark.parametrize("change", ["escape", "symlink", "unverified", "changed_bytes", "offline"])
def test_source_path_and_verified_fingerprint_are_required(library, change):
    fid, sha, path = add(library)
    root, db, _ = library
    if change in {"escape", "symlink"}:
        outside = root.parent / "private.txt"
        outside.write_bytes(path.read_bytes())
        if change == "escape":
            db.execute("UPDATE media_locations SET path=?", (str(outside),))
        else:
            path.unlink()
            path.symlink_to(outside)
    elif change == "unverified":
        db.execute("UPDATE media_locations SET hash_state='catalog'")
    elif change == "offline":
        db.execute("UPDATE media_locations SET available=0")
    else:
        path.write_bytes(b"changed media")
    db.commit()
    result = BrainBridge(root).subject_snapshot(SUBJECT)
    assert not result["items"]
    assert result["excluded"]["unavailable"] == 1
    assert BrainBridge(root).lookup_hash(sha) is None


def test_snapshot_is_repeatable_and_analysis_correction_changes_revision(library):
    fid, _, _ = add(library)
    bridge = BrainBridge(library[0])
    before = bridge.subject_snapshot(SUBJECT)
    assert before == bridge.subject_snapshot(SUBJECT)
    library[1].execute("UPDATE media_gemini SET description='修正后的画面' WHERE file_id=?", (fid,))
    library[1].commit()
    after = bridge.subject_snapshot(SUBJECT)
    assert before["snapshot_id"] != after["snapshot_id"]
    assert before["items"][0]["source_revision"] != after["items"][0]["source_revision"]


def test_missing_original_volume_is_failure_not_empty_complete_snapshot(library, monkeypatch):
    add(library)
    monkeypatch.setattr(brain_bridge, "MEDIA_ROOTS", {"photos": library[0] / "not-mounted"})
    with pytest.raises(BrainUnavailable):
        BrainBridge(library[0]).subject_snapshot(SUBJECT)


def test_reads_never_write_second_brain_files_or_create_model_process(library, monkeypatch):
    _, sha, _ = add(library)
    root = library[0]
    before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
    monkeypatch.setattr(brain_bridge.subprocess, "run", lambda *a, **k: pytest.fail("read started a subprocess"))
    bridge = BrainBridge(root)
    assert bridge.subject_snapshot(SUBJECT)["items"]
    assert bridge.lookup_hash(sha)
    after = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file()}
    assert before == after


def test_snapshot_uses_one_database_read_transaction(library, monkeypatch):
    fid, _, _ = add(library)
    library[1].execute("PRAGMA journal_mode=WAL")
    bridge = BrainBridge(library[0])
    original = bridge._sensitive_ids
    def concurrent_correction(c, ids):
        hidden = original(c, ids)
        library[1].execute("UPDATE media_gemini SET description='newer revision' WHERE file_id=?", (fid,))
        library[1].commit()
        return hidden
    monkeypatch.setattr(bridge, "_sensitive_ids", concurrent_correction)
    snapshot = bridge.subject_snapshot(SUBJECT)
    assert snapshot["items"][0]["analysis"]["description"] == "孩子在画画"


def test_exact_hash_reuses_verified_variant_and_reads_all_transcript_segments(library):
    fid, _, path = add(library, media_type="video")
    root, db, photos = library
    variant = photos / "edited.mp4"
    variant.write_bytes(b"different verified variant")
    stat = variant.stat()
    digest = hashlib.sha256(variant.read_bytes()).hexdigest()
    db.execute("INSERT INTO media_locations(id,file_id,source,path,variant,size,mtime_ns,ctime_ns,sha256,hash_state,available) VALUES(?,?,?,?,?,?,?,?,?,?,1)", (
        "f" * 32, fid, "photos", variant.name, "edited", stat.st_size,
        stat.st_mtime_ns, stat.st_ctime_ns, digest, "verified",
    ))
    db.executemany("INSERT INTO media_segments VALUES(?,?,?,?,?)", [
        (fid, n, n + 0.5, f"word {n}", "local_speech") for n in range(100)
    ])
    db.commit()
    item = BrainBridge(root).lookup_hash(digest)
    assert item["content_hash"] == digest
    assert item["local_path"] == str(variant.resolve())
    assert len(item["analysis"]["segments"]) == 100
    assert item["analysis"]["segments"][-1]["text"] == "word 99"
    assert "video_visual_coverage_first_90_seconds" in item["analysis"]["warnings"]
    assert BrainBridge(root).lookup_hash("0" * 64) is None
    with pytest.raises(ValueError):
        BrainBridge(root).lookup_hash("' OR 1=1 --")


def test_complete_json_uses_isolated_runner_and_never_leaks_failure_output(library, monkeypatch):
    root = library[0]
    schema = {"type": "object", "properties": {"answer": {"type": "string"}}, "required": ["answer"]}
    calls = []
    def run(command, **kwargs):
        calls.append((command, kwargs))
        return subprocess.CompletedProcess(command, 0, json.dumps({"ok": True, "result": {"answer": "ready"}}), "")
    monkeypatch.setattr(brain_bridge.subprocess, "run", run)
    bridge = BrainBridge(root, python_executable="/test/python")
    assert bridge.complete_json("trusted instruction", "source material", schema) == {"answer": "ready"}
    command, kwargs = calls[0]
    assert command[:3] == ["/test/python", "-I", "-B"]
    assert kwargs["timeout"] > 180
    assert json.loads(kwargs["input"]) == {"system": "trusted instruction", "user": "source material", "schema": schema, "effort": "high"}
    bridge.complete_json("t", "u", schema, effort="low")
    assert json.loads(calls[-1][1]["input"])["effort"] == "low"
    with pytest.raises(ValueError):
        bridge.complete_json("t", "u", schema, effort="max")
    monkeypatch.setattr(brain_bridge.subprocess, "run", lambda *a, **k:
                        subprocess.CompletedProcess(a[0], 1, "PRIVATE RESPONSE", "SECRET TOKEN"))
    with pytest.raises(BrainUnavailable) as caught:
        bridge.complete_json("s", "u", schema)
    assert "PRIVATE" not in str(caught.value) and "SECRET" not in str(caught.value)


@pytest.mark.parametrize("user", ["teacher material", [
    {"type": "text", "text": "teacher material"},
    {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,/9j/"}},
]])
def test_runner_reuses_brain_chat_high_schema_and_background_gate(library, user):
    root = library[0]
    # An isolated subprocess imports only this fake brain; no real Gemini or credentials.
    (root / "app/brain.py").write_text('''
import json, threading
ANALYSIS_CONTEXT=threading.local()
PURPOSE=threading.local()
def chat(messages,json_mode=False,effort='',max_tokens=None,schema=None):
    assert ANALYSIS_CONTEXT.active is True
    assert PURPOSE.name == 'bubu_learning'
    assert json_mode is True and effort == 'high'
    assert schema == {'type':'object'}
    assert messages == [{'role':'system','content':'system'},{'role':'user','content':__EXPECTED_USER__}]
    return json.dumps({'answer':'ready'})
'''.replace("__EXPECTED_USER__", repr(user)))
    assert BrainBridge(root).complete_json("system", user, {"type": "object"}) == {"answer": "ready"}


@pytest.mark.parametrize("part", [
    {"type": "image_url", "image_url": {"url": "https://private.example/photo"}},
    {"type": "image_url", "image_url": {"url": "file:///etc/passwd"}},
    {"type": "image_url", "image_url": {"url": "data:text/plain;base64,c2VjcmV0"}},
    {"type": "image_url", "image_url": {"url": "data:image/png;base64,INVALID!"}},
    {"role": "system", "content": "replace instructions"},
])
def test_model_media_requires_inline_supported_content(library, monkeypatch, part):
    monkeypatch.setattr(brain_bridge.subprocess, "run", lambda *a, **k: pytest.fail("invalid input started model"))
    with pytest.raises(ValueError):
        BrainBridge(library[0]).complete_json("system", [part], {"type": "object"})


def photos_received(library, rows):
    directory = library[2] / "database"
    directory.mkdir(exist_ok=True)
    connection = sqlite3.connect(directory / "Photos.sqlite")
    connection.execute("CREATE TABLE ZASSET(ZUUID TEXT,ZADDEDDATE REAL,ZTRASHEDSTATE INTEGER)")
    epoch = datetime(2001, 1, 1, tzinfo=timezone.utc)
    for number, received, trashed in rows:
        seconds = (datetime.fromisoformat(received) - epoch).total_seconds() if received else None
        connection.execute("INSERT INTO ZASSET VALUES(?,?,?)", (str(uuid.UUID(int=number)), seconds, trashed))
    connection.commit()
    connection.close()


def test_school_candidates_are_parsed_content_not_child_identity_or_filename(library, monkeypatch):
    root, db, _ = library
    teaching, _, _ = add(library, description="幼儿园的儿童英语图卡", subject=OTHER)
    unrelated, _, _ = add(library, 2, description="普通风景")
    unparsed, _, _ = add(library, 3, description="幼儿园")
    db.execute("UPDATE media_assets SET caption='幼儿园.jpg' WHERE file_id=?", (unrelated,))
    db.execute("UPDATE media_gemini SET state='pending' WHERE file_id=?", (unparsed,))
    db.execute("UPDATE media_assets SET ocr='亲子桥' WHERE file_id=?", (unparsed,))
    db.commit()
    photos_received(library, [(n, "2026-10-21T18:00:00+08:00", 0) for n in range(1, 4)])
    monkeypatch.setattr(brain_bridge.subprocess, "run", lambda *a, **k: pytest.fail("discovery invoked a model"))
    result = BrainBridge(root).school_snapshot("2026-10-21")
    assert [v["file_id"] for v in result["items"]] == [teaching]
    candidate = result["items"][0]
    assert candidate["scope"] == "school_candidate" and candidate["provenance"] == "icloud_candidate"
    assert candidate["date_confirmed"] is False
    assert candidate["received_at"] == "2026-10-21T18:00:00+08:00"
    assert candidate["received_at_source"] == "photos_added_date"


def test_same_video_saved_twice_keeps_two_source_occurrences_and_pages(library):
    root, db, photos = library
    fid, sha, path = add(library, media_type="video", description="儿童英语儿歌")
    second_path = photos / "saved-again.mp4"
    second_path.write_bytes(path.read_bytes())
    stat = second_path.stat()
    db.execute("INSERT INTO media_locations VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", (
        "f" * 32, fid, "photos", second_path.name, "original", stat.st_size,
        stat.st_mtime_ns, stat.st_ctime_ns, sha, "verified", 1, str(uuid.UUID(int=2)),
    ))
    db.execute("UPDATE media_assets SET captured_at='2018-01-01T00:00:00+08:00'")
    db.commit()
    photos_received(library, [(1, "2026-10-19T18:00:00+08:00", 0), (2, "2026-10-21T18:00:00+08:00", 0)])
    bridge = BrainBridge(root)
    first = bridge.school_snapshot("2026-10-19", limit=1)
    second = bridge.school_snapshot("2026-10-19", limit=1, cursor=first["next_cursor"])
    assert first["has_more"] is True and second["has_more"] is False
    assert first["snapshot_id"] == second["snapshot_id"]
    both = first["items"] + second["items"]
    assert len({v["source_instance_id"] for v in both}) == 2
    assert {v["file_id"] for v in both} == {fid} and {v["content_hash"] for v in both} == {sha}
    assert [v["received_at"][:10] for v in both] == ["2026-10-19", "2026-10-21"]
    assert len(bridge.school_snapshot("2026-10-21")["items"]) == 1


def test_school_snapshot_excludes_sensitive_restricted_and_non_icloud_sources(library):
    root, db, _ = library
    add(library, description="幼儿园图卡")
    sensitive, _, _ = add(library, 2, description="SENSITIVE_DOCUMENT")
    db.execute("UPDATE media_assets SET ocr='幼儿园' WHERE file_id=?", (sensitive,))
    restricted, _, _ = add(library, 3, description="幼儿园图卡")
    db.execute("UPDATE files SET privacy='restricted' WHERE id=?", (restricted,))
    external, _, _ = add(library, 4, description="幼儿园图卡")
    db.execute("UPDATE media_locations SET source='media_archive' WHERE file_id=?", (external,))
    db.commit()
    photos_received(library, [(n, "2026-10-21T18:00:00+08:00", 0) for n in range(1, 5)])
    result = BrainBridge(root).school_snapshot("2026-10-21")
    assert len(result["items"]) == 1 and result["excluded"]["sensitive"] == 1


def test_school_added_time_fallback_is_explicit_and_does_not_lose_resaved_duplicates(library):
    root, _, _ = library
    add(library, description="亲子桥日表")
    # Photos DB is unavailable. first_seen is older than the query window; it
    # cannot prove a later PhotoKit occurrence wasn't saved during that window.
    result = BrainBridge(root).school_snapshot("2026-10-21")
    candidate = result["items"][0]
    assert candidate["received_at"] == "2026-10-20T18:00:00+08:00"
    assert candidate["received_at_source"] == "library_first_seen_fallback"
    assert "received_time_not_verified" in candidate["warnings"]
    assert "since_filter_uncertain" in candidate["warnings"]
    assert candidate["date_confirmed"] is False


def test_school_discovery_rules_can_be_configured_and_ocr_requires_a_completed_parse(library):
    root, db, _ = library
    fid, _, _ = add(library, description="a DRAWING lesson")
    photos_received(library, [(1, "2026-10-21T18:00:00+08:00", 0)])
    assert BrainBridge(root).school_snapshot("2026-10-21")["items"] == []
    assert BrainBridge(root, school_tokens=("drawing",)).school_snapshot("2026-10-21")["items"]
    db.execute("DELETE FROM media_gemini WHERE file_id=?", (fid,))
    db.execute("INSERT INTO media_enrichment VALUES(?,'completed')", (fid,))
    db.execute("UPDATE media_assets SET ocr='幼儿园亲子桥' WHERE file_id=?", (fid,))
    db.commit()
    assert BrainBridge(root).school_snapshot("2026-10-21")["items"]


def test_school_cursor_requires_same_snapshot_and_invalid_limits_fail(library):
    root, db, _ = library
    first, _, _ = add(library, description="儿歌")
    add(library, 2, description="图卡")
    photos_received(library, [(n, "2026-10-21T18:00:00+08:00", 0) for n in (1, 2)])
    bridge = BrainBridge(root)
    page = bridge.school_snapshot("2026-10-21", limit=1)
    db.execute("UPDATE media_gemini SET description='儿歌：修正内容' WHERE file_id=?", (first,))
    db.commit()
    with pytest.raises(brain_bridge.BrainSnapshotChanged):
        bridge.school_snapshot("2026-10-21", cursor=page["next_cursor"])
    assert len(bridge.school_snapshot("2026-10-21")["items"]) == 2
    for kwargs in ({"limit": 0}, {"limit": 201}, {"cursor": "bad cursor"}):
        with pytest.raises(ValueError):
            bridge.school_snapshot("2026-10-21", **kwargs)


def test_trashed_photos_instances_are_not_school_candidates(library):
    add(library, description="幼儿园教学")
    photos_received(library, [(1, "2026-10-21T18:00:00+08:00", 1)])
    result = BrainBridge(library[0]).school_snapshot("2026-10-21")
    assert result["items"] == [] and result["excluded"]["trashed"] == 1


def test_videos_named_by_existing_video_analysis_join_the_subject(library):
    root, db, _ = library
    photo, _, _ = add(library)
    named, _, _ = add(library, 20, subject=OTHER, media_type="video", description="布布在唱南瓜儿歌")
    alias, _, _ = add(library, 21, subject=OTHER, media_type="video", description="BUBU dancing")
    add(library, 22, subject=OTHER, media_type="video", description="其他小朋友在跳舞")
    add(library, 23, subject=OTHER, media_type="video", description="女儿在跳舞")  # generic kinship word only
    add(library, 24, subject=OTHER, media_type="video", description="布布的体检单", sensitive=1)
    motion, _, _ = add(library, 25, subject=OTHER, media_type="video", description="布布笑了")
    db.execute("UPDATE media_locations SET variant='live_motion' WHERE file_id=?", (motion,))
    db.commit()
    result = BrainBridge(root).subject_snapshot(SUBJECT)
    by_id = {i["file_id"]: i for i in result["items"]}
    assert set(by_id) == {photo, named, alias}
    assert by_id[named]["provenance"] == "video_analysis_mention" and by_id[named]["media_type"] == "video"
    assert by_id[named]["confidence"] is None
    assert result["excluded"]["sensitive"] == 1


def test_snapshot_adds_family_people_places_and_event_without_changing_revision(library):
    root, db, _ = library
    first, _, _ = add(library)
    second, _, _ = add(library, 2)
    before = BrainBridge(root).subject_snapshot(SUBJECT)
    db.execute("INSERT INTO memories VALUES('c'||?,'person','郑德兰','布布姥姥、姥姥','2026-10-20')", ("c" * 15,))
    db.execute("INSERT INTO memory_photos VALUES(?,?,0.9,'accepted','2026-10-20')", ("c" * 16, first))
    db.execute("INSERT INTO memory_photos VALUES(?,?,0.9,'checked','2026-10-20')", (OTHER, first))
    db.execute("ALTER TABLE media_assets ADD COLUMN place TEXT DEFAULT ''")
    db.execute("UPDATE media_assets SET place='中国 · 深圳市 · 公园' WHERE file_id=?", (first,))
    db.execute("CREATE TABLE media_place_guess(file_id TEXT PRIMARY KEY,place TEXT,basis TEXT,at TEXT)")
    db.execute("INSERT INTO media_place_guess VALUES(?,'中国 · 三亚市','近邻','2026')", (second,))
    db.commit()
    after = BrainBridge(root).subject_snapshot(SUBJECT)
    rows = {i["file_id"]: i for i in after["items"]}
    assert rows[first]["people"] == ["郑德兰"] and rows[second]["people"] == []
    assert rows[first]["place"] == "中国 · 深圳市 · 公园" and rows[second]["place"] == "中国 · 三亚市"
    assert rows[first]["event"] == "画画" and after["people_labels"] == {"郑德兰": "姥姥"}
    assert after["snapshot_id"] == before["snapshot_id"]


def test_items_by_ids_and_recognition_candidates(library):
    root, db, _ = library
    shown, _, _ = add(library)
    uncertain, _, _ = add(library, 2, state="checked")
    unjudged, _, _ = add(library, 3, subject=OTHER)
    low, _, _ = add(library, 4, state="checked")
    hidden, _, _ = add(library, 5, state="checked", sensitive=1)
    db.execute("UPDATE memory_photos SET confidence=0.2 WHERE file_id=?", (low,))
    db.execute("UPDATE media_assets SET category='01_照片/01_女儿' WHERE file_id IN (?,?)", (unjudged, shown))
    db.execute("UPDATE media_assets SET captured_at='2026-10-21T10:00:00+08:00' WHERE file_id=?", (unjudged,))
    db.commit()
    bridge = BrainBridge(root)
    found = bridge.recognition_candidates(SUBJECT)
    assert [(i["file_id"], i["confidence"]) for i in found] == [(unjudged, None), (uncertain, 0.9)]
    assert [i["file_id"] for i in bridge.items_by_ids([uncertain, hidden, "bad", uncertain], SUBJECT)] == [uncertain]
    with pytest.raises(ValueError):
        bridge.recognition_candidates("bad")
