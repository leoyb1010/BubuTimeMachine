"""
布布时光机 · AI 伴生服务（FastAPI）
================================

隐私至上、自托管。App 端的 BubuAIService 调用本服务，本服务再调 LLM。
换模型 = 改本服务配置，App 一行不改。

能力：
  POST /rewrite-first-person   父母视角 → 布布第一人称日记
  POST /classify               一条记录的事件/地点/标签归类
  POST /detect-first-time      依据标签判断"是否人生第一次"
  POST /movie-narration        年度成长电影旁白稿
  POST /transcribe             语音转写（Whisper，可选；未装则降级提示）
  POST /parse-natural-capture  一句话自然语言 → 多条结构化记录（疫苗/成长/餐食/睡眠…）
  POST /sound-ring/draft       真实原声清单（家庭确认前不渲染）
  POST /sound-ring/render      声音年轮异步渲染
  GET  /health                 健康检查

默认接 DeepSeek（OpenAI 兼容协议）。环境变量见 .env.example。
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import secrets
import time
import httpx
from collections import Counter, defaultdict, deque
from datetime import datetime
from pathlib import Path
from threading import Lock
from typing import Any, Literal, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Request, UploadFile, File
from fastapi.responses import FileResponse, Response, StreamingResponse
from pydantic import BaseModel, Field

from llm import LLMClient, LLMError
from artifact_workflow import ArtifactUnavailable
import movie_render
from semantic_index import SemanticIndex
from semantic_model import MobileCLIPEncoder, SemanticModelUnavailable
from memory_query import PocketBaseMemoryStore
from weekly_report import WeeklyReportService, WeeklyReportUnavailable
from sound_ring import SoundRingService, SoundRingUnavailable

logging.basicConfig(
    level=os.environ.get("AI_LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)

app = FastAPI(title="布布时光机 AI 服务", version="1.4.0")

llm = LLMClient()

logger = logging.getLogger("bubu.ai")

# /parse-natural-capture 质量观测：warnings 计数（含 llm_output_unparseable 率），
# 进程内累计，带鉴权的 /health 返回快照——LLM 输出漂移早发现。
_parse_stats_lock = Lock()
_parse_stats: Counter = Counter()
_semantic_lock = Lock()
_semantic_index: Optional[SemanticIndex] = None
_semantic_encoder: Optional[MobileCLIPEncoder] = None


def _record_parse_stats(resp: "NaturalParseResp") -> None:
    with _parse_stats_lock:
        _parse_stats["requests"] += 1
        _parse_stats["items"] += len(resp.items)
        for w in resp.warnings:
            _parse_stats[f"warn:{w}"] += 1
    if resp.warnings:
        logger.info("parse-natural-capture warnings=%s items=%d",
                    ",".join(resp.warnings), len(resp.items))

# ---------- 鉴权 + 限流（公网暴露时的最低防线）----------
# 客户端是原生 App，无需 CORS；浏览器跨域一律不放行（不挂 CORSMiddleware 即默认拒绝）。

_API_KEY = os.environ.get("AI_API_KEY", "")
_RATE_LIMIT = int(os.environ.get("AI_RATE_LIMIT_PER_MINUTE", "30"))
_PREAUTH_RATE_LIMIT = int(os.environ.get("AI_PREAUTH_RATE_LIMIT_PER_MINUTE", "120"))
_rate_lock = Lock()
_rate_buckets: dict[str, deque] = defaultdict(deque)
_pb_auth_lock = Lock()
_pb_auth_cache: dict[str, tuple[float, str]] = {}
_PB_AUTH_CACHE_SECONDS = max(30, int(os.environ.get("PB_AUTH_CACHE_SECONDS", "300")))


def _check_rate(bucket_key: str, limit: Optional[int] = None) -> None:
    now = time.monotonic()
    effective_limit = _RATE_LIMIT if limit is None else limit
    with _rate_lock:
        for key, bucket in list(_rate_buckets.items()):
            while bucket and now - bucket[0] > 60:
                bucket.popleft()
            if not bucket:
                del _rate_buckets[key]
        bucket = _rate_buckets[bucket_key]
        if len(bucket) >= effective_limit:
            raise HTTPException(status_code=429, detail="请求太频繁，请稍后再试。")
        bucket.append(now)


def _pocketbase_principal(
    authorization: Optional[str], preauth_bucket: str = "preauth:unknown"
) -> Optional[str]:
    """把 App 已有的 PocketBase 登录态换成 AI 服务主体；只缓存 token 摘要，不落原文。"""
    value = (authorization or "").strip()
    if not value.lower().startswith("bearer "):
        return None
    token = value[7:].strip()
    if not token:
        return None
    digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
    now = time.monotonic()
    with _pb_auth_lock:
        cached = _pb_auth_cache.get(digest)
        if cached and cached[0] > now:
            return "pb:" + cached[1]
        if cached:
            _pb_auth_cache.pop(digest, None)

    # 只有未命中合法 token 缓存、确实要打到 PocketBase 时才计数，避免伪造 Bearer
    # 把公网一次请求放大成一次本机 auth-refresh；缓存内的家庭正常请求不占该桶。
    _check_rate(preauth_bucket, _PREAUTH_RATE_LIMIT)
    base_url = os.environ.get("PB_BASE_URL", "http://127.0.0.1:8090").rstrip("/")
    try:
        with httpx.Client(timeout=5, trust_env=False) as client:
            response = client.post(
                base_url + "/api/collections/users/auth-refresh",
                headers={"Authorization": "Bearer " + token},
            )
    except httpx.HTTPError:
        return None
    if response.status_code != 200:
        return None
    try:
        record = response.json().get("record") or {}
        user_id = str(record.get("id") or "")
    except (TypeError, ValueError):
        return None
    if not user_id:
        return None
    with _pb_auth_lock:
        _pb_auth_cache[digest] = (now + _PB_AUTH_CACHE_SECONDS, user_id)
    return "pb:" + user_id


def _authorized_principal(
    x_api_key: Optional[str], authorization: Optional[str], preauth_bucket: str
) -> Optional[str]:
    if _API_KEY and secrets.compare_digest(x_api_key or "", _API_KEY):
        return "service:" + hashlib.sha256(_API_KEY.encode("utf-8")).hexdigest()
    return _pocketbase_principal(authorization, preauth_bucket)


def require_api_key(
    request: Request,
    x_api_key: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
) -> None:
    """业务路由接受服务账号 key 或 App 的 PocketBase 用户登录态；两者都没有时 fail-closed。"""
    client_host = request.client.host if request.client else "unknown"
    principal = _authorized_principal(
        x_api_key, authorization, "preauth:" + client_host
    )
    if principal is None:
        logger.warning("unauthorized request path=%s ip=%s",
                       request.url.path, request.client.host if request.client else "unknown")
        raise HTTPException(status_code=401, detail="鉴权失败：请先登录家庭服务器。")
    # 鉴权后按服务主体/用户计数，反代后的共享源 IP 不会让全家互相挤占额度。
    _check_rate(principal)


# ---------- 请求/响应模型 ----------

class RewriteReq(BaseModel):
    note: str = Field(..., max_length=4000)
    child_name: str = Field("布布", max_length=40)
    mood: Optional[str] = Field(default=None, max_length=80)
    age_description: Optional[str] = Field(default=None, max_length=80)


class RewriteResp(BaseModel):
    first_person: str


class ClassifyReq(BaseModel):
    note: Optional[str] = Field(default=None, max_length=4000)
    tags: list[str] = Field(default_factory=list, max_length=50)
    location_name: Optional[str] = Field(default=None, max_length=120)


class ClassifyResp(BaseModel):
    suggested_title: Optional[str] = None
    event_cluster: Optional[str] = None
    place_name: Optional[str] = None
    visual_tags: list[str] = []


class DetectFirstReq(BaseModel):
    tags: list[str] = Field(default_factory=list, max_length=50)
    note: Optional[str] = Field(default=None, max_length=4000)
    child_name: str = Field("布布", max_length=40)


class DetectFirstResp(BaseModel):
    is_first: bool
    what: Optional[str] = None
    confidence: float = 0.0


class MovieReq(BaseModel):
    child_name: str = Field("布布", max_length=40)
    year: int
    highlights: list[str] = Field(default_factory=list, max_length=200)   # 该岁的若干记录摘要


class MovieResp(BaseModel):
    narration: str


class QARecord(BaseModel):
    id: str = Field(max_length=64)
    date: str = Field("", max_length=40)       # 已在 App 侧格式化，如 "2025年6月3日"
    age: str = Field("", max_length=40)         # 当时年龄
    text: str = Field("", max_length=1000)


class AskReq(BaseModel):
    question: str = Field(max_length=500)
    child_name: str = Field("布布", max_length=40)
    records: list[QARecord] = Field(default_factory=list, max_length=40)   # App 检索出的相关记录


class AskResp(BaseModel):
    answer: str
    used_ids: list[str] = Field(default_factory=list)   # 答案实际引用到的记录 id


class SemanticSearchReq(BaseModel):
    query: str = Field(..., min_length=1, max_length=200)
    limit: int = Field(20, ge=1, le=50)


class SemanticSearchHit(BaseModel):
    asset_id: str
    entry_local_id: str
    media_record_id: str
    captured_at: str
    score: float
    reason: str


class SemanticSearchResp(BaseModel):
    query: str
    model_version: str
    hits: list[SemanticSearchHit] = Field(default_factory=list)


class WeeklyReportSource(BaseModel):
    source_id: str
    collection: str
    record_id: str
    local_id: str
    happened_at: str
    title: str
    excerpt: str
    kind: str


class WeeklyReportSection(BaseModel):
    kind: str
    title: str
    text: str
    sourceIds: list[str] = Field(default_factory=list)


class WeeklyReportResp(BaseModel):
    id: str
    artifact_key: str
    status: str
    title: str
    summary: str
    week_start: str
    week_end: str
    generated_at: str
    model_version: str
    content_hash: str
    sections: list[WeeklyReportSection] = Field(default_factory=list)
    source_refs: list[WeeklyReportSource] = Field(default_factory=list)


class WeeklyReportArchiveReq(BaseModel):
    artifact_id: str = Field(..., min_length=1, max_length=64)


class SoundRingClipResp(BaseModel):
    source_id: str
    photo_source_id: str
    age_years: int
    kind: str
    title: str
    recorded_at: str
    transcript: str
    duration_seconds: float
    start_seconds: float
    end_seconds: float


class SoundRingResp(BaseModel):
    id: str
    artifact_key: str
    status: str
    title: str
    summary: str
    generated_at: str
    model_version: str
    original_duration_seconds: float
    rendered_duration_seconds: float
    attempts: int
    error: str
    narrator: str
    voice_cloning: bool
    has_audio: bool
    clips: list[SoundRingClipResp] = Field(default_factory=list)
    source_refs: list[WeeklyReportSource] = Field(default_factory=list)
    content_hash: str


class SoundRingArtifactReq(BaseModel):
    artifact_id: str = Field(..., min_length=1, max_length=64)


class SoundRingRemoveReq(SoundRingArtifactReq):
    source_id: str = Field(..., min_length=1, max_length=160)


def _semantic_enabled() -> bool:
    return os.environ.get("SEMANTIC_SEARCH_ENABLED", "false").lower() in {
        "1", "true", "yes", "on"
    }


def _semantic_components() -> tuple[SemanticIndex, MobileCLIPEncoder]:
    global _semantic_index, _semantic_encoder
    if not _semantic_enabled():
        raise HTTPException(status_code=503, detail="语义搜图尚未在服务器开启。")
    with _semantic_lock:
        if _semantic_encoder is None:
            _semantic_encoder = MobileCLIPEncoder()
        if _semantic_index is None:
            configured = os.environ.get("SEMANTIC_INDEX_PATH", "../derived/memory_index.sqlite")
            path = Path(configured).expanduser()
            if not path.is_absolute():
                path = Path(__file__).resolve().parent / path
            _semantic_index = SemanticIndex(path.resolve(), _semantic_encoder.model_version)
    return _semantic_index, _semantic_encoder


def _weekly_family_id() -> str:
    family_id = os.environ.get("WEEKLY_REPORT_FAMILY_ID", "").strip()
    if not family_id:
        raise HTTPException(status_code=503, detail="服务器尚未绑定周报家庭。")
    return family_id


def _weekly_report_call(action):
    try:
        with PocketBaseMemoryStore() as store:
            service = WeeklyReportService(store, llm)
            return action(service)
    except WeeklyReportUnavailable as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except httpx.HTTPError as exc:
        logger.exception("weekly report PocketBase request failed")
        raise HTTPException(status_code=503, detail="周报暂时无法读取家庭档案。") from exc
    except RuntimeError as exc:
        logger.warning("weekly report unavailable: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="周报服务尚未准备好。") from exc


def _sound_ring_family_id() -> str:
    family_id = os.environ.get("SOUND_RING_FAMILY_ID", "").strip()
    if not family_id:
        family_id = os.environ.get("WEEKLY_REPORT_FAMILY_ID", "").strip()
    if not family_id:
        raise HTTPException(status_code=503, detail="服务器尚未绑定声音年轮家庭。")
    return family_id


def _sound_ring_call(action):
    try:
        with PocketBaseMemoryStore() as store:
            return action(SoundRingService(store))
    except (SoundRingUnavailable, ArtifactUnavailable) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except httpx.HTTPError as exc:
        logger.exception("sound ring PocketBase request failed")
        raise HTTPException(status_code=503, detail="声音年轮暂时无法读取家庭档案。") from exc
    except RuntimeError as exc:
        logger.warning("sound ring unavailable: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="声音年轮服务尚未准备好。") from exc


# ---------- 路由 ----------

@app.get("/health")
def health(
    request: Request,
    x_api_key: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    # 连通性检查无需鉴权；服务 key 或 App 登录态有效时才返回服务详情。
    client_host = request.client.host if request.client else "unknown"
    if _authorized_principal(
        x_api_key, authorization, "preauth:" + client_host
    ) is not None:
        with _parse_stats_lock:
            stats = dict(_parse_stats)
        semantic_count = _semantic_index.active_count() if _semantic_index is not None else 0
        return {"ok": True, "model": llm.model, "configured": llm.is_configured,
                "auth": True, "parse_stats": stats,
                "semantic_search": {"enabled": _semantic_enabled(), "indexed": semantic_count}}
    return {"ok": True, "auth": False}


@app.post("/rewrite-first-person", response_model=RewriteResp,
          dependencies=[Depends(require_api_key)])
def rewrite_first_person(req: RewriteReq):
    sys = (
        f"你在替孩子「{req.child_name}」写一小段第一人称成长日记。"
        "口吻要像小宝宝/幼儿正在感受这个世界，不要像成年人总结。"
        "只能使用父母记录里明确出现的事实；不要新增人物、地点、动作、外貌、物品或因果。"
        "如果原文信息很少（例如只有笑声、几个字或情绪词），就写成1-2句短短的小感受，宁可朴素，也不要扩写剧情。"
        "在事实足够时，可以写具体感官和动作：看到什么、摸到什么、听到什么、身体怎么动、嘴巴尝到什么；"
        "少写抽象评价，不要重复照抄父母原文。"
        "避免套话和重复句式，尤其不要反复使用‘今天我好开心’‘妈妈说’‘我觉得’。"
        "通常80-140字；信息不足时20-50字即可。温柔、有画面感，可以有一点孩子式表达；不要用引号包裹，直接输出正文。"
    )
    parts = [f"父母记录：{req.note}"]
    if req.mood:
        parts.append(f"当时心情：{req.mood}")
    if req.age_description:
        parts.append(f"当时年龄：{req.age_description}")
    user = "\n".join(parts)
    try:
        text = llm.complete(sys, user, max_tokens=400)
    except LLMError as e:
        raise HTTPException(status_code=502, detail=str(e))
    return RewriteResp(first_person=text.strip())


@app.post("/classify", response_model=ClassifyResp,
          dependencies=[Depends(require_api_key)])
def classify(req: ClassifyReq):
    sys = (
        "你是图片/记录归类助手。基于给定的视觉标签、文字、地点，"
        "输出一个 JSON：{suggested_title:简短标题, event_cluster:事件类别(如 日常/出游/节日/里程碑), "
        "place_name:地点名或null, visual_tags:精简后的中文标签数组}。只输出 JSON。"
    )
    user = f"标签:{req.tags}\n文字:{req.note or ''}\n地点:{req.location_name or ''}"
    try:
        data = llm.complete_json(sys, user, max_tokens=300)
    except LLMError as e:
        raise HTTPException(status_code=502, detail=str(e))
    return ClassifyResp(
        suggested_title=data.get("suggested_title"),
        event_cluster=data.get("event_cluster"),
        place_name=data.get("place_name") or req.location_name,
        visual_tags=data.get("visual_tags") or req.tags,
    )


@app.post("/detect-first-time", response_model=DetectFirstResp,
          dependencies=[Depends(require_api_key)])
def detect_first_time(req: DetectFirstReq):
    sys = (
        f"你判断一张照片是否可能是孩子「{req.child_name}」的人生第一次。"
        "基于标签和文字，输出 JSON：{is_first:bool, what:'第一次xxx'或null, confidence:0~1}。"
        "保守一些，只有较明显时才 is_first=true。只输出 JSON。"
    )
    user = f"标签:{req.tags}\n文字:{req.note or ''}"
    try:
        data = llm.complete_json(sys, user, max_tokens=200)
    except LLMError as e:
        raise HTTPException(status_code=502, detail=str(e))
    return DetectFirstResp(
        is_first=bool(data.get("is_first")),
        what=data.get("what"),
        confidence=float(data.get("confidence") or 0.0),
    )


@app.post("/movie-narration", response_model=MovieResp,
          dependencies=[Depends(require_api_key)])
def movie_narration(req: MovieReq):
    sys = (
        f"你是温暖的家庭纪录片旁白撰稿人。为孩子「{req.child_name}」第{req.year}岁的"
        "年度成长电影写一段旁白，串起这一年的高光瞬间，抒情而克制，150-250字。直接输出旁白正文。"
    )
    user = "这一年的瞬间：\n" + "\n".join(f"- {h}" for h in req.highlights) if req.highlights \
        else "这一年的记录不多，请写得温柔而充满期待。"
    try:
        text = llm.complete(sys, user, max_tokens=500)
    except LLMError as e:
        raise HTTPException(status_code=502, detail=str(e))
    return MovieResp(narration=text.strip())


@app.post("/ask", response_model=AskResp, dependencies=[Depends(require_api_key)])
def ask(req: AskReq):
    """布布问答：App 检索出相关记录传来，这里用它们组织答案并给出处。检索在 App 端（离线优先）。"""
    name = req.child_name
    if not req.records:
        return AskResp(answer=f"我在{name}的时光里没有找到相关的记录。换个说法再问问，或者先去记一笔？", used_ids=[])

    sys = (
        f"你是「{name}」的家庭记忆助手。家长会问关于{name}成长的问题，"
        "你只能依据下面提供的记录回答，不得编造记录里没有的事实、日期或数字。"
        "回答简短温暖、像家人聊天；如果记录里没有足够信息，就如实说没找到，不要猜。"
        "在句末用【记录N】的形式标注你用到的记录编号（N 是记录前的编号）。"
    )
    lines = []
    for i, r in enumerate(req.records, start=1):
        meta = " · ".join(x for x in [r.date, r.age] if x)
        lines.append(f"[{i}] （{meta}）{r.text}")
    user = "已有记录：\n" + "\n".join(lines) + f"\n\n问题：{req.question}"
    try:
        text = llm.complete(sys, user, max_tokens=500)
    except LLMError as e:
        raise HTTPException(status_code=502, detail=str(e))

    # 从答案里解析出引用到的编号 → 映射回记录 id
    import re as _re
    used_idx = set(int(n) for n in _re.findall(r"【记录(\d+)】", text))
    used_ids = [req.records[i - 1].id for i in sorted(used_idx) if 1 <= i <= len(req.records)]
    return AskResp(answer=text.strip(), used_ids=used_ids)


@app.post("/semantic/search", response_model=SemanticSearchResp,
          dependencies=[Depends(require_api_key)])
def semantic_search(req: SemanticSearchReq):
    """在 mini 的可重建索引里检索照片；每个结果必须带回原 Entry/Media 引用。"""
    query = req.query.strip()
    if not query:
        raise HTTPException(status_code=422, detail="搜索内容不能为空。")
    index, encoder = _semantic_components()
    try:
        embedding = encoder.encode_text(query)
    except SemanticModelUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    family_id = os.environ.get("SEMANTIC_FAMILY_ID", "").strip()
    if not family_id:
        raise HTTPException(status_code=503, detail="服务器尚未绑定语义搜索家庭。")
    min_score = float(os.environ.get("SEMANTIC_MIN_SCORE", "0.52"))
    hits = index.search(query, embedding, limit=req.limit, family_id=family_id,
                        min_score=min_score)
    return SemanticSearchResp(
        query=query,
        model_version=encoder.model_version,
        hits=[
            SemanticSearchHit(
                asset_id=hit.asset_id,
                entry_local_id=hit.entry_local_id,
                media_record_id=hit.media_record_id,
                captured_at=hit.captured_at,
                score=hit.score,
                reason=hit.reason,
            )
            for hit in hits
        ],
    )


@app.get("/weekly-report/latest", response_model=WeeklyReportResp,
         dependencies=[Depends(require_api_key)])
def weekly_report_latest():
    """返回服务端派生的最新周报。不存在时用 404，客户端显示可理解的空状态。"""
    family_id = _weekly_family_id()
    result = _weekly_report_call(lambda service: service.latest(family_id))
    if result is None:
        raise HTTPException(status_code=404, detail="还没有生成周报。")
    return WeeklyReportResp(**result)


@app.get("/weekly-report/history", response_model=list[WeeklyReportResp],
         dependencies=[Depends(require_api_key)])
def weekly_report_history():
    """最近一年的周报，含已确认归档项；家庭只由服务端绑定决定。"""
    family_id = _weekly_family_id()
    result = _weekly_report_call(lambda service: service.history(family_id, 52))
    return [WeeklyReportResp(**item) for item in result]


@app.post("/weekly-report/generate", response_model=WeeklyReportResp,
          dependencies=[Depends(require_api_key)])
def weekly_report_generate():
    """幂等生成上一个完整自然周；只写派生层，不改家庭事实。"""
    family_id = _weekly_family_id()
    child_name = os.environ.get("WEEKLY_REPORT_CHILD_NAME", "布布").strip() or "布布"
    result = _weekly_report_call(
        lambda service: service.generate(family_id, child_name)
    )
    return WeeklyReportResp(**result)


@app.post("/weekly-report/archive", response_model=WeeklyReportResp,
          dependencies=[Depends(require_api_key)])
def weekly_report_archive(req: WeeklyReportArchiveReq):
    """显式确认后把周报标为已归档；仍是可重建作品，不写入事实集合。"""
    family_id = _weekly_family_id()
    result = _weekly_report_call(
        lambda service: service.archive(family_id, req.artifact_id)
    )
    return WeeklyReportResp(**result)


@app.get("/weekly-report/events", dependencies=[Depends(require_api_key)])
async def weekly_report_events():
    """周报轻量 SSE：只发送派生产物 id，不把家庭正文放进事件流。"""
    family_id = _weekly_family_id()

    async def stream():
        last_id = ""
        while True:
            try:
                def fetch_latest():
                    with PocketBaseMemoryStore() as store:
                        return WeeklyReportService(store, llm).latest(family_id)

                latest = await asyncio.to_thread(fetch_latest)
                artifact_id = str((latest or {}).get("id") or "")
                if artifact_id and artifact_id != last_id:
                    last_id = artifact_id
                    data = json.dumps({"id": artifact_id}, separators=(",", ":"))
                    yield "event: weekly-report\ndata: %s\n\n" % data
                else:
                    yield ": keep-alive\n\n"
            except asyncio.CancelledError:
                return
            except Exception:
                logger.exception("weekly report SSE poll failed")
                yield ": temporarily-unavailable\n\n"
            await asyncio.sleep(15)

    return StreamingResponse(
        stream(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ---------- 声音年轮 · 原声优先音频章 ----------

@app.get("/sound-ring/latest", response_model=SoundRingResp,
         dependencies=[Depends(require_api_key)])
def sound_ring_latest():
    family_id = _sound_ring_family_id()
    result = _sound_ring_call(lambda service: service.latest(family_id))
    if result is None:
        raise HTTPException(status_code=404, detail="还没有声音年轮。")
    return SoundRingResp(**result)


@app.get("/sound-ring/history", response_model=list[SoundRingResp],
         dependencies=[Depends(require_api_key)])
def sound_ring_history():
    family_id = _sound_ring_family_id()
    result = _sound_ring_call(lambda service: service.history(family_id, 24))
    return [SoundRingResp(**item) for item in result]


@app.post("/sound-ring/draft", response_model=SoundRingResp,
          dependencies=[Depends(require_api_key)])
def sound_ring_draft():
    """只挑选并展示来源，用户确认前不开始渲染。"""
    family_id = _sound_ring_family_id()
    child_name = os.environ.get("SOUND_RING_CHILD_NAME", "").strip()
    if not child_name:
        child_name = os.environ.get("WEEKLY_REPORT_CHILD_NAME", "布布").strip() or "布布"
    result = _sound_ring_call(lambda service: service.draft(family_id, child_name))
    return SoundRingResp(**result)


@app.post("/sound-ring/render", response_model=SoundRingResp,
          dependencies=[Depends(require_api_key)])
def sound_ring_render(req: SoundRingArtifactReq):
    """家庭确认后发起渲染；失败可用同一个 artifact id 重试。"""
    family_id = _sound_ring_family_id()
    result = _sound_ring_call(lambda service: service.render(family_id, req.artifact_id))
    return SoundRingResp(**result)


@app.post("/sound-ring/remove", response_model=SoundRingResp,
          dependencies=[Depends(require_api_key)])
def sound_ring_remove(req: SoundRingRemoveReq):
    """只从尚未渲染的清单移除一段；不会删除或修改原声事实。"""
    family_id = _sound_ring_family_id()
    result = _sound_ring_call(
        lambda service: service.remove_clip(
            family_id, req.artifact_id, req.source_id
        )
    )
    return SoundRingResp(**result)


@app.get("/sound-ring/status/{artifact_id}", response_model=SoundRingResp,
         dependencies=[Depends(require_api_key)])
def sound_ring_status(artifact_id: str):
    family_id = _sound_ring_family_id()
    result = _sound_ring_call(lambda service: service.get(family_id, artifact_id))
    return SoundRingResp(**result)


@app.post("/sound-ring/archive", response_model=SoundRingResp,
          dependencies=[Depends(require_api_key)])
def sound_ring_archive(req: SoundRingArtifactReq):
    family_id = _sound_ring_family_id()
    result = _sound_ring_call(lambda service: service.archive(family_id, req.artifact_id))
    return SoundRingResp(**result)


@app.get("/sound-ring/file/{artifact_id}", dependencies=[Depends(require_api_key)])
def sound_ring_file(artifact_id: str):
    family_id = _sound_ring_family_id()

    def fetch(service: SoundRingService):
        current = service.workflow.owned(family_id, artifact_id)
        if str(current.get("status") or "") not in {"ready", "archived"}:
            raise SoundRingUnavailable("声音年轮尚未准备好。")
        file_value = current.get("file")
        if isinstance(file_value, list):
            file_name = str(file_value[0] if file_value else "")
        else:
            file_name = str(file_value or "")
        if not file_name:
            raise SoundRingUnavailable("声音年轮文件不存在。")
        response = service.store.artifact_file_response(artifact_id, file_name)
        return response.content, response.headers.get("content-type", "audio/mp4")

    data, media_type = _sound_ring_call(fetch)
    return Response(
        content=data,
        media_type=media_type,
        headers={
            "Content-Disposition": 'attachment; filename="bubu-sound-ring.m4a"',
            "Cache-Control": "private, no-store",
        },
    )


# ---------- 成长电影 · 服务端合成（ffmpeg）----------
# 隐私：照片本就通过家庭自己的 PocketBase 同步到本机，App 只传【本机照片 URL】+ 文案。

class MovieRenderPhoto(BaseModel):
    url: str = Field(max_length=2000)          # 家庭自托管 PocketBase 上的照片 URL
    caption: str = Field("", max_length=120)


class MovieRenderReq(BaseModel):
    child_name: str = Field("布布", max_length=40)
    year: int = 0
    template: str = Field("documentary", max_length=40)
    narration: str = Field("", max_length=2000)
    photos: list[MovieRenderPhoto] = Field(default_factory=list, max_length=60)


class MovieRenderResp(BaseModel):
    job_id: str
    status: str
    progress: float = 0.0
    error: str = ""
    ready: bool = False
    year: int = 0


@app.post("/movie/render", response_model=MovieRenderResp,
          dependencies=[Depends(require_api_key)])
def movie_render_start(req: MovieRenderReq):
    if not movie_render.ffmpeg_available():
        raise HTTPException(status_code=503, detail="服务器未安装 ffmpeg，无法服务端合成")
    if not req.photos:
        raise HTTPException(status_code=400, detail="没有可合成的照片")
    photos = [movie_render.RenderPhoto(url=p.url, caption=p.caption) for p in req.photos]
    job = movie_render.submit_render(req.child_name, req.year, req.template, photos, req.narration)
    return MovieRenderResp(**job.public())


@app.get("/movie/status/{job_id}", response_model=MovieRenderResp,
         dependencies=[Depends(require_api_key)])
def movie_render_status(job_id: str):
    job = movie_render.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="任务不存在或已过期")
    return MovieRenderResp(**job.public())


@app.get("/movie/file/{job_id}", dependencies=[Depends(require_api_key)])
def movie_render_file(job_id: str):
    job = movie_render.get_job(job_id)
    if not job or job.status != "ready" or not job.file_path:
        raise HTTPException(status_code=404, detail="成片尚未就绪")
    return FileResponse(job.file_path, media_type="video/mp4",
                        filename=f"{job.child_name}_{job.year}.mp4")


# ---------- 一句话自然语言 → 结构化记录 ----------

class NaturalParseReq(BaseModel):
    text: str = Field(..., max_length=3000)
    childName: str = Field("布布", max_length=40)
    timezone: str = Field("Asia/Shanghai", max_length=80)
    referenceDate: datetime


class ParsedNaturalItem(BaseModel):
    # 注意：与全文件保持 Optional[...] 写法（不要用 `str | None`）——
    # pydantic 需要在运行时求值注解，PEP 604 联合类型在 Python 3.9 服务器上会直接崩。
    domain: Literal[
        "vaccine", "growth", "meal", "snack", "supplement", "water", "sleep",
        "symptom", "checkup", "timeline", "milestone", "first_time", "unknown"
    ]
    action: Literal["create", "update", "complete"] = "create"
    title: str
    note: Optional[str] = None
    date: Optional[datetime] = None
    fields: dict[str, Any] = {}
    tags: list[str] = []
    confidence: float = 0.0
    needs_confirmation: bool = True
    source_text: str


class NaturalParseResp(BaseModel):
    confidence: float = 0.0
    items: list[ParsedNaturalItem] = []
    warnings: list[str] = []


_ALLOWED_DOMAINS = {
    "vaccine", "growth", "meal", "snack", "supplement", "water", "sleep",
    "symptom", "checkup", "timeline", "milestone", "first_time", "unknown",
}
_SENSITIVE_DOMAINS = {"vaccine", "symptom", "supplement"}


def _safe_confidence(value: Any) -> float:
    """置信度容错：解析不了一律归 0——客户端对低置信强制人工确认，比丢整条记录更安全。"""
    try:
        return float(value or 0.0)
    except (TypeError, ValueError):
        return 0.0


def _sanitize_parse_result(data: dict, original_text: str) -> NaturalParseResp:
    """LLM 输出不可信：逐条清洗。原则是能抢救就抢救（坏字段降级/置空），
    实在构造不出来才丢弃该条，绝不让 ValidationError 变 500。"""
    warnings = [w for w in data.get("warnings", []) if isinstance(w, str)]
    items: list[ParsedNaturalItem] = []
    for raw in data.get("items", []):
        if not isinstance(raw, dict):
            continue
        domain = raw.get("domain")
        if domain not in _ALLOWED_DOMAINS:
            domain = "unknown"
            warnings.append("domain_coerced_unknown")
        kwargs = dict(
            domain=domain,
            action=raw.get("action") if raw.get("action") in ("create", "update", "complete") else "create",
            title=str(raw.get("title") or "")[:60] or "未命名记录",
            note=raw.get("note") if isinstance(raw.get("note"), str) else None,
            date=raw.get("date"),
            fields=raw.get("fields") if isinstance(raw.get("fields"), dict) else {},
            tags=[t for t in (raw.get("tags") or []) if isinstance(t, str)][:8],
            confidence=_safe_confidence(raw.get("confidence")),
            needs_confirmation=bool(raw.get("needs_confirmation", True)),
            source_text=str(raw.get("source_text") or original_text)[:200],
        )
        try:
            item = ParsedNaturalItem(**kwargs)
        except Exception:  # noqa: BLE001  多半是日期格式不合法：置空重试，保住记录本体
            kwargs["date"] = None
            try:
                item = ParsedNaturalItem(**kwargs)
                warnings.append("item_date_dropped")
            except Exception:  # noqa: BLE001
                warnings.append("item_dropped_invalid")
                continue
        if item.domain in _SENSITIVE_DOMAINS:
            item.needs_confirmation = True  # 服务端兜底：敏感内容永远要确认
        items.append(item)
    return NaturalParseResp(confidence=_safe_confidence(data.get("confidence")),
                            items=items, warnings=warnings)


@app.post("/parse-natural-capture", response_model=NaturalParseResp,
          dependencies=[Depends(require_api_key)])
def parse_natural_capture(req: NaturalParseReq):
    if not req.text.strip():
        resp = NaturalParseResp(confidence=0.0, items=[], warnings=["empty_text"])
        _record_parse_stats(resp)
        return resp

    sys = f"""
你是一个家庭成长记录 App 的结构化解析器。孩子名叫「{req.childName}」。
你的任务：把父母输入的一句话拆成可保存的结构化记录。

必须遵守：
1. 只记录输入中明确出现的事实，不要编造疫苗名、剂次、药名、剂量、症状、时间。
2. 日期必须结合 referenceDate 和 timezone 解析；无法确定年份时，使用 referenceDate 所在年份，并在 warnings 加 date_inferred。
3. 一句话可以拆成多条 items，例如「今天吃了南瓜米糊，喝水120ml，体重10.6kg」拆三条。
4. 疫苗、症状、药物、过敏、体温异常相关内容，needs_confirmation 必须为 true。
5. 普通餐食/喝水/睡眠，如果字段完整且 confidence >= 0.82，可以 needs_confirmation=false。
6. 不提供诊断，不推荐治疗，只做事实归档。
7. 只输出 JSON，不要输出 Markdown，不要解释。

允许的 domain：
- vaccine: 疫苗接种
- growth: 身高、体重、头围等成长测量
- meal: 正餐/辅食
- snack: 零食
- supplement: 营养补充
- water: 喝水
- sleep: 睡眠
- symptom: 不舒服/症状/体温
- checkup: 体检/护理
- timeline: 普通时光记录
- milestone: 里程碑
- first_time: 第一次
- unknown: 无法判断

字段建议：
- vaccine: vaccine_name, dose_label, injection_site, hospital, reaction
- growth: height_cm, weight_kg, head_circumference_cm
- meal/snack: food_items, amount_text, reaction
- supplement: supplement_name, amount_text
- water: amount_ml
- sleep: start_at, end_at, duration_minutes, quality（start_at/end_at 用 ISO8601 字符串）
- symptom: symptoms, temperature_celsius, severity
- checkup: height_cm, weight_kg, note
- timeline/milestone/first_time: event, people, place
"""

    user = f"""
referenceDate: {req.referenceDate.isoformat()}
timezone: {req.timezone}
input: {req.text}

输出 JSON schema:
{{
  "confidence": 0.0,
  "items": [
    {{
      "domain": "meal",
      "action": "create",
      "title": "南瓜米糊",
      "note": null,
      "date": "2026-06-12T12:00:00+08:00",
      "fields": {{"food_items": ["南瓜米糊"], "amount_text": "半碗"}},
      "tags": ["辅食"],
      "confidence": 0.9,
      "needs_confirmation": false,
      "source_text": "中午吃了南瓜米糊半碗"
    }}
  ],
  "warnings": []
}}
"""

    try:
        data = llm.complete_json(sys, user, max_tokens=1200)
    except LLMError as e:
        raise HTTPException(status_code=502, detail=str(e))
    if not data:
        # _extract_json 兜底返回空 dict：优雅降级，让 App 提示换个说法而不是 500
        resp = NaturalParseResp(confidence=0.0, items=[], warnings=["llm_output_unparseable"])
    else:
        resp = _sanitize_parse_result(data, req.text)
    _record_parse_stats(resp)
    return resp


@app.post("/transcribe", dependencies=[Depends(require_api_key)])
async def transcribe(request: Request, file: UploadFile = File(...)):
    """语音转写。需安装 faster-whisper（见 requirements）；未装则返回 501。"""
    limit = 52_428_800  # 50MB 上限，防止公网恶意大文件耗尽 CPU/磁盘
    content_length = request.headers.get("content-length")
    if content_length:
        try:
            if int(content_length) > limit:
                raise HTTPException(status_code=413, detail="音频文件太大（上限 50MB）。")
        except ValueError:
            raise HTTPException(status_code=400, detail="Content-Length 不正确。")
    try:
        from transcribe import transcribe_audio
    except Exception:
        raise HTTPException(
            status_code=501,
            detail="转写功能未启用：请在服务器安装 faster-whisper（pip install faster-whisper）。",
        )
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await file.read(1024 * 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise HTTPException(status_code=413, detail="音频文件太大（上限 50MB）。")
        chunks.append(chunk)
    data = b"".join(chunks)
    try:
        text = transcribe_audio(data, file.filename or "audio.m4a")
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"转写失败：{e}")
    return {"transcript": text}
