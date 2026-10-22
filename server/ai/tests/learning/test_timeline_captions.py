"""Family wording overlay: rename the child only, never touch the library."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning.store import LearningStore
from learning.timeline_captions import TimelineCaptions, acceptable


def item(fid, text):
    return {"file_id": fid, "analysis": {"description": text}}


class Bridge:
    def __init__(self, replies):
        self.replies, self.calls = replies, 0

    def complete_json(self, system, user, schema, effort='high'):
        self.effort = effort
        self.calls += 1
        return {"items": self.replies}


def test_only_renaming_is_accepted():
    original = "一名扎着双马尾的女童坐在草地的露营椅上，手拿红丝带。"
    assert acceptable(original, "布布（袁晨希）扎着双马尾坐在草地的露营椅上，手拿红丝带。")
    assert not acceptable(original, "布布（袁晨希）在海边奔跑，非常开心。")  # invented facts
    assert not acceptable(original, original)
    assert not acceptable(original, "一名扎着双马尾的女孩坐在草地的露营椅上，手拿红丝带。")  # no name added


def test_rewrite_overlay_follows_library_text(tmp_path):
    store = LearningStore(tmp_path)
    captions = TimelineCaptions(store)
    single = item("a" * 24, "一名女婴坐在窗边花丛旁摸着花朵。")
    multi = item("b" * 24, "两名女童同骑一辆红色三轮车。")
    bad = item("c" * 24, "一名幼童在步道上举手。")
    bridge = Bridge([
        {"id": "a" * 24, "description": "布布（袁晨希）坐在窗边花丛旁摸着花朵。", "changed": True},
        {"id": "b" * 24, "description": "两名女童同骑一辆红色三轮车。", "changed": False},
        {"id": "c" * 24, "description": "布布（袁晨希）在游乐园坐过山车。", "changed": True},
    ])
    report = captions.rewrite(bridge, "fam", [single, multi, bad])
    assert report == {"changed": 1, "kept": 1, "rejected": 1}
    assert captions.overlays("fam", [single, multi, bad]) == {"a" * 24: "布布（袁晨希）坐在窗边花丛旁摸着花朵。"}
    assert captions.pending("fam", [single, multi, bad]) == []
    assert captions.overlays("other-family", [single]) == {}
    # The library re-analysed the photo: old family wording no longer applies and it is pending again.
    updated = item("a" * 24, "一名女婴坐在窗边，阳光洒在花上。")
    assert captions.overlays("fam", [updated]) == {}
    assert captions.pending("fam", [updated]) == [updated]


def test_missing_reply_is_retried(tmp_path):
    captions = TimelineCaptions(LearningStore(tmp_path))
    one = item("d" * 24, "一名女童在画画。")
    assert captions.rewrite(Bridge([]), "fam", [one])["rejected"] == 1
    assert captions.pending("fam", [one]) == [one]
