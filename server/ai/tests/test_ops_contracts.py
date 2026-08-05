from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


def test_automation_collections_are_service_only():
    migration = (
        REPO_ROOT
        / "server/pocketbase/migrations/1700000011_add_automation_collections.js"
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
