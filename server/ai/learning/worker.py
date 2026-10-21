"""Bounded second-brain polling and durable course jobs. No automatic publishing."""
from __future__ import annotations
from contextlib import contextmanager
from datetime import datetime
import fcntl
import hashlib
import logging
import mimetypes
from pathlib import Path
import time
from zoneinfo import ZoneInfo

from .brain_bridge import BrainSnapshotChanged
from .processing import MediaProcessor, ProcessingUnavailable
from .store import Conflict, digest, valid_day

log = logging.getLogger('bubu.learning.worker')

class LearningWorker:
    def __init__(self, store, bridge, processor, *, family, child, since_day,
                 inbox: Path | None = None, timeline=None, pocketbase=None):
        if not family or not child: raise ValueError('学习同步须配置家庭和孩子')
        self.store, self.bridge, self.processor = store, bridge, processor
        self.family, self.child, self.since_day = family, child, valid_day(since_day)
        self.inbox = Path(inbox).resolve() if inbox else None
        self.timeline = timeline
        self.pocketbase = pocketbase
        self.cursor_key = 'school-import:' + digest([family, child])
        self.status_key = 'school-status:' + digest([family, child])

    @contextmanager
    def lock(self):
        # One worker owns this store, including long audio jobs. An API process
        # only enqueues work; it never imports or calls Gemini on request threads.
        with (self.store.root/'learning-worker.lock').open('a+') as handle:
            try: fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError as exc: raise Conflict('学习整理任务正在运行') from exc
            try: yield
            finally: fcntl.flock(handle,fcntl.LOCK_UN)

    def _import(self,item,registry):
        instance=item['source_instance_id']
        if instance in registry: return False
        path=Path(item['local_path'])
        # Verify while copying; checking a path and later re-opening it leaves a
        # source mutation race. The private spool is the exact imported bytes.
        import tempfile
        checksum=hashlib.sha256();size=0
        with tempfile.TemporaryDirectory(prefix='bubu-school-import-') as tmp:
            spool=Path(tmp)/'source'
            with path.open('rb') as source,spool.open('wb') as target:
                for chunk in iter(lambda:source.read(1024*1024),b''):
                    size+=len(chunk)
                    if size>256*1024*1024:raise ValueError('素材过大')
                    checksum.update(chunk);target.write(chunk)
            if not size or checksum.hexdigest()!=item['content_hash']:raise ValueError('素材校验失败')
            received=item.get('received_at')
            day=(datetime.fromisoformat(received.replace('Z','+00:00')).astimezone(ZoneInfo('Asia/Shanghai')).date().isoformat()
                 if received else datetime.now(ZoneInfo('Asia/Shanghai')).date().isoformat())
            mime=mimetypes.guess_type(item.get('name') or path.name)[0]
            source=self.store.add_source(self.family,self.child,day,instance,item.get('name') or path.name,spool,mime,
                media_ref={'origin':'icloud_candidate' if instance.startswith('photos:') else 'school_inbox',
                           'source_instance_id':instance,'received_at':received,'date_confirmed':False,
                           'warnings':item.get('warnings',[]),'source_revision':item.get('source_revision','')})
        registry[instance]={'source_id':source['id'],'hash':source['hash']}
        self.store.set_cursor(self.cursor_key,registry)
        return True

    def sync_school(self):
        registry=self.store.get_cursor(self.cursor_key,{})
        report={'imported':0,'failed':0,'pending':0,'last_sync':datetime.now(ZoneInfo('UTC')).isoformat(),'error':''}
        cursor=None;restarts=0
        # Pagination cursors are used only within this pass. Every later poll
        # restarts the snapshot so merged/late iCloud save events aren't missed.
        for _ in range(100):
            try: page=self.bridge.school_snapshot(self.since_day,limit=200,cursor=cursor)
            except BrainSnapshotChanged:
                restarts+=1;cursor=None
                if restarts>2:raise
                continue
            for item in page['items']:
                if item.get('scope')!='school_candidate':continue
                try: report['imported']+=int(self._import(item,registry))
                except (OSError,ValueError,Conflict):report['failed']+=1
            if not page.get('has_more'):break
            cursor=page['next_cursor']
        else: report['error']='教学候选过多，请缩短同步起始日期。'
        if self.inbox and self.inbox.is_dir():
            # Explicit backup inbox only; never recursively crawl the brain.
            for path in sorted(self.inbox.glob('*'))+sorted(self.inbox.glob('*/*')):
                if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(self.inbox):continue
                mime=mimetypes.guess_type(path.name)[0] or ''
                if not mime.startswith(('image/','video/','audio/')):continue
                if not 0<path.stat().st_size<=256*1024*1024:continue
                sha=hashlib.sha256(path.read_bytes()).hexdigest()
                item={'source_instance_id':'inbox:'+digest([str(path.relative_to(self.inbox)),sha]),
                      'content_hash':sha,'local_path':str(path),'name':path.name,
                      'received_at':datetime.fromtimestamp(path.stat().st_mtime,ZoneInfo('Asia/Shanghai')).isoformat(),
                      'warnings':['inbox_time_is_not_lesson_date']}
                try:report['imported']+=int(self._import(item,registry))
                except (OSError,ValueError,Conflict):report['failed']+=1
        report['pending']=sum(j['state'] in {'queued','running'} for j in self.store.jobs(self.family))
        if report['failed']:report['error']='部分素材校验或导入失败，将在下次重试。'
        self.store.set_cursor(self.status_key,report)
        return report

    def enqueue_day(self,child,day,*,force=True):
        self.store.enqueue(self.family,'compose',child+':'+day,{'child_id':child,'school_date':day},force=force)

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
                child,day=data['child_id'],data['school_date']
                if child=='__media_analysis__':
                    self.store.finish_job(job,success=True);return True
                sources=self.store.sources(family,child,day)
                if not sources:
                    self.store.finish_job(job,success=True);return True
                analyses=[self.store.analysis(family,s['asset_id']) for s in sources]
                if any(a and a['state']=='failed' for a in analyses):raise ProcessingUnavailable('素材解析失败，需重试后生成')
                if any(not a or a['state']!='ready' for a in analyses):
                    self.store.finish_job(job,success=False,defer=True);return True
                before=digest([(s['id'],a['revision']) for s,a in zip(sources,analyses)])
                payload=self.processor.compose(family,sources,nonce=data.get('nonce',''))
                current=self.store.sources(family,child,day)
                after=digest([(s['id'],(self.store.analysis(family,s['asset_id']) or {}).get('revision')) for s in current])
                if before!=after:
                    self.store.finish_job(job,success=False,defer=True);return True
                self.store.create_pack(family,child,day,payload,[s['id'] for s in sources])
            self.store.finish_job(job,success=True)
        except Conflict:
            # A reviewer corrected the evidence during this model call. Keep
            # the newer revision; its own transaction already queues composition.
            self.store.finish_job(job,success=True)
        except Exception:
            # Avoid logging model replies, local media paths or credentials.
            if job['kind']=='analyze':
                try:
                    self.store.set_analysis(family,data['asset_id'],{},state='failed',
                        error='素材完整解析失败，请核对原件后重试。',expected_revision=locals().get('expected_revision',0))
                    self._update_media_cache(family,data['asset_id'],'failed')
                except Conflict:
                    self.store.finish_job(job,success=True);return True
            self.store.finish_job(job,success=False,error='learning_processing_failed')
            log.warning('learning job failed kind=%s attempt=%d',job['kind'],job['attempts'])
        return True

    def run(self,once=False):
        with self.lock():
            while True:
                try:
                    self.sync_school()
                    if self.timeline:self.timeline.run_once(limit=25)
                except Exception:
                    self.store.set_cursor(self.status_key,{'last_sync':datetime.now(ZoneInfo('UTC')).isoformat(),
                        'error':'第二大脑暂时不可用；已有课程仍保留。','imported':0,'pending':0})
                    log.warning('second brain sync unavailable')
                for _ in range(10):
                    self.process_media_requests()
                    if not self.process_one():break
                if once:return
                time.sleep(30)

if __name__=='__main__':
    import argparse
    from .runtime import create_worker
    parser=argparse.ArgumentParser();parser.add_argument('--once',action='store_true')
    args=parser.parse_args();create_worker().run(once=args.once)
