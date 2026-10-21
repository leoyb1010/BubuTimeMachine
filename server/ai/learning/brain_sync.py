"""Bounded, manually attributed second-brain photos -> PocketBase timeline.

Automatic face matches remain identity candidates. This module never identifies
a person, scans a photo library, or retracts records because a snapshot omitted
them. Registry state is independent of school lessons and of the source library.
"""
from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime
import fcntl
import hashlib
import mimetypes
from pathlib import Path
import re
import tempfile
import time
import uuid
from zoneinfo import ZoneInfo

import httpx

from memory_query import PocketBaseMemoryStore, _pb_quote, pb_filter_datetime
from .brain_bridge import BrainUnavailable
from .store import digest


AUTO_SOURCE = "second-brain-auto"
PENDING_SOURCE = "second-brain-pending"
TERMINAL = {"hidden", "tombstoned"}


class TimelineWriteError(RuntimeError):
    """Stable error code only; never include file paths or provider payloads."""


def _valid_hash(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value):
        raise ValueError("文件校验值格式无效")
    return value


def registry_cursor_key(family_id: str, child_id: str, subject_id: str) -> str:
    return "brain-timeline:" + digest([family_id, child_id, subject_id])


class BrainSyncService:
    def __init__(self, bridge, store, writer, family_id: str, child_id: str, subject_id: str):
        if not all(isinstance(v, str) and v.strip() for v in (family_id, child_id, subject_id)):
            raise ValueError("自动时光缺少明确归属")
        if getattr(writer, "family_id", family_id) != family_id:
            raise ValueError("写入器与同步家庭不一致")
        self.bridge, self.store, self.writer = bridge, store, writer
        self.family_id, self.child_id, self.subject_id = family_id, child_id, subject_id
        self.cursor_key = registry_cursor_key(family_id, child_id, subject_id)

    def registry(self) -> dict:
        value = self.store.get_cursor(self.cursor_key)
        if value is None:
            return {"family_id": self.family_id, "child_id": self.child_id,
                    "subject_id": self.subject_id, "items": {}}
        if not isinstance(value, dict) or not isinstance(value.get("items"), dict):
            raise TimelineWriteError("registry_invalid")
        if (value.get("family_id"), value.get("child_id"), value.get("subject_id")) != (
                self.family_id, self.child_id, self.subject_id):
            raise TimelineWriteError("registry_scope_mismatch")
        return value

    @contextmanager
    def _lock(self):
        path = self.store.root / ("brain-sync-" + self.cursor_key.split(":", 1)[1] + ".lock")
        with path.open("a+") as handle:
            path.chmod(0o600)
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise TimelineWriteError("sync_busy") from exc
            yield

    def exclude(self, content_hash: str) -> None:
        """Persist a local user exclusion, even if no timeline record exists yet."""
        sha = _valid_hash(content_hash)
        with self._lock():
            registry = self.registry()
            registry["items"][sha] = {**registry["items"].get(sha, {}), "content_hash": sha,
                                      "status": "hidden", "reason": "user_hidden"}
            self.store.set_cursor(self.cursor_key, registry)

    def media_analysis(self, media_id: str) -> dict | None:
        """Internal lookup. API callers still verify current PB family/media access."""
        return next((row for row in self.registry()["items"].values()
                     if row.get("status") == "synced" and row.get("media_id") == media_id), None)

    def run_once(self, dry_run: bool = False, limit: int = 25) -> dict:
        if type(limit) is not int or not 1 <= limit <= 100:
            raise ValueError("每轮同步数量须为1–100")
        if dry_run:
            return self._run(self.bridge.subject_snapshot(self.subject_id), True, limit)
        with self._lock():
            return self._run(self.bridge.subject_snapshot(self.subject_id), False, limit)

    def _run(self, snapshot: dict, dry_run: bool, limit: int) -> dict:
        if (not isinstance(snapshot, dict) or snapshot.get("complete") is not True
                or not isinstance(snapshot.get("snapshot_id"), str) or not snapshot["snapshot_id"]
                or not isinstance(snapshot.get("items"), list)):
            raise BrainUnavailable("第二大脑没有返回完整快照。")
        current: dict[str, dict] = {}
        identities: dict[str, set[str]] = {}
        for item in snapshot["items"]:
            try:
                sha = _valid_hash(item["content_hash"])
                fid = item["file_id"]
                if not re.fullmatch(r"[a-f0-9]{24}", fid) or not item.get("source_revision"):
                    raise ValueError()
            except (KeyError, TypeError, ValueError) as exc:
                raise BrainUnavailable("第二大脑素材标识不完整。") from exc
            # Equal verified bytes share one moment. A manual attribution takes
            # precedence over another alias's automatic identity suggestion.
            if sha not in current or item.get("provenance") == "manual":
                current[sha] = item
            identities.setdefault(sha, set()).add(fid)
        registry = self.registry()
        rows = registry["items"]
        pending = []
        for sha, item in current.items():
            prior = rows.get(sha, {})
            if prior.get("status") in TERMINAL:
                continue
            prior["brain_file_ids"] = sorted(identities[sha])
            prior["content_hash"] = sha
            rows[sha] = prior
            if item.get("provenance") != "manual":
                # Existing Gemini two-pass accepted matches (even .99) are not
                # user confirmation. No curated-source shortcut is inferred.
                prior.update(status="pending_identity", provenance=item.get("provenance", "unknown"))
                continue
            if prior.get("status") in {None, "pending_identity"}:
                prior["status"] = "pending"
            if prior.get("status") != "synced" or prior.get("source_revision") != item["source_revision"]:
                pending.append(item)
        for sha, prior in rows.items():
            if sha not in current and prior.get("status") not in TERMINAL:
                prior["status"] = "needs_recheck"
        # Failed/held items do not monopolize the front of a historical scan.
        pending.sort(key=lambda item: (rows[item["content_hash"]].get("attempts", 0),
                                       rows[item["content_hash"]].get("last_attempt_at", 0)))
        report = {"state": "dry_run" if dry_run else "completed", "snapshot_id": snapshot["snapshot_id"],
                  "available": len(current), "planned": min(limit, len(pending)), "processed": 0,
                  "created": 0, "reused": 0, "failed": 0, "excluded": snapshot.get("excluded", {})}
        if not dry_run:
            registry["last_snapshot_id"] = snapshot["snapshot_id"]
            self.store.set_cursor(self.cursor_key, registry)
            for item in pending[:limit]:
                sha = item["content_hash"]
                rows[sha]["attempts"] = rows[sha].get("attempts", 0) + 1
                rows[sha]["last_attempt_at"] = time.time()
                try:
                    mapping = self.writer.upsert(item)
                    if mapping.get("status") not in {"synced", "tombstoned", "needs_recheck"}:
                        raise TimelineWriteError("writer_result_invalid")
                    # Whitelist registry fields: local_path and original bytes
                    # never enter a cursor, an API response, or a log.
                    rows[sha].update({k: mapping[k] for k in (
                        "status", "media_id", "entry_id", "media_local_id", "entry_local_id", "owned",
                    ) if k in mapping})
                    rows[sha].update(source_revision=item["source_revision"], analysis=item.get("analysis", {}),
                                     captured_at=item.get("captured_at"), provenance="manual",
                                     confidence=item.get("confidence"), updated_at=time.time())
                    rows[sha].pop("error", None)
                    if mapping["status"] == "synced":
                        report["created" if mapping.get("action") in {"created", "resumed"} else "reused"] += 1
                except Exception:
                    rows[sha].update(status="failed", error="timeline_write_failed")
                    report["failed"] += 1
                report["processed"] += 1
                # A partial run/crash acknowledges only each successful item;
                # the snapshot ID is never used to skip the unprocessed tail.
                self.store.set_cursor(self.cursor_key, registry)
        report["pending"] = sum(
            item.get("provenance") == "manual" and rows.get(sha, {}).get("status") not in TERMINAL
            and (rows.get(sha, {}).get("status") != "synced"
                 or rows.get(sha, {}).get("source_revision") != item["source_revision"])
            for sha, item in current.items())
        report["pending_identity"] = sum(row.get("status") == "pending_identity" for row in rows.values())
        report["needs_recheck"] = sum(row.get("status") == "needs_recheck" for row in rows.values())
        report["hidden"] = sum(row.get("status") in TERMINAL for row in rows.values())
        return report


class PocketBaseTimelineWriter:
    """Create/reuse facts. Published Entry prose is never overwritten by AI.

    Ordinary PocketBase PATCH has no atomic compare-and-swap. Consequently even
    apparently untouched published prose stays unchanged; corrections live in
    the independently versioned analysis registry.
    """
    def __init__(self, family_id: str, author_user_id: str, author_role: str, *, store=None):
        if (not isinstance(family_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", family_id)
                or not isinstance(author_user_id, str) or not author_user_id.isalnum()
                or not isinstance(author_role, str) or not author_role.strip()):
            raise ValueError("自动记录必须明确家庭、作者账号和角色")
        self.family_id, self.author_user_id, self.author_role = family_id, author_user_id, author_role.strip()[:40]
        self.store = store or PocketBaseMemoryStore()

    def close(self):
        self.store.close()

    def _find_local(self, collection, local_id):
        return self.store.first_record(collection, filter_value="familyId='%s' && localId='%s'" % (
            _pb_quote(self.family_id), _pb_quote(local_id)), sort="id")

    def _owned(self, entry, local_id):
        return (entry.get("familyId") == self.family_id and entry.get("localId") == local_id
                and entry.get("authorUserId") == self.author_user_id
                and entry.get("sourceRaw") in {AUTO_SOURCE, PENDING_SOURCE})

    def _mapping(self, entry, media, status="synced", action="reused", owned=False):
        return {"status": status, "action": action, "entry_id": entry.get("id", ""),
                "entry_local_id": entry.get("localId", ""), "media_id": media.get("id", ""),
                "media_local_id": media.get("localId", ""), "owned": owned}

    def _finish_pending(self, entry, media, entry_local_id):
        fresh = self.store.get_record("entries", entry["id"])
        current_media = self.store.get_record("media", media["id"])
        if fresh.get("isDeleted") or current_media.get("isDeleted"):
            return self._mapping(fresh, current_media, "tombstoned", owned=self._owned(fresh, entry_local_id))
        if (current_media.get("familyId") != self.family_id or current_media.get("entryLocalId") != entry_local_id
                or current_media.get("contentHash") != media.get("contentHash") or not current_media.get("file")
                or (current_media.get("resourceRole") or "display") != "display"):
            return self._mapping(fresh, current_media, "needs_recheck")
        if (not self._owned(fresh, entry_local_id) or fresh.get("editedAt")
                or fresh.get("sourceRaw") != PENDING_SOURCE or not fresh.get("isArchived")):
            return self._mapping(fresh, media, "needs_recheck", owned=self._owned(fresh, entry_local_id))
        ready = self.store.request("PATCH", "/api/collections/entries/records/" + entry["id"], json={
            "isArchived": False, "sourceRaw": AUTO_SOURCE,
            "clientUpdatedAt": datetime.now(ZoneInfo("UTC")).isoformat(),
        }).json()
        return self._mapping(ready, media, action="resumed", owned=True)

    @contextmanager
    def _verified_copy(self, item):
        try:
            with tempfile.SpooledTemporaryFile(max_size=8 * 1024 * 1024) as copy_file:
                checksum, size = hashlib.sha256(), 0
                with Path(item["local_path"]).open("rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        size += len(chunk)
                        if size > 256 * 1024 * 1024:
                            raise TimelineWriteError("source_too_large")
                        checksum.update(chunk)
                        copy_file.write(chunk)
                if not size or checksum.hexdigest() != item["content_hash"]:
                    raise TimelineWriteError("source_changed")
                copy_file.seek(0)
                yield copy_file
        except OSError as exc:
            raise TimelineWriteError("source_unavailable") from exc

    def upsert(self, item: dict) -> dict:
        mapping = self._upsert(item)
        return {**mapping, "content_hash": item["content_hash"], "analysis": item.get("analysis", {})}

    def _upsert(self, item: dict) -> dict:
        if item.get("provenance") != "manual":
            raise TimelineWriteError("identity_confirmation_required")
        sha = _valid_hash(item["content_hash"])
        if item.get("media_type") not in {"photo", "video"}:
            raise TimelineWriteError("unsupported_media")
        author = self.store.get_record("users", self.author_user_id)
        if author.get("familyId") != self.family_id:
            raise TimelineWriteError("author_family_mismatch")
        entry_local = str(uuid.uuid5(uuid.NAMESPACE_URL, "bubu-brain-entry:" + self.family_id + ":" + sha))
        media_local = str(uuid.uuid5(uuid.NAMESPACE_URL, "bubu-brain-media:" + self.family_id + ":" + sha))
        matches = self.store.list_records("media", filter_value="familyId='%s' && contentHash='%s'" % (
            _pb_quote(self.family_id), sha), sort="id")
        pending, blocked = [], []
        for media in matches:
            if media.get("familyId") != self.family_id:
                raise TimelineWriteError("media_family_mismatch")
            entry = self._find_local("entries", media.get("entryLocalId", ""))
            if entry is None:
                blocked.append(self._mapping({}, media, "needs_recheck"))
            elif media.get("isDeleted") or entry.get("isDeleted"):
                blocked.append(self._mapping(entry, media, "tombstoned"))
            elif not media.get("file") or (media.get("resourceRole") or "display") != "display":
                # Do not promote someone's original-only attachment, or claim
                # a placeholder without its bytes is already visible in the app.
                blocked.append(self._mapping(entry, media, "needs_recheck"))
            elif entry.get("isArchived"):
                if self._owned(entry, entry_local) and entry.get("sourceRaw") == PENDING_SOURCE:
                    pending.append((entry, media))
                else:
                    blocked.append(self._mapping(entry, media, "tombstoned"))
            else:
                return self._mapping(entry, media, owned=self._owned(entry, entry_local))
        if pending:
            return self._finish_pending(*pending[0], entry_local)
        if blocked:
            return blocked[0]
        entry = self._find_local("entries", entry_local)
        if entry and (entry.get("isDeleted") or (entry.get("isArchived") and entry.get("sourceRaw") != PENDING_SOURCE)):
            return self._mapping(entry, {}, "tombstoned")
        if entry and (not self._owned(entry, entry_local) or entry.get("editedAt")):
            return self._mapping(entry, {}, "needs_recheck")
        # Copy+hash before the first write, and upload that verified copy so a
        # changing original cannot race verification or a transport auth retry.
        with self._verified_copy(item) as original:
            happened = datetime.fromisoformat(item["captured_at"].replace("Z", "+00:00"))
            if happened.tzinfo is None:
                happened = happened.replace(tzinfo=ZoneInfo("Asia/Shanghai"))
            stamp = datetime.now(ZoneInfo("UTC")).isoformat()
            if not entry:
                description = str((item.get("analysis") or {}).get("description") or "")[:4000]
                payload = {"localId": entry_local, "familyId": self.family_id, "authorUserId": self.author_user_id,
                           "authorRole": self.author_role, "title": "布布的一段时光",
                           "note": "【第二大脑自动整理】\n人物归属来自已确认标签。" + ("\n\n" + description if description else ""),
                           "happenedAt": pb_filter_datetime(happened), "happenedAtClient": pb_filter_datetime(happened),
                           "sourceRaw": PENDING_SOURCE, "isArchived": True, "isDeleted": False, "clientUpdatedAt": stamp}
                entry = self._create_unique("entries", payload)
            if not self._owned(entry, entry_local) or entry.get("isDeleted") or entry.get("editedAt"):
                return self._mapping(entry, {}, "needs_recheck")
            media = self._find_local("media", media_local)
            if media:
                if media.get("isDeleted") or media.get("contentHash") != sha:
                    return self._mapping(entry, media, "tombstoned")
            else:
                name = Path(str(item.get("name") or "photo.jpg").replace("\\", "/")).name
                fields = {"localId": media_local, "entryLocalId": entry_local, "familyId": self.family_id,
                          "authorUserId": self.author_user_id, "mediaType": item["media_type"], "contentHash": sha,
                          "sourceRaw": AUTO_SOURCE, "sourceAssetKey": item["file_id"], "resourceRole": "display",
                          "assetGroupId": media_local, "isDeleted": "false", "clientUpdatedAt": stamp}
                try:
                    media = self.store.request("POST", "/api/collections/media/records", data=fields,
                                               files={"file": (name, original, mimetypes.guess_type(name)[0] or "application/octet-stream")}).json()
                except httpx.HTTPStatusError as exc:
                    if exc.response.status_code not in {400, 409}:
                        raise
                    media = self._find_local("media", media_local)
                    if not media or media.get("contentHash") != sha or media.get("isDeleted"):
                        raise
            return self._finish_pending(entry, media, entry_local)

    def _create_unique(self, collection, payload):
        try:
            return self.store.request("POST", "/api/collections/" + collection + "/records", json=payload).json()
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code not in {400, 409}:
                raise
            existing = self._find_local(collection, payload["localId"])
            if not existing:
                raise
            return existing
