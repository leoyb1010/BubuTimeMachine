from pathlib import Path

import pytest

from semantic_index import SemanticAsset, SemanticIndex


def asset(
    asset_id: str,
    entry_id: str,
    caption: str,
    tags=(),
    family_id: str = "family-a",
) -> SemanticAsset:
    return SemanticAsset(
        asset_id=asset_id,
        entry_local_id=entry_id,
        media_record_id="media-" + asset_id,
        file_url="http://127.0.0.1:8090/api/files/media/%s/photo.jpg" % asset_id,
        captured_at="2026-08-05T12:00:00Z",
        caption=caption,
        tags=tags,
        family_id=family_id,
    )


def test_visual_similarity_returns_source_references(tmp_path: Path):
    index = SemanticIndex(tmp_path / "memory.sqlite", "test-model-v1")
    index.upsert(asset("swing", "entry-swing", "在公园玩秋千", ["户外"]), [1, 0, 0])
    index.upsert(asset("cake", "entry-cake", "生日蛋糕", ["生日"]), [0, 1, 0])

    hits = index.search("荡秋千", [0.98, 0.02, 0], family_id="family-a")

    assert hits[0].asset_id == "swing"
    assert hits[0].entry_local_id == "entry-swing"
    assert hits[0].media_record_id == "media-swing"
    assert hits[0].file_url.endswith("/swing/photo.jpg")
    assert "荡秋千" in hits[0].reason or "秋千" in hits[0].reason


def test_exact_caption_or_tag_can_boost_hybrid_result(tmp_path: Path):
    index = SemanticIndex(tmp_path / "memory.sqlite", "test-model-v1")
    index.upsert(asset("bath", "entry-bath", "第一次游泳", ["泳池"]), [0.5, 0.5])
    index.upsert(asset("other", "entry-other", "室内玩耍", ["积木"]), [0.8, 0.2])

    hits = index.search("游泳", [0.7, 0.3])

    assert hits[0].asset_id == "bath"
    assert hits[0].reason == "文字或标签命中“游泳”"


def test_family_filter_never_crosses_family_boundary(tmp_path: Path):
    index = SemanticIndex(tmp_path / "memory.sqlite", "test-model-v1")
    index.upsert(asset("ours", "entry-ours", "公园", family_id="family-a"), [1, 0])
    index.upsert(asset("theirs", "entry-theirs", "公园", family_id="family-b"), [1, 0])

    hits = index.search("公园", [1, 0], family_id="family-a")

    assert [hit.asset_id for hit in hits] == ["ours"]


def test_upsert_is_idempotent_and_remove_is_rebuild_safe(tmp_path: Path):
    index = SemanticIndex(tmp_path / "memory.sqlite", "test-model-v1")
    index.upsert(asset("one", "entry-old", "旧说明"), [1, 0])
    index.upsert(asset("one", "entry-new", "新说明"), [0, 1])

    assert index.count() == 1
    assert index.search("新说明", [0, 1])[0].entry_local_id == "entry-new"
    index.remove("one")
    assert index.count() == 0


def test_model_version_change_ignores_stale_vectors(tmp_path: Path):
    path = tmp_path / "memory.sqlite"
    old_index = SemanticIndex(path, "model-v1")
    old_index.upsert(asset("old", "entry-old", "旧模型"), [1, 0])

    new_index = SemanticIndex(path, "model-v2")

    assert new_index.count() == 1
    assert new_index.active_count() == 0
    assert new_index.search("旧模型", [1, 0]) == []


def test_equal_score_prefers_recent_capture(tmp_path: Path):
    index = SemanticIndex(tmp_path / "memory.sqlite", "test-model-v1")
    old = asset("old", "entry-old", "公园")
    recent = asset("recent", "entry-recent", "公园")
    object.__setattr__(old, "captured_at", "2025-01-01T00:00:00Z")
    object.__setattr__(recent, "captured_at", "2026-01-01T00:00:00Z")
    index.upsert(old, [1, 0])
    index.upsert(recent, [1, 0])

    assert [hit.asset_id for hit in index.search("公园", [1, 0])] == ["recent", "old"]


def test_low_confidence_results_can_be_rejected(tmp_path: Path):
    index = SemanticIndex(tmp_path / "memory.sqlite", "test-model-v1")
    index.upsert(asset("unrelated", "entry-unrelated", "室内积木"), [0, 1])

    assert index.search("海边冲浪", [1, 0], min_score=0.52) == []


@pytest.mark.parametrize("embedding", [[], [0, 0], [float("nan"), 1]])
def test_invalid_embeddings_are_rejected(tmp_path: Path, embedding):
    index = SemanticIndex(tmp_path / "memory.sqlite", "test-model-v1")
    with pytest.raises(ValueError):
        index.upsert(asset("bad", "entry-bad", ""), embedding)
