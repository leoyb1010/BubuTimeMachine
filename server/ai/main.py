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
  GET  /health                 健康检查

默认接 DeepSeek（OpenAI 兼容协议）。环境变量见 .env.example。
"""
from __future__ import annotations

import os
from typing import Optional

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from llm import LLMClient, LLMError

app = FastAPI(title="布布时光机 AI 服务", version="1.0.0")

# 家庭内网，放开 CORS（仅 Tailscale 可达，外部访问不到）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)

llm = LLMClient()


# ---------- 请求/响应模型 ----------

class RewriteReq(BaseModel):
    note: str
    child_name: str = "布布"
    mood: Optional[str] = None
    age_description: Optional[str] = None


class RewriteResp(BaseModel):
    first_person: str


class ClassifyReq(BaseModel):
    note: Optional[str] = None
    tags: list[str] = []
    location_name: Optional[str] = None


class ClassifyResp(BaseModel):
    suggested_title: Optional[str] = None
    event_cluster: Optional[str] = None
    place_name: Optional[str] = None
    visual_tags: list[str] = []


class DetectFirstReq(BaseModel):
    tags: list[str] = []
    note: Optional[str] = None
    child_name: str = "布布"


class DetectFirstResp(BaseModel):
    is_first: bool
    what: Optional[str] = None
    confidence: float = 0.0


class MovieReq(BaseModel):
    child_name: str = "布布"
    year: int
    highlights: list[str] = []   # 该岁的若干记录摘要


class MovieResp(BaseModel):
    narration: str


# ---------- 路由 ----------

@app.get("/health")
def health():
    return {"ok": True, "model": llm.model, "configured": llm.is_configured}


@app.post("/rewrite-first-person", response_model=RewriteResp)
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


@app.post("/classify", response_model=ClassifyResp)
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


@app.post("/detect-first-time", response_model=DetectFirstResp)
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


@app.post("/movie-narration", response_model=MovieResp)
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


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    """语音转写。需安装 faster-whisper（见 requirements）；未装则返回 501。"""
    try:
        from transcribe import transcribe_audio
    except Exception:
        raise HTTPException(
            status_code=501,
            detail="转写功能未启用：请在服务器安装 faster-whisper（pip install faster-whisper）。",
        )
    data = await file.read()
    try:
        text = transcribe_audio(data, file.filename or "audio.m4a")
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"转写失败：{e}")
    return {"transcript": text}
