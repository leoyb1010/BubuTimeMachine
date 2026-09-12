"""2026-09-12 第一轮审计修复的回归：日期字面量、空环境变量、LLM 截断/非字典、鉴权字节比较、摄取卡死。"""
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import httpx
import pytest

import llm as llm_module
import memory_query
import semantic_worker
from intake_staging import IntakeConflict, IntakeItem, IntakeStagingStore


def test_pb_filter_datetime_matches_pocketbase_storage_text():
    value = datetime(2026, 8, 30, 16, 0, 0, 123456, tzinfo=timezone.utc)
    text = memory_query.pb_filter_datetime(value)
    assert text == "2026-08-30 16:00:00.123Z"
    # 存储文本 "2026-08-30 18:00:00.000Z" 必须按字符串比较大于窗口起点
    assert "2026-08-30 18:00:00.000Z" >= text
    assert "T" not in text and "+00:00" not in text
    assert semantic_worker.filter_now().count(" ") == 1


def test_pb_base_url_falls_back_when_env_is_blank(monkeypatch):
    monkeypatch.setenv("PB_BASE_URL", "")
    assert memory_query.pb_base_url() == "http://127.0.0.1:8090"
    monkeypatch.setenv("PB_BASE_URL", " http://pb.local:8090/ ")
    assert memory_query.pb_base_url() == "http://pb.local:8090"


def _llm_with(handler, monkeypatch):
    monkeypatch.setenv("DEEPSEEK_API_KEY", "test-key")
    client = llm_module.LLMClient()
    real = httpx.Client

    class Patched(real):
        def __init__(self, *args, **kwargs):
            kwargs.pop("transport", None)
            super().__init__(*args, transport=httpx.MockTransport(handler), **kwargs)

    monkeypatch.setattr(llm_module.httpx, "Client", Patched)
    return client


def test_complete_json_returns_dict_even_when_model_answers_a_list(monkeypatch):
    def handler(request):
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop",
                                                      "message": {"content": "[{\"domain\": \"x\"}]"}}]})
    assert _llm_with(handler, monkeypatch).complete_json("s", "u") == {}


def test_truncated_output_is_not_silently_accepted(monkeypatch):
    seen = []

    def handler(request):
        seen.append(json.loads(request.content)["model"])
        return httpx.Response(200, json={"choices": [{"finish_reason": "length",
                                                      "message": {"content": "{\"partial\": "}}]})
    with pytest.raises(llm_module.LLMError, match="截断"):
        _llm_with(handler, monkeypatch).complete("s", "u", max_tokens=50)
    assert len(seen) == 2  # 首选截断后尝试了兜底模型


def test_upstream_error_body_never_reaches_client_message(monkeypatch):
    def handler(request):
        return httpx.Response(402, text="Insufficient Balance for key sk-secret")
    with pytest.raises(llm_module.LLMError) as info:
        _llm_with(handler, monkeypatch).complete("s", "u")
    assert "sk-secret" not in str(info.value) and "LLM 402" in str(info.value)


def test_api_key_compare_tolerates_non_ascii_header(monkeypatch):
    import main
    monkeypatch.setattr(main, "_API_KEY", "expected-key")
    assert main._authorized_principal("expected-key", None, "b").startswith("service:")
    assert main._authorized_principal("\xe9\xff-not-key", None, "b") is None


def test_corrupted_staged_file_does_not_wedge_batch(tmp_path: Path):
    store = IntakeStagingStore(tmp_path / "staging")
    owner = "pb:user-1"
    content = b"photo-bytes"
    digest = hashlib.sha256(content).hexdigest()
    store.create_batch("batch-0000001", owner, "family-1", {"note": "n"}, [
        IntakeItem(asset_key="asset-key-0001", file_name="a.jpg", media_type="photo",
                   captured_at="2026-09-01T00:00:00Z", expected_size=len(content),
                   expected_mime="image/jpeg", resource_role="display"),
    ])
    source = tmp_path / "upload.bin"
    source.write_bytes(content)
    staged = store.stage_file("batch-0000001", "asset-key-0001", source, digest, len(content))
    assert staged["state"] == "staged"
    stored_path = next((store.files / "batch-0000001").iterdir())
    stored_path.write_bytes(b"tampered")
    with pytest.raises(IntakeConflict):
        store.begin_commit("batch-0000001", owner)
    batch = store.batch("batch-0000001", owner)
    assert batch["state"] != "committing", "校验失败不能把批次留在 committing"
    item = batch["items"][0]
    assert item["state"] == "failed" and not item.get("stored_path")
    # 坏素材允许重新上传，重传后批次重新可提交
    source.write_bytes(content)
    restaged = store.stage_file("batch-0000001", "asset-key-0001", source, digest, len(content))
    assert restaged["state"] == "staged"
    assert store.begin_commit("batch-0000001", owner)["state"] == "committing"
