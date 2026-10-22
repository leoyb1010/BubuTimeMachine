"""Read the configured second-brain collection directly; never join local Entries.

Membership comes from the existing library: accepted person photos plus videos
whose completed video analysis names the child. This service runs no face
matching and never presents historical machine labels as manual confirmation.
Original paths stay server-side; every media URL still needs family auth.
"""
from collections import Counter
from datetime import date as Date, datetime, timedelta, timezone
import difflib
import json
import logging
import mimetypes
import os
from pathlib import Path
import re
import tempfile
import threading
import time
from zoneinfo import ZoneInfo

from fastapi import HTTPException
import httpx

from .brain_bridge import BrainUnavailable
from .recognition import decisions
from .store import Missing, digest, valid_day
from .timeline_captions import TimelineCaptions

log = logging.getLogger('bubu.learning.online')
LOCAL = ZoneInfo('Asia/Shanghai')
PREVIEW_SIZES = {'thumb': 480, 'card': 900, 'large': 1600}
PROVENANCE = {'manual': '家人标注', 'gemini_two_pass': '第二大脑人物识别',
              'video_analysis_mention': '第二大脑视频解析提到布布', 'family_confirmed': '家人认一认确认'}
# Same tuning as the library's own gallery: bge-m3 scores drift per query, so keep
# what is close to the best hit and above an absolute floor.
SEM_FLOOR, SEM_BAND = 0.6, 0.1
CJK = re.compile(r'[\u3400-\u9fff]')
# Common ASR hallucinations on silence/music (zh-only local speech model).
JUNK_PHRASES = ('字幕由', '请不吝点赞', '订阅转发', '打赏支持', '明镜与点点', '谢谢观看', '感谢观看')
HIGHLIGHT_REASONS = ('那年今天', '那年这几天', '最近精选')
UNAVAILABLE = '家里的服务器暂时读不到素材库，请稍后重试。'


def plausible_segment(text, start, end):
    """Conservative ASR quality check for the library's zh-only transcripts.

    English or toddler speech comes back as Latin gibberish ("Bu bu goob wasin"),
    lone letters ("H", "you") or bare punctuation. Real Chinese speech always has
    CJK characters; a single character stretched over many seconds is also noise.
    """
    text = str(text or '')
    compact = re.sub(r'[\s\W_]+', '', text)
    if not compact:
        return False
    cjk = len(CJK.findall(compact))
    if not cjk:
        return False
    if cjk * 3 < len(compact):
        return False
    if any(phrase in compact for phrase in JUNK_PHRASES):
        return False
    duration = max(0.0, float(end) - float(start))
    return not (cjk <= 2 and duration > 5)


def jpeg_size(path):
    """(width, height) from a baseline/progressive JPEG SOF header, or None."""
    try:
        data = Path(path).read_bytes()
    except OSError:
        return None
    if data[:2] != b'\xff\xd8':
        return None
    index = 2
    while index + 9 < len(data):
        if data[index] != 0xFF:
            return None
        marker = data[index + 1]
        if marker == 0xFF:
            index += 1
            continue
        if marker in (0x01, 0xD8) or 0xD0 <= marker <= 0xD7:
            index += 2
            continue
        length = int.from_bytes(data[index + 2:index + 4], 'big')
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height = int.from_bytes(data[index + 5:index + 7], 'big')
            width = int.from_bytes(data[index + 7:index + 9], 'big')
            return (width, height) if width and height else None
        if length < 2:
            return None
        index += 2 + length
    return None


def place_parts(value):
    # " · " separates levels; a bare "·" can sit inside one name (城投·七里香榭).
    return [p.strip() for p in re.split(r'\s+·\s+', str(value or '').strip()) if p.strip()]


def place_city(value):
    """The city of a "中国 · 深圳市 · 小区" style place; bare POI names carry no city."""
    return next((p for p in place_parts(value) if p.endswith(('市', '州', '盟', '地区'))), '')


def short_place(value):
    parts = place_parts(value)
    if parts and parts[0] == '中国':
        parts = parts[1:]
    return ' · '.join(parts) or None


GPS_PLACE = re.compile(r'GPS_(-?\d{1,2}(?:\.\d+)?)_(-?\d{1,3}(?:\.\d+)?)')


def gps_place(value):
    """(lat, lon) for the library's raw "GPS_22.657_114.183" place names, else None."""
    match = GPS_PLACE.fullmatch(str(value or '').strip())
    if not match:
        return None
    lat, lon = float(match.group(1)), float(match.group(2))
    return (lat, lon) if -90 <= lat <= 90 and -180 <= lon <= 180 else None


def poi(value):
    """(city, point of interest) for one place string; None for empty or raw GPS names.

    "中国 · 深圳市 · 尚云花园" and a bare "尚云花园" share the POI, so callers can
    merge them; a city-only place ("中国 · 深圳市") is its own POI.
    """
    if not str(value or '').strip() or gps_place(value):
        return None
    parts = place_parts(value)
    if parts and parts[0] == '中国':
        parts = parts[1:]
    if not parts:
        return None
    return place_city(value), parts[-1]


# Family wording: the library knows each co-occurring person by full name; parents
# read roles. Cold adult terms become the role when exactly one such relative is
# in the picture.
MALE_ROLES = ('爸爸', '爷爷', '姥爷', '外公', '舅舅', '叔叔', '伯伯', '姑父', '姨父')
FEMALE_ROLES = ('妈妈', '奶奶', '姥姥', '外婆', '阿姨', '姑姑', '小姨', '舅妈', '婶婶')
ADULT_TERMS = {
    MALE_ROLES: re.compile(r'(?:一名|一位|一个)?(?:成年|中年|青年|年轻|老年|年长)?的?(?:男子|男性|男士)'),
    FEMALE_ROLES: re.compile(r'(?:一名|一位|一个)?(?:成年|中年|青年|年轻|老年|年长)?的?(?:女子|女性|女士)'),
}
PLURAL = re.compile(r'[两二三四几多众另其]\S{0,3}(?:男|女)|(?:男|女)(?:子|性|士)们')


def familiar(text, labels, people=()):
    """Replace relatives' full names with their family role (袁博 → 爸爸), and, with
    `people`, a lone "成年男子/一名女性" with the single relative of that gender."""
    text = str(text or '')
    if not text:
        return text
    pairs = sorted(((n, r) for n, r in (labels or {}).items()
                    if isinstance(n, str) and isinstance(r, str) and len(n) >= 2 and r and r != n and r not in n),
                   key=lambda pair: -len(pair[0]))
    for name, role in pairs:
        if name not in text:
            continue
        for pattern in (role + '（' + name + '）', role + '(' + name + ')', name + '（' + role + '）',
                        name + '(' + role + ')', role + name, name + role):
            text = text.replace(pattern, role)
        text = text.replace(name, role)
    roles = [labels.get(p) for p in people if (labels or {}).get(p)]
    if roles and not PLURAL.search(text):
        for group, pattern in ADULT_TERMS.items():
            present = {r for r in roles if r in group}
            if len(present) == 1:
                text = pattern.sub(present.pop(), text)
    return text


CHILD_TERMS = re.compile(r'(?:一名|一位|一个)?(?:女童|幼童|小女孩|女婴|婴儿)')


def family_story(text, labels):
    """Event titles/stories: roles for relatives, 布布 for the one child they are about."""
    text = familiar(text, labels)
    text = re.sub(r'(?<!布布（)(?<!布布\()袁晨希', '布布', text)
    if not re.search(r'[两二三几多另其]\S{0,2}(?:孩子|小朋友|女童|幼童|女孩)|小朋友们', text):
        text = CHILD_TERMS.sub('布布', text)
    return text


SCREEN_TAGS = ('截图', '截屏', 'screenshot', '证件照', '聊天记录', '二维码', '文档', '界面', '票据', '收据')
ID_PHOTO = ('证件照', '抠图', '白底照', '一寸照', '二寸照')
SCREEN_HEAD = ('截图', '截屏', 'screenshot', '屏幕截图', '证件照', '聊天记录', '界面截图', '软件界面', 'app界面')
CHILD_WORDS_EARLY = ('布布', '袁晨希', '她', '女童', '小女孩', '女孩', '宝宝', '婴儿', '女婴', '幼儿', '幼童')
ADULT_FIRST = ('成年', '男子', '女子', '男性', '女性', '男士', '女士', '爸爸', '妈妈', '姥姥', '姥爷', '奶奶', '爷爷', '大人')
CLOSE_UP = ('特写', '自拍', '近景', '大脸', '面部', '脸部')


def item_aspect(item):
    width, height = item.get('width') or 0, item.get('height') or 0
    return round(width / height, 4) if width and height else None


def unsuitable(row):
    """Screenshots, ID photos, documents and phone-tall images never lead picks or covers."""
    item = row['item']
    tags = ' '.join(row.get('tags') or []).casefold()
    head = str(row.get('description') or '')[:40].casefold()
    if any(w in tags for w in SCREEN_TAGS) or any(w in head for w in SCREEN_HEAD):
        return True
    if any(w in str(row.get('description') or '') for w in ID_PHOTO):
        return True
    ratio = item_aspect(item)
    return item.get('media_type') == 'photo' and ratio is not None and ratio < 0.5


def quality(row):
    """Cover/pick preference: suitable, her (not an adult's face) up front, family-checked wording, photo, smiling."""
    text = str(row.get('description') or '')
    head = re.split(r'[，,。；;]', text, maxsplit=1)[0]
    child_at = min((head.find(w) for w in CHILD_WORDS_EARLY if w in head), default=-1)
    adult_at = min((head.find(w) for w in ADULT_FIRST if w in head), default=-1)
    adult_led = adult_at >= 0 and (child_at < 0 or adult_at < child_at)
    close_up = adult_led and any(w in text[:60] for w in CLOSE_UP)
    return (not unsuitable(row), not close_up, child_at >= 0 and not adult_led,
            bool(row.get('adjusted') or row.get('confirmed')), row['item'].get('media_type') == 'photo',
            '笑' in text[:80])


GENERIC_TAGS = {'布布', '袁晨希', '女童', '小女孩', '女孩', '儿童', '幼儿', '幼童', '宝宝', '婴儿', '女婴', '孩子', '人物',
                '室内', '户外', '家庭', '生活', '日常', '笑容', '可爱'}


def _scene_words(text):
    text = re.sub(r'布布（袁晨希）|袁晨希|布布|一名|扎着|扎|双马尾|双丸子头', '', text)
    return text[:60]


def _similar(a, b):
    """Same place and two shared specific tags, or near-identical wording once her name and hairstyle are dropped."""
    if a['place'] != b['place']:
        return False
    if len((set(a['tags']) - GENERIC_TAGS) & (set(b['tags']) - GENERIC_TAGS)) >= 2:
        return True
    return difflib.SequenceMatcher(None, _scene_words(a['description']), _scene_words(b['description'])).ratio() >= 0.55


def mark_bursts(rows, gap=30):
    """Near-duplicate photo bursts: consecutive photos ≤gap seconds apart with a similar scene.

    Every member gets row['burst'] = (lead file_id, size); the lead is the best by quality().
    """
    group = []

    def close():
        if len(group) > 1:
            lead = max(group, key=lambda r: (quality(r), r['item']['file_id']))['item']['file_id']
            for member in group:
                member['burst'] = (lead, len(group))
        group.clear()
    previous_at = None
    for row in rows:  # newest first
        at = datetime.fromisoformat(row['stamp']).timestamp() if row['stamp'] else None
        joins = (group and at is not None and previous_at is not None and row['item']['media_type'] == 'photo'
                 and previous_at - at <= gap and _similar(group[-1], row))
        if not joins:
            close()
        if row['item']['media_type'] == 'photo' and at is not None:
            group.append(row)
        previous_at = at
    close()
    return rows


# Natural search phrasing: "第一次骑车" means 骑车, "在海边" means 海边.
SEARCH_DROP = ('第一次', '第一回', '头一次', '首次', '最早', '什么时候', '的时候', '时候', '布布', '袁晨希', '我们',
               '一起', '照片', '视频', '那次', '有没有')
EDGE_CHARS = '在去的了吗呢吧啊呀和跟与'
SYNONYMS = {
    '看海': ('海边', '沙滩', '大海', '海浪', '海滩'), '海边': ('沙滩', '大海', '海浪', '海滩'),
    '大海': ('海边', '沙滩', '海浪'), '沙滩': ('海边', '海滩'),
    '玩水': ('戏水', '泳池', '游泳', '水池', '水枪', '踩水'), '戏水': ('玩水', '泳池', '踩水'),
    '游泳': ('泳池', '泳圈', '戏水'), '骑车': ('自行车', '单车', '平衡车', '滑步车', '三轮车', '骑行'),
    '自行车': ('单车', '骑车'), '水果': ('西瓜', '苹果', '香蕉', '草莓', '葡萄', '蓝莓', '橙子', '芒果', '桃子', '果泥', '橘子'),
    '幼儿园': ('托育', '入园', '园所'), '上学': ('幼儿园', '托育', '上课'), '生日': ('蛋糕', '蜡烛'),
    '看雪': ('雪地', '下雪', '雪人', '玩雪', '积雪'), '下雪': ('雪地', '雪人', '玩雪', '积雪'),
    '坐飞机': ('机舱', '飞机上', '登机', '航班', '机场'), '飞机': ('机舱', '航班', '机场'),
    '睡觉': ('熟睡', '午睡', '睡着', '入睡'), '吃饭': ('进餐', '用餐', '餐桌'), '画画': ('涂鸦', '绘画', '蜡笔', '画笔'),
    '唱歌': ('儿歌', '哼唱'), '跳舞': ('舞蹈', '律动'), '滑梯': ('滑滑梯',), '荡秋千': ('秋千',), '公园': ('草地', '草坪'),
}


def search_terms(query):
    """Content words of a parent's search: filler phrases and edge particles removed."""
    terms = []
    for token in str(query or '').casefold().split():
        for phrase in SEARCH_DROP:
            token = token.replace(phrase, ' ')
        for part in token.split():
            while len(part) > 2 and part[0] in EDGE_CHARS:
                part = part[1:]
            while len(part) > 2 and part[-1] in EDGE_CHARS:
                part = part[:-1]
            if part:
                terms.append(part)
    return terms or str(query or '').casefold().split()


def _pattern(term):
    """Chinese phrases tolerate a short gap: 吃西瓜 also finds 吃着西瓜 / 吃了西瓜."""
    if 2 <= len(term) <= 8 and CJK.search(term):
        return re.compile('.{0,2}'.join(map(re.escape, term)))
    return term


class Term:
    """One search term: the phrase or a synonym; a long Chinese term may also match as two halves (大理玩水)."""

    def __init__(self, term, depth=0):
        self.options = [_pattern(t) for t in (term, *SYNONYMS.get(term, ()))]
        self.halves = []
        if depth == 0 and len(term) >= 4 and all(CJK.match(c) for c in term):
            self.halves = [(Term(term[:i], 1), Term(term[i:], 1)) for i in range(2, len(term) - 1)]

    def __call__(self, text):
        if any((o in text) if isinstance(o, str) else o.search(text) for o in self.options):
            return True
        return any(a(text) and b(text) for a, b in self.halves)


class SemanticGateway:
    """bge-m3 media similarity from the library's local gateway; failure means keywords only."""

    def __init__(self, token_path, url='http://127.0.0.1:8878', timeout=2.0):
        self.token_path, self.url, self.timeout = Path(token_path), url.rstrip('/'), timeout
        self.cache = {}

    def scores(self, query):
        query = str(query or '').strip()[:200]
        if not query:
            return None
        hit = self.cache.get(query)
        if hit and time.monotonic() - hit[0] < 300:
            return hit[1]
        try:
            token = json.loads(self.token_path.read_text())['token']
            with httpx.Client(timeout=self.timeout, trust_env=False) as client:
                response = client.get(self.url + '/v1/media/semantic', params={'q': query, 'limit': 3000},
                                      headers={'Authorization': 'Bearer ' + token})
            body = response.json() if response.status_code == 200 else {}
            value = {str(k): float(v) for k, v in (body.get('scores') or {}).items()} if body.get('available') else None
        except Exception:
            value = None
        if value is not None:
            if len(self.cache) > 64:
                self.cache.clear()
            self.cache[query] = (time.monotonic(), value)
        return value


class OnlineTimeline:
    def __init__(self, bridge, processor, store, family, child, subject, *, ttl=30, born=None, semantic=None, wait=3.0):
        self.bridge, self.processor, self.store = bridge, processor, store
        self.semantic = semantic
        self.family, self.child, self.subject, self.ttl = family, child, subject, ttl
        # Library labels can be wrong (other children, a cartoon called 布布); nothing
        # captured before she was born belongs in her timeline.
        self.born = valid_day(born) if born else None
        self.captions = TimelineCaptions(store)
        # The library lives on an external disk that can stall indefinitely (macOS
        # privacy prompts, sleep). Only the refresher thread ever reads it; requests
        # wait at most `wait` seconds and otherwise use the last good snapshot.
        self.lock = threading.Lock()
        self.ready = threading.Condition(self.lock)
        self.wake = threading.Event()
        self.refresher = None
        self.wait = wait
        self.cached = None
        self.cached_at = 0.0
        self.built_at = None
        self.generation = 0
        self.built_generation = self.failed_generation = -1
        self.error = None
        self.aspects = {}

    def authorize(self, scope):
        if scope.family_id != self.family:
            raise Missing('素材不存在')
        scope.require_child(self.child)

    def _start(self):
        if self.refresher is None or not self.refresher.is_alive():
            self.refresher = threading.Thread(target=self._refresh_loop, name='online-timeline-refresh', daemon=True)
            self.refresher.start()

    def _refresh_loop(self):
        while True:
            self.wake.wait()
            self.wake.clear()
            with self.lock:
                generation = self.generation
            try:
                value, error = self._build(), None
            except Exception as exc:
                value, error = None, exc
                log.warning('online timeline refresh failed error=%s', type(exc).__name__)
            with self.ready:
                if value is not None:
                    self.cached, self.cached_at, self.built_at = value, time.monotonic(), time.time()
                    self.built_generation = generation
                else:
                    self.failed_generation = generation
                self.error = error
                self.ready.notify_all()

    def snapshot(self):
        deadline = time.monotonic() + self.wait
        with self.ready:
            self._start()
            if self.cached is None and self.built_generation >= self.generation:
                self.generation += 1
            current = self.cached is not None and self.built_generation >= self.generation
            if current and time.monotonic() - self.cached_at < self.ttl:
                return self.cached
            self.wake.set()
            if current:
                return self.cached  # stale by age only: serve it while the refresher runs
            wanted = self.generation
            while self.built_generation < wanted and self.failed_generation < wanted:
                left = deadline - time.monotonic()
                if left <= 0:
                    break
                self.ready.wait(left)
            if self.cached is not None:
                return self.cached  # fresh, or the last good one when the library is stuck
        raise HTTPException(503, UNAVAILABLE)

    def peek(self, wait=0.0):
        """The last good snapshot (None before the first one) without waiting longer than `wait`
        for a first build; refreshes in the background."""
        deadline = time.monotonic() + wait
        with self.ready:
            self._start()
            if self.cached is None or time.monotonic() - self.cached_at >= self.ttl or self.built_generation < self.generation:
                self.wake.set()
            while self.cached is None and time.monotonic() < deadline:
                self.ready.wait(deadline - time.monotonic())
            return self.cached

    def snapshot_age(self):
        return None if self.built_at is None else max(0, int(time.time() - self.built_at))

    def _build(self):
        value = self.bridge.subject_snapshot(self.subject)
        if value.get('complete') is not True:
            raise BrainUnavailable('第二大脑素材库尚未就绪。')
        decided = decisions(self.store, self.family)
        source = [i for i in value['items'] if decided.get(i['file_id']) != 'no']
        present = {i['file_id'] for i in source}
        extra = [fid for fid, choice in decided.items() if choice == 'yes' and fid not in present]
        if extra:
            try:
                for item in self.bridge.items_by_ids(extra, self.subject):
                    source.append({**item, 'provenance': 'family_confirmed', 'confidence': None})
            except BrainUnavailable as exc:
                log.warning('family confirmed items unavailable error=%s', type(exc).__name__)
        labels = value.get('people_labels') or {}
        items = []
        family_words = self.captions.overlays(self.family, source)
        for item in source:
            if item.get('media_type') not in {'photo', 'video'}:
                continue
            analysis = item.get('analysis') or {}
            # Show parsed library material, never unprocessed inbox files.
            if not any(analysis.get(k) for k in ('description', 'ocr', 'tags', 'segments')):
                continue
            stamp = self.stamp(item.get('captured_at'))
            day = datetime.fromisoformat(stamp).astimezone(LOCAL).date().isoformat() if stamp else None
            if self.born and (not day or day < self.born):
                continue
            segments, hidden = [], 0
            for segment in analysis.get('segments') or []:
                try:
                    clean = {'id': str(segment['id']), 'start': float(segment['start']),
                             'end': float(segment['end']), 'text': str(segment['text'])}
                except (KeyError, TypeError, ValueError):
                    continue
                if plausible_segment(clean['text'], clean['start'], clean['end']):
                    segments.append(clean)
                else:
                    hidden += 1
            original = str(analysis.get('description') or '')
            adjusted = item['file_id'] in family_words and family_words[item['file_id']] != original
            people = [p for p in item.get('people') or [] if isinstance(p, str)]
            description = familiar(family_words.get(item['file_id'], original), labels, people)
            tags = [t for t in analysis.get('tags') or [] if isinstance(t, str)]
            place = str(item.get('place') or '')
            text = ' '.join([original, description, str(analysis.get('ocr') or ''), ' '.join(tags),
                             str(item.get('event') or ''), place, ' '.join(people),
                             ' '.join(labels.get(p, '') for p in people),
                             ' '.join(s['text'] for s in segments)]).casefold()
            items.append({'item': item, 'stamp': stamp, 'day': day, 'text': text,
                          'description': description, 'adjusted': adjusted,
                          'segments': segments, 'hidden': hidden, 'people': people, 'place': place,
                          'event': str(item.get('event') or ''), 'tags': tags,
                          'confirmed': decided.get(item['file_id']) == 'yes'})
        items.sort(key=lambda row: (row['stamp'] or '', row['item']['file_id']), reverse=True)
        mark_bursts(items)
        # Only what the feed shows defines a page snapshot; still-unparsed
        # library files must not reset a parent's scroll position.
        snapshot_id = digest([(row['item']['file_id'], row['item'].get('source_revision', ''), row['confirmed'])
                              for row in items])
        events = []
        if hasattr(self.bridge, 'auto_events'):
            try:
                events = self.bridge.auto_events()
            except Exception as exc:
                log.warning('auto events unavailable error=%s', type(exc).__name__)
                events = (self.cached or {}).get('events', [])
        return {'snapshot_id': snapshot_id, 'rows': items, 'labels': labels, 'events': events,
                'by_id': {row['item']['file_id']: row['item'] for row in items},
                'rows_by_id': {row['item']['file_id']: row for row in items}}

    def invalidate(self):
        with self.lock:
            self.generation += 1
            self.wake.set()

    @staticmethod
    def stamp(value):
        try:
            parsed = datetime.fromisoformat(str(value or '').replace('Z', '+00:00'))
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=LOCAL)
        return parsed.astimezone(timezone.utc).isoformat()

    def aspect(self, sha, item=None):
        """A rendered preview is exact; otherwise the library's pixel size; 1.0 only when neither exists."""
        if sha in self.aspects:
            return self.aspects[sha]
        directory = self.store.root / 'online-previews'
        for size in ('thumb', 'card', 'large'):
            dims = jpeg_size(directory / ('%s-%s.jpg' % (sha, size)))
            if dims:
                self.aspects[sha] = round(dims[0] / dims[1], 4)
                return self.aspects[sha]
        return item_aspect(item or {}) or 1.0

    def public(self, row):
        item = row['item']
        analysis = item.get('analysis') or {}
        fid, sha = item['file_id'], item['content_hash']
        base = '/learning/api/online-timeline/' + fid
        provenance = item.get('provenance') or 'library'
        return {'id': fid, 'content_hash': sha, 'kind': item['media_type'], 'captured_at': row['stamp'],
                'local_day': row['day'], 'description': row.get('description', str(analysis.get('description') or '')),
                'description_adjusted': bool(row.get('adjusted')),
                'ocr': str(analysis.get('ocr') or ''),
                'tags': [t for t in analysis.get('tags') or [] if isinstance(t, str)],
                'segments': row.get('segments', []), 'transcript_hidden': row.get('hidden', 0),
                'label_provenance': provenance,
                'label_provenance_text': PROVENANCE.get(provenance, '第二大脑'),
                # Family roles (爸爸/妈妈…) read better than names; filtering accepts either.
                'aspect': self.aspect(sha, item),
                'people': [(self.cached or {}).get('labels', {}).get(name) or name for name in row.get('people', [])],
                'place': short_place(row.get('place')),
                'confirmed_by_family': bool(row.get('confirmed')),
                # Near-duplicate bursts share burst_id (the lead's id); burst_count is the group size.
                'burst_id': (row.get('burst') or (None, 1))[0], 'burst_count': (row.get('burst') or (None, 1))[1],
                'source': 'second-brain', 'preview_url': base + '/preview?size=thumb&revision=' + sha,
                'large_url': base + '/preview?size=large&revision=' + sha,
                'media_url': base + '/original?revision=' + sha}

    def _semantic(self, query, snapshot):
        if not self.semantic or not str(query).strip():
            return {}
        try:
            scores = self.semantic.scores(query) or {}
        except Exception:
            return {}
        mine = {fid: score for fid, score in scores.items() if fid in snapshot['rows_by_id']}
        if not mine:
            return {}
        floor = max(SEM_FLOOR, max(mine.values()) - SEM_BAND)
        return {fid: score for fid, score in mine.items() if score >= floor}

    @staticmethod
    def _matchers(tokens):
        return [Term(token) for token in tokens]

    @staticmethod
    def _person_match(row, person, labels):
        return any(person in (name, labels.get(name)) for name in row['people'])

    def feed(self, scope, query='', kind='all', start=None, end=None, order='desc', page=1, limit=40, person=None,
             collapse_bursts=False):
        self.authorize(scope)
        if kind not in {'all', 'photo', 'video'} or order not in {'asc', 'desc'}:
            raise ValueError('筛选条件无效')
        if type(page) is not int or type(limit) is not int or not 1 <= page <= 10000 or not 1 <= limit <= 100:
            raise ValueError('分页无效')
        if start:
            valid_day(start)
        if end:
            valid_day(end)
        if start and end and start > end:
            raise ValueError('日期范围无效')
        person = str(person or '').strip()
        snapshot = self.snapshot()
        tokens = search_terms(query) if str(query).strip() else []
        semantic = self._semantic(' '.join(tokens), snapshot) if tokens else {}
        matchers = self._matchers(tokens)
        counts = {'photo': 0, 'video': 0}
        ranked, matched = [], []
        for row in snapshot['rows']:
            counts[row['item']['media_type']] += 1
            if kind != 'all' and row['item']['media_type'] != kind:
                continue
            if (start and (not row['day'] or row['day'] < start)) or (end and (not row['day'] or row['day'] > end)):
                continue
            if person and not self._person_match(row, person, snapshot['labels']):
                continue
            fid = row['item']['file_id']
            if fid in semantic:
                ranked.append(row)
            elif all(m(row['text']) for m in matchers):
                matched.append(row)
        if order == 'asc':
            matched.reverse()
        ranked.sort(key=lambda row: (-semantic[row['item']['file_id']], row['item']['file_id']))
        matched = ranked + matched
        if collapse_bursts:
            matched = self._collapse(matched)
        offset = (page - 1) * limit
        result = {'items': [self.public(row) for row in matched[offset:offset + limit]],
                  'total': len(matched), 'page': page, 'has_more': offset + limit < len(matched),
                  'photos': counts['photo'], 'videos': counts['video'], 'source': 'second-brain',
                  'collection_name': '布布', 'snapshot_id': snapshot['snapshot_id'],
                  'semantic': bool(semantic), 'updated_at': datetime.now(timezone.utc).isoformat()}
        if page == 1:
            months = Counter(row['day'][:7] for row in matched if row['day'])
            result['months'] = [{'month': m, 'count': months[m]} for m in sorted(months, reverse=True)]
        return result

    @staticmethod
    def _collapse(rows):
        """One row per burst: its lead when the lead is in the result, else the first member shown."""
        present = {row['item']['file_id'] for row in rows}
        kept, seen = [], set()
        for row in rows:
            burst = row.get('burst')
            if burst:
                lead = burst[0]
                if lead in seen or (lead in present and row['item']['file_id'] != lead):
                    continue
                seen.add(lead)
            kept.append(row)
        return kept

    def people(self, scope):
        self.authorize(scope)
        snapshot = self.snapshot()
        counts = Counter(name for row in snapshot['rows'] for name in row['people'])
        return {'items': [{'name': name, 'label': snapshot['labels'].get(name, name), 'count': count}
                          for name, count in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))]}

    def items(self, scope, ids):
        self.authorize(scope)
        if isinstance(ids, str):
            ids = [i.strip() for i in ids.split(',') if i.strip()]
        if not isinstance(ids, list) or len(ids) > 60:
            raise ValueError('一次最多查询60个素材')
        rows = self.snapshot()['rows_by_id']
        return {'items': [self.public(rows[fid]) for fid in dict.fromkeys(ids) if fid in rows]}

    @staticmethod
    def _quality(row):
        return quality(row)

    def highlight_rows(self, day):
        """那年今天 (same month-day, earlier years) first, then 那年这几天 (±3 days), ≤4 together;
        then the best of the last 60 days; ≤6, one per day and one per burst first.
        Screenshots, ID photos and documents are never picked."""
        anchor = Date.fromisoformat(valid_day(day))
        rows = [r for r in self.snapshot()['rows'] if r['day'] and r['day'] <= anchor.isoformat() and not unsuitable(r)]
        exact, near = [], []
        for row in rows:
            when = Date.fromisoformat(row['day'])
            if when.year >= anchor.year:
                continue
            try:
                same = anchor.replace(year=when.year)
            except ValueError:
                same = anchor.replace(year=when.year, day=28)
            gap = abs((when - same).days)
            if gap == 0:
                exact.append(row)
            elif gap <= 3:
                near.append(row)
        old = {id(r) for r in exact + near}
        recent = [r for r in rows if id(r) not in old and (anchor - Date.fromisoformat(r['day'])).days <= 60]
        chosen, reasons, bursts = [], {}, set()
        for reason, pool, cap in zip(HIGHLIGHT_REASONS, (exact, near, recent), (4, 4, 6)):
            pool = sorted(pool, key=lambda r: (self._quality(r), r['day'], r['item']['file_id']), reverse=True)
            for allowed in (1, 2):
                for row in pool:
                    fid = row['item']['file_id']
                    burst = (row.get('burst') or (fid,))[0]
                    if len(chosen) >= cap or fid in reasons or burst in bursts:
                        continue
                    if sum(1 for c in chosen if c['day'] == row['day']) >= allowed:
                        continue
                    chosen.append(row)
                    reasons[fid] = reason
                    bursts.add(burst)
        return chosen, reasons

    def caption(self, row, events=None):
        """A short parent-facing line (≤14 characters) for widgets and the watch, or None.

        Event album title, else who she is with and where; never the raw description.
        """
        labels = (self.cached or {}).get('labels') or {}
        fid = row['item']['file_id']
        for album in events if events is not None else (self.cached or {}).get('events') or []:
            if fid in (album.get('file_ids') or []):
                title = family_story(album.get('title') or '', labels).strip()
                if 2 <= len(title) <= 14:
                    return title
        roles = list(dict.fromkeys(labels[p] for p in row.get('people') or [] if labels.get(p) and labels[p] != p))[:2]
        found = poi(row.get('place'))
        where = found[1] if found else ''
        if roles:
            line = '和' + ''.join(roles) + ('在' + where if where else '在一起')
            return line if len(line) <= 14 else '和' + ''.join(roles) + '在一起'
        if where and len(where) <= 13:
            return '在' + where
        return None

    def highlights(self, scope, day):
        self.authorize(scope)
        chosen, reasons = self.highlight_rows(day)
        return {'items': [self.public(row) for row in chosen], 'reason_by_id': reasons,
                'caption_by_id': {row['item']['file_id']: self.caption(row) for row in chosen}}

    def media(self, scope, fid, size='thumb'):
        self.authorize(scope)
        if not isinstance(fid, str) or not re.fullmatch(r'[a-f0-9]{24}', fid) or size not in {'thumb', 'card', 'large', 'original'}:
            raise Missing('素材不存在')
        item = self.snapshot()['by_id'].get(fid)
        if not item:
            raise Missing('素材已不在当前专属库中')
        if size == 'original':
            path = Path(item['local_path'])
            if not path.is_file():
                raise Missing('原件暂时不可用')
            return path, mimetypes.guess_type(item['name'])[0] or 'application/octet-stream'
        return self.render_preview(item, size)

    def render_preview(self, item, size='thumb'):
        # A cached preview needs no trip to the original on the external disk.
        directory = self.store.root / 'online-previews'
        directory.mkdir(mode=0o700, exist_ok=True)
        target = directory / ('%s-%s.jpg' % (item['content_hash'], size))
        if not target.is_file():
            path = Path(item['local_path'])
            if not path.is_file():
                raise Missing('原件暂时不可用')
            self._render(path, item['media_type'], PREVIEW_SIZES[size], directory, target)
        return target, 'image/jpeg'

    def _render(self, path, kind, edge, directory, target):
        fd, name = tempfile.mkstemp(prefix='.preview-', suffix='.jpg', dir=directory)
        os.close(fd)
        temporary = Path(name)
        try:
            try:
                if kind == 'photo':
                    # sips handles HEIC tile grids and orientation reliably on macOS.
                    self.processor._run(['/usr/bin/sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '78',
                                         '-Z', str(edge), str(path), '--out', str(temporary)], 60)
                else:
                    self.processor._run([self.processor.ffmpeg, '-v', 'error', '-ss', '0.5', '-i', str(path),
                                         '-frames:v', '1', '-vf',
                                         'scale=%d:%d:force_original_aspect_ratio=decrease' % (edge, edge),
                                         '-q:v', '4', '-y', str(temporary)], 60)
            except Exception as exc:
                raise Missing('缩略图暂时无法生成') from exc
            if not temporary.is_file() or not temporary.stat().st_size:
                raise Missing('缩略图暂时无法生成')
            temporary.chmod(0o600)
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
