#!/usr/bin/env python3
"""One-shot launchd entrypoint for the configured read-only Bubu Inbox."""
from __future__ import annotations

import json
import os
from pathlib import Path

from intake_staging import IntakeStagingStore
from memory_query import PocketBaseMemoryStore
from ssd_intake import SSDIntakeScanner


def main() -> int:
    source = os.environ.get("BUBU_INBOX_ROOT", "").strip()
    family = os.environ.get("INTAKE_FAMILY_ID", "").strip()
    if not source or not family:
        print("SSD_INTAKE_SKIPPED missing_configuration")
        return 0
    staging = IntakeStagingStore()
    existing_hashes = set()
    try:
        with PocketBaseMemoryStore() as pocketbase:
            records = pocketbase.list_records(
                "media", filter_value="contentHash!=''", sort="created", per_page=500
            )
        existing_hashes = {
            str(record.get("contentHash") or "") for record in records
            if record.get("contentHash")
        }
    except Exception as exc:
        # 事实 hash 读不到时宁可整次延期，不冒跨来源重复入库风险。
        # 只记录错误类型，不输出凭证、URL 或家庭数据。
        print("SSD_INTAKE_HASH_LOOKUP_DEFERRED " + type(exc).__name__)
        return 1
    batches = SSDIntakeScanner(Path(source), staging).stage_candidates(
        family, existing_hashes=existing_hashes
    )
    cleaned = staging.cleanup()
    print(json.dumps({"status": "ok", "candidate_batches": len(batches), "cleaned": cleaned}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
