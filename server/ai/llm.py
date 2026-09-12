"""
LLM 客户端 · DeepSeek（OpenAI 兼容协议）
====================================
首选 deepseek-v4-flash，失败/超时兜底 deepseek-v4-pro。
配置全走环境变量（见 .env.example），换厂商只改这里。
"""
from __future__ import annotations

import json
import logging
import os
import re
from typing import Any

import httpx


class LLMError(Exception):
    pass


logger = logging.getLogger("bubu.llm")


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

    def complete_json(self, system: str, user: str, max_tokens: int = 800) -> dict[str, Any]:
        raw = self.complete(system, user, max_tokens=max_tokens, temperature=0.3)
        data = _extract_json(raw)
        # 模型偶尔回一个数组/字符串；调用方全部按 dict 取字段，这里统一收口避免 500。
        return data if isinstance(data, dict) else {}

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
            # 家庭证据只发往显式配置的模型端点，不能被 shell/launchd 的代理环境改道。
            with httpx.Client(timeout=self.timeout, trust_env=False) as client:
                resp = client.post(url, json=payload, headers=headers)
        except httpx.HTTPError as e:
            raise LLMError(f"网络错误：{e}") from e
        if resp.status_code != 200:
            # 上游返回体可能含请求回显/内部信息，只进服务端日志，不随 HTTP detail 外泄。
            logger.warning("llm upstream error model=%s status=%s body=%s",
                           model, resp.status_code, resp.text[:200].replace("\n", " "))
            raise LLMError(f"LLM {resp.status_code}: 上游模型服务返回错误")
        try:
            data = resp.json()
            choice = data["choices"][0]
            content = choice["message"]["content"]
        except (KeyError, IndexError, TypeError, json.JSONDecodeError) as e:
            raise LLMError("响应解析失败") from e
        if isinstance(choice, dict) and choice.get("finish_reason") == "length":
            # 被 max_tokens 截断的 JSON/正文不能当成功结果静默返回（推理模型尤其容易）。
            raise LLMError(f"LLM 输出被截断: model={model} max_tokens={max_tokens}")
        return content


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
    if message.startswith("网络错误") or message.startswith("LLM 输出被截断"):
        return True
    match = re.match(r"LLM (\d+):", message)
    if not match:
        return False
    code = int(match.group(1))
    return code == 429 or 500 <= code <= 599
