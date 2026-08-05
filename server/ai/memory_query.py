"""家庭事实查询层。

所有周报、声音年轮等派生能力只能从这里读取事实，并且必须保留可回查的来源引用。
本模块只读业务集合；写入仅允许落到可重建的 ``derived_artifacts``。
"""
from __future__ import annotations

import os
import logging
import hashlib
import json
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

import httpx


UTC = timezone.utc
# httpx 的 INFO 日志会打印完整 URL；protected file token 位于 query，绝不能落日志。
logging.getLogger("httpx").setLevel(logging.WARNING)


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


@dataclass(frozen=True)
class SoundRingMaterial:
    voice: MemoryEvidence
    file_name: str
    duration_seconds: float
    age_years: int
    kind: str
    source_updated_at: str = ""
    related_entry: Optional[MemoryEvidence] = None


def sound_source_revision(record: dict[str, Any]) -> str:
    """返回可复算的原声修订标识；兼容旧集合没有系统 updated 的记录。"""
    explicit = _text(record.get("updated") or record.get("clientUpdatedAt"))
    if explicit:
        return explicit
    fields = {
        key: record.get(key)
        for key in (
            "familyId", "localId", "isDeleted", "file", "durationSeconds",
            "recordedAt", "ageYears", "kind", "title", "transcript",
        )
    }
    encoded = json.dumps(fields, ensure_ascii=False, sort_keys=True, default=str)
    return "fallback:" + hashlib.sha256(encoded.encode("utf-8")).hexdigest()


class PocketBaseMemoryStore:
    """使用服务账户读取 PocketBase，家庭客户端无法直接访问派生产物。"""

    def __init__(self) -> None:
        self.base_url = os.environ.get("PB_BASE_URL", "http://127.0.0.1:8090").rstrip("/")
        self.api_token = os.environ.get("PB_WORKER_TOKEN", "").strip()
        self.identity = os.environ.get("PB_WORKER_EMAIL", "").strip()
        self.password = os.environ.get("PB_WORKER_PASSWORD", "")
        self._token = self.api_token
        self._file_token_value = ""
        # PocketBase 永远是本机/家庭内服务；不得被系统 HTTP_PROXY 转发到代理进程。
        self._client = httpx.Client(base_url=self.base_url, timeout=30, trust_env=False)

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

    def update_artifact(
        self, artifact_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        if not artifact_id.isalnum():
            raise ValueError("派生产物 id 格式非法")
        return self.request(
            "PATCH", "/api/collections/derived_artifacts/records/%s" % artifact_id,
            json=payload,
        ).json()

    def upload_artifact_file(
        self, artifact_id: str, file_path: str, file_name: str
    ) -> dict[str, Any]:
        if not artifact_id.isalnum():
            raise ValueError("派生产物 id 格式非法")
        path = Path(file_path)
        if not path.is_file():
            raise FileNotFoundError(file_path)
        with path.open("rb") as handle:
            return self.request(
                "PATCH",
                "/api/collections/derived_artifacts/records/%s" % artifact_id,
                files={"file": (file_name, handle, "audio/mp4")},
            ).json()

    def download_record_file(
        self,
        collection: str,
        record_id: str,
        file_name: str,
        destination: str,
        *,
        max_bytes: int = 110 * 1024 * 1024,
    ) -> None:
        if not record_id.isalnum() or not file_name or "/" in file_name or "\\" in file_name:
            raise ValueError("媒体文件引用格式非法")
        response = self._protected_file_response(
            "/api/files/%s/%s/%s" % (collection, record_id, file_name)
        )
        data = response.content
        if not data or len(data) > max_bytes:
            raise RuntimeError("媒体文件为空或超过安全上限")
        Path(destination).write_bytes(data)

    def artifact_file_response(self, artifact_id: str, file_name: str) -> httpx.Response:
        if not artifact_id.isalnum() or not file_name or "/" in file_name or "\\" in file_name:
            raise ValueError("作品文件引用格式非法")
        return self._protected_file_response(
            "/api/files/derived_artifacts/%s/%s" % (artifact_id, file_name)
        )

    def protected_file_token(self) -> str:
        if self._file_token_value:
            return self._file_token_value
        response = self.request("POST", "/api/files/token")
        token = str(response.json().get("token") or "")
        if not token:
            raise RuntimeError("PocketBase 未返回受保护文件令牌")
        self._file_token_value = token
        return token

    def _protected_file_response(self, path: str) -> httpx.Response:
        try:
            return self.request(
                "GET", path, params={"token": self.protected_file_token()}
            )
        except httpx.HTTPStatusError as exc:
            # 受保护文件 token 是短时效令牌。长音频章在第 N 段下载时可能刚好过期；
            # PocketBase 对无效 token 通常回 404，刷新一次后仍失败才按真实缺文件处理。
            if exc.response.status_code not in {401, 403, 404}:
                raise RuntimeError(
                    "受保护文件读取失败（%d）" % exc.response.status_code
                ) from None
            self._file_token_value = ""
            try:
                return self.request(
                    "GET", path, params={"token": self.protected_file_token()}
                )
            except httpx.HTTPStatusError as retry_exc:
                raise RuntimeError(
                    "受保护文件读取失败（%d）" % retry_exc.response.status_code
                ) from None

    def get_artifact(self, artifact_id: str) -> dict[str, Any]:
        if not artifact_id.isalnum():
            raise ValueError("派生产物 id 格式非法")
        return self.request(
            "GET", "/api/collections/derived_artifacts/records/%s" % artifact_id
        ).json()

    def get_record(self, collection: str, record_id: str) -> dict[str, Any]:
        if not collection.replace("_", "").isalnum() or not record_id.isalnum():
            raise ValueError("记录引用格式非法")
        return self.request(
            "GET", "/api/collections/%s/records/%s" % (collection, record_id)
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
        family = _pb_quote(fact_family_value(family_id))
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

    def sound_ring_materials(self, family_id: str) -> list[SoundRingMaterial]:
        """读取可渲染原声，并给每段声音配一条 14 天内最近的照片时光引用。

        音频二进制不进入派生 payload；这里只保留 PocketBase 受保护文件名，真正
        渲染时再由服务账户下载。关联照片也只返回原 Entry 引用，App 用本地副本展示。
        """
        if not family_id.strip():
            raise ValueError("family_id 不能为空")
        family = _pb_quote(fact_family_value(family_id))
        voice_records = self.store.list_records(
            "voicememos",
            filter_value="familyId='%s' && isDeleted=false && file!=''" % family,
            sort="recordedAt",
        )
        if not voice_records:
            return []

        valid: list[tuple[dict[str, Any], datetime, str, float, int, str, str, MemoryEvidence]] = []
        for item in voice_records:
            record_id = _text(item.get("id"))
            local_id = _text(item.get("localId"))
            file_name = _single_file_name(item.get("file"))
            recorded_at = _parse_date(item.get("recordedAt"))
            if not record_id or not local_id or not file_name or recorded_at is None:
                continue
            try:
                duration = float(item.get("durationSeconds") or 0)
                age_years = max(0, int(float(item.get("ageYears") or 0)))
            except (TypeError, ValueError):
                continue
            if duration <= 0:
                continue
            kind = _text(item.get("kind")) or "childVoice"
            title = "布布的声音" if kind == "childVoice" else "家人对她说"
            transcript = _text(item.get("transcript"))
            voice = _evidence(
                "voicememos", item, "recordedAt", title,
                transcript or "原声未转写", "voice",
            )
            source_updated_at = sound_source_revision(item)
            valid.append((
                item, recorded_at, file_name, duration, age_years, kind,
                source_updated_at, voice,
            ))
        if not valid:
            return []

        first_voice = min(item[1] for item in valid) - timedelta(days=14)
        last_voice = max(item[1] for item in valid) + timedelta(days=14, seconds=1)
        entry_records = self.store.list_records(
            "entries",
            filter_value=self._range_filter(
                family, "happenedAt", _pb_date(first_voice), _pb_date(last_voice)
            ) + " && isArchived=false",
            sort="happenedAt",
        )
        parsed_entries: list[tuple[datetime, dict[str, Any]]] = []
        for item in entry_records:
            happened_at = _parse_date(item.get("happenedAt"))
            if happened_at is not None and _text(item.get("localId")):
                parsed_entries.append((happened_at, item))

        # 照片会持续累积，不能每做一圈就全表扫描。每段原声只取 14 天内最近的
        # 三条 Entry 当候选，再分批查询这些 Entry 是否真的有照片。
        candidate_ids: set[str] = set()
        for _, recorded_at, *_ in valid:
            nearby = sorted(
                (
                    (abs((date - recorded_at).total_seconds()), _text(item.get("localId")))
                    for date, item in parsed_entries
                    if abs((date - recorded_at).total_seconds()) <= 14 * 86400
                ),
                key=lambda pair: pair[0],
            )
            candidate_ids.update(local_id for _, local_id in nearby[:3] if local_id)

        entries_with_photos: set[str] = set()
        sorted_candidates = sorted(candidate_ids)
        for start in range(0, len(sorted_candidates), 30):
            chunk = sorted_candidates[start:start + 30]
            if not chunk:
                continue
            entry_filter = " || ".join(
                "entryLocalId='%s'" % _pb_quote(local_id) for local_id in chunk
            )
            photo_records = self.store.list_records(
                "media",
                filter_value=(
                    "familyId='%s' && isDeleted=false && mediaType='photo' && file!=''"
                    " && (%s)" % (family, entry_filter)
                ),
                # PocketBase 0.38 对这个迁移集合禁用系统 created 排序；localId 有唯一索引且稳定。
                sort="localId",
            )
            entries_with_photos.update(
                _text(item.get("entryLocalId")) for item in photo_records
                if _text(item.get("entryLocalId"))
            )

        dated_entries: list[tuple[datetime, MemoryEvidence]] = []
        for happened_at, item in parsed_entries:
            if _text(item.get("localId")) not in entries_with_photos:
                continue
            title = _text(item.get("title")) or "关联照片"
            excerpt = _join_text(item.get("note"), item.get("firstPersonNote"))
            dated_entries.append((happened_at, _evidence(
                "entries", item, "happenedAt", title, excerpt, "photo_moment"
            )))

        result: list[SoundRingMaterial] = []
        for _, recorded_at, file_name, duration, age_years, kind, source_updated_at, voice in valid:
            nearby = [
                (abs((date - recorded_at).total_seconds()), evidence)
                for date, evidence in dated_entries
                if abs((date - recorded_at).total_seconds()) <= 14 * 86400
            ]
            related = min(nearby, key=lambda pair: pair[0])[1] if nearby else None
            result.append(SoundRingMaterial(
                voice=voice,
                file_name=file_name,
                duration_seconds=duration,
                age_years=age_years,
                kind=kind,
                source_updated_at=source_updated_at,
                related_entry=related,
            ))
        return result

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


def _single_file_name(value: Any) -> str:
    if isinstance(value, list):
        return _text(value[0]) if value else ""
    return _text(value)


def _parse_date(value: Any) -> Optional[datetime]:
    text = _text(value)
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=UTC)


def _pb_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def fact_family_value(logical_family_id: str) -> str:
    """旧单家庭库可只读空 familyId，派生产物仍使用非空逻辑家庭 id。"""
    legacy = os.environ.get("FACTS_LEGACY_EMPTY_FAMILY", "false").strip().lower()
    return "" if legacy in {"1", "true", "yes", "on"} else logical_family_id


def fact_record_belongs_to_family(
    record: dict[str, Any], logical_family_id: str
) -> bool:
    return str(record.get("familyId") or "") == fact_family_value(logical_family_id)


def _pb_date(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).isoformat()
