"""Internal scoped reader for the existing second-brain library.

This module never scans original media, changes second-brain data, or exposes a
general search capability. ``root`` comes from server configuration. local_path
is for the trusted import worker only and must never be serialized to clients.
Only complete_json explicitly invokes the existing Gemini pipeline.
"""
from __future__ import annotations

from contextlib import contextmanager
import base64
from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
from typing import Any
import uuid
from zoneinfo import ZoneInfo

from .brain_bridge_runner import validate_request


# Same allowlist as second-brain media.safe_path; configuration of a library DB
# must not turn arbitrary paths found inside it into readable Bubu assets.
MEDIA_ROOTS = {
    "photos": Path("/Volumes/Leo-bubu/Photos Library.photoslibrary"),
    "media_archive": Path("/Volumes/Leo-bubu/影像档案"),
}
DEFAULT_SCHOOL_TOKENS = (
    "幼儿园", "亲子桥", "图卡", "识字卡", "儿童英语", "英语启蒙", "儿歌", "童谣",
    "nursery rhyme", "flashcard", "kindergarten", "preschool",
)


GENERIC_ALIASES = {"女儿", "我女儿", "儿子", "我儿子", "宝宝", "孩子"}


class BrainUnavailable(RuntimeError):
    pass


class BrainSnapshotChanged(BrainUnavailable):
    """Restart this pagination pass; deduplicate by source_instance_id, not offset."""


class BrainBlocked(BrainUnavailable):
    """The model refused this particular request (safety filter, length, rejected input)."""


class BrainTimeout(BrainUnavailable):
    """The model call ran past its deadline."""


# The library's model gateway caps one call at 180 s; leave headroom for process start-up.
MODEL_TIMEOUT = 210


def _encoded(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _digest(value: Any) -> str:
    return hashlib.sha256(_encoded(value).encode()).hexdigest()


class BrainBridge:
    def __init__(self, root: Path, python_executable: str | None = None, *, school_tokens=None):
        self.root = Path(root).expanduser().resolve()
        self.python_executable = python_executable or sys.executable
        tokens = DEFAULT_SCHOOL_TOKENS if school_tokens is None else school_tokens
        if (not isinstance(tokens, (list, tuple)) or not 1 <= len(tokens) <= 32
                or any(not isinstance(token, str) or not 2 <= len(token.strip()) <= 80 for token in tokens)):
            raise ValueError("教学候选关键词须为1–32个明确词语")
        self.school_tokens = tuple(dict.fromkeys(token.strip().casefold() for token in tokens))

    @contextmanager
    def _database(self):
        connection = None
        try:
            path = self.root / "data/library.sqlite"
            if not path.is_file():
                raise BrainUnavailable("第二大脑资料库尚不可用。")
            connection = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=10)
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA query_only=ON")
            connection.execute("BEGIN")
            yield connection
        except BrainUnavailable:
            raise
        except (OSError, sqlite3.Error, ValueError, TypeError, KeyError, IndexError) as exc:
            # Do not copy paths, SQL values, private descriptions or credentials
            # into API errors/logs. A failed read is never a successful empty feed.
            raise BrainUnavailable("第二大脑快照读取失败，请稍后重试。") from exc
        finally:
            if connection is not None:
                connection.rollback()
                connection.close()

    def _sensitive_ids(self, connection, ids: list[str]) -> set[str]:
        if not ids:
            return set()
        try:
            source = self.root / "app/sensitive_media.py"
            namespace = {"__name__": "bubu_sensitive_media_rules", "__file__": str(source)}
            # The archive's shared pure classifier imports no storage/model code.
            # Compile directly to avoid writing __pycache__ into its source tree.
            exec(compile(source.read_text(encoding="utf-8"), str(source), "exec"), namespace)
            result: set[str] = set()
            for offset in range(0, len(ids), 200):
                result.update(namespace["flagged_ids"](connection, ids[offset:offset + 200]))
            return result
        except Exception as exc:
            raise BrainUnavailable("第二大脑敏感素材检查不可用。") from exc

    def subject_snapshot(self, subject_id: str) -> dict:
        if not re.fullmatch(r"[a-f0-9]{16}", subject_id):
            raise ValueError("人物编号格式无效")
        with self._database() as connection:
            subject = connection.execute(
                "SELECT name,aliases FROM memories WHERE id=? AND kind='person'", (subject_id,),
            ).fetchone()
            if subject is None:
                raise BrainUnavailable("第二大脑尚未绑定这个人物。")
            names = list(dict.fromkeys([subject["name"], *re.split(r"[,，、;；\n]", subject["aliases"] or "")]))
            names = [name.strip() for name in names if name and name.strip()]
            accepted = connection.execute(
                "SELECT file_id,confidence,at FROM memory_photos WHERE memory_id=? AND state='accepted' ORDER BY file_id",
                (subject_id,),
            ).fetchall()
            labels: dict[str, set[str]] = {}
            for row in connection.execute(
                "SELECT file_id,source FROM tags WHERE label IN (" + ",".join("?" * len(names)) + ")", names,
            ):
                labels.setdefault(row["file_id"], set()).add(row["source"])
            hidden = self._sensitive_ids(connection, [row["file_id"] for row in accepted])
            excluded = {"sensitive": 0, "unavailable": 0, "unlabelled": 0}
            items = []
            for row in accepted:
                fid = row["file_id"]
                if fid in hidden:
                    excluded["sensitive"] += 1
                    continue
                sources = labels.get(fid, set())
                provenance = "manual" if "manual" in sources else "gemini_two_pass" if "auto" in sources else None
                confidence = float(row["confidence"] or 0)
                if provenance is None or not math.isfinite(confidence) or not 0 <= confidence <= 1:
                    excluded["unlabelled"] += 1
                    continue
                item = self._item(connection, fid)
                if item is None:
                    excluded["unavailable"] += 1
                    continue
                item.update(provenance=provenance, confidence=confidence)
                item["source_revision"] = _digest([item["source_revision"], provenance, confidence, row["at"]])
                items.append(item)
            items.extend(self._subject_videos(connection, names, {i["file_id"] for i in items}, excluded))
            labels = self._annotate(connection, subject_id, items)
            snapshot_id = _digest([subject_id, [(i["file_id"], i["source_revision"]) for i in items], excluded])
            return {"complete": True, "snapshot_id": snapshot_id, "items": items, "excluded": excluded,
                    "people_labels": labels}

    def _annotate(self, connection, subject_id: str, items: list[dict]) -> dict:
        """Co-occurring family members and guessed places; kept out of source_revision.

        Returns name -> kinship label (布布姥姥 -> 姥姥) for display.
        """
        labels: dict[str, str] = {}
        people: dict[str, list[str]] = {}
        for row in connection.execute(
            "SELECT p.file_id,m.name,m.aliases FROM memory_photos p JOIN memories m ON m.id=p.memory_id "
            "WHERE m.kind='person' AND p.state='accepted' AND p.memory_id!=? ORDER BY m.name", (subject_id,),
        ):
            name = (row["name"] or "").strip()
            if not name:
                continue
            people.setdefault(row["file_id"], []).append(name)
            if name not in labels:
                alias = next((a.strip() for a in re.split(r"[,，、;；\n]", row["aliases"] or "")
                              if a.strip().startswith("布布") and len(a.strip()) > 2), "")
                labels[name] = alias.removeprefix("布布").removeprefix("的") or name
        guesses: dict[str, str] = {}
        if connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='media_place_guess'").fetchone():
            ids = [i["file_id"] for i in items if not i.get("place")]
            for offset in range(0, len(ids), 400):
                batch = ids[offset:offset + 400]
                for row in connection.execute("SELECT file_id,place FROM media_place_guess WHERE file_id IN ("
                                              + ",".join("?" * len(batch)) + ")", batch):
                    if row["place"]:
                        guesses[row["file_id"]] = row["place"]
        for item in items:
            item["people"] = list(dict.fromkeys(people.get(item["file_id"], [])))
            if not item.get("place"):
                item["place"] = guesses.get(item["file_id"], "")
        return labels

    def items_by_ids(self, ids: list[str], subject_id: str = "") -> list[dict]:
        """Exact library items a family member explicitly confirmed; sensitive ones never return."""
        ids = [i for i in dict.fromkeys(ids) if isinstance(i, str) and re.fullmatch(r"[a-f0-9]{24}", i)]
        if not ids:
            return []
        with self._database() as connection:
            hidden = self._sensitive_ids(connection, ids)
            items = []
            for fid in ids:
                if fid in hidden:
                    continue
                try:
                    item = self._item(connection, fid)
                except BrainUnavailable:
                    continue
                if item is not None:
                    items.append(item)
            self._annotate(connection, subject_id, items)
            return items

    def recognition_candidates(self, subject_id: str, min_confidence: float = 0.5,
                               category: str = "01_照片/01_女儿") -> list[dict]:
        """Photos the library judged uncertain for the subject, or filed under her folder without judgement.

        Newest first. Families decide; nothing here is treated as confirmation.
        """
        if not re.fullmatch(r"[a-f0-9]{16}", subject_id):
            raise ValueError("人物编号格式无效")
        with self._database() as connection:
            rows = connection.execute(
                "SELECT p.file_id,p.confidence FROM memory_photos p JOIN media_assets m ON m.file_id=p.file_id "
                "WHERE p.memory_id=? AND p.state='checked' AND p.confidence>=? AND m.media_kind='photo' "
                "UNION ALL SELECT m.file_id,NULL FROM media_assets m WHERE m.category=? AND m.media_kind='photo' "
                "AND NOT EXISTS(SELECT 1 FROM memory_photos p WHERE p.file_id=m.file_id AND p.memory_id=?)",
                (subject_id, float(min_confidence), category, subject_id),
            ).fetchall()
            confidence = {}
            for row in rows:
                confidence.setdefault(row["file_id"], row["confidence"])
            ids = sorted(confidence)
            hidden = self._sensitive_ids(connection, ids)
            items = []
            for fid in ids:
                if fid in hidden:
                    continue
                try:
                    item = self._item(connection, fid)
                except BrainUnavailable:
                    continue
                if item is None:
                    continue
                value = confidence[fid]
                item["confidence"] = round(float(value), 3) if value is not None and math.isfinite(float(value)) else None
                items.append(item)
            items.sort(key=lambda i: (str(i.get("captured_at") or ""), i["file_id"]), reverse=True)
            return items

    def _subject_videos(self, connection, names: list[str], seen: set[str], excluded: dict) -> list[dict]:
        """Videos whose existing second-brain video analysis names the subject.

        The library has no person labels for videos. Its own completed video
        summaries/tags naming the child are the pipeline's evidence; no new face
        matching happens here. Generic kinship words are not identifying names.
        """
        strong = [n for n in names if len(n) >= 2 and n not in GENERIC_ALIASES]
        if not strong:
            return []
        predicate = " OR ".join("instr(lower(coalesce(v.summary,'') || ' ' || coalesce(v.tags,'')),?)>0" for _ in strong)
        rows = connection.execute(
            "SELECT v.file_id FROM media_video_gemini v JOIN media_assets m ON m.file_id=v.file_id "
            "WHERE v.state='completed' AND m.media_kind='video' AND (" + predicate + ") "
            "AND EXISTS(SELECT 1 FROM media_locations l WHERE l.file_id=v.file_id AND l.available=1 "
            "AND l.hash_state='verified' AND coalesce(l.variant,'original')!='live_motion') ORDER BY v.file_id",
            [n.casefold() for n in strong],
        ).fetchall()
        ids = [row["file_id"] for row in rows if row["file_id"] not in seen]
        hidden = self._sensitive_ids(connection, ids)
        result = []
        for fid in ids:
            if fid in hidden:
                excluded["sensitive"] += 1
                continue
            item = self._item(connection, fid)
            if item is None or item["media_type"] != "video":
                excluded["unavailable"] += 1
                continue
            item.update(provenance="video_analysis_mention", confidence=None)
            item["source_revision"] = _digest([item["source_revision"], "video_analysis_mention"])
            result.append(item)
        return result

    def lookup_hash(self, sha: str) -> dict | None:
        """Exact reuse for a file whose Bubu ownership the caller already proved.

        This is not an ownership check: teaching videos need not show the child.
        Results therefore contain no invented person provenance/confidence.
        """
        if not re.fullmatch(r"[a-f0-9]{64}", sha):
            raise ValueError("文件校验值格式无效")
        with self._database() as connection:
            ids = [row[0] for row in connection.execute(
                "SELECT DISTINCT file_id FROM media_locations WHERE sha256=? AND hash_state='verified' AND available=1 ORDER BY file_id",
                (sha,),
            )]
            hidden = self._sensitive_ids(connection, ids)
            for fid in ids:
                if fid not in hidden:
                    item = self._item(connection, fid, sha)
                    if item is not None:
                        return item
            return None

    def school_snapshot(self, since_day: str, limit: int = 200, *, cursor: str | None = None) -> dict:
        """Discover parsed iCloud teaching candidates, never confirmed lessons.

        A PhotoKit UUID is one save/import occurrence even after hash dedup merges
        its file_id. Cursor offsets are valid only for the returned snapshot;
        restart from page one on BrainSnapshotChanged and on each polling pass.
        Missing Photos added dates fall back explicitly to library first_seen;
        an uncertain old fallback cannot exclude a potentially recent re-save.
        """
        since = date.fromisoformat(since_day)
        if since.isoformat() != since_day or type(limit) is not int or not 1 <= limit <= 200:
            raise ValueError("候选日期或分页数量无效")
        page = self._school_cursor(cursor)
        # Only completed analysis contributes text. A filename/person label is
        # not a teaching classification, and no unparsed originals are inspected.
        evidence = " || ' ' || ".join([
            "coalesce(g.description,'')", "coalesce(g.tags,'')", "coalesce(g.event,'')", "coalesce(g.scene,'')",
            "coalesce(v.summary,'')", "coalesce(v.tags,'')", "coalesce(v.event,'')", "coalesce(v.scene,'')",
            "coalesce(m.ocr,'')", "CASE WHEN e.file_id IS NOT NULL THEN coalesce(m.caption,'') ELSE '' END",
        ])
        predicate = " OR ".join("instr(lower(" + evidence + "),?)>0" for _ in self.school_tokens)
        with self._database() as connection:
            rows = connection.execute(
                "SELECT l.id location_id,l.file_id,l.source_uuid,f.first_seen,(" + evidence + ") evidence "
                "FROM media_locations l JOIN media_assets m ON m.file_id=l.file_id JOIN files f ON f.id=l.file_id "
                "LEFT JOIN media_gemini g ON g.file_id=l.file_id AND g.state='completed' "
                "LEFT JOIN media_video_gemini v ON v.file_id=l.file_id AND v.state='completed' "
                "LEFT JOIN media_enrichment e ON e.file_id=l.file_id AND e.state='completed' "
                "WHERE l.source='photos' AND l.available=1 AND l.hash_state='verified' "
                "AND coalesce(l.variant,'original')!='live_motion' AND f.exists_now=1 "
                "AND f.privacy IN ('private','general') AND m.media_kind IN ('photo','video') "
                "AND (g.file_id IS NOT NULL OR v.file_id IS NOT NULL OR e.file_id IS NOT NULL) "
                "AND (" + predicate + ") ORDER BY l.source_uuid,l.variant='original' DESC,l.size DESC,l.id",
                self.school_tokens,
            ).fetchall()
            excluded = {"sensitive": 0, "unavailable": 0, "invalid_source_instance": 0,
                        "trashed": 0, "missing_photos_instance": 0, "before_since": 0}
            instances: dict[str, list] = {}
            for row in rows:
                try:
                    key = str(uuid.UUID(row["source_uuid"]))
                except (ValueError, TypeError, AttributeError):
                    excluded["invalid_source_instance"] += 1
                    continue
                instances.setdefault(key, []).append(row)
            times, photos_available = self._photos_received([r["source_uuid"] for rs in instances.values() for r in rs])
            hidden = self._sensitive_ids(connection, list({r["file_id"] for r in rows}))
            items = []
            for instance, locations in instances.items():
                added = times.get(instance)
                if photos_available and added is None:
                    excluded["missing_photos_instance"] += 1
                    continue
                if added and added["trashed"]:
                    excluded["trashed"] += 1
                    continue
                warnings = ["school_candidate_requires_confirmation", "received_time_is_not_lesson_date"]
                received = added["received_at"] if added else None
                received_source = "photos_added_date"
                if received:
                    if datetime.fromisoformat(received).date() < since:
                        excluded["before_since"] += 1
                        continue
                else:
                    received = _received_iso(locations[0]["first_seen"])
                    received_source = "library_first_seen_fallback" if received else "unavailable"
                    warnings.append("received_time_not_verified")
                    if not received or datetime.fromisoformat(received).date() < since:
                        warnings.append("since_filter_uncertain")
                # One occurrence may have original/edited representations; choose
                # a verified Photos location belonging to THIS source UUID only.
                candidate = None
                if any(row["file_id"] in hidden for row in locations):
                    excluded["sensitive"] += 1
                    continue
                for row in locations:
                    candidate = self._item(connection, row["file_id"], location_id=row["location_id"])
                    if candidate:
                        matched = [token for token in self.school_tokens if token in row["evidence"].casefold()]
                        candidate.update(scope="school_candidate", provenance="icloud_candidate", date_confirmed=False,
                                         source_instance_id="photos:" + instance, received_at=received,
                                         received_at_source=received_source, candidate_tokens=matched, warnings=warnings)
                        candidate["source_revision"] = _digest([
                            candidate["source_revision"], candidate["source_instance_id"], received, received_source, matched, warnings,
                        ])
                        items.append(candidate)
                        break
                if candidate is None:
                    excluded["unavailable"] += 1
            items.sort(key=lambda item: (item["received_at"] or "", item["source_instance_id"]))
            snapshot_id = _digest([since_day, self.school_tokens,
                                   [(i["source_instance_id"], i["source_revision"]) for i in items], excluded])
            if page is not None and page["snapshot_id"] != snapshot_id:
                raise BrainSnapshotChanged("教学候选快照已变化，请从第一页继续核对。")
            offset = page["offset"] if page else 0
            if offset > len(items):
                raise ValueError("候选分页游标无效")
            end = min(offset + limit, len(items))
            next_cursor = None
            if end < len(items):
                next_cursor = base64.urlsafe_b64encode(_encoded({"v": 1, "snapshot_id": snapshot_id, "offset": end}).encode()).decode()
            return {"complete": True, "snapshot_id": snapshot_id, "items": items[offset:end],
                    "has_more": end < len(items), "next_cursor": next_cursor, "excluded": excluded,
                    "warnings": [] if photos_available else ["photos_added_date_catalog_unavailable"]}

    @staticmethod
    def _school_cursor(value):
        if value is None:
            return None
        try:
            if not isinstance(value, str) or len(value) > 1024:
                raise ValueError()
            page = json.loads(base64.b64decode(value.encode(), altchars=b"-_", validate=True))
            if (not isinstance(page, dict) or page.get("v") != 1 or type(page.get("offset")) is not int
                    or page["offset"] < 0 or not re.fullmatch(r"[a-f0-9]{64}", page.get("snapshot_id", ""))):
                raise ValueError()
            return page
        except (ValueError, TypeError, UnicodeError) as exc:
            raise ValueError("候选分页游标无效") from exc

    @staticmethod
    def _photos_received(source_uuids: list[str]) -> tuple[dict, bool]:
        """Read only UUID/add-date/trash state for already parsed candidates."""
        connection = None
        try:
            path = MEDIA_ROOTS["photos"] / "database/Photos.sqlite"
            if not path.is_file():
                return {}, False
            connection = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=5)
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA query_only=ON")
            connection.execute("BEGIN")
            columns = {row[1] for row in connection.execute("PRAGMA table_info(ZASSET)")}
            if not {"ZUUID", "ZADDEDDATE", "ZTRASHEDSTATE"} <= columns:
                return {}, False
            result = {}
            ids = list(dict.fromkeys(source_uuids))
            for offset in range(0, len(ids), 200):
                batch = ids[offset:offset + 200]
                for row in connection.execute(
                    "SELECT ZUUID,ZADDEDDATE,ZTRASHEDSTATE FROM ZASSET WHERE ZUUID IN (" + ",".join("?" * len(batch)) + ")", batch,
                ):
                    try:
                        seconds = float(row["ZADDEDDATE"])
                        stamp = datetime(2001, 1, 1, tzinfo=timezone.utc) + timedelta(seconds=seconds)
                        received = stamp.astimezone(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds") if math.isfinite(seconds) and seconds > 0 else None
                    except (ValueError, TypeError, OverflowError):
                        received = None
                    result[str(uuid.UUID(row["ZUUID"]))] = {"received_at": received, "trashed": bool(row["ZTRASHEDSTATE"])}
            return result, True
        except (OSError, sqlite3.Error, ValueError, KeyError):
            return {}, False
        finally:
            if connection is not None:
                connection.rollback()
                connection.close()

    def _item(self, connection, fid: str, exact_hash: str | None = None, *, location_id: str | None = None) -> dict | None:
        if not re.fullmatch(r"[a-f0-9]{24}", fid):
            return None
        asset = connection.execute(
            "SELECT m.* FROM media_assets m JOIN files f ON f.id=m.file_id WHERE m.file_id=? AND f.exists_now=1",
            (fid,),
        ).fetchone()
        if asset is None or asset["media_kind"] not in {"photo", "video"}:
            return None
        locations = connection.execute(
            "SELECT * FROM media_locations WHERE file_id=? AND available=1 AND hash_state='verified'"
            + (" AND sha256=?" if exact_hash else "")
            + (" AND id=?" if location_id else "")
            + " ORDER BY source='photos' DESC,variant!='live_motion' DESC,variant='original' DESC,size DESC,path,id",
            [fid] + ([exact_hash] if exact_hash else []) + ([location_id] if location_id else []),
        ).fetchall()
        unavailable_root = False
        for location in locations:
            try:
                path = self._verified_path(location)
            except BrainUnavailable:
                unavailable_root = True
                continue
            if path is None:
                continue
            extra: dict = {}
            analysis = self._analysis(connection, asset, extra)
            columns = asset.keys()
            item = {
                "file_id": fid, "content_hash": location["sha256"],
                "captured_at": asset["captured_at"], "media_type": asset["media_kind"],
                "name": path.name, "analysis": analysis, "local_path": str(path),
            }
            item["source_revision"] = _digest([
                fid, location["id"], location["sha256"], asset["captured_at"], analysis,
            ])
            # Display-only facts below stay out of source_revision (timeline sync keys on it).
            item.update(place=str(asset["place"] or "") if "place" in columns else "",
                        category=str(asset["category"] or "") if "category" in columns else "",
                        event=extra.get("event", ""))
            return item
        if unavailable_root:
            raise BrainUnavailable("第二大脑原片存储尚未连接。")
        return None

    @staticmethod
    def _verified_path(location) -> Path | None:
        root = MEDIA_ROOTS.get(location["source"])
        if root is None or not re.fullmatch(r"[a-f0-9]{64}", location["sha256"] or ""):
            return None
        if not root.is_dir():
            raise BrainUnavailable("第二大脑原片存储尚未连接。")
        try:
            root = root.resolve(strict=True)
            path = (root / location["path"]).resolve(strict=True)
            path.relative_to(root)
            stat = path.stat()
            if not path.is_file() or getattr(stat, "st_flags", 0) & 0x40000000:
                return None
            if (stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns) != (
                location["size"], location["mtime_ns"], location["ctime_ns"],
            ):
                return None
            return path
        except (OSError, ValueError, TypeError):
            return None

    @staticmethod
    def _analysis(connection, asset, extra: dict | None = None) -> dict:
        fid = asset["file_id"]
        video = asset["media_kind"] == "video"
        table, text = ("media_video_gemini", "summary") if video else ("media_gemini", "description")
        row = connection.execute("SELECT * FROM " + table + " WHERE file_id=? AND state='completed'", (fid,)).fetchone()
        warnings = ["existing_analysis_not_bound_to_content_hash", "historical_model_version_not_recorded"]
        if row is None:
            warnings.append("analysis_pending")
        elif extra is not None:
            extra["event"] = str(row["event"] or "")
        if video:
            warnings.append("video_visual_coverage_first_90_seconds")
        segments = []
        for source in connection.execute(
            "SELECT start,end,text,method FROM media_segments WHERE file_id=? ORDER BY start,end,method", (fid,),
        ):
            try:
                start, end = float(source["start"]), float(source["end"])
                if not all(math.isfinite(v) for v in (start, end)) or start < 0 or end <= start or not source["text"]:
                    raise ValueError()
            except (ValueError, TypeError):
                if "invalid_transcript_segments_skipped" not in warnings:
                    warnings.append("invalid_transcript_segments_skipped")
                continue
            segment = {"start": start, "end": end, "text": source["text"], "method": source["method"]}
            segments.append({"id": "seg-" + _digest(segment)[:20], **segment})
        if segments:
            warnings.append("transcript_requires_source_verification")
        return {
            "description": row[text] if row else "", "ocr": asset["ocr"] or "",
            "tags": [t for t in re.split(r"[、,，;；]", row["tags"] or "") if t] if row else [],
            "segments": segments, "provider": "second-brain-gemini", "model_version": "legacy-unversioned",
            "analyzed_at": row["at"] if row else None, "warnings": warnings,
        }

    def complete_json(self, system: str, user: str | list[dict], schema: dict, *, effort: str = "high",
                      timeout: float = MODEL_TIMEOUT) -> dict:
        """Explicit model operation; domain validation remains with its caller."""
        if effort not in {"low", "medium", "high"}:
            raise ValueError("推理强度无效")
        payload = _encoded({**validate_request(system, user, schema), "effort": effort})
        command = [self.python_executable, "-I", "-B", str(Path(__file__).with_name("brain_bridge_runner.py")), str(self.root)]
        try:
            result = subprocess.run(command, input=payload, text=True, capture_output=True,
                                    timeout=min(float(timeout), MODEL_TIMEOUT), check=False)
            if len(result.stdout.encode()) > 1_000_000:
                raise BrainUnavailable("第二大脑 Gemini 暂不可用。")
            if result.returncode != 0:
                try:
                    error = json.loads(result.stdout).get("error")
                except (ValueError, AttributeError):
                    error = None
                if error == "blocked":
                    raise BrainBlocked("第二大脑 Gemini 拒绝了这次请求。")
                if error == "timeout":
                    raise BrainTimeout("第二大脑 Gemini 响应超时。")
                raise BrainUnavailable("第二大脑 Gemini 暂不可用。")
            response = json.loads(result.stdout)
            if response.get("ok") is not True or not isinstance(response.get("result"), dict):
                raise BrainUnavailable("第二大脑 Gemini 返回格式异常。")
            _encoded(response["result"])
            return response["result"]
        except BrainUnavailable:
            raise
        except subprocess.TimeoutExpired as exc:
            raise BrainTimeout("第二大脑 Gemini 响应超时。") from exc
        except (OSError, subprocess.SubprocessError, ValueError, AttributeError, TypeError) as exc:
            raise BrainUnavailable("第二大脑 Gemini 暂不可用。") from exc

    def auto_events(self) -> list[dict]:
        """The library's own automatic event albums (read-only); members are filtered by the caller."""
        with self._database() as connection:
            if not connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='media_albums'").fetchone():
                return []
            albums = {str(row["id"]): {"id": str(row["id"]), "title": str(row["name"] or ""), "story": str(row["story"] or ""),
                                       "day": row["day"], "place": str(row["place"] or ""), "cover_id": row["cover_id"],
                                       "file_ids": []}
                      for row in connection.execute("SELECT id,name,story,day,place,cover_id FROM media_albums "
                                                    "WHERE kind='auto_event'")}
            for row in connection.execute("SELECT album_id,file_id FROM album_items ORDER BY album_id,position"):
                album = albums.get(str(row["album_id"]))
                if album is not None and isinstance(row["file_id"], str):
                    album["file_ids"].append(row["file_id"])
            return list(albums.values())


def _received_iso(value) -> str | None:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=ZoneInfo("Asia/Shanghai"))
        return parsed.astimezone(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds")
    except (ValueError, TypeError):
        return None
