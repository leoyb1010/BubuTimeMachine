"""每周一零点后由 launchd 调用，按家庭时区幂等生成刚结束的一周周报。"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timezone

import httpx

from llm import LLMClient
from memory_query import PocketBaseMemoryStore
from weekly_report import WeeklyReportService, WeeklyReportUnavailable, previous_complete_week


def notify_ready(report_id: str) -> None:
    url = os.environ.get("WEEKLY_REPORT_NTFY_URL", "").strip()
    if not url:
        return
    token = os.environ.get("WEEKLY_REPORT_NTFY_TOKEN", "").strip()
    headers = {
        "Title": "家庭周报写好了",
        "Tags": "newspaper",
        "X-Bubu-Artifact": report_id,
    }
    if token:
        headers["Authorization"] = "Bearer %s" % token
    # 不发送家庭正文、姓名、生日或来源摘要，通知只说明有新派生产物。
    response = httpx.post(url, content="新一周的家庭周报已经生成，请在 App 内查看。",
                          headers=headers, timeout=15)
    response.raise_for_status()


def main() -> int:
    family_id = os.environ.get("WEEKLY_REPORT_FAMILY_ID", "").strip()
    child_name = os.environ.get("WEEKLY_REPORT_CHILD_NAME", "布布").strip() or "布布"
    if not family_id:
        print("WEEKLY_REPORT_FAILED missing_family_binding", file=sys.stderr)
        return 2
    window = previous_complete_week()
    artifact_key = "weekly_report:%s:%s" % (family_id, window.key)
    try:
        with PocketBaseMemoryStore() as store:
            existing = store.find_artifact(artifact_key)
            existed = existing is not None
            report = WeeklyReportService(store, LLMClient()).generate(
                family_id, child_name, window
            )
            stored = store.find_artifact(artifact_key) or existing or {}
            if not stored.get("notifiedAt"):
                notify_ready(report["id"])
                store.mark_artifact_notified(
                    report["id"], datetime.now(timezone.utc).isoformat()
                )
        print("WEEKLY_REPORT_OK id=%s existing=%s" % (report["id"], existed))
        return 0
    except WeeklyReportUnavailable as exc:
        # 材料不足是正常状态，不制造空周报，也不触发告警重试风暴。
        print("WEEKLY_REPORT_SKIPPED reason=%s" % type(exc).__name__)
        return 0
    except Exception as exc:  # noqa: BLE001
        print("WEEKLY_REPORT_FAILED type=%s" % type(exc).__name__, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
