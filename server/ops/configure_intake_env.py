#!/usr/bin/env python3
"""Configure reliable intake secrets without printing or committing them."""
from __future__ import annotations

import argparse
import os
import secrets
import shlex
import sqlite3
from pathlib import Path


def parse_env(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        result[key.strip()] = value.strip().strip("\"").strip("'")
    return result


def update_env(text: str, updates: dict[str, str]) -> str:
    remaining = dict(updates)
    lines: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and "=" in stripped:
            key = stripped.split("=", 1)[0].strip()
            if key in remaining:
                lines.append(f"{key}={shlex.quote(remaining.pop(key))}")
                continue
        lines.append(line)
    if remaining:
        lines += ["", "# Reliable confirmed-media intake (managed locally; do not commit)"]
        lines += [f"{key}={shlex.quote(value)}" for key, value in remaining.items()]
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, type=Path)
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--public-base", required=True)
    parser.add_argument("--staging-root", required=True, type=Path)
    parser.add_argument("--inbox-root", type=Path)
    parser.add_argument(
        "--allowed-pb-user-id", action="append", required=True,
        help="Explicit verified family user id; repeat for each intended account",
    )
    args = parser.parse_args()

    env_path = args.env.expanduser().resolve()
    database = args.database.expanduser().resolve()
    if not env_path.is_file() or not database.is_file():
        raise SystemExit("environment or PocketBase database is missing")
    original = env_path.read_text(encoding="utf-8")
    current = parse_env(original)
    family_id = (
        current.get("INTAKE_FAMILY_ID")
        or current.get("SEMANTIC_FAMILY_ID")
        or current.get("WEEKLY_REPORT_FAMILY_ID")
    )
    if not family_id:
        raise SystemExit("no server-bound family id is configured")
    requested_ids = sorted(set(args.allowed_pb_user_id))
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as db:
        rows = db.execute(
            "SELECT id,verified FROM users WHERE id IN (%s)" % ",".join("?" for _ in requested_ids),
            requested_ids,
        ).fetchall()
    verified_ids = sorted(str(row[0]) for row in rows if bool(row[1]))
    if verified_ids != requested_ids:
        raise SystemExit("every allowed PocketBase user must exist and be verified")

    staging = args.staging_root.expanduser().resolve()
    staging.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(staging, 0o700)
    updates = {
        "AI_ALLOWED_PB_USER_IDS": ",".join(verified_ids),
        "INTAKE_ALLOWED_PB_USER_IDS": ",".join(verified_ids),
        "INTAKE_FAMILY_ID": family_id,
        "INTAKE_PUBLIC_BASE_URL": args.public_base.rstrip("/"),
        "INTAKE_STAGING_ROOT": str(staging),
        "INTAKE_UPLOAD_SECRET": current.get("INTAKE_UPLOAD_SECRET") or secrets.token_hex(32),
        "INTAKE_COMMIT_KEY": current.get("INTAKE_COMMIT_KEY") or secrets.token_hex(32),
        "INTAKE_MIN_FREE_BYTES": current.get("INTAKE_MIN_FREE_BYTES") or str(10 * 1024**3),
        "INTAKE_MAX_UPLOAD_BYTES": current.get("INTAKE_MAX_UPLOAD_BYTES") or str(2 * 1024**3),
        "INTAKE_SSD_SCAN_BUDGET_BYTES": current.get("INTAKE_SSD_SCAN_BUDGET_BYTES") or str(8 * 1024**3),
    }
    if args.inbox_root:
        inbox = args.inbox_root.expanduser().resolve()
        inbox.mkdir(parents=True, exist_ok=True, mode=0o750)
        updates["BUBU_INBOX_ROOT"] = str(inbox)
    temporary = env_path.with_name(env_path.name + ".next")
    temporary.write_text(update_env(original, updates), encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, env_path)
    os.chmod(env_path, 0o600)
    print(f"INTAKE_ENV_CONFIGURED allowed_users={len(verified_ids)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
