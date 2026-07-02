"""
LLM 客户端 · DeepSeek（OpenAI 兼容协议）
====================================
首选 deepseek-v4-flash，失败/超时兜底 deepseek-v4-pro。
配置全走环境变量（见 .env.example），换厂商只改这里。
"""
from __future__ import annotations

import json
import os
import re
from typing import Any

import httpx


class LLMError(Exception):
    pass


class LLMClient:
    def __init__(self) -> None:
        self.api_key = os.environ.get("DEEPSEEK_API_KEY", "")
        self.base_url = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
        self.model = os.environ.get("DEEPSEEK_MODEL", "deepseek-v4-flash")
        self.fallback_model = os.environ.get("DEEPSEEK_FALLBACK_MODEL", "deepseek-v4-pro")
        self.timeout = float(os.environ.get("LLM_TIMEOUT", "60"))

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    def complete(self, system: str, user: str, max_tokens: int = 400,
                 temperature: float = 0.8) -> str:
        if not self.is_configured:
            raise LLMError("未配置 DEEPSEEK_API_KEY")
        # 只对瞬时错误兜底。401/402/403 等配置、鉴权、额度问题必须保留真实错误，
        # 否则排障时会被“首选与兜底模型均调用失败”抹平。
        errors: list[str] = []
        for model in (self.model, self.fallback_model):
            try:
                return self._chat(model, system, user, max_tokens, temperature)
            except LLMError as exc:
                message = str(exc)
                errors.append(f"{model}: {message}")
                if not _can_try_fallback(message):
                    raise
        raise LLMError("首选与兜底模型均调用失败：" + "；".join(errors))

    def complete_json(self, system: str, user: str, max_tokens: int = 300) -> dict[str, Any]:
        raw = self.complete(system, user, max_tokens=max_tokens, temperature=0.3)
        return _extract_json(raw)

    def _chat(self, model: str, system: str, user: str,
              max_tokens: int, temperature: float) -> str:
        url = f"{self.base_url}/chat/completions"
        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": False,
        }
        headers = {"Authorization": f"Bearer {self.api_key}",
                   "Content-Type": "application/json"}
        try:
            with httpx.Client(timeout=self.timeout) as client:
                resp = client.post(url, json=payload, headers=headers)
        except httpx.HTTPError as e:
            raise LLMError(f"网络错误：{e}") from e
        if resp.status_code != 200:
            raise LLMError(f"LLM {resp.status_code}: {resp.text[:200]}")
        try:
            data = resp.json()
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, json.JSONDecodeError) as e:
            raise LLMError(f"响应解析失败：{e}") from e


def _extract_json(text: str) -> dict[str, Any]:
    """从 LLM 输出中提取 JSON（容忍 ```json 包裹或前后噪声）。"""
    text = text.strip()
    # 去掉 markdown 围栏
    text = re.sub(r"^```(?:json)?", "", text).strip()
    text = re.sub(r"```$", "", text).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # 兜底：抓第一个 {...}
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(0))
        except json.JSONDecodeError:
            pass
    return {}


def _can_try_fallback(message: str) -> bool:
    if message.startswith("网络错误"):
        return True
    match = re.match(r"LLM (\d+):", message)
    if not match:
        return False
    code = int(match.group(1))
    return code == 429 or 500 <= code <= 599
