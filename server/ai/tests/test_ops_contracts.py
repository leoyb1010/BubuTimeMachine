import os
from pathlib import Path
import plistlib
import sqlite3
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[3]


def test_automation_collections_are_service_only():
    migration = (
        REPO_ROOT
        / "server/pocketbase/migrations/1700000012_add_automation_collections.js"
    ).read_text(encoding="utf-8")

    assert "name: 'automation_jobs'" in migration
    assert "name: 'derived_artifacts'" in migration
    for rule in ("listRule", "viewRule", "createRule", "updateRule", "deleteRule"):
        assert f"collection.{rule} = null" in migration
    assert "idx_automation_jobs_jobKey" in migration
    assert "idx_derived_artifacts_artifactKey" in migration

    notification_migration = (
        REPO_ROOT
        / "server/pocketbase/migrations/1700000013_add_weekly_notification_state.js"
    ).read_text(encoding="utf-8")
    assert "new DateField({ name: 'notifiedAt' })" in notification_migration
    assert "if (!existing)" in notification_migration
    assert "removeById(field.id)" in notification_migration


def test_migration_numbers_are_unique_and_preserve_production_autodate_slot():
    migration_dir = REPO_ROOT / "server/pocketbase/migrations"
    files = sorted(migration_dir.glob("*.js"))
    numbers = [path.name.split("_", 1)[0] for path in files]
    assert len(numbers) == len(set(numbers))
    assert not (migration_dir / "1700000011_add_automation_collections.js").exists()
    assert (migration_dir / "1700000012_add_automation_collections.js").exists()


def test_ntfy_hook_only_reports_dead_letters_without_memory_content():
    hook = (REPO_ROOT / "server/pocketbase/pb_hooks/notify.pb.js").read_text(
        encoding="utf-8"
    )

    assert '"automation_jobs"' in hook
    assert '"dead_letter"' in hook
    assert '"entries"' not in hook
    assert '"milestones"' not in hook
    assert '"voicememos"' not in hook
    assert "getString(\"note\")" not in hook


def test_healthcheck_supports_backup_age_and_private_ops_alerts():
    script = (REPO_ROOT / "server/ops/healthcheck.sh").read_text(encoding="utf-8")

    assert 'MAX_BACKUP_AGE_HOURS="${MAX_BACKUP_AGE_HOURS:-30}"' in script
    assert "Backup is stale" in script
    assert 'NTFY_URL="${NTFY_URL:-}"' in script
    assert "Authorization: Bearer $NTFY_TOKEN" in script


def test_pb_backup_uses_sqlite_snapshot_and_never_mirror_deletes(tmp_path: Path):
    source = tmp_path / "pb_data"
    mirror = tmp_path / "mirror"
    (source / "storage/records").mkdir(parents=True)
    (source / "storage/records/photo.jpg").write_bytes(b"photo")
    (source / "types.d.ts").write_text("types", encoding="utf-8")
    with sqlite3.connect(source / "data.db") as db:
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("CREATE TABLE memories (id TEXT PRIMARY KEY, title TEXT)")
        db.execute("INSERT INTO memories VALUES ('1', 'Bubu')")

    script = REPO_ROOT / "server/ops/backup_pb_data.sh"
    env = os.environ | {
        "PB_DATA_DIR": str(source),
        "MIRROR_DIR": str(mirror),
        "LOCK_DIR": str(tmp_path / "backup.lock"),
        "WORK_ROOT": str(tmp_path / "work"),
    }
    result = subprocess.run(
        ["bash", str(script)], env=env, text=True, capture_output=True, check=False
    )
    assert result.returncode == 0, result.stderr
    assert (mirror / "storage/records/photo.jpg").read_bytes() == b"photo"
    assert (mirror / "backup-manifest.json").is_file()
    assert not (mirror / "data.db-wal").exists()
    with sqlite3.connect(mirror / "data.db") as db:
        assert db.execute("SELECT title FROM memories").fetchone() == ("Bubu",)

    # 源文件被删后再跑，镜像仍保留上一份，避免把误删传播到唯一副本。
    (source / "storage/records/photo.jpg").unlink()
    result = subprocess.run(
        ["bash", str(script)], env=env, text=True, capture_output=True, check=False
    )
    assert result.returncode == 0, result.stderr
    assert (mirror / "storage/records/photo.jpg").read_bytes() == b"photo"

    verify = REPO_ROOT / "server/ops/verify_pb_backup.sh"
    verified = subprocess.run(
        ["bash", str(verify), str(mirror)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert verified.returncode == 0, verified.stderr

    with (mirror / "data.db").open("ab") as db_file:
        db_file.write(b"tamper")
    rejected = subprocess.run(
        ["bash", str(verify), str(mirror)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert rejected.returncode != 0
    assert "SHA-256" in rejected.stderr


def test_backup_launch_agent_runs_daily_without_embedded_secrets():
    path = REPO_ROOT / "server/ops/com.bubu.backup.plist.example"
    raw = path.read_text(encoding="utf-8")
    config = plistlib.loads(raw.encode("utf-8"))
    assert config["StartCalendarInterval"] == {"Hour": 3, "Minute": 17}
    assert config["EnvironmentVariables"]["PB_DATA_DIR"]
    assert config["EnvironmentVariables"]["MIRROR_DIR"]
    assert "RESTIC_PASSWORD=" not in raw


def test_tracked_duplicate_review_was_removed():
    assert not (REPO_ROOT / "REVIEW_2026-07-12 2.md").exists()
    assert (REPO_ROOT / "REVIEW_2026-07-12.md").exists()


def test_semantic_queue_is_append_only_and_ignores_audio():
    hook = (REPO_ROOT / "server/pocketbase/pb_hooks/semantic_queue.pb.js").read_text(
        encoding="utf-8"
    )

    assert '$security.randomString(8)' in hook
    assert 'findFirstRecordByFilter' not in hook
    assert 'mediaType !== "photo" && mediaType !== "video"' in hook
