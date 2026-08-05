"""历史图库/模型升级语义任务核对器。

默认只预览；显式 --enqueue 才写 automation_jobs，且绝不修改 entries/media 事实记录。
任务键同时包含媒体、Entry 与模型版本，重复运行幂等，正文修改也会触发重建。
"""
from __future__ import annotations

import argparse
import hashlib
import os
import time
from typing import Any

from semantic_worker import PocketBaseWorkerClient, iso_now


def list_all(client: PocketBaseWorkerClient, collection: str) -> list[dict[str, Any]]:
    page = 1
    result: list[dict[str, Any]] = []
    while True:
        response = client._request(  # 同一服务进程内的受控 superuser 客户端
            "GET", f"/api/collections/{collection}/records",
            params={"page": page, "perPage": 200},
        ).json()
        result.extend(response.get("items", []))
        if page >= int(response.get("totalPages") or 1):
            return result
        page += 1


def reconcile(client: PocketBaseWorkerClient, enqueue: bool, force: bool = False) -> tuple[int, int]:
    model_version = os.environ.get(
        "SEMANTIC_MODEL_VERSION", "mobileclip-s0-datacompdr-1b"
    )
    entries = {
        str(item.get("localId") or ""): item
        for item in list_all(client, "entries")
    }
    planned = created = 0
    jobs_collection = "automation_jobs"
    for media in list_all(client, "media"):
        if media.get("mediaType") not in {"photo", "video"}:
            continue
        entry = entries.get(str(media.get("entryLocalId") or ""), {})
        source_revision = "|".join([
            str(media.get("clientUpdatedAt") or media.get("updated") or ""),
            str(bool(media.get("isDeleted"))),
            str(entry.get("clientUpdatedAt") or entry.get("updated") or ""),
            str(bool(entry.get("isDeleted"))),
            model_version,
        ])
        digest = hashlib.sha256(source_revision.encode("utf-8")).hexdigest()[:20]
        suffix = f":force:{time.time_ns()}" if force else ""
        job_key = f"semantic_reconcile:{media['id']}:{digest}{suffix}"
        planned += 1
        if not enqueue:
            continue
        existing = client._request(
            "GET", f"/api/collections/{jobs_collection}/records",
            params={"page": 1, "perPage": 1, "filter": f"jobKey='{job_key}'"},
        ).json().get("items", [])
        if existing:
            continue
        deleted = bool(media.get("isDeleted")) or bool(entry.get("isDeleted"))
        client._request(
            "POST", f"/api/collections/{jobs_collection}/records",
            json={
                "jobKey": job_key,
                "kind": "semantic_media_delete" if deleted else "semantic_media_upsert",
                "sourceCollection": "media",
                "sourceRecordId": media["id"],
                "sourceLocalId": media.get("localId", ""),
                "familyId": media.get("familyId", ""),
                "state": "queued",
                "attempts": 0,
                "availableAt": iso_now(),
                "modelVersion": model_version,
                "payload": {"reason": "reconcile"},
            },
        )
        created += 1
    return planned, created


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--enqueue", action="store_true", help="确认创建派生任务")
    parser.add_argument("--force", action="store_true", help="索引丢失/损坏后强制全量重建")
    args = parser.parse_args()
    client = PocketBaseWorkerClient()
    try:
        planned, created = reconcile(client, enqueue=args.enqueue, force=args.force)
    finally:
        client.close()
    mode = "已创建" if args.enqueue else "仅预览"
    print(f"{mode}: 扫描 {planned} 个照片/视频，新增任务 {created}")


if __name__ == "__main__":
    main()
