from datetime import date
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from learning.store import LearningStore, Conflict, Missing

@pytest.fixture
def store(tmp_path):
    return LearningStore(tmp_path)

def put(store, day='2026-10-20', family='family-a', origin='message-a'):
    return store.add_source(family, 'child-a', day, origin, 'lesson.mp4', b'video bytes', 'video/mp4')

def test_same_blob_on_two_days_keeps_two_occurrences(store):
    first = put(store)
    assert put(store)['id'] == first['id']
    second = put(store, day='2026-10-21')
    assert second['id'] != first['id']
    assert second['asset_id'] == first['asset_id']
    assert len(store.sources('family-a', 'child-a', '2026-10-20')) == 1
    assert len(store.sources('family-a', 'child-a', '2026-10-21')) == 1

def test_family_cannot_read_or_reuse_other_family_source(store):
    first = put(store)
    with pytest.raises(Missing):
        store.source('family-b', first['id'])
    second = put(store, family='family-b')
    assert first['asset_id'] != second['asset_id']

def test_same_upload_key_cannot_silently_change_contents(store):
    put(store)
    with pytest.raises(Conflict):
        store.add_source('family-a','child-a','2026-10-20','message-a','lesson.mp4',b'changed','video/mp4')

def test_invalid_day_and_path_dont_escape_storage(store):
    with pytest.raises(ValueError):
        put(store, day='2026-02-31')
    src = store.add_source('family-a','child-a','2026-10-20','x','../../secret.mp4',b'v','video/mp4')
    assert store.asset_path('family-a',src['asset_id']).is_relative_to(store.root)
    assert src['name'] == 'secret.mp4'

def test_durable_queue_deduplicates_and_recovers_lease(store):
    job = store.enqueue('family-a','analyze','asset-a',{'asset_id':'asset-a'})
    assert store.enqueue('family-a','analyze','asset-a',{}) == job
    claimed = store.claim(now=100, lease=30)
    # available_at follows real clock; deterministic caller can explicitly schedule.
    if claimed is None:
        claimed = store.claim(now=10**12, lease=30)
        now = 10**12
    else: now = 100
    assert claimed['id'] == job
    assert store.claim(now=now+1) is None
    reopened = LearningStore(store.root)
    assert reopened.claim(now=now+31)['id'] == job

def test_completion_requires_current_lease_owner(store):
    store.enqueue('family-a','analyze','x',{})
    old = store.claim(now=10**12,lease=1)
    fresh = store.claim(now=10**12+2,lease=30)
    with pytest.raises(Conflict):store.finish_job(old,success=True)
    store.finish_job(fresh,success=True)

def test_source_deletion_invalidates_published_material(store):
    src=put(store)
    store.remove_source('family-a',src['id'])
    with pytest.raises(Missing):store.source('family-a',src['id'])
    assert store.sources('family-a','child-a','2026-10-20') == []

def test_same_hash_new_day_reuses_analysis_but_enqueues_new_compose(store):
    first=put(store)
    store.set_analysis('family-a',first['asset_id'],{'segments':[]})
    second=put(store,day='2026-10-21')
    with store.db() as db:
        job=db.execute("SELECT payload FROM jobs WHERE kind='compose' AND job_key='child-a:2026-10-21'").fetchone()
    assert job is not None
    assert second['date_confirmed']==0


def test_analysis_history_cas_and_date_move_are_one_transaction(store):
    src=put(store)
    store.set_analysis('family-a',src['asset_id'],{'segments':[{'id':'s1','start':1,'end':2,'text':'old'}]})
    updated=store.update_source_analysis('family-a',src['id'],1,{'segments':[{'id':'s1','start':1,'end':2,'text':'new'}]},'2026-10-21',True)
    assert updated['id']!=src['id'] and updated['date_confirmed']==1
    with pytest.raises(Missing):store.source('family-a',src['id'])
    with store.db() as db:
        original=dict(db.execute('SELECT * FROM sources WHERE id=?',(src['id'],)).fetchone())
    assert original['school_date']=='2026-10-20' and original['deleted']==1
    history=store.analysis_history('family-a',src['asset_id'])
    assert [x['revision'] for x in history]==[1,2]
    assert history[0]['payload']['segments'][0]['text']=='old'
    with pytest.raises(Conflict):store.update_source_analysis('family-a',updated['id'],1,{},'2026-10-21',True)
    assert store.analysis('family-a',src['asset_id'])['revision']==2


def test_moving_date_conflict_rolls_back_analysis_and_preserves_sources(store):
    src=put(store)
    other=store.add_source('family-a','child-a','2026-10-21','message-a','different.mp4',b'different','video/mp4')
    store.set_analysis('family-a',src['asset_id'],{'segments':[]})
    with pytest.raises(Conflict):
        store.update_source_analysis('family-a',src['id'],1,{'changed':True},'2026-10-21',True)
    assert store.analysis('family-a',src['asset_id'])['revision']==1
    assert store.source('family-a',src['id'])['school_date']=='2026-10-20'
    assert store.source('family-a',other['id'])['deleted']==0


def test_moving_to_identical_existing_occurrence_reuses_it(store):
    first=put(store);second=put(store,day='2026-10-21')
    store.set_analysis('family-a',first['asset_id'],{'segments':[]})
    updated=store.update_source_analysis('family-a',first['id'],1,{'segments':[]},'2026-10-21',True)
    assert updated['id']==second['id']
    assert len(store.sources('family-a','child-a','2026-10-21'))==1

def test_stale_revision_rolls_back_an_entire_date_move(store):
    src=put(store)
    store.set_analysis('family-a',src['asset_id'],{'segments':[]})
    store.set_analysis('family-a',src['asset_id'],{'segments':[]})
    with pytest.raises(Conflict):
        store.update_source_analysis('family-a',src['id'],1,{'changed':True},'2026-10-22',True)
    assert store.source('family-a',src['id'])['school_date']=='2026-10-20'
    assert store.sources('family-a','child-a','2026-10-22')==[]
    assert len(store.analysis_history('family-a',src['asset_id']))==2


def test_additive_migration_preserves_originals_and_analysis_history(tmp_path):
    s=LearningStore(tmp_path)
    src=put(s)
    s.set_analysis('family-a',src['asset_id'],{'description':'keep original explanation','segments':[]})
    with s.db() as db:
        db.execute('ALTER TABLE sources DROP COLUMN date_confirmed')
        db.execute('ALTER TABLE packs DROP COLUMN analysis_revisions')
        db.execute('DROP TABLE analysis_history')
    reopened=LearningStore(tmp_path)
    assert reopened.source('family-a',src['id'])['date_confirmed']==0
    assert reopened.asset_path('family-a',src['asset_id']).read_bytes()==b'video bytes'
    assert reopened.analysis_history('family-a',src['asset_id'])[0]['payload']['description']=='keep original explanation'
    with pytest.raises(Missing):reopened.analysis_history('other-family',src['asset_id'])


def test_correcting_a_date_back_appends_occurrence_without_reviving_history(store):
    src=put(store)
    store.set_analysis('family-a',src['asset_id'],{'segments':[]})
    moved=store.update_source_analysis('family-a',src['id'],1,{'segments':[]},'2026-10-21',True)
    corrected=store.update_source_analysis('family-a',moved['id'],2,{'segments':[]},'2026-10-20',True)
    assert corrected['id'] not in {src['id'],moved['id']}
    assert len(store.sources('family-a','child-a','2026-10-20'))==1
    with pytest.raises(Missing):store.source('family-a',src['id'])
    with pytest.raises(Missing):store.source('family-a',moved['id'])
    assert len(store.analysis_history('family-a',src['asset_id']))==3


def test_forced_running_job_keeps_new_payload_for_its_rerun(store):
    store.enqueue('family-a','compose','child:2026-10-20',{'nonce':'old'})
    running=store.claim(now=10**12,lease=30,family='family-a')
    store.enqueue('family-a','compose','child:2026-10-20',{'nonce':'new'},force=True)
    assert running['payload']=={'nonce':'old'}
    store.finish_job(running,success=True)
    rerun=store.claim(now=10**12,lease=30,family='family-a')
    assert rerun['payload']=={'nonce':'new'}
