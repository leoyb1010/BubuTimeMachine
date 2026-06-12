"""/parse-natural-capture 行为测试：清洗、降级、异常路径（monkeypatch LLM，不打真实模型）。

两种运行方式：
  pytest server/ai/tests -q          # CI / 装了 pytest 的环境
  python3 server/ai/tests/test_parse.py   # 本地无 pytest 时直跑

无 httpx / python-multipart 的环境（仅本地裸跑）自动注入 stub——
被测对象是解析路由与清洗逻辑，不触网络与 multipart。
"""
import json
import os
import sys
import types
from datetime import datetime
from pathlib import Path

os.environ.setdefault("AI_API_KEY", "test-key-123")

# 缺依赖时 stub（CI 装全依赖则直接用真模块）
try:
    import httpx  # noqa: F401
except ModuleNotFoundError:
    stub = types.ModuleType("httpx")
    stub.Client = object
    stub.HTTPError = Exception
    sys.modules["httpx"] = stub
try:
    import python_multipart  # noqa: F401
except ModuleNotFoundError:
    pm = types.ModuleType("python_multipart")
    pm.__version__ = "0.0.20"
    sys.modules["python_multipart"] = pm
    mp = types.ModuleType("multipart")
    mp.__version__ = "0.0.20"
    sub = types.ModuleType("multipart.multipart")
    sub.parse_options_header = lambda *a, **k: (b"", {})
    mp.multipart = sub
    sys.modules["multipart"] = mp
    sys.modules["multipart.multipart"] = sub

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main  # noqa: E402
from fastapi import HTTPException  # noqa: E402


def _req(text="6月20日布布打了麻腮风疫苗，下午喝水120ml"):
    return main.NaturalParseReq(
        text=text, childName="布布", timezone="Asia/Shanghai",
        referenceDate=datetime.fromisoformat("2026-06-12T10:00:00+08:00"))


def test_normal_multi_item_and_sensitive_forced_confirmation():
    main.llm.complete_json = lambda s, u, max_tokens=0: {
        "confidence": 0.9,
        "items": [
            {"domain": "vaccine", "title": "麻腮风疫苗", "date": "2026-06-20T10:00:00+08:00",
             "fields": {"vaccine_name": "麻腮风疫苗"}, "confidence": 0.95,
             "needs_confirmation": False, "source_text": "打了麻腮风疫苗"},
            {"domain": "water", "title": "喝水", "fields": {"amount_ml": 120},
             "confidence": 0.9, "needs_confirmation": False, "source_text": "喝水120ml"},
        ],
        "warnings": [],
    }
    resp = main.parse_natural_capture(_req())
    assert len(resp.items) == 2
    assert resp.items[0].needs_confirmation is True, "疫苗必须被服务端强制确认"
    assert resp.items[1].needs_confirmation is False
    dumped = json.loads(resp.model_dump_json())
    assert "2026-06-20" in dumped["items"][0]["date"]


def test_dirty_output_salvaged_not_500():
    main.llm.complete_json = lambda s, u, max_tokens=0: {
        "confidence": "高",
        "items": [
            {"domain": "made_up_domain", "title": "??", "source_text": "x", "confidence": "abc"},
            "这不是字典",
            {"domain": "meal"},
            {"domain": "sleep", "title": "睡觉", "date": "不是日期",
             "source_text": "昨晚睡觉", "confidence": 0.9},
        ],
        "warnings": ["date_inferred"],
    }
    resp = main.parse_natural_capture(_req())
    domains = [i.domain for i in resp.items]
    assert "unknown" in domains, "非法 domain 降级 unknown 且保留"
    unknown = next(i for i in resp.items if i.domain == "unknown")
    assert unknown.confidence == 0.0, "坏置信度归 0（客户端会强制确认）"
    assert any(i.domain == "sleep" and i.date is None for i in resp.items), "坏日期置空保留记录本体"
    meal = next(i for i in resp.items if i.domain == "meal")
    assert meal.title == "未命名记录" and "麻腮风" in meal.source_text
    assert resp.confidence == 0.0
    assert "date_inferred" in resp.warnings and "item_date_dropped" in resp.warnings


def test_unparseable_llm_output_degrades():
    main.llm.complete_json = lambda s, u, max_tokens=0: {}
    resp = main.parse_natural_capture(_req())
    assert resp.items == [] and resp.warnings == ["llm_output_unparseable"]


def test_empty_text_skips_llm():
    called = {"n": 0}

    def counting(s, u, max_tokens=0):
        called["n"] += 1
        return {}
    main.llm.complete_json = counting
    resp = main.parse_natural_capture(_req("   "))
    assert resp.warnings == ["empty_text"]
    assert called["n"] == 0


def test_llm_error_maps_to_502():
    def boom(s, u, max_tokens=0):
        raise main.LLMError("模型挂了")
    main.llm.complete_json = boom
    try:
        main.parse_natural_capture(_req())
        raise AssertionError("应抛出 HTTPException")
    except HTTPException as e:
        assert e.status_code == 502


def test_parse_stats_accumulate():
    main.llm.complete_json = lambda s, u, max_tokens=0: {}
    before = dict(main._parse_stats)
    main.parse_natural_capture(_req())
    after = dict(main._parse_stats)
    assert after.get("requests", 0) == before.get("requests", 0) + 1
    assert after.get("warn:llm_output_unparseable", 0) == before.get("warn:llm_output_unparseable", 0) + 1


if __name__ == "__main__":
    # 本地无 pytest 时直跑
    failures = []
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("PASS", name)
            except Exception as exc:  # noqa: BLE001
                print("FAIL", name, "->", exc)
                failures.append(name)
    print("\n==> " + ("ALL PASS" if not failures else "FAILURES: " + ", ".join(failures)))
    sys.exit(1 if failures else 0)
