"""家庭事实查询层。

所有周报、声音年轮等派生能力只能从这里读取事实，并且必须保留可回查的来源引用。
本模块只读业务集合；写入仅允许落到可重建的 ``derived_artifacts``。
"""
from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any, Iterable, Optional

import httpx


UTC = timezone.utc


@dataclass(frozen=True)
class MemoryEvidence:
    source_id: str
    collection: str
    record_id: str
    local_id: str
    happened_at: str
    title: str
    excerpt: str
    kind: str

    def public(self) -> dict[str, str]:
        return asdict(self)


class PocketBaseMemoryStore:
    """使用服务账户读取 PocketBase，家庭客户端无法直接访问派生产物。"""

    def __init__(self) -> None:
        self.base_url = os.environ.get("PB_BASE_URL", "http://127.0.0.1:8090").rstrip("/")
        self.api_token = os.environ.get("PB_WORKER_TOKEN", "").strip()
        self.identity = os.environ.get("PB_WORKER_EMAIL", "").strip()
        self.password = os.environ.get("PB_WORKER_PASSWORD", "")
        self._token = self.api_token
        self._client = httpx.Client(base_url=self.base_url, timeout=30)

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "PocketBaseMemoryStore":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _headers(self) -> dict[str, str]:
        if not self._token:
            self.authenticate()
        return {"Authorization": self._token}

    def authenticate(self) -> None:
        if self.api_token:
            self._token = self.api_token
            return
        if not self.identity or not self.password:
            raise RuntimeError("缺少 PB_WORKER_TOKEN 或 PB_WORKER_EMAIL / PB_WORKER_PASSWORD")
        response = self._client.post(
            "/api/collections/_superusers/auth-with-password",
            json={"identity": self.identity, "password": self.password},
        )
        response.raise_for_status()
        self._token = str(response.json().get("token") or "")
        if not self._token:
            raise RuntimeError("PocketBase 服务账户认证响应异常")

    def request(self, method: str, path: str, **kwargs: Any) -> httpx.Response:
        response = self._client.request(method, path, headers=self._headers(), **kwargs)
        if response.status_code == 401 and not self.api_token:
            self._token = ""
            response = self._client.request(method, path, headers=self._headers(), **kwargs)
        response.raise_for_status()
        return response

    def list_records(
        self,
        collection: str,
        *,
        filter_value: str,
        sort: str,
        per_page: int = 200,
    ) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        page = 1
        while True:
            payload = self.request(
                "GET",
                "/api/collections/%s/records" % collection,
                params={
                    "page": page,
                    "perPage": min(max(per_page, 1), 500),
                    "sort": sort,
                    "filter": filter_value,
                },
            ).json()
            result.extend(payload.get("items", []))
            if page >= int(payload.get("totalPages") or 1):
                break
            page += 1
        return result

    def find_artifact(self, artifact_key: str) -> Optional[dict[str, Any]]:
        safe_key = _pb_quote(artifact_key)
        return self.first_record(
            "derived_artifacts",
            filter_value="artifactKey='%s'" % safe_key,
            sort="-generatedAt",
        )

    def latest_artifact(self, family_id: str, kind: str) -> Optional[dict[str, Any]]:
        filter_value = "familyId='%s' && kind='%s'" % (
            _pb_quote(family_id), _pb_quote(kind)
        )
        return self.first_record(
            "derived_artifacts", filter_value=filter_value,
            sort="-generatedAt",
        )

    def recent_artifacts(
        self, family_id: str, kind: str, limit: int = 52
    ) -> list[dict[str, Any]]:
        filter_value = "familyId='%s' && kind='%s'" % (
            _pb_quote(family_id), _pb_quote(kind)
        )
        payload = self.request(
            "GET",
            "/api/collections/derived_artifacts/records",
            params={
                "page": 1,
                "perPage": min(max(limit, 1), 100),
                "sort": "-generatedAt",
                "filter": filter_value,
            },
        ).json()
        return payload.get("items", [])

    def first_record(
        self, collection: str, *, filter_value: str, sort: str
    ) -> Optional[dict[str, Any]]:
        payload = self.request(
            "GET",
            "/api/collections/%s/records" % collection,
            params={"page": 1, "perPage": 1, "sort": sort, "filter": filter_value},
        ).json()
        items = payload.get("items", [])
        return items[0] if items else None

    def create_artifact(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request(
            "POST", "/api/collections/derived_artifacts/records", json=payload
        ).json()

    def get_artifact(self, artifact_id: str) -> dict[str, Any]:
        if not artifact_id.isalnum():
            raise ValueError("派生产物 id 格式非法")
        return self.request(
            "GET", "/api/collections/derived_artifacts/records/%s" % artifact_id
        ).json()

    def archive_artifact(self, artifact_id: str) -> dict[str, Any]:
        if not artifact_id.isalnum():
            raise ValueError("派生产物 id 格式非法")
        return self.request(
            "PATCH", "/api/collections/derived_artifacts/records/%s" % artifact_id,
            json={"status": "archived"},
        ).json()

    def mark_artifact_notified(self, artifact_id: str, notified_at: str) -> dict[str, Any]:
        if not artifact_id.isalnum():
            raise ValueError("派生产物 id 格式非法")
        return self.request(
            "PATCH", "/api/collections/derived_artifacts/records/%s" % artifact_id,
            json={"notifiedAt": notified_at},
        ).json()


class MemoryQuery:
    """第二个 AI 消费者开始共用的事实查询入口。"""

    def __init__(self, store: PocketBaseMemoryStore) -> None:
        self.store = store

    def weekly_evidence(
        self, family_id: str, start: datetime, end: datetime
    ) -> list[MemoryEvidence]:
        if not family_id.strip():
            raise ValueError("family_id 不能为空")
        if end <= start:
            raise ValueError("周报时间范围无效")
        family = _pb_quote(family_id)
        start_text = _pb_date(start)
        end_text = _pb_date(end)
        evidence: list[MemoryEvidence] = []

        evidence.extend(self._entries(family, start_text, end_text))
        evidence.extend(self._health(family, start_text, end_text))
        evidence.extend(self._growth(family, start_text, end_text))
        evidence.extend(self._milestones(family, start_text, end_text))
        evidence.extend(self._voice_memos(family, start_text, end_text))
        # 一周资料也要有确定性上限，避免整批健康/原声文本被无界发送给 LLM。
        caps = {
            "entries": 24,
            "healthrecords": 12,
            "growthmeasurements": 8,
            "milestones": 8,
            "voicememos": 8,
        }
        limited: list[MemoryEvidence] = []
        for collection, cap in caps.items():
            limited.extend(
                [item for item in evidence if item.collection == collection][:cap]
            )
        return sorted(limited, key=lambda item: (item.happened_at, item.source_id))

    def _range_filter(self, family: str, field: str, start: str, end: str) -> str:
        return (
            "familyId='%s' && isDeleted=false && %s>='%s' && %s<'%s'"
            % (family, field, start, field, end)
        )

    def _entries(self, family: str, start: str, end: str) -> Iterable[MemoryEvidence]:
        records = self.store.list_records(
            "entries",
            filter_value=self._range_filter(family, "happenedAt", start, end)
            + " && isArchived=false",
            sort="happenedAt",
        )
        for item in records:
            text = _join_text(item.get("note"), item.get("firstPersonNote"))
            title = _text(item.get("title")) or "一段时光"
            if not text and not title:
                continue
            yield _evidence("entries", item, "happenedAt", title, text, "moment")

    def _health(self, family: str, start: str, end: str) -> Iterable[MemoryEvidence]:
        records = self.store.list_records(
            "healthrecords",
            filter_value=self._range_filter(family, "recordedAt", start, end),
            sort="recordedAt",
        )
        for item in records:
            title = _text(item.get("title")) or "照护记录"
            excerpt = _join_text(item.get("amountText"), item.get("detail"))
            yield _evidence(
                "healthrecords", item, "recordedAt", title, excerpt,
                _text(item.get("kind")) or "care",
            )

    def _growth(self, family: str, start: str, end: str) -> Iterable[MemoryEvidence]:
        records = self.store.list_records(
            "growthmeasurements",
            filter_value=self._range_filter(family, "measuredAt", start, end),
            sort="measuredAt",
        )
        for item in records:
            values = []
            if item.get("heightCm") is not None:
                values.append("身高 %scm" % _number(item["heightCm"]))
            if item.get("weightKg") is not None:
                values.append("体重 %skg" % _number(item["weightKg"]))
            if item.get("headCircumferenceCm") is not None:
                values.append("头围 %scm" % _number(item["headCircumferenceCm"]))
            if not values:
                continue
            yield _evidence(
                "growthmeasurements", item, "measuredAt", "成长测量",
                "，".join(values), "growth",
            )

    def _milestones(self, family: str, start: str, end: str) -> Iterable[MemoryEvidence]:
        records = self.store.list_records(
            "milestones",
            filter_value=self._range_filter(family, "happenedAt", start, end),
            sort="happenedAt",
        )
        for item in records:
            title = _text(item.get("title")) or "里程碑"
            yield _evidence(
                "milestones", item, "happenedAt", title,
                _join_text(item.get("detail"), item.get("ageDescription")), "milestone",
            )

    def _voice_memos(self, family: str, start: str, end: str) -> Iterable[MemoryEvidence]:
        records = self.store.list_records(
            "voicememos",
            filter_value=self._range_filter(family, "recordedAt", start, end),
            sort="recordedAt",
        )
        for item in records:
            transcript = _text(item.get("transcript"))
            if not transcript:
                continue
            yield _evidence(
                "voicememos", item, "recordedAt",
                _text(item.get("title")) or "一段原声", transcript, "voice",
            )


def _evidence(
    collection: str, item: dict[str, Any], date_field: str,
    title: str, excerpt: str, kind: str,
) -> MemoryEvidence:
    record_id = _text(item.get("id"))
    local_id = _text(item.get("localId"))
    return MemoryEvidence(
        source_id="%s:%s" % (collection, local_id or record_id),
        collection=collection,
        record_id=record_id,
        local_id=local_id,
        happened_at=_text(item.get(date_field)),
        title=title[:120],
        excerpt=excerpt[:400],
        kind=kind[:40],
    )


def _text(value: Any) -> str:
    return str(value or "").strip()


def _join_text(*values: Any) -> str:
    return "；".join(_text(value) for value in values if _text(value))


def _number(value: Any) -> str:
    number = float(value)
    return str(int(number)) if number.is_integer() else ("%.1f" % number)


def _pb_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def _pb_date(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).isoformat()
