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
  GET  /health                 健康检查

默认接 DeepSeek（OpenAI 兼容协议）。环境变量见 .env.example。
"""
from __future__ import annotations

import logging
import os
import secrets
import time
from collections import Counter, defaultdict, deque
from datetime import datetime
from threading import Lock
from typing import Any, Literal, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Request, UploadFile, File
from pydantic import BaseModel, Field

from llm import LLMClient, LLMError

logging.basicConfig(
    level=os.environ.get("AI_LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)

app = FastAPI(title="布布时光机 AI 服务", version="1.2.0")

llm = LLMClient()

logger = logging.getLogger("bubu.ai")

# /parse-natural-capture 质量观测：warnings 计数（含 llm_output_unparseable 率），
# 进程内累计，带鉴权的 /health 返回快照——LLM 输出漂移早发现。
_parse_stats_lock = Lock()
_parse_stats: Counter = Counter()


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
_rate_lock = Lock()
_rate_buckets: dict[str, deque] = defaultdict(deque)


def _check_rate(client_ip: str) -> None:
    now = time.monotonic()
    with _rate_lock:
        for ip, bucket in list(_rate_buckets.items()):
            while bucket and now - bucket[0] > 60:
                bucket.popleft()
            if not bucket:
                del _rate_buckets[ip]
        bucket = _rate_buckets[client_ip]
        if len(bucket) >= _RATE_LIMIT:
            raise HTTPException(status_code=429, detail="请求太频繁，请稍后再试。")
        bucket.append(now)


def require_api_key(request: Request,
                    x_api_key: Optional[str] = Header(default=None)) -> None:
    """业务路由必须带 X-API-Key。未配置 AI_API_KEY 时拒绝服务（fail-closed），
    防止把无鉴权服务误暴露到公网。"""
    _check_rate(request.client.host if request.client else "unknown")
    if not _API_KEY:
        raise HTTPException(status_code=503,
                            detail="服务端未配置 AI_API_KEY，请在 .env 设置后重启。")
    if not secrets.compare_digest(x_api_key or "", _API_KEY):
        logger.warning("unauthorized request path=%s ip=%s",
                       request.url.path, request.client.host if request.client else "unknown")
        raise HTTPException(status_code=401, detail="鉴权失败：X-API-Key 不正确。")


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


# ---------- 路由 ----------

@app.get("/health")
def health(x_api_key: Optional[str] = Header(default=None)):
    # 连通性检查无需鉴权，但只有带正确 key 才返回服务详情。
    if _API_KEY and x_api_key == _API_KEY:
        with _parse_stats_lock:
            stats = dict(_parse_stats)
        return {"ok": True, "model": llm.model, "configured": llm.is_configured,
                "auth": True, "parse_stats": stats}
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
