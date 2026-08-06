"""Read-only Bubu Inbox scanner that feeds the same durable intake contract.

The scanner never writes, moves, renames, or deletes source files. It hashes and
copies candidates into isolated staging; a family user must confirm the batch in
the iPhone app before facts can be committed.
"""
from __future__ import annotations

import hashlib
import json
import mimetypes
import os
import shutil
import subprocess
import tempfile
import uuid
from dataclasses import asdict, dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Optional

from intake_staging import IntakeItem, IntakeStagingStore


SUPPORTED = {
    ".jpg": "photo", ".jpeg": "photo", ".heic": "photo", ".heif": "photo",
    ".png": "photo", ".gif": "photo", ".webp": "photo", ".dng": "photo",
    ".mov": "video", ".mp4": "video", ".m4v": "video",
    ".m4a": "audio", ".wav": "audio", ".aac": "audio",
}
NAMESPACE = uuid.UUID("8c7191cc-2b65-46ff-a376-2623f89c50e0")
MAX_BATCH_ITEMS = 500
MAX_ITEM_BYTES = 2_147_483_648


@dataclass(frozen=True)
class ScannedFile:
    source_path: str
    relative_path: str
    size: int
    modified_at: float
    captured_epoch: float
    captured_at: str
    capture_time_source: str
    media_type: str
    mime_type: str
    sha256: str
    status: str
    error: Optional[str] = None


class SSDIntakeScanner:
    def __init__(self, source_root: Path, staging: IntakeStagingStore):
        self.source_root = source_root.expanduser().resolve()
        self.staging = staging
        if not self.source_root.is_dir():
            raise ValueError("Bubu Inbox directory does not exist")

    def scan(self, existing_hashes: Iterable[str] = ()) -> list[ScannedFile]:
        known = set(existing_hashes)
        results: list[ScannedFile] = []
        for path in sorted(self.source_root.rglob("*")):
            if path.is_symlink() or not path.is_file():
                continue
            media_type = SUPPORTED.get(path.suffix.lower())
            if not media_type:
                continue
            try:
                before = path.stat()
                digest = _sha256(path)
                after = path.stat()
                if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
                    raise OSError("source changed while hashing")
                captured_epoch, capture_source = _capture_time(path, after)
                captured = datetime.fromtimestamp(
                    captured_epoch, timezone.utc
                ).isoformat(timespec="seconds")
                results.append(ScannedFile(
                    source_path=str(path),
                    relative_path=str(path.relative_to(self.source_root)),
                    size=after.st_size,
                    modified_at=after.st_mtime,
                    captured_epoch=captured_epoch,
                    captured_at=captured,
                    capture_time_source=capture_source,
                    media_type=media_type,
                    mime_type=mimetypes.guess_type(path.name)[0] or "application/octet-stream",
                    sha256=digest,
                    status="duplicate" if digest in known else "candidate",
                ))
                known.add(digest)
            except OSError as exc:
                results.append(ScannedFile(
                    source_path=str(path), relative_path=str(path.relative_to(self.source_root)),
                    size=0, modified_at=0, captured_epoch=0, captured_at="",
                    capture_time_source="unavailable", media_type=media_type,
                    mime_type="application/octet-stream", sha256="", status="error",
                    error=type(exc).__name__,
                ))
        return results

    def stage_candidates(self, family_id: str, existing_hashes: Iterable[str] = ()) -> list[dict]:
        # 合并调用方从 PocketBase 取回的事实 hash 与本地历次暂存 hash。
        # 否则“旧文件旁边又放入一张新照片”会因为事件分组 digest 改变，
        # 把旧文件再次组成新批次。
        known = set(existing_hashes) | self.staging.known_hashes(family_id)
        scanned = self.scan(known)
        candidates = [item for item in scanned if item.status == "candidate"]
        batches: list[dict] = []
        remaining_budget = int(os.environ.get("INTAKE_SSD_SCAN_BUDGET_BYTES", str(8 * 1024**3)))
        minimum_free = int(os.environ.get("INTAKE_MIN_FREE_BYTES", str(10 * 1024**3)))
        groups, initially_deferred = _bounded_groups(candidates, remaining_budget)
        deferred: dict[str, str] = {
            item.relative_path: reason for item, reason in initially_deferred
        }
        for group in groups:
            group_bytes = sum(item.size for item in group)
            if group_bytes > remaining_budget:
                deferred.update((item.relative_path, "scan_budget_exhausted") for item in group)
                continue
            if shutil.disk_usage(self.staging.root).free - group_bytes < minimum_free:
                deferred.update((item.relative_path, "minimum_free_space_guard") for item in group)
                continue
            digest = hashlib.sha256(
                "\n".join(sorted(item.relative_path + ":" + item.sha256 for item in group)).encode("utf-8")
            ).hexdigest()
            batch_id = str(uuid.uuid5(NAMESPACE, "batch:" + digest))
            entry_id = str(uuid.uuid5(NAMESPACE, "entry:" + digest))
            items = [
                IntakeItem(
                    asset_key=str(uuid.uuid5(NAMESPACE, "asset:" + item.sha256)),
                    file_name=Path(item.relative_path).name,
                    media_type=item.media_type,
                    captured_at=item.captured_at,
                    expected_size=item.size,
                    expected_mime=item.mime_type,
                    # SSD 每个文件本身就是这一资产唯一的可见版本，不是 PhotoKit
                    # 同资产下的附加保真副本。
                    resource_role="display",
                )
                for item in group
            ]
            entry = {
                "local_id": entry_id,
                "happened_at": min(item.captured_at for item in group),
                "author_role": "爸爸",
                "note": "",
                "source": "ssd-bubu-inbox",
                "source_paths": [item.relative_path for item in group],
                "capture_time_sources": sorted({item.capture_time_source for item in group}),
            }
            batch = self.staging.create_batch(
                batch_id, "service:ssd-inbox", family_id, entry, items, confirmed=False
            )
            try:
                if batch["state"] == "awaiting_confirmation" and any(
                    item["state"] != "staged" for item in batch["items"]
                ):
                    by_key = {str(uuid.uuid5(NAMESPACE, "asset:" + item.sha256)): item for item in group}
                    for intake_item in batch["items"]:
                        if intake_item["state"] == "staged":
                            continue
                        source_item = by_key[intake_item["asset_key"]]
                        source = Path(source_item.source_path)
                        # Re-check before every file. Other upload paths may consume
                        # space while a large SSD event is being copied.
                        if shutil.disk_usage(self.staging.root).free - source_item.size < minimum_free:
                            raise OSError("minimum free space guard")
                        self.staging.mark_uploading(batch_id, intake_item["asset_key"])
                        descriptor, name = tempfile.mkstemp(
                            prefix="ssd-", suffix=".part", dir=self.staging.root
                        )
                        os.close(descriptor)
                        temporary = Path(name)
                        try:
                            before = source.stat()
                            shutil.copyfile(source, temporary)
                            after = source.stat()
                            copied_hash = _sha256(temporary)
                            if (before.st_size != after.st_size
                                    or before.st_mtime_ns != after.st_mtime_ns
                                    or copied_hash != source_item.sha256):
                                raise OSError("source changed while copying")
                            if shutil.disk_usage(self.staging.root).free < minimum_free:
                                raise OSError("minimum free space guard")
                            self.staging.stage_file(
                                batch_id, intake_item["asset_key"], temporary,
                                copied_hash, temporary.stat().st_size,
                            )
                        finally:
                            temporary.unlink(missing_ok=True)
            except (OSError, KeyError):
                # A partial hidden candidate is never publishable. Remove only
                # its isolated copy/metadata; the read-only source is retried.
                self.staging.abandon_unconfirmed(batch_id, family_id)
                deferred.update((item.relative_path, "copy_deferred") for item in group)
                continue
            final = self.staging.batch(batch_id)
            self._write_manifest(batch_id, group, final)
            batches.append(final)
            remaining_budget -= group_bytes

        if deferred:
            scanned = [
                replace(item, status="deferred", error=deferred[item.relative_path])
                if item.relative_path in deferred else item
                for item in scanned
            ]
        self._write_scan_manifest(scanned)
        return batches

    def _write_manifest(self, batch_id: str, source: list[ScannedFile], batch: dict) -> None:
        directory = self.staging.root / "manifests"
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        target = directory / f"{batch_id}.json"
        payload = {"batch": batch, "source": [asdict(item) for item in source]}
        target.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        os.chmod(target, 0o600)

    def _write_scan_manifest(self, scanned: list[ScannedFile]) -> None:
        directory = self.staging.root / "manifests"
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        target = directory / "latest-scan.json"
        target.write_text(
            json.dumps([asdict(item) for item in scanned], ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        os.chmod(target, 0o600)


def _group_by_time(items: list[ScannedFile], gap_seconds: int = 90 * 60) -> list[list[ScannedFile]]:
    ordered = sorted(items, key=lambda item: (item.captured_epoch, item.relative_path))
    groups: list[list[ScannedFile]] = []
    for item in ordered:
        if not groups or item.captured_epoch - groups[-1][-1].captured_epoch > gap_seconds:
            groups.append([item])
        else:
            groups[-1].append(item)
    return groups


def _bounded_groups(
    items: list[ScannedFile], max_group_bytes: int
) -> tuple[list[list[ScannedFile]], list[tuple[ScannedFile, str]]]:
    """Preserve event order while enforcing the server's batch contract."""
    groups: list[list[ScannedFile]] = []
    deferred: list[tuple[ScannedFile, str]] = []
    limit = max(1, max_group_bytes)
    for event in _group_by_time(items):
        current: list[ScannedFile] = []
        current_bytes = 0
        for item in event:
            if item.size > MAX_ITEM_BYTES:
                deferred.append((item, "item_exceeds_2gb_limit"))
                continue
            if item.size > limit:
                deferred.append((item, "scan_budget_exhausted"))
                continue
            if current and (
                len(current) >= MAX_BATCH_ITEMS or current_bytes + item.size > limit
            ):
                groups.append(current)
                current = []
                current_bytes = 0
            current.append(item)
            current_bytes += item.size
        if current:
            groups.append(current)
    return groups, deferred


def _capture_time(path: Path, stat_result: os.stat_result) -> tuple[float, str]:
    """Prefer embedded image/video creation metadata; copying time is only a labelled fallback."""
    try:
        result = subprocess.run(
            ["/usr/bin/mdls", "-raw", "-name", "kMDItemContentCreationDate", str(path)],
            check=False, capture_output=True, text=True, timeout=5,
        )
        value = result.stdout.strip()
        if result.returncode == 0 and value and value != "(null)":
            parsed = datetime.strptime(value, "%Y-%m-%d %H:%M:%S %z")
            return parsed.timestamp(), "embedded-metadata"
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    birth = float(getattr(stat_result, "st_birthtime", 0) or 0)
    if birth > 0:
        return birth, "file-creation-fallback"
    return float(stat_result.st_mtime), "file-modified-fallback"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
