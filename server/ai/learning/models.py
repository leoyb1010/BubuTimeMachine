"""Content contracts. Model output is untrusted data, never runnable page code."""
from __future__ import annotations
import math
import re
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator

class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

class Segment(StrictModel):
    id: str = Field(min_length=1,max_length=80,pattern=r'^[a-zA-Z0-9_-]+$')
    start: float = Field(ge=0,le=14400)
    end: float = Field(gt=0,le=14400)
    text: str = Field(min_length=1,max_length=3000)
    @model_validator(mode="after")
    def duration(self):
        if not math.isfinite(self.start+self.end) or self.end<=self.start:
            raise ValueError("转写时间段无效")
        return self

class Clip(StrictModel):
    source_id: str = Field(min_length=1,max_length=80)
    segment_id: str = Field(min_length=1,max_length=80)
    role: Literal["question","cue","answer","context"]

class Choice(StrictModel):
    id: str = Field(min_length=1,max_length=60,pattern=r'^[a-zA-Z0-9_-]+$')
    label: str = Field(min_length=1,max_length=80)
    evidence: Clip
    color: str | None = Field(default=None,pattern=r'^#[0-9a-fA-F]{6}$')
    colors: list[str] = Field(default_factory=list,max_length=6)

class Activity(StrictModel):
    id: str = Field(min_length=1,max_length=60,pattern=r'^[a-zA-Z0-9_-]+$')
    kind: Literal["listen_choice","color_choice","sort","speak","music"]
    title: str = Field(min_length=1,max_length=60)
    concept: str = Field(min_length=1,max_length=100)
    instruction: str = Field(min_length=1,max_length=200)
    prompt: Clip
    answer: Clip | None = None
    choices: list[Choice] = Field(default_factory=list,max_length=6)
    correct_choice: str | None = Field(default=None,max_length=60)
    @model_validator(mode="after")
    def consistent(self):
        ids=[x.id for x in self.choices]
        if len(ids)!=len(set(ids)):
            raise ValueError("选项编号重复")
        if self.kind in {"listen_choice","color_choice","sort"}:
            if len(ids)<2 or self.correct_choice not in ids or self.answer is None:
                raise ValueError("题目缺少选项或原声答案")
        if self.kind=="color_choice" and any(not label_colors(c.label) for c in self.choices):
            raise ValueError("颜色题缺少可见色块")
        if self.kind=="music":
            if self.prompt.role!="context":raise ValueError("歌曲只能作为情境")
        elif self.prompt.role not in {"question","cue"}:
            raise ValueError("介绍或答案不能作为题目")
        if self.answer and self.answer.role!="answer":raise ValueError("答案角色无效")
        if self.kind=="speak" and (self.answer is None or self.prompt.role!="question"):
            raise ValueError("表达题须包含老师的问题与示范答案")
        return self

class Draft(StrictModel):
    title: str = Field(min_length=1,max_length=100)
    summary: str = Field(default="",max_length=500)
    material_kind: Literal["teaching","practice","song","daily","care","uncertain"]
    activities: list[Activity] = Field(default_factory=list,max_length=12)
    warnings: list[str] = Field(default_factory=list,max_length=20)
    @model_validator(mode="after")
    def ids(self):
        if len({x.id for x in self.activities})!=len(self.activities):raise ValueError("活动编号重复")
        if self.material_kind in {"daily","care","uncertain"} and self.activities:
            raise ValueError("非教学材料不能强行出题")
        return self


def normalize(text: str) -> str:
    return re.sub(r"[^\w]+"," ",text.casefold()).strip()


def label_colors(text: str) -> list[str]:
    palette = {"yellow": "#F5CF39", "green": "#4A955E", "orange": "#F29A38",
               "red": "#D95B50", "blue": "#528BCE", "purple": "#9567B0",
               "pink": "#ECA1B2", "brown": "#936649", "black": "#242424",
               "white": "#FFFFFF", "gray": "#888888", "grey": "#888888"}
    aliases = {"黄色":"yellow", "绿色":"green", "橙色":"orange", "红色":"red",
               "蓝色":"blue", "紫色":"purple", "粉色":"pink", "棕色":"brown",
               "黑色":"black", "白色":"white", "灰色":"gray"}
    for word, english in aliases.items():
        text = text.replace(word, " " + english + " ")
    return list(dict.fromkeys(palette[w] for w in normalize(text).split() if w in palette))


def resolve_clip(clip: Clip, sources: dict) -> dict:
    source=sources.get(clip.source_id)
    if not source:raise ValueError("题目引用了未知来源")
    segments=source.get("analysis",{}).get("segments",[])
    segment=next((s for s in segments if s.get("id")==clip.segment_id),None)
    if not segment:raise ValueError("题目没有可回查的转写时间段")
    segment=Segment.model_validate(segment)
    duration=source.get("analysis",{}).get("duration")
    if duration is not None and segment.end>float(duration)+.15:
        raise ValueError("题目时间码超出原音轨")
    if segment.end-segment.start>45:
        raise ValueError("该段过长，需先切分核对，不能把整段介绍当题目")
    return {**clip.model_dump(),**segment.model_dump(),"source_id":clip.source_id,"role":clip.role,
            "source_hash":source["hash"]}


def ground_draft(draft: Draft, sources: dict) -> dict:
    result=draft.model_dump()
    for activity in result["activities"]:
        original=Activity.model_validate(activity)
        activity["prompt"]=resolve_clip(original.prompt,sources)
        if original.answer:activity["answer"]=resolve_clip(original.answer,sources)
        for choice,model_choice in zip(activity["choices"],original.choices):
            choice["evidence"]=resolve_clip(model_choice.evidence,sources)
            if normalize(choice["label"]) not in normalize(choice["evidence"]["text"]):
                raise ValueError("选项文字没有出现在引用的教学原文中")
        if original.correct_choice:
            answer=activity["answer"]["text"]
            right=next(c for c in activity["choices"] if c["id"]==original.correct_choice)
            if normalize(right["label"]) not in normalize(answer):raise ValueError("选项与老师答案不一致")
            if original.kind == "color_choice":
                if set(label_colors(right["label"])) != set(label_colors(answer)):
                    raise ValueError("颜色选项未覆盖老师完整答案")
                for choice in activity["choices"]:
                    choice["colors"] = label_colors(choice["label"])
                    choice["color"] = choice["colors"][0]
    return result
