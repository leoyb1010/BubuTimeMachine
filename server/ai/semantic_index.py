"""可重建的照片语义索引。

事实仍在 PocketBase；这里只保存可删除重算的向量、展示摘要和来源引用。
SQLite 文件不得放进 pb_data，也不参与事实层同步。
"""
from __future__ import annotations

import json
import math
import re
import sqlite3
import struct
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Optional, Sequence


SCHEMA_VERSION = 1


@dataclass(frozen=True)
class SemanticAsset:
    asset_id: str
    entry_local_id: str
    media_record_id: str
    file_url: str
    captured_at: str
    caption: str = ""
    tags: Sequence[str] = ()
    family_id: str = ""


@dataclass(frozen=True)
class SemanticHit:
    asset_id: str
    entry_local_id: str
    media_record_id: str
    file_url: str
    captured_at: str
    caption: str
    tags: tuple[str, ...]
    score: float
    reason: str


class SemanticIndex:
    def __init__(self, path: Path, model_version: str):
        self.path = Path(path)
        self.model_version = model_version
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(str(self.path), timeout=30)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA busy_timeout = 30000")
        return connection

    def _initialize(self) -> None:
        with self._lock, self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS semantic_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS semantic_assets (
                    asset_id TEXT PRIMARY KEY,
                    entry_local_id TEXT NOT NULL,
                    media_record_id TEXT NOT NULL,
                    family_id TEXT NOT NULL DEFAULT '',
                    file_url TEXT NOT NULL,
                    captured_at TEXT NOT NULL,
                    caption TEXT NOT NULL DEFAULT '',
                    tags_json TEXT NOT NULL DEFAULT '[]',
                    model_version TEXT NOT NULL,
                    embedding_dim INTEGER NOT NULL,
                    embedding BLOB NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_semantic_entry
                    ON semantic_assets(entry_local_id);
                CREATE INDEX IF NOT EXISTS idx_semantic_family_date
                    ON semantic_assets(family_id, captured_at DESC);
                """
            )
            connection.execute(
                "INSERT OR REPLACE INTO semantic_meta(key, value) VALUES('schema_version', ?)",
                (str(SCHEMA_VERSION),),
            )

    def upsert(self, asset: SemanticAsset, embedding: Sequence[float]) -> None:
        vector = _normalize(embedding)
        if not asset.asset_id or not asset.entry_local_id or not asset.media_record_id:
            raise ValueError("asset/source identifiers must not be empty")
        if not asset.file_url:
            raise ValueError("file_url must not be empty")
        payload = struct.pack("<%sf" % len(vector), *vector)
        now = datetime.now(timezone.utc).isoformat()
        tags = [str(tag).strip() for tag in asset.tags if str(tag).strip()]
        with self._lock, self._connect() as connection:
            connection.execute(
                """
                INSERT INTO semantic_assets(
                    asset_id, entry_local_id, media_record_id, family_id, file_url,
                    captured_at, caption, tags_json, model_version,
                    embedding_dim, embedding, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(asset_id) DO UPDATE SET
                    entry_local_id=excluded.entry_local_id,
                    media_record_id=excluded.media_record_id,
                    family_id=excluded.family_id,
                    file_url=excluded.file_url,
                    captured_at=excluded.captured_at,
                    caption=excluded.caption,
                    tags_json=excluded.tags_json,
                    model_version=excluded.model_version,
                    embedding_dim=excluded.embedding_dim,
                    embedding=excluded.embedding,
                    updated_at=excluded.updated_at
                """,
                (
                    asset.asset_id,
                    asset.entry_local_id,
                    asset.media_record_id,
                    asset.family_id,
                    asset.file_url,
                    asset.captured_at,
                    asset.caption.strip(),
                    json.dumps(tags, ensure_ascii=False),
                    self.model_version,
                    len(vector),
                    payload,
                    now,
                ),
            )

    def remove(self, asset_id: str) -> None:
        with self._lock, self._connect() as connection:
            connection.execute("DELETE FROM semantic_assets WHERE asset_id = ?", (asset_id,))

    def count(self) -> int:
        with self._lock, self._connect() as connection:
            row = connection.execute("SELECT COUNT(*) AS total FROM semantic_assets").fetchone()
        return int(row["total"] if row else 0)

    def active_count(self) -> int:
        """只统计当前模型可检索的向量。旧向量留到重建完成，避免切换时破坏索引。"""
        with self._lock, self._connect() as connection:
            row = connection.execute(
                "SELECT COUNT(*) AS total FROM semantic_assets WHERE model_version = ?",
                (self.model_version,),
            ).fetchone()
        return int(row["total"] if row else 0)

    def search(
        self,
        query: str,
        query_embedding: Sequence[float],
        limit: int = 20,
        family_id: str = "",
        min_score: float = 0.0,
    ) -> list[SemanticHit]:
        clean_query = query.strip()
        if not clean_query:
            return []
        vector = _normalize(query_embedding)
        safe_limit = max(1, min(int(limit), 50))
        params: tuple[str, ...] = (family_id,) if family_id else ()
        where = "WHERE family_id = ?" if family_id else ""
        with self._lock, self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM semantic_assets " + where,
                params,
            ).fetchall()

        ranked = []
        for row in rows:
            if row["model_version"] != self.model_version:
                continue
            stored = _unpack(row["embedding"], int(row["embedding_dim"]))
            if len(stored) != len(vector):
                continue
            visual_score = max(-1.0, min(1.0, _dot(vector, stored)))
            tags = tuple(_safe_tags(row["tags_json"]))
            text_score, evidence = _text_score(clean_query, row["caption"], tags)
            # 视觉语义是主信号；明确文字/标签命中时给足权重，保证老照片已有描述仍可靠。
            combined = (visual_score + 1.0) * 0.375 + text_score * 0.25
            if combined < max(0.0, min(float(min_score), 1.0)):
                continue
            reason = _reason(clean_query, evidence, tags)
            ranked.append(
                SemanticHit(
                    asset_id=row["asset_id"],
                    entry_local_id=row["entry_local_id"],
                    media_record_id=row["media_record_id"],
                    file_url=row["file_url"],
                    captured_at=row["captured_at"],
                    caption=row["caption"],
                    tags=tags,
                    score=round(combined, 6),
                    reason=reason,
                )
            )
        # 同分时优先最近拍摄内容；分两次稳定排序，避免 ISO 日期被误排成升序。
        ranked.sort(key=lambda item: (item.captured_at, item.asset_id), reverse=True)
        ranked.sort(key=lambda item: item.score, reverse=True)
        return ranked[:safe_limit]


def _normalize(values: Sequence[float]) -> tuple[float, ...]:
    vector = tuple(float(value) for value in values)
    if not vector or not all(math.isfinite(value) for value in vector):
        raise ValueError("embedding must contain finite values")
    norm = math.sqrt(sum(value * value for value in vector))
    if norm <= 1e-12:
        raise ValueError("embedding norm must be positive")
    return tuple(value / norm for value in vector)


def _unpack(payload: bytes, dimension: int) -> tuple[float, ...]:
    if dimension <= 0 or len(payload) != dimension * 4:
        return ()
    return tuple(struct.unpack("<%sf" % dimension, payload))


def _dot(lhs: Sequence[float], rhs: Sequence[float]) -> float:
    return sum(a * b for a, b in zip(lhs, rhs))


def _tokens(text: str) -> set[str]:
    normalized = re.sub(r"[^\w\u3400-\u9fff]+", " ", text.lower()).strip()
    words = {word for word in normalized.split() if word}
    cjk = "".join(re.findall(r"[\u3400-\u9fff]", normalized))
    words.update(cjk[index:index + 2] for index in range(max(0, len(cjk) - 1)))
    if cjk:
        words.add(cjk)
    return words


def _text_score(query: str, caption: str, tags: Sequence[str]) -> tuple[float, str]:
    haystack = " ".join([caption, *tags]).lower()
    lowered = query.lower()
    if lowered and lowered in haystack:
        return 1.0, lowered
    query_tokens = _tokens(query)
    if not query_tokens:
        return 0.0, ""
    matched = query_tokens & _tokens(haystack)
    score = len(matched) / len(query_tokens)
    evidence = max(matched, key=len) if matched else ""
    return score, evidence


def _reason(query: str, evidence: str, tags: Sequence[str]) -> str:
    if evidence:
        return "文字或标签命中“%s”" % evidence
    visible_tags = "、".join(tags[:2])
    if visible_tags:
        return "画面语义接近“%s”；已有标签：%s" % (query, visible_tags)
    return "画面语义接近“%s”" % query


def _safe_tags(payload: str) -> Iterable[str]:
    try:
        value = json.loads(payload)
    except (TypeError, json.JSONDecodeError):
        return ()
    if not isinstance(value, list):
        return ()
    return tuple(str(item) for item in value if str(item).strip())
