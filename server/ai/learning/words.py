"""语言成长线: words she said, from voice clips Gemini confirmed as her own speech.

Dictionary segmentation over a bundled toddler wordlist (no NLP dependency): each
run of Chinese is split into the fewest pieces that cover the most characters with
known words. Unknown characters are dropped, except a whole short utterance of 2–3
characters that is not a fragment (大宝, 好可爱). Her own names are not words she
"learned"; reduplicated variants (滑滑梯/滑梯, 妞妞妞妞/妞妞) count once. A word's
first appearance is the earliest ready clip containing it.
"""
from __future__ import annotations

from datetime import datetime
import re

from .online_timeline import LOCAL
from .voices import CHILD_WORDS

_WORDLIST = """
爸爸 妈妈 姥姥 姥爷 奶奶 爷爷 外公 外婆 哥哥 姐姐 弟弟 妹妹 阿姨 叔叔 伯伯 舅舅 姑姑 小姨 老师 宝贝 宝宝 大宝 小朋友 同学 朋友
妈咪 爹地 家人 自己 大家 别人
小狗 狗狗 小猫 猫猫 小鸟 鸟 小鱼 鱼 鸭子 鸭鸭 小鸭 兔子 小兔 老虎 狮子 大象 长颈鹿 熊猫 猴子 老鼠 小羊 羊 牛 马 猪 小猪
鸡 小鸡 恐龙 蝴蝶 蚂蚁 虫子 蜜蜂 海狮 海豚 企鹅 乌龟 青蛙 动物
汽车 车车 车 飞机 火车 地铁 公交车 公交 自行车 单车 船 轮船 挖掘机 警车 消防车 救护车 平衡车 滑板车 三轮车 推车
苹果 香蕉 西瓜 草莓 葡萄 蓝莓 橙子 橘子 芒果 桃子 梨 水果 牛奶 奶奶 饼干 面包 蛋糕 糖 糖果 巧克力 冰淇淋 雪糕 鸡蛋 蛋蛋
米饭 饭饭 饭 面条 面面 饺子 包子 粥 肉肉 肉 烤肉 鱼肉 菜 青菜 玉米 土豆 番茄 胡萝卜 水水 水 甜水 果汁 零食 酸奶 奶
喝水 吃饭 睡觉 回家 出去 上学 放学 上班 下班 洗澡 洗手 刷牙 尿尿 拉粑粑 穿衣服 穿鞋 拖鞋 鞋子 鞋鞋 袜子 帽子 衣服 裤子 裙子
玩 玩具 积木 拼图 气球 球球 球 皮球 篮球 娃娃 玩偶 小熊 滑梯 滑滑梯 秋千 荡秋千 沙子 铲子 桶 画画 唱歌 跳舞 跳 跑 走 走走
看看 抱抱 亲亲 抱 亲 吃 喝 睡 坐 站 爬 飞 游泳 骑车 开车 拍手 拍照 照片 手机 电视 动画片 故事 绘本 书 读书 讲故事
看书 听 唱 不要 我要 不给 给我 给你 帮我 来 去 回来 下来 上去 下去 进来 出来 过来 起来 回去
等一下 等等 再来 一起 一起玩 这里 那里 那边 这边 上面 下面 里面 外面 前面 后面 家 幼儿园 公园 超市 医院
好 坏 冷 热 烫 甜 酸 苦 辣 香 臭 脏 干净 快 慢 胖 瘦 红 黄 蓝 绿 白 黑 粉 紫 红色 黄色 蓝色
绿色 白色 黑色 粉色 紫色 颜色
好吃 好玩 好看 可爱 漂亮 开心 高兴 喜欢 不喜欢 爱 我爱你 害怕 怕 生气 难过 伤心 哭 笑 疼 痛 痒 累
困 饿 饱 渴 舒服 厉害 棒 真棒 加油 好棒 天哪 哇 哎呦 哎哟 糟糕 完了 没了 没有 不是 不对 对不起 谢谢 谢谢你
再见 拜拜 你好 晚安 早上好 没关系 不客气 好的 可以 不可以 不行 知道 不知道 记得 记住 忘了 故意 小心 危险
月亮 太阳 星星 云 雨 下雨 雪 下雪 风 刮风 天空 花 花花 小花 草 树 树叶 石头 山 河 海 大海 海边 沙滩 水池 泳池 灯 门 窗户
椅子 桌子 床 沙发 杯子 杯杯 碗 勺子 筷子 盘子 瓶子 奶瓶 被子 枕头 毛巾 牙刷 梳子 包包 书包 雨伞 钥匙 眼镜 手表 心
头 头发 眼睛 鼻子 嘴巴 耳朵 手 手手 脚 脚脚 肚子 屁股 牙齿 脸 腿 手指
一二三 三四五 一二三四 数一数 一点点 很多
早上 晚上 中午 今天 明天 昨天 现在 马上 一会儿 待会
训练 上课 下课 排队 吃药 打针 生日 生日快乐 礼物 唱歌歌 跳舞舞 捉迷藏 躲猫猫 抓 扔 打 踢 推 拉 打开 关上 找 藏 掉了
感觉 觉得 尝尝 烤 鸭鸭
"""
CHILD_NAMES = {"布布", "晨希", "袁晨希", "布"}
# Function words and pronouns: never "words she learned" on their own.
STOPWORDS = {"啊", "呀", "吧", "的", "了", "吗", "呢", "嗯", "哦", "哎", "诶", "噢", "喔", "哈", "啦", "嘛", "呃", "唉", "哒", "咯",
             "哟", "呗", "嘿", "这", "那", "个", "一", "就", "也", "都", "还", "和", "在", "我", "你", "他", "她", "它", "们",
             "我们", "你们", "他们", "这个", "那个", "就是", "还是", "然后", "什么", "怎么", "哈哈", "嘻嘻",
             "the", "a", "an", "is", "it", "uh", "um", "oh", "ah"}
# A fragment starts or ends with one of these ("的照片", "说我", "你身").
EDGE = set("的了着我你他她它们吗呢吧啊呀这那个在和跟")
VARIANTS = {"哎哟": "哎呦", "拜拜": "再见"}
LEXICON = frozenset(set(_WORDLIST.split()) | set(CHILD_WORDS)) - CHILD_NAMES
LONGEST = max(map(len, LEXICON))
RUN = re.compile(r"[㐀-鿿]+|[A-Za-z]+")
REPEAT = re.compile(r"(.{1,2}?)\1{2,}")


def _segment(run: str) -> list[tuple[str, bool]]:
    """(piece, known) covering run: most characters in known words, then fewest pieces."""
    best = [(0, 0, [])] + [None] * len(run)  # per prefix length: (-covered, pieces, path)
    for end in range(1, len(run) + 1):
        options = []
        for size in range(1, min(LONGEST, end) + 1):
            piece = run[end - size:end]
            known = piece in LEXICON or piece in STOPWORDS
            if not known and size > 1:
                continue
            uncovered, pieces, path = best[end - size]
            options.append((uncovered + (0 if known else 1), pieces + 1, path + [(piece, known)]))
        best[end] = min(options, key=lambda o: (o[0], o[1]))
    merged = []  # glue neighbouring unknown characters back together
    for piece, known in best[-1][2]:
        if merged and not known and not merged[-1][1]:
            merged[-1] = (merged[-1][0] + piece, False)
        else:
            merged.append((piece, known))
    return merged


def key(word: str) -> str:
    """Variants count once: 滑滑梯 ≈ 滑梯, 哎哟 ≈ 哎呦 (two-character words stay: 奶奶 is not 奶)."""
    word = VARIANTS.get(word, word)
    return re.sub(r"(.)\1+", r"\1", word) if len(word) >= 3 else word


def tokens(text: str) -> list[str]:
    """Distinct words in order of appearance."""
    result = []
    for run in RUN.findall(str(text or "")):
        if run.isascii():
            word = run.casefold()
            if len(word) >= 2 and word not in STOPWORDS:
                result.append(word)
            continue
        run = REPEAT.sub(r"\1\1", run)  # 妞妞妞妞 → 妞妞, 哈哈哈 → 哈哈
        pieces = _segment(run)
        for piece, known in pieces:
            if piece in STOPWORDS or piece in CHILD_NAMES:
                continue
            if known:
                result.append(piece)
            elif piece == run and 2 <= len(piece) <= 3 and piece[0] not in EDGE and piece[-1] not in EDGE:
                result.append(piece)  # a whole short utterance the wordlist lacks
    seen, words = set(), []
    for word in result:
        if key(word) not in seen:
            seen.add(key(word))
            words.append(word)
    return words


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
            counts = dict(db.execute("SELECT state,count(*) FROM voices WHERE family_id=? GROUP BY state",
                                     (self.family,)).fetchall())
            since = db.execute("SELECT min(captured_at) FROM voices WHERE family_id=? AND state='pending'",
                               (self.family,)).fetchone()[0]
        pending = counts.get("pending", 0)
        rows = [r for r in rows if r["item_id"] in by_id and r["captured_at"]]
        firsts = {}
        for row in rows:
            for word in tokens(row["heard"]):
                if key(word) not in firsts:
                    firsts[key(word)] = {"word": word, "item_id": row["item_id"], "voice_id": row["id"],
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
        # While much is still unheard, "第一次说" dates are only the earliest found so far.
        incomplete = pending > 0.2 * max(1, sum(counts.values()))
        return {"months": result, "firsts": list(firsts.values()), "source_count": len(rows), "pending": pending,
                "incomplete": incomplete, "pending_since": since}
