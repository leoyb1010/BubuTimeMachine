"""PocketBase 派生任务 worker：并发 2、租约、指数退避、三次失败进死信。

只读取事实层并写入可重建 SQLite 索引，不写回或覆盖任何家庭记录。
"""
from __future__ import annotations

import json
import logging
import os
import re
import socket
import tempfile
import time
import fcntl
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Lock
from typing import Any, Optional
from urllib.parse import quote

import httpx

from semantic_index import SemanticAsset, SemanticIndex
from semantic_model import MobileCLIPEncoder


logger = logging.getLogger("bubu.semantic-worker")
UTC = timezone.utc


def iso_now(offset_seconds: int = 0) -> str:
    return (datetime.now(UTC) + timedelta(seconds=offset_seconds)).isoformat()


def retry_delay_seconds(attempts: int) -> int:
    return min(3600, 60 * (2 ** max(0, attempts - 1)))


@dataclass(frozen=True)
class ClaimedJob:
    id: str
    kind: str
    source_record_id: str
    source_local_id: str
    family_id: str
    attempts: int


class PocketBaseWorkerClient:
    def __init__(self) -> None:
        self.base_url = os.environ.get("PB_BASE_URL", "http://127.0.0.1:8090").rstrip("/")
        # 长期 superuser token 比在常驻 worker 中保存账户密码更合适；
        # 兼容旧部署，未提供 token 时才回退到邮箱 + 密码认证。
        self.api_token = os.environ.get("PB_WORKER_TOKEN", "").strip()
        self.identity = os.environ.get("PB_WORKER_EMAIL", "").strip()
        self.password = os.environ.get("PB_WORKER_PASSWORD", "")
        self.worker_id = os.environ.get(
            "SEMANTIC_WORKER_ID", "%s-%d" % (socket.gethostname(), os.getpid())
        )
        self._client = httpx.Client(base_url=self.base_url, timeout=30)
        self._token = self.api_token
        self._file_token = ""
        self._file_token_expires_at = 0.0
        self._claim_lock = Lock()

    def close(self) -> None:
        self._client.close()

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
        self._token = response.json()["token"]

    def _request(self, method: str, path: str, **kwargs: Any) -> httpx.Response:
        response = self._client.request(method, path, headers=self._headers(), **kwargs)
        if response.status_code == 401:
            if self.api_token:
                raise RuntimeError("PB_WORKER_TOKEN 已失效或无权限")
            self._token = ""
            response = self._client.request(method, path, headers=self._headers(), **kwargs)
        response.raise_for_status()
        return response

    def claim(self, limit: int = 1, lease_seconds: int = 300) -> list[ClaimedJob]:
        # 单 mini 单 worker 串行领取：同一照片的更新/删除按队列顺序最终收敛。
        with self._claim_lock:
            now = iso_now()
            filter_value = (
                "(state='queued' && availableAt<='%s') || "
                "(state='running' && leaseUntil<'%s')" % (now, now)
            )
            response = self._request(
                "GET",
                "/api/collections/automation_jobs/records",
                params={
                    "page": 1,
                    "perPage": 1,
                    "sort": "availableAt,jobKey",
                    "filter": filter_value,
                },
            )
            claimed = []
            for raw in response.json().get("items", []):
                updated = self._request(
                    "PATCH",
                    "/api/collections/automation_jobs/records/%s" % raw["id"],
                    json={
                        "state": "running",
                        "leaseOwner": self.worker_id,
                        "leaseUntil": iso_now(lease_seconds),
                    },
                ).json()
                claimed.append(
                    ClaimedJob(
                        id=updated["id"],
                        kind=updated.get("kind", ""),
                        source_record_id=updated.get("sourceRecordId", ""),
                        source_local_id=updated.get("sourceLocalId", ""),
                        family_id=updated.get("familyId", ""),
                        attempts=int(updated.get("attempts") or 0),
                    )
                )
            return claimed

    def complete(self, job: ClaimedJob, model_version: str) -> None:
        self._request(
            "PATCH",
            "/api/collections/automation_jobs/records/%s" % job.id,
            json={
                "state": "done",
                "leaseOwner": "",
                "leaseUntil": "",
                "lastError": "",
                "modelVersion": model_version,
            },
        )

    def fail(self, job: ClaimedJob, error: Exception) -> None:
        attempts = job.attempts + 1
        dead = attempts >= 3
        self._request(
            "PATCH",
            "/api/collections/automation_jobs/records/%s" % job.id,
            json={
                "state": "dead_letter" if dead else "queued",
                "attempts": attempts,
                "availableAt": iso_now(retry_delay_seconds(attempts)),
                "leaseOwner": "",
                "leaseUntil": "",
                "lastError": (type(error).__name__ + ": " + str(error))[:500],
            },
        )

    def fetch_media(self, record_id: str) -> dict[str, Any]:
        try:
            return self._request(
                "GET", "/api/collections/media/records/%s" % record_id
            ).json()
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 404:
                return {}
            raise

    def fetch_entry(self, local_id: str) -> dict[str, Any]:
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", local_id):
            raise RuntimeError("entryLocalId 格式非法")
        response = self._request(
            "GET",
            "/api/collections/entries/records",
            params={"page": 1, "perPage": 1, "filter": "localId='%s'" % local_id},
        ).json()
        items = response.get("items", [])
        return items[0] if items else {}

    def download_media(self, media: dict[str, Any], destination: Path) -> None:
        # 视频优先使用 PocketBase 已有缩略图；照片取原图。URL 只由配置的 PB host 与记录字段拼出。
        media_type = media.get("mediaType", "photo")
        filename = media.get("thumbnail") if media_type == "video" else media.get("file")
        filename = filename or media.get("thumbnail") or media.get("file")
        if not filename:
            raise RuntimeError("媒体没有可索引的文件")
        encoded = quote(str(filename), safe="")
        path = "/api/files/media/%s/%s" % (media["id"], encoded)
        with self._client.stream(
            "GET", path, headers=self._headers(),
            params={"token": self._protected_file_token()},
        ) as response:
            response.raise_for_status()
            max_bytes = max(1, int(os.environ.get("SEMANTIC_MAX_DOWNLOAD_BYTES", "134217728")))
            content_length = int(response.headers.get("content-length") or 0)
            if content_length > max_bytes:
                raise RuntimeError("媒体超过语义索引下载上限")
            with destination.open("wb") as output:
                total = 0
                for chunk in response.iter_bytes(1024 * 1024):
                    total += len(chunk)
                    if total > max_bytes:
                        raise RuntimeError("媒体超过语义索引下载上限")
                    output.write(chunk)

    def _protected_file_token(self) -> str:
        if self._file_token and time.monotonic() < self._file_token_expires_at:
            return self._file_token
        response = self._request("POST", "/api/files/token")
        token = str(response.json().get("token") or "")
        if not token:
            raise RuntimeError("PocketBase 文件访问令牌响应异常")
        self._file_token = token
        self._file_token_expires_at = time.monotonic() + 90
        return token

    def public_file_url(self, media: dict[str, Any]) -> str:
        media_type = media.get("mediaType", "photo")
        filename = media.get("thumbnail") if media_type == "video" else media.get("file")
        filename = filename or media.get("thumbnail") or media.get("file") or ""
        return "%s/api/files/media/%s/%s" % (
            self.base_url,
            media.get("id", ""),
            quote(str(filename), safe=""),
        )


class SemanticWorker:
    def __init__(
        self,
        client: PocketBaseWorkerClient,
        index: SemanticIndex,
        encoder: MobileCLIPEncoder,
    ) -> None:
        self.client = client
        self.index = index
        self.encoder = encoder

    def run_once(self) -> int:
        jobs = self.client.claim(limit=1)
        if not jobs:
            return 0
        for job in jobs:
            self._process_safely(job)
        return len(jobs)

    def _process_safely(self, job: ClaimedJob) -> None:
        try:
            self._process(job)
            self.client.complete(job, self.encoder.model_version)
        except Exception as exc:
            logger.exception("semantic job failed id=%s kind=%s", job.id, job.kind)
            self.client.fail(job, exc)

    def _process(self, job: ClaimedJob) -> None:
        if job.kind not in {"semantic_media_upsert", "semantic_media_delete"}:
            raise RuntimeError("未知任务类型: %s" % job.kind)

        # 任务只是 wake-up 信号，真正动作永远重读当前事实。这样乱序、重试、删除后撤销
        # 都会收敛到 media/entry 的最新状态，而不是盲信过期的任务 kind。
        media = self.client.fetch_media(job.source_record_id)
        if not media or media.get("isDeleted"):
            self.index.remove(job.source_record_id)
            return
        entry_local_id = media.get("entryLocalId")
        if not entry_local_id:
            raise RuntimeError("媒体缺少 entryLocalId")
        entry = self.client.fetch_entry(entry_local_id)
        media_family = str(media.get("familyId") or job.family_id)
        entry_family = str(entry.get("familyId") or "")
        if entry.get("isDeleted"):
            self.index.remove(job.source_record_id)
            return
        if media_family and entry_family and media_family != entry_family:
            raise RuntimeError("媒体与时光记录不属于同一家庭")
        caption_parts = [
            entry.get("title", ""),
            entry.get("note", ""),
            entry.get("firstPersonNote", ""),
            entry.get("locationName", ""),
        ]
        caption = " · ".join(str(item).strip() for item in caption_parts if str(item).strip())
        tags = media.get("aiTags") or []
        if not isinstance(tags, list):
            tags = []

        with tempfile.TemporaryDirectory(prefix="bubu-semantic-") as temp_dir:
            image_path = Path(temp_dir) / "visual"
            self.client.download_media(media, image_path)
            embedding = self.encoder.encode_image(image_path)
        self.index.upsert(
            SemanticAsset(
                asset_id=job.source_record_id,
                entry_local_id=entry_local_id,
                media_record_id=job.source_record_id,
                file_url=self.client.public_file_url(media),
                captured_at=str(entry.get("happenedAt") or media.get("created") or ""),
                caption=caption,
                tags=[str(tag) for tag in tags],
                family_id=media_family,
            ),
            embedding,
        )


def build_worker() -> SemanticWorker:
    encoder = MobileCLIPEncoder()
    configured = os.environ.get("SEMANTIC_INDEX_PATH", "../derived/memory_index.sqlite")
    path = Path(configured).expanduser()
    if not path.is_absolute():
        path = Path(__file__).resolve().parent / path
    index = SemanticIndex(path.resolve(), encoder.model_version)
    return SemanticWorker(PocketBaseWorkerClient(), index, encoder)


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("AI_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    )
    if os.environ.get("SEMANTIC_SEARCH_ENABLED", "false").lower() not in {
        "1", "true", "yes", "on"
    }:
        raise SystemExit("SEMANTIC_SEARCH_ENABLED 未开启，worker 不启动")
    lock_path = Path(os.environ.get("SEMANTIC_WORKER_LOCK", "../derived/semantic-worker.lock"))
    if not lock_path.is_absolute():
        lock_path = (Path(__file__).resolve().parent / lock_path).resolve()
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_handle = lock_path.open("a+")
    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        raise SystemExit("已有语义 worker 在运行，拒绝启动第二实例") from exc
    worker = build_worker()
    poll_seconds = max(2, int(os.environ.get("SEMANTIC_WORKER_POLL_SECONDS", "10")))
    try:
        while True:
            processed = worker.run_once()
            if not processed:
                time.sleep(poll_seconds)
    finally:
        worker.client.close()
        lock_handle.close()


if __name__ == "__main__":
    main()
