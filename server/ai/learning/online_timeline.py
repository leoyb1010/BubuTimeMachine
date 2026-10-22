"""Read the configured second-brain collection directly; never join local Entries.

Membership comes from the existing library: accepted person photos plus videos
whose completed video analysis names the child. This service runs no face
matching and never presents historical machine labels as manual confirmation.
Original paths stay server-side; every media URL still needs family auth.
"""
from collections import Counter
from datetime import date as Date, datetime, timedelta, timezone
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
PREVIEW_SIZES = {'thumb': 480, 'large': 1600}
PROVENANCE = {'manual': '家人标注', 'gemini_two_pass': '第二大脑人物识别',
              'video_analysis_mention': '第二大脑视频解析提到布布', 'family_confirmed': '家人认一认确认'}
# Same tuning as the library's own gallery: bge-m3 scores drift per query, so keep
# what is close to the best hit and above an absolute floor.
SEM_FLOOR, SEM_BAND = 0.6, 0.1
CJK = re.compile(r'[\u3400-\u9fff]')
# Common ASR hallucinations on silence/music (zh-only local speech model).
JUNK_PHRASES = ('字幕由', '请不吝点赞', '订阅转发', '打赏支持', '明镜与点点', '谢谢观看', '感谢观看')
HIGHLIGHT_REASONS = ('那年今天', '最近精选')


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
    def __init__(self, bridge, processor, store, family, child, subject, *, ttl=30, born=None, semantic=None):
        self.bridge, self.processor, self.store = bridge, processor, store
        self.semantic = semantic
        self.family, self.child, self.subject, self.ttl = family, child, subject, ttl
        # Library labels can be wrong (other children, a cartoon called 布布); nothing
        # captured before she was born belongs in her timeline.
        self.born = valid_day(born) if born else None
        self.captions = TimelineCaptions(store)
        self.lock = threading.RLock()
        self.cached = None
        self.cached_at = 0.0
        self.aspects = {}

    def authorize(self, scope):
        if scope.family_id != self.family:
            raise Missing('素材不存在')
        scope.require_child(self.child)

    def snapshot(self):
        with self.lock:
            if self.cached and time.monotonic() - self.cached_at < self.ttl:
                return self.cached
            try:
                value = self.bridge.subject_snapshot(self.subject)
            except BrainUnavailable:
                raise HTTPException(503, '第二大脑素材库暂时不可用，请稍后重试。') from None
            if value.get('complete') is not True:
                raise HTTPException(503, '第二大脑素材库尚未就绪。')
            decided = decisions(self.store, self.family)
            source = [i for i in value['items'] if decided.get(i['file_id']) != 'no']
            present = {i['file_id'] for i in source}
            extra = [fid for fid, choice in decided.items() if choice == 'yes' and fid not in present]
            if extra:
                try:
                    for item in self.bridge.items_by_ids(extra, self.subject):
                        source.append({**item, 'provenance': 'family_confirmed', 'confidence': None})
                except BrainUnavailable:
                    log.warning('family confirmed items unavailable')
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
                description = family_words.get(item['file_id'], original)
                people = [p for p in item.get('people') or [] if isinstance(p, str)]
                tags = [t for t in analysis.get('tags') or [] if isinstance(t, str)]
                place = str(item.get('place') or '')
                text = ' '.join([original, description, str(analysis.get('ocr') or ''), ' '.join(tags),
                                 str(item.get('event') or ''), place, ' '.join(people),
                                 ' '.join(labels.get(p, '') for p in people),
                                 ' '.join(s['text'] for s in segments)]).casefold()
                items.append({'item': item, 'stamp': stamp, 'day': day, 'text': text,
                              'description': description, 'adjusted': description != original,
                              'segments': segments, 'hidden': hidden, 'people': people, 'place': place,
                              'event': str(item.get('event') or ''), 'tags': tags,
                              'confirmed': decided.get(item['file_id']) == 'yes'})
            items.sort(key=lambda row: (row['stamp'] or '', row['item']['file_id']), reverse=True)
            # Only what the feed shows defines a page snapshot; still-unparsed
            # library files must not reset a parent's scroll position.
            snapshot_id = digest([(row['item']['file_id'], row['item'].get('source_revision', ''), row['confirmed'])
                                  for row in items])
            self.cached = {'snapshot_id': snapshot_id, 'rows': items, 'labels': labels,
                           'by_id': {row['item']['file_id']: row['item'] for row in items},
                           'rows_by_id': {row['item']['file_id']: row for row in items}}
            self.cached_at = time.monotonic()
            return self.cached

    def invalidate(self):
        with self.lock:
            self.cached = None

    @staticmethod
    def stamp(value):
        try:
            parsed = datetime.fromisoformat(str(value or '').replace('Z', '+00:00'))
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=LOCAL)
        return parsed.astimezone(timezone.utc).isoformat()

    def aspect(self, sha):
        if sha in self.aspects:
            return self.aspects[sha]
        directory = self.store.root / 'online-previews'
        for size in ('thumb', 'large'):
            dims = jpeg_size(directory / ('%s-%s.jpg' % (sha, size)))
            if dims:
                self.aspects[sha] = round(dims[0] / dims[1], 4)
                return self.aspects[sha]
        return 1.0

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
                'aspect': self.aspect(sha),
                'people': [(self.cached or {}).get('labels', {}).get(name) or name for name in row.get('people', [])],
                'place': short_place(row.get('place')),
                'confirmed_by_family': bool(row.get('confirmed')),
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
        """Chinese phrases tolerate a short gap: 吃西瓜 also finds 吃着西瓜 / 吃了西瓜."""
        result = []
        for token in tokens:
            if 2 <= len(token) <= 8 and re.search(r'[\u4e00-\u9fff]', token):
                result.append(re.compile('.{0,2}'.join(map(re.escape, token))))
            else:
                result.append(token)
        return result

    @staticmethod
    def _person_match(row, person, labels):
        return any(person in (name, labels.get(name)) for name in row['people'])

    def feed(self, scope, query='', kind='all', start=None, end=None, order='desc', page=1, limit=40, person=None):
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
        tokens = str(query).casefold().split()
        semantic = self._semantic(query, snapshot) if tokens else {}
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
            elif all((m in row['text']) if isinstance(m, str) else m.search(row['text']) for m in matchers):
                matched.append(row)
        if order == 'asc':
            matched.reverse()
        ranked.sort(key=lambda row: (-semantic[row['item']['file_id']], row['item']['file_id']))
        matched = ranked + matched
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
        return (row['adjusted'], row['item']['media_type'] == 'photo', min(len(row['description']), 120))

    def highlight_rows(self, day):
        """On-this-day (±3 days, earlier years, ≤4) first, then the best of the last 60 days; ≤6, one per day first."""
        anchor = Date.fromisoformat(valid_day(day))
        rows = [r for r in self.snapshot()['rows'] if r['day'] and r['day'] <= anchor.isoformat()]
        past = []
        for row in rows:
            when = Date.fromisoformat(row['day'])
            if when.year >= anchor.year:
                continue
            try:
                same = anchor.replace(year=when.year)
            except ValueError:
                same = anchor.replace(year=when.year, day=28)
            if abs((when - same).days) <= 3:
                past.append(row)
        old = {id(r) for r in past}
        recent = [r for r in rows if id(r) not in old and (anchor - Date.fromisoformat(r['day'])).days <= 60]
        chosen, reasons = [], {}
        for reason, pool, cap in zip(HIGHLIGHT_REASONS, (past, recent), (4, 6)):
            pool = sorted(pool, key=lambda r: (self._quality(r), r['day'], r['item']['file_id']), reverse=True)
            for allowed in (1, 2):
                for row in pool:
                    fid = row['item']['file_id']
                    if len(chosen) >= cap or fid in reasons:
                        continue
                    if sum(1 for c in chosen if c['day'] == row['day']) >= allowed:
                        continue
                    chosen.append(row)
                    reasons[fid] = reason
        return chosen, reasons

    def highlights(self, scope, day):
        self.authorize(scope)
        chosen, reasons = self.highlight_rows(day)
        return {'items': [self.public(row) for row in chosen], 'reason_by_id': reasons}

    def media(self, scope, fid, size='thumb'):
        self.authorize(scope)
        if not isinstance(fid, str) or not re.fullmatch(r'[a-f0-9]{24}', fid) or size not in {'thumb', 'large', 'original'}:
            raise Missing('素材不存在')
        item = self.snapshot()['by_id'].get(fid)
        if not item:
            raise Missing('素材已不在当前专属库中')
        path = Path(item['local_path'])
        if not path.is_file():
            raise Missing('原件暂时不可用')
        if size == 'original':
            return path, mimetypes.guess_type(item['name'])[0] or 'application/octet-stream'
        return self.render_preview(item, size)

    def render_preview(self, item, size='thumb'):
        path = Path(item['local_path'])
        if not path.is_file():
            raise Missing('原件暂时不可用')
        directory = self.store.root / 'online-previews'
        directory.mkdir(mode=0o700, exist_ok=True)
        target = directory / ('%s-%s.jpg' % (item['content_hash'], size))
        if not target.is_file():
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
