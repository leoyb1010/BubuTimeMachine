"""Family-scoped application service for lessons and existing timeline evidence.

HTTP requests authorize/read immutable resources or enqueue work. They never
call a model, identify a child, or download an original from another service.
"""
from __future__ import annotations

from datetime import date as Date, datetime, timedelta, timezone
import math
from pathlib import Path
import re
import time
from urllib.parse import quote
import uuid
from zoneinfo import ZoneInfo

import httpx
from fastapi import HTTPException

from memory_query import PocketBaseMemoryStore, _pb_quote
from . import fsrs
from .models import Draft, Segment, ground_draft, label_colors, normalize, prompt_role
from .processing import CONTENT_PIPELINE_VERSION, MediaProcessor, ProcessingUnavailable, clip_parameters
from .store import COURSE_KINDS, Conflict, Missing, digest, valid_day


RESOURCE = re.compile(r"^[a-f0-9]{64}\.(?:jpg|m4a)$")
HASH = re.compile(r"^[a-f0-9]{64}$")
CHOICE_KINDS = {"listen_choice", "color_choice", "sort"}
CURRENT_PACKS = {"draft", "published", "no_lesson"}
UPLOAD_MIMES = {"image/jpeg", "image/png", "image/heic", "image/heif", "video/mp4", "video/quicktime",
                "audio/mp4", "audio/mpeg", "audio/wav"}


def _iso(value):
    if value is None:
        return None
    try:
        stamp = datetime.fromtimestamp(value, timezone.utc) if isinstance(value, (int, float)) else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=ZoneInfo("Asia/Shanghai"))
        return stamp.astimezone(timezone.utc).isoformat()
    except (ValueError, TypeError, OverflowError):
        return None


def _analysis_public(payload):
    segments = []
    for raw in payload.get("segments", []):
        try:
            segments.append(Segment.model_validate({k: raw[k] for k in ("id", "start", "end", "text")}).model_dump())
        except (ValueError, TypeError, KeyError):
            continue
    return {"description": str(payload.get("description") or ""), "ocr": str(payload.get("ocr") or ""),
            "tags": [t for t in payload.get("tags", []) if isinstance(t, str)], "segments": segments,
            "warnings": [w for w in payload.get("warnings", []) if isinstance(w, str)]}


class LearningService:
    def __init__(self, store, processor, *, brain_sync=None, pocketbase=None,
                 school_inbox_display="iPhone 保存到照片后自动同步；收件夹仅作备用入口"):
        self.store, self.processor = store, processor
        self.brain_sync, self.pocketbase = brain_sync, pocketbase
        self.school_inbox_display = school_inbox_display

    def _pb(self):
        if self.pocketbase is None:
            self.pocketbase = PocketBaseMemoryStore()
        return self.pocketbase

    def context(self, scope):
        pending = sum(job["state"] in {"queued", "running"} for job in self.store.jobs(scope.family_id))
        return {"user": {"id": scope.user_id, "can_review": scope.can_review}, "children": scope.children,
                "default_child": scope.children[0]["id"] if scope.children else None,
                "source_status": {"last_sync": None, "imported": 0, "pending": pending, "error": ""},
                "course_kinds": [{"id": "teaching", "label": "教学"}, {"id": "practice", "label": "练习"}, {"id": "song", "label": "儿歌"}]}

    def _pack(self, scope, pid, *, published=False):
        pack = self.store.pack(scope.family_id, pid)
        scope.require_child(pack["child_id"])
        if (published or not scope.can_review) and pack["status"] != "published":
            raise Missing("课程尚未发布")
        if pack["status"] == "published":
            pack = self.store.pack(scope.family_id, pid, require_published=True)
        return pack

    def days(self, scope, child_id, start, end):
        scope.require_child(child_id)
        valid_day(start); valid_day(end)
        if not 0 <= (Date.fromisoformat(end) - Date.fromisoformat(start)).days <= 400:
            raise ValueError("日期范围无效")
        result = {}
        for course in self.courses(scope, child_id, start, end)["items"]:
            counts = result.setdefault(course["school_date"], {"date": course["school_date"], "course_count": 0,
                                                              "source_count": 0, "pack_count": 0, "published_count": 0})
            counts["course_count"] += 1
            counts["source_count"] += course["source_count"]
            counts["pack_count"] += int(course["pack"] is not None)
            counts["published_count"] += int(course["state"] == "published")
        return {"days": [result[key] for key in sorted(result)]}

    def packs(self, scope, child_id, day):
        scope.require_child(child_id); valid_day(day)
        result = []
        for pack in self.store.packs(scope.family_id, child_id, day, published_only=not scope.can_review, courses_only=True):
            if pack["status"] not in CURRENT_PACKS:
                continue
            try:
                result.append(self._public_pack(self._pack(scope, pack["id"])))
            except (Missing, Conflict):
                continue
        return {"items": result}

    def pack(self, scope, pid):
        return self._public_pack(self._pack(scope, pid))

    @staticmethod
    def _resource_url(pid, name):
        if not isinstance(name, str) or not RESOURCE.fullmatch(name):
            return None
        return "/learning/api/packs/" + quote(pid, safe="") + "/resources/" + name

    def _public_clip(self, pid, clip):
        if not isinstance(clip, dict):
            return None
        result = {key: clip[key] for key in ("source_id", "segment_id", "role", "text", "start", "end", "audio_hash") if key in clip}
        result["audio_url"] = self._resource_url(pid, clip.get("audio_resource"))
        result["image_url"] = self._resource_url(pid, clip.get("image_resource"))
        return result

    def _public_activity(self, pid, activity):
        result = {key: activity.get(key) for key in ("id", "kind", "title", "concept", "instruction", "correct_choice")}
        result.update(prompt=self._public_clip(pid, activity.get("prompt")), answer=self._public_clip(pid, activity.get("answer")), choices=[])
        for choice in activity.get("choices", []):
            row = {key: choice[key] for key in ("id", "label", "color") if key in choice}
            if activity.get("kind") == "color_choice":
                row["colors"] = label_colors(str(choice.get("label") or ""))
            row.update(evidence=self._public_clip(pid, choice.get("evidence")), image_url=self._resource_url(pid, choice.get("image_resource")))
            result["choices"].append(row)
        return result

    def _readable(self, pack, text):
        """Model notes may cite internal source IDs; parents see file names instead."""
        text = str(text)
        for sid in pack.get("source_ids", []):
            if sid in text:
                try:
                    name = self.store.source(pack["family_id"], sid)["name"]
                except Missing:
                    name = "一份素材"
                text = text.replace(sid, "「" + name + "」")
        return re.sub(r"\b[a-f0-9]{24,64}\b", "一份素材", text)

    def _public_pack(self, pack):
        payload = pack["payload"]
        return {key: pack[key] for key in ("id", "child_id", "school_date", "revision", "status")} | {
            "course_id": pack.get("course_id", ""),
            "title": payload.get("title", "学习内容"),
            "payload": {"title": payload.get("title", "学习内容"), "summary": self._readable(pack, payload.get("summary", "")),
                        "intro": self._readable(pack, payload.get("intro", "")),
                        "key_words": [w for w in payload.get("key_words", []) if isinstance(w, str)],
                        "activities": [self._public_activity(pack["id"], a) for a in payload.get("activities", [])],
                        "warnings": [self._readable(pack, w) for w in payload.get("warnings", [])]},
            "confirmations": [{"activity_id": a["id"], "digest": digest(a)} for a in payload.get("activities", [])],
        }

    def _source(self, scope, sid):
        source = self.store.source(scope.family_id, sid)
        scope.require_child(source["child_id"])
        return source

    def _public_source(self, source):
        analysis = self.store.analysis(source["family_id"], source["asset_id"])
        state = analysis["state"] if analysis else "queued"
        if state != "ready":
            with self.store.db() as db:
                job = db.execute("SELECT state FROM jobs WHERE family_id=? AND kind='analyze' AND job_key=?",
                                 (source["family_id"], source["asset_id"])).fetchone()
            if job and job[0] == "running":
                state = "processing"
        return {"id": source["id"], "name": source["name"], "kind": source["kind"], "mime": source["mime"],
                "school_date": source["school_date"], "date_confirmed": bool(source.get("date_confirmed")), "state": state,
                "revision": analysis["revision"] if analysis else 0,
                "analysis": _analysis_public(analysis["payload"]) if analysis and state == "ready" else _analysis_public({}),
                "error": "素材解析未完成，请核对原片后重试。" if state in {"failed", "unavailable"} else "",
                "original_url": "/learning/api/sources/" + quote(source["id"], safe="") + "/file"}

    def sources(self, scope, child_id, day):
        scope.require_child(child_id); valid_day(day)
        if not scope.can_review:
            return {"items": []}
        result = []
        for source in self.store.sources(scope.family_id, child_id, day):
            try:
                result.append(self._public_source(self._source(scope, source["id"])))
            except (Missing, Conflict):
                continue
        return {"items": result}

    def source_file(self, scope, sid):
        scope.require_review()
        source = self._source(scope, sid)
        try:
            path = self.store.asset_path(scope.family_id, source["asset_id"])
            MediaProcessor.verify_file(path, source["hash"])
        except (OSError, ProcessingUnavailable) as exc:
            raise Missing("原片不可用") from exc
        return path, source["mime"]

    @staticmethod
    def _resources(pack):
        result = set()
        for activity in pack["payload"].get("activities", []):
            for clip in (activity.get("prompt"), activity.get("answer")):
                if isinstance(clip, dict):
                    result.update(name for key in ("audio_resource", "image_resource")
                                  if isinstance(name := clip.get(key), str) and RESOURCE.fullmatch(name))
            result.update(c["image_resource"] for c in activity.get("choices", [])
                          if isinstance(c.get("image_resource"), str) and RESOURCE.fullmatch(c["image_resource"]))
        return result

    def resource(self, scope, pid, name):
        pack = self._pack(scope, pid)
        if pack["status"] not in {"draft", "published"} or not RESOURCE.fullmatch(name) or name not in self._resources(pack):
            raise Missing("资源不属于当前课程")
        self._check_sources(pack)
        try:
            path = self.processor.resource_path(scope.family_id, name)
        except (OSError, ValueError, ProcessingUnavailable) as exc:
            raise Missing("课程资源不可用") from exc
        return path, "audio/mp4" if name.endswith(".m4a") else "image/jpeg"

    def _check_sources(self, pack):
        result = {}
        for sid in pack["source_ids"]:
            source = self.store.source(pack["family_id"], sid)
            analysis = self.store.analysis(pack["family_id"], source["asset_id"])
            if (source["child_id"] != pack["child_id"] or source["school_date"] != pack["school_date"]
                    or not analysis or analysis["state"] != "ready"
                    or pack.get("analysis_revisions", {}).get(source["asset_id"]) != analysis["revision"]):
                raise Conflict("课程证据已更新")
            result[sid] = {**source, "analysis": analysis["payload"]}
        return result

    def _validate_content(self, pack, sources):
        """Content lessons: narrator prompts, frames from the course's own analysis, exact song clips."""
        frames = {f.get("resource") for s in sources.values() for f in s["analysis"].get("frames", []) if isinstance(f, dict)}
        def audio(clip):
            name = clip.get("audio_resource")
            if name is None:
                return
            if not isinstance(name, str) or not RESOURCE.fullmatch(name) or not name.endswith(".m4a") or clip.get("audio_hash") != name[:-4]:
                raise ValueError("音频引用无效")
        def image(owner):
            name = owner.get("image_resource")
            if name is not None and name not in frames:
                raise ValueError("图片不是本课的采样画面")
        activities = pack["payload"].get("activities", [])
        if not activities or len({a["id"] for a in activities}) != len(activities):
            raise ValueError("活动为空或编号重复")
        for raw in activities:
            if raw["kind"] not in {"listen_choice", "color_choice", "sort", "speak", "music"}:
                raise ValueError("活动类型无效")
            if not all(isinstance(raw.get(key), str) and raw[key] for key in ("id", "title", "concept", "instruction")):
                raise ValueError("活动文字缺失")
            prompt, answer = raw["prompt"], raw.get("answer")
            if prompt.get("role") != prompt_role(raw["kind"]) or not isinstance(prompt.get("text"), str) or not prompt["text"]:
                raise ValueError("题目角色无效")
            audio(prompt); image(prompt)
            if prompt.get("origin") == "source":
                source = sources[prompt["source_id"]]
                expected = clip_parameters(source, prompt["segment_id"])
                if raw["kind"] != "music" or prompt.get("source_hash") != source["hash"] or any(prompt.get(k) != v for k, v in expected.items()):
                    raise ValueError("原片片段不一致")
            if answer is not None:
                if answer.get("role") != "answer" or not isinstance(answer.get("text"), str) or not answer["text"]:
                    raise ValueError("反馈无效")
                audio(answer)
            ids = [c["id"] for c in raw.get("choices", [])]
            for choice in raw.get("choices", []):
                image(choice)
                if not isinstance(choice.get("label"), str) or not choice["label"]:
                    raise ValueError("选项文字缺失")
            if raw["kind"] in CHOICE_KINDS:
                if not 2 <= len(ids) <= 4 or len(set(ids)) != len(ids) or raw.get("correct_choice") not in ids or answer is None:
                    raise ValueError("选择题不完整")
            elif ids or raw.get("correct_choice"):
                raise ValueError("非选择题不带选项")
            if raw["kind"] == "speak" and answer is None:
                raise ValueError("跟说缺少目标")
        for source in sources.values():
            MediaProcessor.verify_file(self.store.asset_path(pack["family_id"], source["asset_id"]), source["hash"])
        for name in self._resources(pack):
            self.processor.resource_path(pack["family_id"], name)

    def _validate_materials(self, pack):
        sources = self._check_sources(pack)
        if pack["payload"].get("pipeline_version") == CONTENT_PIPELINE_VERSION:
            try:
                return self._validate_content(pack, sources)
            except (ValueError, TypeError, KeyError, AttributeError, OSError, ProcessingUnavailable) as exc:
                raise Conflict("题目、声音或图片尚未核对完整，请重新生成。") from exc
        def reference(value):
            return {key: value[key] for key in ("source_id", "segment_id", "role")}
        try:
            activities = []
            for raw in pack["payload"].get("activities", []):
                value = {key: raw.get(key) for key in ("id", "kind", "title", "concept", "instruction", "correct_choice")}
                value.update(prompt=reference(raw["prompt"]), answer=reference(raw["answer"]) if raw.get("answer") else None,
                             choices=[{**{key: c[key] for key in ("id", "label", "color") if key in c}, "evidence": reference(c["evidence"])} for c in raw.get("choices", [])])
                activities.append(value)
            draft = Draft.model_validate({"title": pack["payload"]["title"], "summary": pack["payload"].get("summary", ""),
                "material_kind": pack["payload"].get("material_kind", "uncertain"), "activities": activities})
            grounded = ground_draft(draft, sources)
            for raw, checked in zip(pack["payload"]["activities"], grounded["activities"]):
                for field in ("prompt", "answer"):
                    if checked.get(field) is None:
                        continue
                    clip, expected = raw[field], checked[field]
                    if any(clip.get(key) != expected.get(key) for key in ("source_id", "segment_id", "source_hash", "role", "text", "start", "end")):
                        raise ValueError()
                    name = clip.get("audio_resource", "")
                    if not RESOURCE.fullmatch(name) or not name.endswith(".m4a") or clip.get("audio_hash") != name[:-4]:
                        raise ValueError()
                for owner in [raw.get("prompt"), raw.get("answer"), *raw.get("choices", [])]:
                    image = owner.get("image_resource") if isinstance(owner, dict) else None
                    if image and (not isinstance(image, str) or not RESOURCE.fullmatch(image) or not image.endswith(".jpg")):
                        raise ValueError("图片证据引用无效")
                if raw["kind"] in CHOICE_KINDS:
                    right = next(c for c in raw["choices"] if c["id"] == raw["correct_choice"])
                    if raw["prompt"]["role"] == "cue" and normalize(right["label"]) not in normalize(raw["prompt"]["text"]):
                        raise ValueError("介绍不能替代目标原声")
                    if raw["prompt"]["role"] == "question" and not raw["prompt"].get("image_resource"):
                        raise ValueError("提问缺少画面依据")
            for source in sources.values():
                MediaProcessor.verify_file(self.store.asset_path(pack["family_id"], source["asset_id"]), source["hash"])
            for name in self._resources(pack):
                self.processor.resource_path(pack["family_id"], name)
        except (ValueError, TypeError, KeyError, StopIteration, OSError, ProcessingUnavailable) as exc:
            raise Conflict("题目、原声或图片证据尚未核对完整，请重新生成。") from exc

    def publish(self, scope, pid, revision, confirmations, date_confirmed):
        scope.require_review()
        pack = self._pack(scope, pid)
        if pack["revision"] != revision or date_confirmed is not True:
            raise Conflict("请核对当前版本和授课日期")
        self._validate_materials(pack)
        return self._public_pack(self.store.publish(scope.family_id, pid, revision, scope.user_id, confirmations, date_confirmed=True))

    def exclude(self, scope, pid, revision, activity_id):
        scope.require_review()
        pack = self._pack(scope, pid)
        if pack["revision"] != revision or pack["status"] not in {"draft", "published"}:
            raise Conflict("课程已更新")
        return self._public_pack(self.store.exclude_activity(scope.family_id, pid, revision, activity_id))

    def regenerate(self, scope, pid):
        scope.require_review()
        pack = self._pack(scope, pid)
        if not pack.get("course_id"):
            raise Conflict("旧的自动课程已停用")
        self.store.enqueue_compose(scope.family_id, pack["child_id"], pack["school_date"], pack["course_id"], uuid.uuid4().hex)
        return {"queued": True}

    def update_segments(self, scope, sid, revision, segments, school_date, date_confirmed):
        scope.require_review()
        source = self._source(scope, sid)
        analysis = self.store.analysis(scope.family_id, source["asset_id"])
        if not analysis or analysis["revision"] != revision or analysis["state"] != "ready":
            raise Conflict("素材解析已变化")
        valid_day(school_date)
        if date_confirmed is not True or not 1 <= len(segments) <= 500:
            raise ValueError("请核对转写和授课日期")
        checked = [Segment.model_validate(s).model_dump() for s in segments]
        duration = float(analysis["payload"].get("duration") or 0)
        if (not math.isfinite(duration) or duration <= 0 or any(s["end"] > duration + .15 for s in checked)
                or len({s["id"] for s in checked}) != len(checked)):
            raise ValueError("转写缺少有效时间范围")
        payload = {**analysis["payload"], "segments": checked,
                   "transcript_review": {"reviewer": scope.user_id, "at": datetime.now(timezone.utc).isoformat()}}
        source = self.store.update_source_analysis(scope.family_id, sid, revision, payload, school_date, True)
        return self._public_source(source)

    def _attempt_public(self, scope, row):
        kind = "unknown"
        try:
            pack = self.store.pack(scope.family_id, row["pack_id"])
            scope.require_child(pack["child_id"])
            kind = next(a["kind"] for a in pack["payload"].get("activities", []) if a["id"] == row["activity_id"])
        except (Missing, StopIteration):
            pass
        return {k: v for k, v in row.items() if k not in {"request_digest", "kind"}} | {"kind": kind, "event_kind": row["kind"]}

    def save_attempt(self, scope, body):
        allowed = {"id", "child_id", "pack_id", "activity_id", "kind", "choice", "run_id", "assistance", "note"}
        if set(body) - allowed:
            raise ValueError("互动记录格式无效")
        child = scope.require_child(body["child_id"])
        pack = self._pack(scope, body["pack_id"], published=True)
        if pack["child_id"] != child:
            raise Missing("课程不属于当前孩子")
        activity = next((a for a in pack["payload"]["activities"] if a["id"] == body["activity_id"]), None)
        if not activity or activity["kind"] != body["kind"]:
            raise ValueError("互动类别与当前活动不一致")
        if activity["kind"] in CHOICE_KINDS:
            event = "choice"
            if not body.get("choice"):
                raise ValueError("请选择本题选项")
        else:
            if body.get("choice"):
                raise ValueError("此活动不接受选择结果")
            event = "speaking_attempt" if activity["kind"] == "speak" else "participation"
        request = {k: body[k] for k in ("activity_id", "choice", "run_id", "assistance", "note") if k in body}
        request["kind"] = event
        saved = self.store.save_attempt(scope.family_id, child, pack["id"], body["id"], request)
        return self._attempt_public(scope, {**saved, "id": body["id"], "child_id": child, "pack_id": pack["id"]})

    def attempts(self, scope, child_id, start=None, end=None):
        scope.require_child(child_id)
        if start:
            valid_day(start)
        if end:
            valid_day(end)
        if start and end and start > end:
            raise ValueError("日期范围无效")
        rows = self.store.attempts(scope.family_id, child_id, limit=5000 if start or end else 1000)
        if start or end:
            def day(row):
                try:
                    return datetime.fromtimestamp(float(row["created_at"]), ZoneInfo("Asia/Shanghai")).date().isoformat()
                except (KeyError, TypeError, ValueError, OverflowError):
                    return None
            rows = [r for r in rows if day(r) and (not start or day(r) >= start) and (not end or day(r) <= end)]
        return {"items": [self._attempt_public(scope, row) for row in rows]}

    def reviews(self, scope, child_id, period, day):
        """FSRS-4.5 picks what is due (Good = answered alone, Again = wrong or helped); ≤5 per session."""
        scope.require_child(child_id); valid_day(day)
        if period not in {"week", "month"}:
            raise ValueError("复习范围无效")
        today = Date.fromisoformat(day)
        start = (today - timedelta(days=6 if period == "week" else 29)).isoformat()
        history = {}
        for attempt in self.attempts(scope, child_id)["items"]:
            if attempt.get("kind") == "unknown" or attempt.get("event_kind") not in {"choice", "speaking_attempt", "participation"}:
                continue
            try:
                when = datetime.fromtimestamp(float(attempt["created_at"]), ZoneInfo("Asia/Shanghai")).date()
            except (KeyError, TypeError, ValueError, OverflowError):
                continue
            if when > today:
                continue
            failed = attempt.get("correct") is False or attempt.get("assistance") is True
            history.setdefault((attempt.get("concept"), attempt["kind"]), []).append((when, fsrs.AGAIN if failed else fsrs.GOOD))
        selected = {}
        for pack in self.store.packs(scope.family_id, child_id, published_only=True, courses_only=True):
            if pack["school_date"] > day:
                continue
            try:
                pack = self._pack(scope, pack["id"], published=True)
            except (Missing, Conflict):
                continue
            for activity in pack["payload"].get("activities", []):
                key = (activity.get("concept"), activity["kind"])
                if key in selected:
                    continue
                state = fsrs.due(history.get(key, []), today)
                if state is None:
                    if pack["school_date"] < start:
                        continue
                    priority, reason = (1, 0.0), "这段原声还没一起玩过。"
                else:
                    is_due, recall, last = state
                    if is_due:
                        priority = (0, recall)
                        reason = "上次需要一点提示，再轻松玩一次。" if last == fsrs.AGAIN else "隔几天，再听一次熟悉的原声。"
                    elif pack["school_date"] >= start:
                        # Not due yet, but from this week/month: offered after everything due,
                        # so a review right after a lesson is never an empty page.
                        priority, reason = (2, recall), "刚学过不久，想玩也可以再听一次。"
                    else:
                        continue
                selected[key] = (priority, {"pack_id": pack["id"], "activity_id": activity["id"], "concept": activity.get("concept", ""),
                                          "reason": reason, "activity": self._public_activity(pack["id"], activity)})
        ordered = sorted(selected.values(), key=lambda value: value[0])[:5]
        return {"window_start": start, "window_end": day, "items": [item for _, item in ordered]}

    # Parent-uploaded courses. Each upload is one lesson; nothing is picked from photos.
    def create_course(self, scope, child_id, day, title, kind, language, files, total_files=0, note=""):
        """total_files > len(files) announces more files that follow via add_course_file."""
        scope.require_review()
        child = scope.require_child(child_id)
        valid_day(day)
        total = total_files or len(files)
        if kind not in COURSE_KINDS or language not in {"en-US", "zh-CN"}:
            raise ValueError("课程类型无效")
        if not 1 <= len(files) <= total <= 8:
            raise ValueError("每节课请上传1到8个文件")
        if not any(mime.startswith(("video/", "audio/")) for _, _, mime in files):
            raise ValueError("每节课至少需要一段带老师声音的视频或音频")
        if any(mime not in UPLOAD_MIMES for _, _, mime in files):
            raise ValueError("不支持的文件格式")
        course = self.store.create_course(scope.family_id, child, day, title, kind, language, scope.user_id, total, note)
        try:
            for index, (name, path, mime) in enumerate(files):
                self.store.add_source(scope.family_id, child, day, "course:%s:%d" % (course["id"], index), name, Path(path),
                                      mime, kind=kind, language=language, course_id=course["id"],
                                      media_ref={"origin": "parent_upload", "uploaded_by": scope.user_id})
        except Exception:
            self.store.remove_course(scope.family_id, course["id"])
            raise
        return self.course(scope, course["id"])

    def add_course_file(self, scope, cid, name, path, mime):
        scope.require_review()
        course = self._course(scope, cid)
        index = self.store.course_file_count(scope.family_id, cid)
        if index >= course["expected_files"]:
            raise Conflict("这节课的文件已经上传完整")
        if mime not in UPLOAD_MIMES:
            raise ValueError("不支持的文件格式")
        self.store.add_source(scope.family_id, course["child_id"], course["school_date"], "course:%s:%d" % (cid, index), name,
                              Path(path), mime, kind=course["kind"], language=course["language"], course_id=cid,
                              media_ref={"origin": "parent_upload", "uploaded_by": scope.user_id})
        return self.course(scope, cid)

    def _course(self, scope, cid):
        course = self.store.course(scope.family_id, cid)
        scope.require_child(course["child_id"])
        return course

    def _course_public(self, scope, course, *, detail=False):
        sources = self.store.sources(scope.family_id, course["child_id"], course["school_date"], course_id=course["id"])
        public_sources = [self._public_source(source) for source in sources]
        packs = [p for p in self.store.packs(scope.family_id, course["child_id"], course["school_date"], course_id=course["id"])
                 if p["status"] in CURRENT_PACKS]
        pack = None
        for candidate in packs:
            try:
                checked = self._pack(scope, candidate["id"])
            except (Missing, Conflict):
                continue
            pack = checked
            break
        states = {source["state"] for source in public_sources}
        if len(sources) < course["expected_files"]:
            state = "uploading"
        elif states & {"failed", "unavailable"}:
            state = "failed"
        elif states - {"ready"} or not public_sources:
            state = "processing"
        elif pack is None:
            failed = self.store.compose_job_state(scope.family_id, course["child_id"], course["school_date"], course["id"]) == "failed"
            state = ("failed" if failed else "processing") if scope.can_review else "waiting"
        else:
            state = pack["status"]
            # A note change or retry is regenerating an unpublished lesson: show that, not the stale draft.
            if state != "published" and self.store.compose_job_state(
                    scope.family_id, course["child_id"], course["school_date"], course["id"]) in {"queued", "running"}:
                state = "processing"
        if not scope.can_review and state != "published":
            state, pack = "waiting", None
        result = {key: course[key] for key in ("id", "child_id", "school_date", "title", "kind", "language")}
        result["note"] = course.get("note") or ""
        result.update(created_at=_iso(course["created_at"]), state=state, source_count=len(sources),
                      expected_files=max(course["expected_files"], len(sources)),
                      activity_count=len(pack["payload"].get("activities", [])) if pack else 0,
                      pack=self._public_pack(pack) if pack and detail else ({"id": pack["id"], "status": pack["status"]} if pack else None))
        if detail:
            result["sources"] = public_sources if scope.can_review else []
        return result

    def courses(self, scope, child_id, start, end):
        child = scope.require_child(child_id)
        valid_day(start); valid_day(end)
        if not 0 <= (Date.fromisoformat(end) - Date.fromisoformat(start)).days <= 400:
            raise ValueError("日期范围无效")
        return {"items": [self._course_public(scope, course) for course in self.store.courses(scope.family_id, child, start, end)]}

    def course(self, scope, cid):
        return self._course_public(scope, self._course(scope, cid), detail=True)

    def retry_course(self, scope, cid):
        scope.require_review()
        self._course(scope, cid)
        self.store.retry_course(scope.family_id, cid, uuid.uuid4().hex)
        return self.course(scope, cid)

    def update_course(self, scope, cid, note):
        """PATCH courses/{cid}: save the parent's note and regenerate the lesson from it."""
        scope.require_review()
        self._course(scope, cid)
        self.store.set_course_note(scope.family_id, cid, note, uuid.uuid4().hex)
        return self.course(scope, cid)

    def delete_course(self, scope, cid):
        scope.require_review()
        self._course(scope, cid)
        self.store.remove_course(scope.family_id, cid)
        return {"deleted": True}

    def _media_fact(self, scope, mid):
        if not isinstance(mid, str) or not mid.isalnum() or len(mid) > 128:
            raise Missing("媒体不存在")
        try:
            media = self._pb().get_record("media", mid)
            if media.get("id") != mid or media.get("familyId") != scope.family_id or media.get("isDeleted") or not media.get("file"):
                raise Missing("媒体不可用")
            local = media.get("entryLocalId")
            if not local:
                raise Missing("媒体尚未关联时光")
            entry = self._pb().first_record("entries", filter_value="familyId='%s' && localId='%s'" % (_pb_quote(scope.family_id), _pb_quote(local)), sort="id")
            if not entry or entry.get("familyId") != scope.family_id or entry.get("isDeleted") or entry.get("isArchived"):
                raise Missing("时光不可用")
            return media, entry
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 404:
                raise Missing("媒体不存在") from None
            raise HTTPException(503, "暂时无法核对时光资料。") from None
        except httpx.HTTPError:
            raise HTTPException(503, "暂时无法核对时光资料。") from None

    def _registry(self, scope):
        if self.brain_sync is None:
            return {}
        registry = self.brain_sync.registry()
        if registry.get("family_id") != scope.family_id or registry.get("child_id") not in {c["id"] for c in scope.children}:
            return {}
        return registry.get("items", {})

    @staticmethod
    def _media_dto(mid, sha, state, *, payload=None, revision=0, updated_at=None):
        return {"media_id": mid, "content_hash": sha, "state": state, "revision": revision,
                "provider": "second-brain", **_analysis_public(payload or {}), "updated_at": _iso(updated_at)}

    def media_analysis(self, scope, mid, retry=False):
        media, _ = self._media_fact(scope, mid)
        sha = media.get("contentHash") or ""
        if not HASH.fullmatch(sha):
            return self._media_dto(mid, None, "unavailable", payload={"warnings": ["素材尚无可核对的校验值，请先完成媒体同步。"]})
        key = "media-analysis:" + digest([scope.family_id, mid])
        cache = self.store.get_cursor(key, {})
        if cache.get("family_id") != scope.family_id or cache.get("media_id") != mid or cache.get("content_hash") != sha:
            cache = {}
        if not retry:
            if cache.get("state") in {"queued", "processing", "failed", "unavailable"}:
                return self._media_dto(mid, sha, cache["state"], updated_at=cache.get("updated_at"))
            analysis = self.store.analysis(scope.family_id, cache["asset_id"]) if cache.get("asset_id") else None
            if analysis and analysis["source_hash"] == sha and analysis["state"] == "ready":
                return self._media_dto(mid, sha, "ready", payload=analysis["payload"], revision=analysis["revision"], updated_at=analysis["updated_at"])
            for row in self._registry(scope).values():
                if row.get("media_id") == mid and row.get("status") == "synced" and row.get("provenance") == "manual" and row.get("content_hash") == sha:
                    return self._media_dto(mid, sha, "ready", payload=row.get("analysis", {}), revision=max(1, int(row.get("attempts") or 1)), updated_at=row.get("updated_at"))
            with self.store.db() as db:
                asset = db.execute("SELECT id FROM assets WHERE family_id=? AND hash=?", (scope.family_id, sha)).fetchone()
            analysis = self.store.analysis(scope.family_id, asset[0]) if asset else None
            if analysis and analysis["state"] == "ready" and analysis["source_hash"] == sha:
                return self._media_dto(mid, sha, "ready", payload=analysis["payload"], revision=analysis["revision"], updated_at=analysis["updated_at"])
        now = datetime.now(timezone.utc).isoformat()
        request = {"family_id": scope.family_id, "media_id": mid, "content_hash": sha, "state": "queued", "requested_at": now, "force": bool(retry)}
        self.store.set_cursor("media-analysis-request:" + digest([scope.family_id, mid, sha]), request)
        self.store.set_cursor(key, {**request, "updated_at": now})
        return self._media_dto(mid, sha, "queued", updated_at=now)

    def timeline_search(self, scope, query, kind, start, end, order, limit):
        if kind not in {"all", "photo", "video"} or order not in {"asc", "desc"} or type(limit) is not int or not 1 <= limit <= 100:
            raise ValueError("时光筛选条件无效")
        if start: valid_day(start)
        if end: valid_day(end)
        if start and end and start > end:
            raise ValueError("日期范围无效")
        tokens = str(query).casefold().split()
        candidates = {}
        for row in self._registry(scope).values():
            if row.get("status") != "synced" or row.get("provenance") != "manual" or not row.get("media_id", "").isalnum():
                continue
            analysis = _analysis_public(row.get("analysis", {}))
            texts = {"描述": analysis["description"], "图片文字": analysis["ocr"], "标签": " ".join(analysis["tags"]),
                     "转写": " ".join(s["text"] for s in analysis["segments"])}
            if not all(token in " ".join(texts.values()).casefold() for token in tokens):
                continue
            reason = "、".join(name for name, text in texts.items() if any(t in text.casefold() for t in tokens)) if tokens else "拍摄日期"
            candidates[row["media_id"]] = (row, analysis, reason)
        media_rows, entries = {}, {}
        try:
            ids = list(candidates)
            for offset in range(0, len(ids), 100):
                batch = ids[offset:offset + 100]
                expression = " || ".join("id='%s'" % _pb_quote(mid) for mid in batch)
                for media in self._pb().list_records("media", filter_value="familyId='%s' && (%s)" % (_pb_quote(scope.family_id), expression), sort="id"):
                    if media.get("id") in batch and media.get("familyId") == scope.family_id and not media.get("isDeleted") and media.get("file"):
                        media_rows[media["id"]] = media
            locals_ = sorted({m.get("entryLocalId") for m in media_rows.values() if m.get("entryLocalId")})
            for offset in range(0, len(locals_), 100):
                batch = locals_[offset:offset + 100]
                expression = " || ".join("localId='%s'" % _pb_quote(local) for local in batch)
                for entry in self._pb().list_records("entries", filter_value="familyId='%s' && (%s)" % (_pb_quote(scope.family_id), expression), sort="id"):
                    if entry.get("localId") in batch and entry.get("familyId") == scope.family_id and not entry.get("isDeleted") and not entry.get("isArchived"):
                        entries[entry["localId"]] = entry
        except httpx.HTTPError:
            raise HTTPException(503, "暂时无法核对时光资料。") from None
        result = []
        for mid, media in media_rows.items():
            row, analysis, reason = candidates[mid]
            entry = entries.get(media.get("entryLocalId"))
            if (not entry or media.get("contentHash") != row.get("content_hash") or not HASH.fullmatch(media.get("contentHash") or "")
                    or media.get("mediaType") not in {"photo", "video"} or (kind != "all" and media["mediaType"] != kind)
                    or (media.get("resourceRole") or "display") != "display"):
                continue
            captured = _iso(entry.get("happenedAt"))
            if not captured:
                continue
            local_day = datetime.fromisoformat(captured).astimezone(ZoneInfo("Asia/Shanghai")).date().isoformat()
            if (start and local_day < start) or (end and local_day > end):
                continue
            result.append({"entry_local_id": entry["localId"], "media_id": mid, "media_local_id": media.get("localId", ""),
                           "captured_at": captured, "description": analysis["description"], "tags": analysis["tags"],
                           "source": "second-brain", "identity_status": "confirmed", "match_reason": reason})
        result.sort(key=lambda row: (row["captured_at"], row["media_id"]), reverse=order == "desc")
        return {"items": result[:limit], "total": len(result), "has_more": len(result) > limit}
