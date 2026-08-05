"""派生作品的最小公共生命周期。

周报与声音年轮都只写 ``derived_artifacts``，共同遵守：
查询素材 -> 家庭确认 -> 渲染 -> 来源校验 -> 发布 -> 归档。
本模块只抽两者已经实际使用的持久化、归属校验和幂等逻辑，不预建更多层。
"""
from __future__ import annotations

from typing import Any, Callable, Optional

import httpx

from memory_query import PocketBaseMemoryStore


class ArtifactUnavailable(RuntimeError):
    pass


class ArtifactWorkflow:
    def __init__(self, store: PocketBaseMemoryStore, kind: str) -> None:
        if not kind.strip():
            raise ValueError("作品类型不能为空")
        self.store = store
        self.kind = kind

    def latest(self, family_id: str) -> Optional[dict[str, Any]]:
        return self.store.latest_artifact(family_id, self.kind)

    def history(self, family_id: str, limit: int) -> list[dict[str, Any]]:
        return self.store.recent_artifacts(family_id, self.kind, limit)

    def create_idempotent(self, payload: dict[str, Any]) -> dict[str, Any]:
        artifact_key = str(payload.get("artifactKey") or "")
        if not artifact_key:
            raise ValueError("作品缺少 artifactKey")
        existing = self.store.find_artifact(artifact_key)
        if existing is not None:
            return existing
        try:
            return self.store.create_artifact(payload)
        except httpx.HTTPStatusError as exc:
            # API、定时 worker 或两台家庭设备同时提交时，唯一键只允许一个胜者。
            if exc.response.status_code not in {400, 409}:
                raise
            concurrent = self.store.find_artifact(artifact_key)
            if concurrent is None:
                raise
            return concurrent

    def owned(self, family_id: str, artifact_id: str) -> dict[str, Any]:
        try:
            current = self.store.get_artifact(artifact_id)
        except (httpx.HTTPError, ValueError) as exc:
            raise ArtifactUnavailable("作品不存在或不属于当前家庭。") from exc
        if (current.get("familyId") != family_id
                or current.get("kind") != self.kind):
            raise ArtifactUnavailable("作品不存在或不属于当前家庭。")
        return current

    def update(
        self, family_id: str, artifact_id: str, changes: dict[str, Any]
    ) -> dict[str, Any]:
        self.owned(family_id, artifact_id)
        return self.store.update_artifact(artifact_id, changes)

    def archive(
        self,
        family_id: str,
        artifact_id: str,
        *,
        allowed: Optional[Callable[[dict[str, Any]], bool]] = None,
    ) -> dict[str, Any]:
        current = self.owned(family_id, artifact_id)
        if allowed is not None and not allowed(current):
            raise ArtifactUnavailable("作品尚未准备好，不能归档。")
        return self.store.archive_artifact(artifact_id)
