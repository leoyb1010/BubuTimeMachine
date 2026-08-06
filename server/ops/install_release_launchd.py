#!/usr/bin/env python3
"""Atomically render release launchd jobs; secrets remain in the 0600 AI env."""
from __future__ import annotations

import argparse
import os
import plistlib
import shutil
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-root", required=True, type=Path)
    parser.add_argument("--release-root", required=True, type=Path)
    parser.add_argument("--launch-agents", required=True, type=Path)
    parser.add_argument("--backup-dir", required=True, type=Path)
    args = parser.parse_args()

    server = args.server_root.expanduser().resolve()
    release = args.release_root.expanduser().resolve()
    agents = args.launch_agents.expanduser().resolve()
    backup = args.backup_dir.expanduser().resolve()
    expected_parent = (server / "releases").resolve()
    if release.parent != expected_parent:
        raise SystemExit("release root must be a direct child of server/releases")
    ai = release / "server/ai"
    pocketbase = release / "server/pocketbase"
    required = [
        ai / "start_ai.sh", ai / "start_semantic_worker.sh",
        ai / "start_weekly_report.sh", ai / "start_ssd_intake.sh",
        ai / ".env", pocketbase / "start_pocketbase.sh",
        server / "pocketbase/pocketbase", server / "pocketbase/pb_data/data.db",
    ]
    if any(not path.exists() for path in required):
        raise SystemExit("release is missing a required runtime file")
    agents.mkdir(parents=True, exist_ok=True)
    backup.mkdir(parents=True, exist_ok=True, mode=0o700)
    logs = server / "logs"
    logs.mkdir(parents=True, exist_ok=True)

    jobs = {
        "top.leoyuan.bubu.pocketbase": {
            "Label": "top.leoyuan.bubu.pocketbase",
            "ProgramArguments": [
                str(pocketbase / "start_pocketbase.sh"),
                str(server / "pocketbase/pb_data"),
            ],
            "EnvironmentVariables": {
                "PB_BIN": str(server / "pocketbase/pocketbase"),
                "PB_HTTP_ADDR": "0.0.0.0:8090",
                "PB_MIGRATIONS_DIR": "./migrations",
                "PB_HOOKS_DIR": "./pb_hooks",
                "BUBU_SERVER_ENV_FILE": str(ai / ".env"),
            },
            "WorkingDirectory": str(pocketbase),
            "RunAtLoad": True,
            "KeepAlive": True,
            "StandardOutPath": str(logs / "pocketbase.out.log"),
            "StandardErrorPath": str(logs / "pocketbase.err.log"),
        },
        "top.leoyuan.bubu.ai": keep_alive_job(
            "top.leoyuan.bubu.ai", ai / "start_ai.sh", ai,
            logs / "ai.out.log", logs / "ai.err.log"),
        "top.leoyuan.bubu.semantic-worker": keep_alive_job(
            "top.leoyuan.bubu.semantic-worker", ai / "start_semantic_worker.sh", ai,
            logs / "semantic-worker.out.log", logs / "semantic-worker.err.log"),
        "top.leoyuan.bubu.weekly-report": {
            "Label": "top.leoyuan.bubu.weekly-report",
            "ProgramArguments": [str(ai / "start_weekly_report.sh")],
            "WorkingDirectory": str(ai),
            "ProcessType": "Background",
            "StartCalendarInterval": {"Weekday": 2, "Hour": 0, "Minute": 5},
            "StandardOutPath": str(logs / "weekly-report.out.log"),
            "StandardErrorPath": str(logs / "weekly-report.err.log"),
        },
        "top.leoyuan.bubu.ssd-intake": {
            "Label": "top.leoyuan.bubu.ssd-intake",
            "ProgramArguments": [str(ai / "start_ssd_intake.sh")],
            "WorkingDirectory": str(ai),
            "ProcessType": "Background",
            "RunAtLoad": True,
            "StartInterval": 900,
            "StandardOutPath": str(logs / "ssd-intake.log"),
            "StandardErrorPath": str(logs / "ssd-intake-error.log"),
        },
    }
    for label, payload in jobs.items():
        target = agents / f"{label}.plist"
        if target.exists():
            shutil.copy2(target, backup / target.name)
        temporary = target.with_suffix(".plist.next")
        with temporary.open("wb") as handle:
            plistlib.dump(payload, handle, fmt=plistlib.FMT_XML, sort_keys=False)
        # LaunchAgents contains paths only (no secrets) and launchd rejects user plists
        # that are not conventionally readable on this host with Bootstrap I/O error.
        os.chmod(temporary, 0o644)
        os.replace(temporary, target)
    print("LAUNCHD_RELEASE_RENDERED " + " ".join(sorted(jobs)))
    return 0


def keep_alive_job(
    label: str, program: Path, working: Path, stdout: Path, stderr: Path
) -> dict:
    return {
        "Label": label,
        "ProgramArguments": [str(program)],
        "WorkingDirectory": str(working),
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 10,
        "StandardOutPath": str(stdout),
        "StandardErrorPath": str(stderr),
    }


if __name__ == "__main__":
    raise SystemExit(main())
