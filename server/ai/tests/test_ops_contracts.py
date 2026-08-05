import os
from pathlib import Path
import plistlib
import hashlib
import json
import socket
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
    assert 'NTFY_TOKEN_FILE="${NTFY_TOKEN_FILE:-}"' in script


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
    assert (mirror / ".bubu-pocketbase-backup-target").read_text().strip() == (
        "bubu-pocketbase-backup-v1"
    )
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


def test_restic_retention_is_versioned_without_automatic_prune():
    script = (REPO_ROOT / "server/ops/backup_pb_data.sh").read_text(encoding="utf-8")
    assert "--keep-daily 14" in script
    assert "--keep-weekly 8" in script
    assert "--keep-monthly 24" in script
    assert "--keep-yearly 18" in script
    assert "restic prune" not in script
    assert 'backup_restic_repository "$RESTIC_REPOSITORY" "本地"' in script
    assert (
        'backup_restic_repository "$RESTIC_SECONDARY_REPOSITORY" "异地"'
        in script
    )
    assert 'REQUIRE_RESTIC_REPOSITORIES="${REQUIRE_RESTIC_REPOSITORIES:-false}"' in script


def test_launchd_backup_template_uses_hardened_runner():
    template = (
        REPO_ROOT / "server/ops/com.bubu.backup.plist.example"
    ).read_text(encoding="utf-8")
    assert "run_scheduled_backup.sh" in template
    assert "BUBU_BACKUP_CONFIG" in template
    assert "backup_pb_data.sh</string>" not in template


def test_backup_rejects_nonempty_target_without_sentinel(tmp_path: Path):
    source = tmp_path / "pb_data"
    mirror = tmp_path / "wrong-wide-directory"
    (source / "storage").mkdir(parents=True)
    mirror.mkdir()
    (mirror / "unrelated.txt").write_text("keep me", encoding="utf-8")
    with sqlite3.connect(source / "data.db") as db:
        db.execute("CREATE TABLE memories (id TEXT PRIMARY KEY)")

    result = subprocess.run(
        ["bash", str(REPO_ROOT / "server/ops/backup_pb_data.sh")],
        env=os.environ | {
            "PB_DATA_DIR": str(source),
            "MIRROR_DIR": str(mirror),
            "LOCK_DIR": str(tmp_path / "backup.lock"),
        },
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "缺少专用标记" in result.stderr
    assert (mirror / "unrelated.txt").read_text(encoding="utf-8") == "keep me"
    assert not (mirror / "data.db").exists()


def test_production_restic_gate_requires_local_and_offsite_repositories(tmp_path: Path):
    source = tmp_path / "pb_data"
    (source / "storage").mkdir(parents=True)
    with sqlite3.connect(source / "data.db") as db:
        db.execute("CREATE TABLE memories (id TEXT PRIMARY KEY)")
    result = subprocess.run(
        ["bash", str(REPO_ROOT / "server/ops/backup_pb_data.sh")],
        env=os.environ | {
            "PB_DATA_DIR": str(source),
            "MIRROR_DIR": str(tmp_path / "mirror"),
            "LOCK_DIR": str(tmp_path / "backup.lock"),
            "REQUIRE_RESTIC_REPOSITORIES": "true",
        },
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "要求本地 restic 仓库" in result.stderr


def test_production_restic_gate_rejects_same_repository(tmp_path: Path):
    source = tmp_path / "pb_data"
    (source / "storage").mkdir(parents=True)
    with sqlite3.connect(source / "data.db") as db:
        db.execute("CREATE TABLE memories (id TEXT PRIMARY KEY)")
    repository = tmp_path / "same-restic"
    result = subprocess.run(
        ["bash", str(REPO_ROOT / "server/ops/backup_pb_data.sh")],
        env=os.environ | {
            "PB_DATA_DIR": str(source),
            "MIRROR_DIR": str(tmp_path / "mirror"),
            "LOCK_DIR": str(tmp_path / "backup.lock"),
            "REQUIRE_RESTIC_REPOSITORIES": "true",
            "RESTIC_REPOSITORY": str(repository),
            "RESTIC_SECONDARY_REPOSITORY": str(repository),
        },
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "不能相同" in result.stderr


def test_backup_rejects_restic_repository_inside_mirror(tmp_path: Path):
    source = tmp_path / "pb_data"
    mirror = tmp_path / "mirror"
    (source / "storage").mkdir(parents=True)
    with sqlite3.connect(source / "data.db") as db:
        db.execute("CREATE TABLE memories (id TEXT PRIMARY KEY)")
    result = subprocess.run(
        ["bash", str(REPO_ROOT / "server/ops/backup_pb_data.sh")],
        env=os.environ | {
            "PB_DATA_DIR": str(source),
            "MIRROR_DIR": str(mirror),
            "LOCK_DIR": str(tmp_path / "backup.lock"),
            "RESTIC_REPOSITORY": str(mirror / "restic"),
        },
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "不能位于镜像目录内" in result.stderr


def test_backup_runs_and_checks_both_restic_repositories(tmp_path: Path):
    source = tmp_path / "pb_data"
    mirror = tmp_path / "mirror"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    (source / "storage").mkdir(parents=True)
    with sqlite3.connect(source / "data.db") as db:
        db.execute("CREATE TABLE memories (id TEXT PRIMARY KEY)")
        db.execute("INSERT INTO memories VALUES ('one')")
    password = tmp_path / "restic-password"
    password.write_text("test-only", encoding="utf-8")
    calls = tmp_path / "restic-calls"
    fake_restic = fake_bin / "restic"
    fake_restic.write_text(
        "#!/bin/sh\nprintf '%s|%s\\n' \"$RESTIC_REPOSITORY\" \"$1\" >> \"$FAKE_RESTIC_CALLS\"\n",
        encoding="utf-8",
    )
    fake_restic.chmod(0o700)

    script = REPO_ROOT / "server/ops/backup_pb_data.sh"
    env = os.environ | {
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "PB_DATA_DIR": str(source),
        "MIRROR_DIR": str(mirror),
        "BACKUP_STAMP": str(tmp_path / "success"),
        "LOCK_DIR": str(tmp_path / "backup.lock"),
        "WORK_ROOT": str(tmp_path / "work"),
        "RESTIC_REPOSITORY": str(tmp_path / "local-restic"),
        "RESTIC_SECONDARY_REPOSITORY": str(tmp_path / "offsite-restic"),
        "RESTIC_PASSWORD_FILE": str(password),
        "FAKE_RESTIC_CALLS": str(calls),
    }
    result = subprocess.run(
        ["bash", str(script)], env=env, text=True, capture_output=True, check=False
    )
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "success").is_file()
    rows = calls.read_text(encoding="utf-8").splitlines()
    assert rows == [
        f"{tmp_path / 'local-restic'}|backup",
        f"{tmp_path / 'local-restic'}|forget",
        f"{tmp_path / 'local-restic'}|check",
        f"{tmp_path / 'offsite-restic'}|backup",
        f"{tmp_path / 'offsite-restic'}|forget",
        f"{tmp_path / 'offsite-restic'}|check",
    ]


def test_semantic_runtime_is_locked_and_skips_training_dependencies():
    installer = (REPO_ROOT / "server/ai/install_semantic_model.sh").read_text(
        encoding="utf-8"
    )
    lock = (REPO_ROOT / "server/ai/requirements-semantic.lock.txt").read_text(
        encoding="utf-8"
    )
    assert "requirements-semantic.lock.txt" in installer
    assert "pip install --no-deps" in installer
    assert "torch==2.8.0" in lock
    assert "urllib3==1.26.20" in lock
    assert "datasets==" not in lock
    assert "clip-benchmark==" not in lock
    assert "pycocoevalcap==" not in lock


def test_private_pocketbase_clients_ignore_system_http_proxy():
    memory = (REPO_ROOT / "server/ai/memory_query.py").read_text(encoding="utf-8")
    worker = (REPO_ROOT / "server/ai/semantic_worker.py").read_text(encoding="utf-8")
    assert "httpx.Client(base_url=self.base_url, timeout=30, trust_env=False)" in memory
    assert "httpx.Client(base_url=self.base_url, timeout=30, trust_env=False)" in worker


def test_backup_launch_agent_runs_daily_without_embedded_secrets():
    path = REPO_ROOT / "server/ops/com.bubu.backup.plist.example"
    raw = path.read_text(encoding="utf-8")
    config = plistlib.loads(raw.encode("utf-8"))
    assert config["StartCalendarInterval"] == {"Hour": 3, "Minute": 17}
    assert config["EnvironmentVariables"]["BUBU_BACKUP_CONFIG"]
    assert "run_scheduled_backup.sh" in config["ProgramArguments"][-1]
    assert "RESTIC_PASSWORD=" not in raw


def test_scheduled_backup_runner_rejects_unknown_config_keys(tmp_path: Path):
    config = tmp_path / "backup.env"
    config.write_text("PB_DATA_DIR=/tmp\nEVIL_COMMAND=touch /tmp/nope\n", encoding="utf-8")
    config.chmod(0o600)
    runner = REPO_ROOT / "server/ops/run_scheduled_backup.sh"
    env = os.environ | {"BUBU_BACKUP_CONFIG": str(config)}
    result = subprocess.run(
        ["bash", str(runner)], env=env, text=True, capture_output=True, check=False
    )
    assert result.returncode != 0
    assert "不允许的键" in result.stderr


def test_localhost_ssh_backup_agent_is_noninteractive_and_pinned_to_key():
    path = REPO_ROOT / "server/ops/com.bubu.backup-localhost-ssh.plist.example"
    config = plistlib.loads(path.read_bytes())
    args = config["ProgramArguments"]
    assert args[0] == "/usr/bin/ssh"
    assert "-T" in args
    assert "BatchMode=yes" in args
    assert "IdentitiesOnly=yes" in args
    assert "ConnectTimeout=10" in args
    assert args[-1] == "localhost"


def test_ntfy_is_private_pinned_and_does_not_forward_message_body():
    compose = (REPO_ROOT / "server/ntfy/docker-compose.yml").read_text(
        encoding="utf-8"
    )
    assert (
        "binwiederhier/ntfy:v2.26.3@sha256:"
        "081b53dbb20674fcfe05fdb4eb8af9036a2645ef979543d16f7f80803af467b1"
    ) in compose
    assert "binwiederhier/ntfy:latest" not in compose
    assert "NTFY_AUTH_DEFAULT_ACCESS=deny-all" in compose
    assert 'NTFY_BIND_ADDRESS:-127.0.0.1' in compose
    assert "NTFY_UPSTREAM_BASE_URL=https://ntfy.sh" in compose
    assert "iOS 即时通知只向 ntfy.sh 转发 poll id" in compose
    readme = (REPO_ROOT / "server/ntfy/README.md").read_text(encoding="utf-8")
    assert "https://bubu-ops.leoyuan.top" in readme
    assert "http://<mini的tailscale-ip>:8095" not in readme


def test_runtime_secrets_and_ntfy_cache_are_git_ignored():
    ignore = (REPO_ROOT / "server/.gitignore").read_text(encoding="utf-8")
    for path in ("ntfy/.env", "ntfy/data/", "ops/backup.env"):
        assert path in ignore


def test_pocketbase_uses_tracked_migrations_without_stale_runtime_copy():
    script = (REPO_ROOT / "server/pocketbase/start_pocketbase.sh").read_text(
        encoding="utf-8"
    )
    assert '--migrationsDir="./migrations"' in script
    assert "cp -f migrations/*.js" not in script
    assert "|| true" not in script


def test_backup_failure_notification_contains_no_family_data():
    runner = (REPO_ROOT / "server/ops/run_scheduled_backup.sh").read_text(
        encoding="utf-8"
    )
    assert "PocketBase 自动备份失败，请检查 mini 备份日志。" in runner
    assert "NTFY_TOKEN_FILE" in runner
    assert "PB_DATA_DIR" not in runner.split("--data-binary", 1)[1]


def test_hourly_healthcheck_uses_token_file_not_inline_secret():
    path = REPO_ROOT / "server/ops/com.bubu.healthcheck.plist.example"
    raw = path.read_text(encoding="utf-8")
    config = plistlib.loads(raw.encode("utf-8"))
    assert config["StartInterval"] == 3600
    assert config["RunAtLoad"] is True
    assert config["EnvironmentVariables"]["NTFY_TOKEN_FILE"]
    assert "NTFY_TOKEN</key>" not in raw


def test_restore_drill_checks_files_and_starts_isolated_server(tmp_path: Path):
    backup = tmp_path / "backup"
    storage = backup / "storage/pbc_media/r1"
    storage.mkdir(parents=True)
    (storage / "photo.jpg").write_bytes(b"photo-bytes")
    database = backup / "data.db"
    fields = json.dumps([{"name": "file", "type": "file"}])
    with sqlite3.connect(database) as db:
        db.execute(
            "CREATE TABLE _collections (id TEXT, system INTEGER, name TEXT, fields TEXT)"
        )
        for collection_id, name, schema in (
            ("pbc_entries", "entries", "CREATE TABLE entries (id TEXT, isDeleted INTEGER)"),
            (
                "pbc_media",
                "media",
                "CREATE TABLE media (id TEXT, file TEXT, isDeleted INTEGER)",
            ),
            (
                "pbc_growth",
                "growthmeasurements",
                "CREATE TABLE growthmeasurements (id TEXT, isDeleted INTEGER)",
            ),
            (
                "pbc_health",
                "healthrecords",
                "CREATE TABLE healthrecords (id TEXT, isDeleted INTEGER)",
            ),
        ):
            db.execute(schema)
            db.execute(
                "INSERT INTO _collections VALUES (?, 0, ?, ?)",
                (collection_id, name, fields if name == "media" else "[]"),
            )
        db.execute("INSERT INTO entries VALUES ('e1', 0)")
        db.execute("INSERT INTO media VALUES ('r1', 'photo.jpg', 0)")

    digest = hashlib.sha256(database.read_bytes()).hexdigest()
    (backup / "backup-manifest.json").write_text(
        json.dumps(
            {
                "completedAtUTC": "test",
                "databases": {
                    "data.db": {"bytes": database.stat().st_size, "sha256": digest}
                },
            }
        ),
        encoding="utf-8",
    )

    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    fake_pb = tmp_path / "pocketbase"
    fake_pb.write_text(
        """#!/usr/bin/env python3
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200 if self.path == '/api/health' else 404)
        self.end_headers()
    def log_message(self, *args):
        pass
HTTPServer(('127.0.0.1', int(os.environ['RESTORE_DRILL_FAKE_PORT'])), Handler).serve_forever()
""",
        encoding="utf-8",
    )
    fake_pb.chmod(0o700)
    script = REPO_ROOT / "server/ops/restore-drill.sh"
    env = os.environ | {
        "POCKETBASE_BIN": str(fake_pb),
        "RESTORE_DRILL_PORT": str(port),
        "RESTORE_DRILL_FAKE_PORT": str(port),
    }
    result = subprocess.run(
        ["bash", str(script), str(backup)],
        env=env,
        text=True,
        capture_output=True,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "RESTORE_DRILL_OK" in result.stdout
    assert "files=1" in result.stdout


def test_tracked_duplicate_review_was_removed():
    assert not (REPO_ROOT / "REVIEW_2026-07-12 2.md").exists()
    assert (REPO_ROOT / "REVIEW_2026-07-12.md").exists()


def test_ai_launcher_uses_relocatable_python_module():
    launcher = (REPO_ROOT / "server/ai/start_ai.sh").read_text(encoding="utf-8")

    assert "./.venv/bin/python -m uvicorn" in launcher
    assert "exec ./.venv/bin/uvicorn" not in launcher


def test_weekly_report_runs_after_the_natural_week_has_finished():
    schedule = (REPO_ROOT / "server/ops/com.bubu.weekly-report.plist.example").read_text(
        encoding="utf-8"
    )

    assert "<key>Weekday</key><integer>2</integer>" in schedule
    assert "<key>Hour</key><integer>0</integer>" in schedule


def test_semantic_worker_does_not_persist_protected_file_tokens_in_http_logs():
    worker = (REPO_ROOT / "server/ai/semantic_worker.py").read_text(encoding="utf-8")

    assert 'logging.getLogger("httpx").setLevel(logging.WARNING)' in worker
    assert 'logging.getLogger("httpcore").setLevel(logging.WARNING)' in worker


def test_semantic_queue_is_append_only_and_ignores_audio():
    hook = (REPO_ROOT / "server/pocketbase/pb_hooks/semantic_queue.pb.js").read_text(
        encoding="utf-8"
    )

    assert '$security.randomString(8)' in hook
    assert 'findFirstRecordByFilter' not in hook
    assert 'mediaType !== "photo" && mediaType !== "video"' in hook
