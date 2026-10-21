from pathlib import Path
import hashlib
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from learning.store import LearningStore
from learning.worker import LearningWorker

class Bridge:
    def __init__(self,items): self.items=items
    def school_snapshot(self,*args,**kwargs):
        return {'items':self.items,'has_more':False,'next_cursor':None}
class Processor:
    def analyze(self,family,aid):return {'material_kind':'teaching','segments':[]}
    def compose(self,family,sources,nonce=''):
        return {'title':'待核对','activities':[]}

def candidate(tmp_path,instance='a'):
    file=tmp_path/'card.jpg';file.write_bytes(b'original evidence')
    return {'scope':'school_candidate','source_instance_id':'photos:'+instance,'content_hash':hashlib.sha256(file.read_bytes()).hexdigest(),
            'local_path':str(file),'received_at':'2026-10-20T10:00:00+08:00','name':'card.jpg','source_revision':'r1'}

def worker(tmp_path,items):
    store=LearningStore(tmp_path/'state')
    return LearningWorker(store,Bridge(items),Processor(),family='f1',child='c1',since_day='2026-10-01')

def test_icloud_repeat_saves_are_occurrences_but_one_asset(tmp_path):
    first=candidate(tmp_path);second={**first,'source_instance_id':'photos:b','received_at':'2026-10-21T10:00:00+08:00'}
    w=worker(tmp_path,[first,second]);assert w.sync_school()['imported']==2
    assert w.sync_school()['imported']==0
    sources=w.store.sources('f1','c1');assert len(sources)==2
    assert len({s['asset_id'] for s in sources})==1
    assert all(not s['date_confirmed'] for s in sources)

def test_changed_original_is_rejected_before_import(tmp_path):
    item=candidate(tmp_path);Path(item['local_path']).write_bytes(b'changed')
    w=worker(tmp_path,[item]);assert w.sync_school()['failed']==1
    assert w.store.sources('f1','c1')==[]

def test_worker_processes_analysis_then_composition_without_publication(tmp_path):
    w=worker(tmp_path,[candidate(tmp_path)]);w.sync_school()
    assert w.process_one()
    assert w.process_one()
    packs=w.store.packs('f1','c1');assert len(packs)==1 and packs[0]['status']=='no_lesson'
    assert not w.process_one()

def test_removed_source_does_not_reappear_on_next_sync(tmp_path):
    w=worker(tmp_path,[candidate(tmp_path)]);w.sync_school()
    w.store.remove_source('f1',w.store.sources('f1','c1')[0]['id'])
    assert w.sync_school()['imported']==0
    assert w.store.sources('f1','c1')==[]

def test_slow_model_cannot_overwrite_reviewer_correction(tmp_path):
    w=worker(tmp_path,[candidate(tmp_path)]);w.sync_school()
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
    w=worker(tmp_path,[]);pb=PB(b'evidence');key=request_media(w,pb)
    w.processor.verify_file=lambda path,sha:__import__('learning.processing',fromlist=['MediaProcessor']).MediaProcessor.verify_file(path,sha)
    w.process_media_requests();assert pb.downloads==1
    assert w.store.get_cursor(key)['state']=='queued'
    w.process_one();assert w.store.get_cursor(key)['state']=='ready'
    w.process_one();assert w.store.packs('f1','__media_analysis__')==[]
    assert w.store.sources('f1','c1')==[]

def test_media_family_revocation_stops_before_download(tmp_path):
    w=worker(tmp_path,[]);pb=PB(b'evidence');key=request_media(w,pb)
    pb.media['familyId']='other'
    w.process_media_requests()
    assert pb.downloads==0 and w.store.get_cursor(key)['state']=='failed'

def test_media_hash_changed_bytes_do_not_enter_store(tmp_path):
    w=worker(tmp_path,[]);pb=PB(b'evidence');key=request_media(w,pb)
    pb.content=b'different'
    from learning.processing import MediaProcessor
    w.processor.verify_file=MediaProcessor.verify_file
    w.process_media_requests()
    assert w.store.get_cursor(key)['state']=='failed'
    assert w.store.sources('f1','__media_analysis__')==[]

def test_worker_never_claims_or_marks_failed_another_family_job(tmp_path):
    w=worker(tmp_path,[])
    foreign=w.store.add_source('other','other-child','2026-10-20','foreign','x.jpg',b'other','image/jpeg')
    own=w.store.add_source('f1','c1','2026-10-20','own','x.jpg',b'own','image/jpeg')
    assert w.process_one()
    assert w.store.analysis('other',foreign['asset_id']) is None
    assert w.store.analysis('f1',own['asset_id'])['state']=='ready'
    assert w.store.jobs('other')[0]['state']=='queued'


def test_media_request_reuses_ready_hash_without_revoking_school_analysis(tmp_path):
    w=worker(tmp_path,[]);pb=PB(b'evidence')
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
    w=worker(tmp_path,[]);pb=PB(b'evidence')
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
