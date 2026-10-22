"""Durable jobs for parent-uploaded lessons. No library scanning, no automatic publishing.

Courses come only from POST /learning/api/courses. Ordinary photos and the
second-brain timeline are never selected as lesson material here.
"""
from __future__ import annotations
from contextlib import contextmanager
from datetime import datetime
import fcntl
import logging
import mimetypes
import os
from pathlib import Path
import re
import shutil
import time
from zoneinfo import ZoneInfo

from .processing import MediaProcessor, ProcessingUnavailable
from .store import Conflict, Missing, digest

log = logging.getLogger('bubu.learning.worker')
HEARTBEAT = 'worker-heartbeat'
BACKUP = 'learning-backup'
BACKUP_KEEP = 7
VOICE_EVERY, VOICE_BATCH = 120, 20  # was 4 clips per 20 min: a 500-clip backlog took days

class LearningWorker:
    def __init__(self, store, bridge, processor, *, family, child, pocketbase=None, subject=None, features=None):
        if not family or not child: raise ValueError('学习任务须配置家庭和孩子')
        self.store, self.bridge, self.processor = store, bridge, processor
        self.family, self.child = family, child
        self.pocketbase = pocketbase
        self.subject = subject
        self.captioned_at = 0.0
        self.features = features or {}
        self.step_at = {}
        self.beat_at = 0.0

    def heartbeat(self, force=False):
        """Loop progress for /health/deep and the status page; at most one write per 30 s."""
        if not force and time.monotonic()-self.beat_at<30:return
        self.beat_at=time.monotonic()
        try:self.store.set_cursor(HEARTBEAT,{'at':time.time()})
        except Exception as exc:log.warning('heartbeat write failed error=%s',type(exc).__name__)

    @contextmanager
    def lock(self):
        # One worker owns this store, including long audio jobs. An API process
        # only enqueues work; it never imports or calls Gemini on request threads.
        with (self.store.root/'learning-worker.lock').open('a+') as handle:
            try: fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError as exc: raise Conflict('学习整理任务正在运行') from exc
            try: yield
            finally: fcntl.flock(handle,fcntl.LOCK_UN)

    def _media_record(self, media_id, sha):
        from memory_query import _pb_quote
        media=self.pocketbase.get_record('media',media_id)
        if (media.get('familyId')!=self.family or media.get('isDeleted')
                or media.get('contentHash')!=sha or not media.get('file')):
            raise ValueError('媒体事实已经变化')
        entry=self.pocketbase.first_record('entries',filter_value="familyId='%s' && localId='%s'" %
            (_pb_quote(self.family),_pb_quote(media.get('entryLocalId',''))),sort='id')
        if not entry or entry.get('familyId')!=self.family or entry.get('isDeleted') or entry.get('isArchived'):
            raise ValueError('时光事实不可用')
        return media

    def process_media_requests(self, limit=5):
        if self.pocketbase is None:return
        import json
        import tempfile
        with self.store.db() as db:
            rows=db.execute("SELECT key,value FROM cursors WHERE key LIKE 'media-analysis-request:%'").fetchall()
        requests=[(r['key'],json.loads(r['value'])) for r in rows]
        pending=[(k,r) for k,r in requests if r.get('family_id')==self.family and r.get('state')=='queued']
        for key,request in pending[:limit]:
            mid,sha=request['media_id'],request['content_hash']
            cache_key='media-analysis:'+digest([self.family,mid])
            cache={'family_id':self.family,'media_id':mid,'content_hash':sha,'state':'processing'}
            self.store.set_cursor(cache_key,cache)
            try:
                media=self._media_record(mid,sha)
                with tempfile.TemporaryDirectory(prefix='bubu-media-analysis-') as tmp:
                    original=Path(tmp)/'original'
                    self.pocketbase.download_record_file('media',mid,media['file'],str(original),max_bytes=256*1024*1024)
                    self.processor.verify_file(original,sha)
                    self._media_record(mid,sha)
                    day=datetime.now(ZoneInfo('Asia/Shanghai')).date().isoformat()
                    source=self.store.add_source(self.family,'__media_analysis__',day,'media:'+mid+':'+sha,
                        media['file'],original,mimetypes.guess_type(media['file'])[0],media_ref={'media_id':mid})
                aid=source['asset_id']
                analysis=self.store.analysis(self.family,aid)
                if analysis and analysis['state']=='ready' and request.get('force') is not True:
                    cache.update(asset_id=aid,state='ready')
                else:
                    self.store.enqueue(self.family,'analyze',aid,{'asset_id':aid},force=True)
                    cache.update(asset_id=aid,state='queued')
                request['state']='done'
            except Exception:
                cache['state']='failed';request['state']='failed'
            cache['updated_at']=datetime.now(ZoneInfo('UTC')).isoformat()
            self.store.set_cursor(cache_key,cache)
            self.store.set_cursor(key,request)

    def _update_media_cache(self, family, aid, state):
        import json
        with self.store.db() as db:
            rows=db.execute("SELECT key,value FROM cursors WHERE key LIKE 'media-analysis:%'").fetchall()
        for row in rows:
            cache=json.loads(row['value'])
            if cache.get('family_id')==family and cache.get('asset_id')==aid:
                cache.update(state=state,updated_at=datetime.now(ZoneInfo('UTC')).isoformat())
                self.store.set_cursor(row['key'],cache)

    def process_one(self):
        job=self.store.claim(lease=3600,family=self.family)
        if not job:return False
        family=job['family_id'];data=job['payload']
        try:
            if family!=self.family:raise ValueError('任务家庭与worker配置不匹配')
            if job['kind']=='analyze':
                aid=data['asset_id']
                expected_revision=(self.store.analysis(family,aid) or {}).get('revision',0)
                output=self.processor.analyze(family,aid)
                self.store.set_analysis(family,aid,output,expected_revision=expected_revision)
                self._update_media_cache(family,aid,'ready')
            else:
                child,day,course_id=data['child_id'],data['school_date'],data.get('course_id','')
                if child=='__media_analysis__' or not course_id:
                    # Legacy automatic day packs are retired; only uploaded courses compose.
                    self.store.finish_job(job,success=True);return True
                try:course=self.store.course(family,course_id)
                except Missing:
                    self.store.finish_job(job,success=True);return True
                if not self.store.course_sealed(family,course_id):
                    # The last file's arrival/analysis enqueues composition again.
                    self.store.finish_job(job,success=True);return True
                sources=self.store.sources(family,child,day,course_id=course_id)
                if not sources:
                    self.store.finish_job(job,success=True);return True
                analyses=[self.store.analysis(family,s['asset_id']) for s in sources]
                if any(a and a['state']=='failed' for a in analyses):raise ProcessingUnavailable('素材解析失败，需重试后生成')
                if any(not a or a['state']!='ready' for a in analyses):
                    self.store.finish_job(job,success=False,defer=True);return True
                before=digest([(s['id'],a['revision']) for s,a in zip(sources,analyses)])
                payload=self.processor.compose(family,sources,nonce=data.get('nonce',''),course=course)
                current=self.store.sources(family,child,day,course_id=course_id)
                after=digest([(s['id'],(self.store.analysis(family,s['asset_id']) or {}).get('revision')) for s in current])
                if before!=after:
                    self.store.finish_job(job,success=False,defer=True);return True
                self.store.create_pack(family,child,day,payload,[s['id'] for s in sources],course_id=course_id)
            self.store.finish_job(job,success=True)
        except Conflict:
            # A reviewer corrected the evidence during this model call. Keep
            # the newer revision; its own transaction already queues composition.
            self.store.finish_job(job,success=True)
        except Exception as exc:
            # Avoid logging model replies, local media paths or credentials.
            if job['kind']=='analyze':
                try:
                    self.store.set_analysis(family,data['asset_id'],{},state='failed',
                        error='素材完整解析失败，请核对原件后重试。',expected_revision=locals().get('expected_revision',0))
                    self._update_media_cache(family,data['asset_id'],'failed')
                except Conflict:
                    self.store.finish_job(job,success=True);return True
            self.store.finish_job(job,success=False,error='learning_processing_failed')
            log.warning('learning job failed kind=%s attempt=%d error=%s',job['kind'],job['attempts'],
                        type(exc).__name__)
        return True

    def caption_new_timeline_items(self):
        """Keep newly added Bubu photos in family wording; one small batch per 10 minutes."""
        if not self.subject or time.monotonic()-self.captioned_at<600:return
        self.captioned_at=time.monotonic()
        from .timeline_captions import TimelineCaptions
        try:
            report=TimelineCaptions(self.store).run(self.bridge,self.family,self.bridge.subject_snapshot(self.subject)['items'])
            if report['failed'] or report['given_up']:
                log.warning('timeline captions failed=%d given_up=%d changed=%d',report['failed'],report['given_up'],report['changed'])
        except Exception as exc:
            log.warning('timeline caption step failed error=%s',type(exc).__name__)

    def backup(self, root, today):
        """Daily copy of the learning state into root/<day>; unchanged files are hard links to the previous day."""
        from .backup import backup
        root=Path(root);root.mkdir(parents=True,exist_ok=True,mode=0o700)
        days=sorted(d for d in root.iterdir() if d.is_dir() and not d.is_symlink() and re.fullmatch(r'\d{4}-\d{2}-\d{2}',d.name)
                    and (d/'.bubu-learning-backup').is_file())
        target=root/today
        previous=[d for d in days if d.name<today]
        if not target.exists() and previous:
            shutil.copytree(previous[-1],target,copy_function=os.link)
        result=backup(self.store.root,target)
        for old in sorted(set(days+[target]))[:-BACKUP_KEEP]:
            shutil.rmtree(old)
        self.store.set_cursor(BACKUP,{'at':time.time(),'day':today,'assets':result['assets']})
        return result

    def _due(self, name, every, now):
        if now-self.step_at.get(name,-1e18)<every:return False
        self.step_at[name]=now;return True

    def periodic(self, now=None, today=None):
        """Family features: cheap, time-guarded, at most one model call per pass; failures only logged."""
        features=self.features
        now=time.monotonic() if now is None else now
        today=(today or datetime.now(ZoneInfo('Asia/Shanghai')).date()).isoformat()
        cursor='feature-day:'+self.family
        done=self.store.get_cursor(cursor,{})
        if 'firsts' in features and done.get('firsts')!=today and self._due('firsts',3600,now):
            try:
                features['firsts'].compute();done['firsts']=today;self.store.set_cursor(cursor,done)
            except Exception as exc:log.warning('firsts recompute failed error=%s',type(exc).__name__)
        if 'monthly' in features and self._due('monthly',3600,now):
            try:
                if features['monthly'].generate_due(datetime.fromisoformat(today).date()):return
            except Exception as exc:log.warning('monthly report failed error=%s',type(exc).__name__)
        backup_root=os.environ.get('LEARNING_BACKUP_DIR','').strip()
        if backup_root and done.get('backup')!=today and self._due('backup',3600,now):
            try:
                self.backup(backup_root,today);done['backup']=today;self.store.set_cursor(cursor,done)
            except Exception as exc:log.warning('learning backup failed error=%s',type(exc).__name__)
        if 'voices' in features and self._due('voices',VOICE_EVERY,now):
            try:
                if done.get('voices')!=today:
                    features['voices'].sync_candidates();done['voices']=today;self.store.set_cursor(cursor,done)
                # The queue is empty here: work through the backlog, bounded by the clip's own time budget
                # (~150 s) so a new lesson waits at most one batch.
                features['voices'].process(VOICE_BATCH)
            except Exception as exc:log.warning('voice archive step failed error=%s',type(exc).__name__)

    def run(self,once=False):
        with self.lock():
            while True:
                self.heartbeat()
                self.caption_new_timeline_items()
                drained=False
                for _ in range(10):
                    self.process_media_requests()
                    if not self.process_one():
                        drained=True;break
                # Lesson jobs always go first; feature steps only run on an empty queue.
                self.heartbeat()
                if drained:self.periodic();self.heartbeat()
                if once:return
                time.sleep(5)

if __name__=='__main__':
    import argparse
    from .runtime import create_worker
    logging.basicConfig(level=logging.WARNING,format='%(asctime)s %(levelname)s [%(name)s] %(message)s')
    parser=argparse.ArgumentParser();parser.add_argument('--once',action='store_true')
    args=parser.parse_args();create_worker().run(once=args.once)
