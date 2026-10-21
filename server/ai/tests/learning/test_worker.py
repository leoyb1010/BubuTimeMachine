from pathlib import Path
import hashlib
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from learning.store import LearningStore
from learning.worker import LearningWorker

class Bridge:
    pass
class Processor:
    def __init__(self):self.compose_calls=[]
    def analyze(self,family,aid):return {'material_kind':'daily','segments':[]}
    def compose(self,family,sources,nonce='',course=None):
        self.compose_calls.append((tuple(s['id'] for s in sources),course and course['id']))
        return {'title':course['title'] if course else '待核对','activities':[],'generation_nonce':nonce}

def worker(tmp_path,items=None):
    store=LearningStore(tmp_path/'state')
    return LearningWorker(store,Bridge(),Processor(),family='f1',child='c1')

def upload(w,title='Fruit words',day='2026-10-21',files=(b'teacher video',)):
    course=w.store.create_course('f1','c1',day,title,'teaching')
    for index,content in enumerate(files):
        w.store.add_source('f1','c1',day,'course:%s:%d'%(course['id'],index),'lesson.mp4',content,'video/mp4',
                           kind='teaching',course_id=course['id'])
    return course

def drain(w):
    while w.process_one():pass

def test_each_upload_is_its_own_lesson_even_on_the_same_day(tmp_path):
    w=worker(tmp_path)
    first=upload(w,'Fruit words',files=(b'fruit video',b'fruit song'))
    second=upload(w,'Colors',files=(b'color video',))
    drain(w)
    calls={course:len(ids) for ids,course in w.processor.compose_calls}
    assert calls=={first['id']:2,second['id']:1}
    assert {p['course_id'] for p in w.store.packs('f1','c1',courses_only=True)}=={first['id'],second['id']}
    assert all(p['status']=='no_lesson' for p in w.store.packs('f1','c1'))

def test_legacy_day_jobs_and_unassigned_sources_never_become_lessons(tmp_path):
    w=worker(tmp_path)
    w.store.add_source('f1','c1','2026-10-20','photos:legacy','card.jpg',b'icloud photo','image/jpeg')
    w.store.enqueue_compose('f1','c1','2026-10-20')
    drain(w)
    assert w.processor.compose_calls==[]
    assert w.store.packs('f1','c1')==[]

def test_removed_course_stops_composition(tmp_path):
    w=worker(tmp_path);course=upload(w)
    w.store.remove_course('f1',course['id'])
    drain(w)
    assert w.processor.compose_calls==[]
    assert w.store.sources('f1','c1')==[]

def test_regenerated_course_supersedes_only_its_own_pack(tmp_path):
    w=worker(tmp_path);first=upload(w,'A',files=(b'a',));second=upload(w,'B',files=(b'b',))
    drain(w)
    w.store.enqueue_compose('f1','c1','2026-10-21',first['id'],'retry');drain(w)
    current={p['course_id']:p['status'] for p in w.store.packs('f1','c1') if p['status']!='superseded'}
    assert current=={first['id']:'no_lesson',second['id']:'no_lesson'}
    assert len(w.store.packs('f1','c1',course_id=first['id']))==2

def test_slow_model_cannot_overwrite_reviewer_correction(tmp_path):
    w=worker(tmp_path);upload(w)
    def analyze(family,aid):
        w.store.set_analysis(family,aid,{'description':'家人核对过的内容','segments':[]})
        return {'description':'迟到的机器结果','segments':[]}
    w.processor.analyze=analyze
    assert w.process_one()
    source=w.store.sources('f1','c1')[0]
    assert w.store.analysis('f1',source['asset_id'])['payload']['description']=='家人核对过的内容'

class PB:
    def __init__(self,content):
        self.content=content;self.media={'id':'m1','familyId':'f1','entryLocalId':'e1','file':'photo.jpg','contentHash':hashlib.sha256(content).hexdigest()}
        self.entry={'familyId':'f1'};self.downloads=0
    def get_record(self,collection,mid):return dict(self.media)
    def first_record(self,collection,*,filter_value,sort):return dict(self.entry)
    def download_record_file(self,collection,mid,name,destination,**kwargs):
        self.downloads+=1;Path(destination).write_bytes(self.content)

def request_media(w,pb):
    from learning.store import digest
    w.pocketbase=pb
    key='media-analysis-request:'+digest(['f1','m1',pb.media['contentHash']])
    w.store.set_cursor(key,{'family_id':'f1','media_id':'m1','content_hash':pb.media['contentHash'],'state':'queued'})
    return 'media-analysis:'+digest(['f1','m1'])

def test_media_parse_uses_current_family_facts_and_does_not_make_school_pack(tmp_path):
    w=worker(tmp_path);pb=PB(b'evidence');key=request_media(w,pb)
    w.processor.verify_file=lambda path,sha:__import__('learning.processing',fromlist=['MediaProcessor']).MediaProcessor.verify_file(path,sha)
    w.process_media_requests();assert pb.downloads==1
    assert w.store.get_cursor(key)['state']=='queued'
    w.process_one();assert w.store.get_cursor(key)['state']=='ready'
    w.process_one();assert w.store.packs('f1','__media_analysis__')==[]
    assert w.store.sources('f1','c1')==[]

def test_media_family_revocation_stops_before_download(tmp_path):
    w=worker(tmp_path);pb=PB(b'evidence');key=request_media(w,pb)
    pb.media['familyId']='other'
    w.process_media_requests()
    assert pb.downloads==0 and w.store.get_cursor(key)['state']=='failed'

def test_media_hash_changed_bytes_do_not_enter_store(tmp_path):
    w=worker(tmp_path);pb=PB(b'evidence');key=request_media(w,pb)
    pb.content=b'different'
    from learning.processing import MediaProcessor
    w.processor.verify_file=MediaProcessor.verify_file
    w.process_media_requests()
    assert w.store.get_cursor(key)['state']=='failed'
    assert w.store.sources('f1','__media_analysis__')==[]

def test_worker_never_claims_or_marks_failed_another_family_job(tmp_path):
    w=worker(tmp_path)
    foreign=w.store.add_source('other','other-child','2026-10-20','foreign','x.jpg',b'other','image/jpeg')
    own=w.store.add_source('f1','c1','2026-10-20','own','x.jpg',b'own','image/jpeg')
    assert w.process_one()
    assert w.store.analysis('other',foreign['asset_id']) is None
    assert w.store.analysis('f1',own['asset_id'])['state']=='ready'
    assert w.store.jobs('other')[0]['state']=='queued'


def test_media_request_reuses_ready_hash_without_revoking_school_analysis(tmp_path):
    w=worker(tmp_path);pb=PB(b'evidence')
    source=w.store.add_source('f1','c1','2026-10-20','school','x.jpg',pb.content,'image/jpeg')
    w.store.set_analysis('f1',source['asset_id'],{'description':'already verified source'})
    with w.store.db() as db:db.execute("UPDATE jobs SET state='done' WHERE kind='analyze'")
    key=request_media(w,pb)
    from learning.processing import MediaProcessor
    w.processor.verify_file=MediaProcessor.verify_file
    w.process_media_requests()
    assert w.store.get_cursor(key)['state']=='ready'
    assert all(j['state']=='done' for j in w.store.jobs('f1') if j['kind']=='analyze')

def test_explicit_retry_can_refresh_an_already_ready_hash(tmp_path):
    from learning.store import digest
    from learning.processing import MediaProcessor
    w=worker(tmp_path);pb=PB(b'evidence')
    source=w.store.add_source('f1','c1','2026-10-20','school','x.jpg',pb.content,'image/jpeg')
    w.store.set_analysis('f1',source['asset_id'],{'description':'old result'})
    with w.store.db() as db:db.execute("UPDATE jobs SET state='done' WHERE kind='analyze'")
    cache_key=request_media(w,pb)
    request_key='media-analysis-request:'+digest(['f1','m1',pb.media['contentHash']])
    request=w.store.get_cursor(request_key);request['force']=True;w.store.set_cursor(request_key,request)
    w.processor.verify_file=MediaProcessor.verify_file
    w.process_media_requests()
    assert w.store.get_cursor(cache_key)['state']=='queued'
    assert any(j['state']=='queued' for j in w.store.jobs('f1') if j['kind']=='analyze')


def test_course_waits_for_every_announced_file_before_composing(tmp_path):
    w=worker(tmp_path)
    course=w.store.create_course('f1','c1','2026-10-21','Big lesson','teaching',expected_files=2)
    w.store.add_source('f1','c1','2026-10-21','course:%s:0'%course['id'],'a.mp4',b'part one','video/mp4',kind='teaching',course_id=course['id'])
    drain(w)
    assert w.processor.compose_calls==[]
    w.store.add_source('f1','c1','2026-10-21','course:%s:1'%course['id'],'b.mp4',b'part two','video/mp4',kind='teaching',course_id=course['id'])
    drain(w)
    assert [len(ids) for ids,_ in w.processor.compose_calls]==[2]
