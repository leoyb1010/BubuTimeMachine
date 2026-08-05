import json
from pathlib import Path

from semantic_index import SemanticAsset, SemanticIndex


ASSETS = {
    "swing": ("公园秋千", ["户外"]),
    "birthday": ("生日蛋糕和蜡烛", ["生日"]),
    "beach": ("海边沙滩", ["玩水"]),
    "sleep": ("安静睡觉", ["午睡"]),
    "strawberry": ("吃草莓", ["水果"]),
    "hug": ("家人拥抱", ["妈妈"]),
    "snow": ("下雪天", ["雪地"]),
    "dog": ("和小狗玩", ["宠物"]),
    "walking": ("学走路", ["迈步"]),
    "bath": ("浴缸洗澡", ["泡泡"]),
}


def test_twenty_family_questions_keep_top_source_traceable(tmp_path: Path):
    """固定 20 问守住检索管线与来源引用；真模型质量在 mini 部署门禁另跑。"""
    index = SemanticIndex(tmp_path / "memory.sqlite", "fixture-encoder-v1")
    for axis, (asset_id, (caption, tags)) in enumerate(ASSETS.items()):
        vector = [0.0] * len(ASSETS)
        vector[axis] = 1.0
        index.upsert(
            SemanticAsset(
                asset_id=asset_id,
                entry_local_id="entry-" + asset_id,
                media_record_id="media-" + asset_id,
                file_url="http://127.0.0.1:8090/" + asset_id + ".jpg",
                captured_at="2026-08-05T12:00:00Z",
                caption=caption,
                tags=tags,
                family_id="family-a",
            ),
            vector,
        )

    fixture = Path(__file__).parent / "fixtures" / "semantic_pipeline_questions.json"
    questions = json.loads(fixture.read_text(encoding="utf-8"))
    assert len(questions) == 20
    for question in questions:
        vector = [0.0] * len(ASSETS)
        vector[question["axis"]] = 1.0
        hit = index.search(question["query"], vector, limit=1, family_id="family-a")[0]
        assert hit.asset_id == question["expected"], question["query"]
        assert hit.entry_local_id == "entry-" + question["expected"]
        assert hit.media_record_id == "media-" + question["expected"]
        assert hit.reason
