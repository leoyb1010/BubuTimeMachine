"""Read the configured second-brain collection directly; never join local Entries.

Membership comes from the existing library: accepted person photos plus videos
whose completed video analysis names the child. This service runs no face
matching and never presents historical machine labels as manual confirmation.
Original paths stay server-side; every media URL still needs family auth.
"""
from datetime import datetime, timezone
import mimetypes
import os
from pathlib import Path
import re
import tempfile
import threading
import time
from zoneinfo import ZoneInfo

from fastapi import HTTPException

from .brain_bridge import BrainUnavailable
from .store import Missing, digest, valid_day

LOCAL = ZoneInfo('Asia/Shanghai')
PREVIEW_SIZES = {'thumb': 480, 'large': 1600}
PROVENANCE = {'manual': '家人标注', 'gemini_two_pass': '第二大脑人物识别',
              'video_analysis_mention': '第二大脑视频解析提到布布'}


class OnlineTimeline:
    def __init__(self, bridge, processor, store, family, child, subject, *, ttl=30):
        self.bridge, self.processor, self.store = bridge, processor, store
        self.family, self.child, self.subject, self.ttl = family, child, subject, ttl
        self.lock = threading.RLock()
        self.cached = None
        self.cached_at = 0.0

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
            items = []
            for item in value['items']:
                if item.get('media_type') not in {'photo', 'video'}:
                    continue
                analysis = item.get('analysis') or {}
                # Show parsed library material, never unprocessed inbox files.
                if not any(analysis.get(k) for k in ('description', 'ocr', 'tags', 'segments')):
                    continue
                stamp = self.stamp(item.get('captured_at'))
                day = datetime.fromisoformat(stamp).astimezone(LOCAL).date().isoformat() if stamp else None
                text = ' '.join([str(analysis.get('description') or ''), str(analysis.get('ocr') or ''),
                                 ' '.join(t for t in analysis.get('tags') or [] if isinstance(t, str)),
                                 ' '.join(str(s.get('text') or '') for s in analysis.get('segments') or [])]).casefold()
                items.append({'item': item, 'stamp': stamp, 'day': day, 'text': text})
            items.sort(key=lambda row: (row['stamp'] or '', row['item']['file_id']), reverse=True)
            # Only what the feed shows defines a page snapshot; still-unparsed
            # library files must not reset a parent's scroll position.
            snapshot_id = digest([(row['item']['file_id'], row['item'].get('source_revision', '')) for row in items])
            self.cached = {'snapshot_id': snapshot_id, 'rows': items,
                           'by_id': {row['item']['file_id']: row['item'] for row in items}}
            self.cached_at = time.monotonic()
            return self.cached

    @staticmethod
    def stamp(value):
        try:
            parsed = datetime.fromisoformat(str(value or '').replace('Z', '+00:00'))
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=LOCAL)
        return parsed.astimezone(timezone.utc).isoformat()

    def public(self, row):
        item = row['item']
        analysis = item.get('analysis') or {}
        fid, sha = item['file_id'], item['content_hash']
        base = '/learning/api/online-timeline/' + fid
        provenance = item.get('provenance') or 'library'
        segments = []
        for segment in analysis.get('segments') or []:
            try:
                segments.append({'id': str(segment['id']), 'start': float(segment['start']),
                                 'end': float(segment['end']), 'text': str(segment['text'])})
            except (KeyError, TypeError, ValueError):
                continue
        return {'id': fid, 'content_hash': sha, 'kind': item['media_type'], 'captured_at': row['stamp'],
                'local_day': row['day'], 'description': str(analysis.get('description') or ''),
                'ocr': str(analysis.get('ocr') or ''),
                'tags': [t for t in analysis.get('tags') or [] if isinstance(t, str)],
                'segments': segments, 'label_provenance': provenance,
                'label_provenance_text': PROVENANCE.get(provenance, '第二大脑'),
                'source': 'second-brain', 'preview_url': base + '/preview?size=thumb&revision=' + sha,
                'large_url': base + '/preview?size=large&revision=' + sha,
                'media_url': base + '/original?revision=' + sha}

    def feed(self, scope, query='', kind='all', start=None, end=None, order='desc', page=1, limit=40):
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
        snapshot = self.snapshot()
        tokens = str(query).casefold().split()
        counts = {'photo': 0, 'video': 0}
        matched = []
        for row in snapshot['rows']:
            counts[row['item']['media_type']] += 1
            if kind != 'all' and row['item']['media_type'] != kind:
                continue
            if (start and (not row['day'] or row['day'] < start)) or (end and (not row['day'] or row['day'] > end)):
                continue
            if not all(token in row['text'] for token in tokens):
                continue
            matched.append(row)
        if order == 'asc':
            matched.reverse()
        offset = (page - 1) * limit
        return {'items': [self.public(row) for row in matched[offset:offset + limit]],
                'total': len(matched), 'page': page, 'has_more': offset + limit < len(matched),
                'photos': counts['photo'], 'videos': counts['video'], 'source': 'second-brain',
                'collection_name': '布布', 'snapshot_id': snapshot['snapshot_id'],
                'updated_at': datetime.now(timezone.utc).isoformat()}

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
