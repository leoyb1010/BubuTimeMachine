"""语言成长线: words she said, from voice clips Gemini confirmed as her own speech.

Plain character-run splitting with a small toddler lexicon and stopword list; no
NLP dependency. A word's first appearance is the earliest ready clip containing it.
"""
from __future__ import annotations

from datetime import datetime
import re

from .online_timeline import LOCAL
from .voices import CHILD_WORDS

LEXICON = sorted(set(CHILD_WORDS) | {
    "哥哥", "姐姐", "弟弟", "妹妹", "阿姨", "叔叔", "老师", "宝贝", "小狗", "小猫", "小鸟", "汽车", "飞机", "苹果",
    "香蕉", "西瓜", "草莓", "牛奶", "喝水", "吃饭", "睡觉", "回家", "出去", "好吃", "好玩", "漂亮", "开心", "害怕",
    "妈咪", "爹地", "月亮", "太阳", "星星", "气球", "球球", "车车", "饭饭", "水水", "看看", "抱抱", "走走",
}, key=len, reverse=True)
STOPWORDS = {"啊", "呀", "吧", "的", "了", "吗", "呢", "嗯", "哦", "哎", "诶", "噢", "喔", "哈", "啦", "嘛", "呃", "唉",
             "这", "那", "个", "是", "一", "就", "也", "都", "还", "和", "在", "有", "我", "你", "他", "她", "它",
             "the", "a", "an", "is", "it", "uh", "um", "oh"}
RUN = re.compile(r"[㐀-鿿]+|[A-Za-z]+")


def tokens(text: str) -> list[str]:
    """Distinct words in order of appearance."""
    result = []
    for run in RUN.findall(str(text or "")):
        if run.isascii():
            word = run.casefold()
            if len(word) >= 2 and word not in STOPWORDS:
                result.append(word)
            continue
        index, rest = 0, ""
        pieces = []
        while index < len(run):
            hit = next((w for w in LEXICON if run.startswith(w, index)), None)
            if hit:
                if rest:
                    pieces.append(rest)
                    rest = ""
                pieces.append(hit)
                index += len(hit)
            else:
                rest += run[index]
                index += 1
        if rest:
            pieces.append(rest)
        for piece in pieces:
            # Long unknown runs become two-character chunks; stopwords drop out.
            chunks = [piece] if len(piece) <= 4 else [piece[i:i + 2] for i in range(0, len(piece), 2)]
            result.extend(c for c in chunks if c not in STOPWORDS and not all(ch in STOPWORDS for ch in c))
    return list(dict.fromkeys(result))


class Words:
    def __init__(self, timeline, voices):
        self.timeline, self.voices = timeline, voices
        self.store, self.family = timeline.store, timeline.family

    def words(self, scope):
        self.timeline.authorize(scope)
        by_id = self.timeline.snapshot()["by_id"]
        with self.store.db() as db:
            rows = [dict(r) for r in db.execute(
                "SELECT id,item_id,captured_at,heard FROM voices WHERE family_id=? AND state='ready' "
                "ORDER BY captured_at,start", (self.family,))]
            pending = db.execute("SELECT count(*) FROM voices WHERE family_id=? AND state='pending'",
                                 (self.family,)).fetchone()[0]
        rows = [r for r in rows if r["item_id"] in by_id and r["captured_at"]]
        firsts = {}
        for row in rows:
            for word in tokens(row["heard"]):
                if word not in firsts:
                    firsts[word] = {"word": word, "item_id": row["item_id"], "voice_id": row["id"],
                                    "captured_at": row["captured_at"], "text": row["heard"]}
        months = {}
        for first in firsts.values():
            try:
                month = datetime.fromisoformat(first["captured_at"].replace("Z", "+00:00")).astimezone(LOCAL).strftime("%Y-%m")
            except ValueError:
                continue
            months.setdefault(month, []).append(first["word"])
        total, result = 0, []
        for month in sorted(months):
            total += len(months[month])
            result.append({"month": month, "new_words": months[month], "total": total})
        return {"months": result, "firsts": list(firsts.values()), "source_count": len(rows), "pending": pending}
