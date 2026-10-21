from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from learning.store import LearningStore,Conflict,Missing,digest

@pytest.fixture
def setup(tmp_path):
    s=LearningStore(tmp_path)
    src=s.add_source('f','c','2026-10-20','message','lesson.mp4',b'original','video/mp4')
    s.set_analysis('f',src['asset_id'],{'segments':[]})
    a={'id':'a1','kind':'listen_choice','concept':'en:corn','prompt':{'source_id':src['id'],'source_hash':src['hash'],'audio_hash':'p'*64},
       'answer':{'audio_hash':'a'*64},'choices':[{'id':'corn'},{'id':'pumpkin'}],'correct_choice':'corn'}
    payload={'title':'课程','activities':[a],'source_fingerprint':digest([(src['id'],src['hash'],1)])}
    pack=s.create_pack('f','c','2026-10-20',payload,[src['id']])
    return s,src,pack

def receipt(pack):
    return [{'activity_id':a['id'],'digest':digest(a),'verified':True} for a in pack['payload']['activities']]

def test_nothing_is_published_until_all_content_confirmed(setup):
    s,_,p=setup
    assert s.packs('f','c',published_only=True)==[]
    with pytest.raises(Conflict):s.publish('f',p['id'],p['revision'],'reviewer',[])
    s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)
    assert s.packs('f','c',published_only=True)[0]['status']=='published'

def test_old_confirmation_does_not_publish_revised_audio(setup):
    s,src,p=setup
    changed={**p['payload'],'title':'改过的课'}
    changed['activities']=[{**p['payload']['activities'][0],'prompt':{'audio_hash':'new'}}]
    newer=s.create_pack('f','c','2026-10-20',changed,[src['id']])
    with pytest.raises(Conflict):s.publish('f',newer['id'],newer['revision'],'reviewer',receipt(p),date_confirmed=True)
    with pytest.raises(Conflict):s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)

def test_source_retraction_blocks_playback_but_preserves_history(setup):
    s,src,p=setup;s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)
    s.save_attempt('f','c',p['id'],'attempt1',{'activity_id':'a1','choice':'corn','kind':'choice'})
    s.remove_source('f',src['id'])
    with pytest.raises(Conflict):s.pack('f',p['id'],require_published=True)
    assert len(s.attempts('f','c'))==1

def test_attempt_is_idempotent_and_outcome_is_server_derived(setup):
    s,_,p=setup;s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)
    body={'activity_id':'a1','choice':'pumpkin','kind':'choice'}
    one=s.save_attempt('f','c',p['id'],'attempt1',body)
    assert one['correct'] is False
    assert s.save_attempt('f','c',p['id'],'attempt1',body)==one
    with pytest.raises(Conflict):s.save_attempt('f','c',p['id'],'attempt1',{**body,'choice':'corn'})
    with pytest.raises(Missing):s.pack('other-family',p['id'])

def test_new_attempt_keeps_earlier_ones(setup):
    s,_,p=setup;s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)
    for i in range(2):s.save_attempt('f','c',p['id'],'attempt'+str(i),{'activity_id':'a1','choice':'corn','kind':'choice'})
    assert len(s.attempts('f','c'))==2
    assert s.attempts('f','another-child')==[]

def test_date_requires_explicit_confirmation(setup):
    s,src,p=setup
    assert not s.source('f',src['id'])['date_confirmed']
    with pytest.raises(Conflict):s.publish('f',p['id'],p['revision'],'reviewer',receipt(p))
    s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)
    assert s.source('f',src['id'])['date_confirmed']


def test_analysis_revision_revokes_old_confirmation_and_preserves_pack(setup):
    s,src,p=setup
    s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)
    s.set_analysis('f',src['asset_id'],{'segments':[]})
    assert s.pack('f',p['id'])['status']=='revoked'
    with pytest.raises(Conflict):s.pack('f',p['id'],require_published=True)
    with pytest.raises(Conflict):s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)


def test_regeneration_after_revision_change_creates_new_pack_even_same_content(setup):
    s,src,p=setup
    s.set_analysis('f',src['asset_id'],{'segments':[]})
    payload={k:v for k,v in p['payload'].items() if k!='source_fingerprint'}
    new=s.create_pack('f','c','2026-10-20',payload,[src['id']])
    assert new['id']!=p['id'] and new['status']=='draft'
    assert new['analysis_revisions'][src['asset_id']]==2

def test_generation_snapshot_cannot_attach_old_output_to_new_analysis(setup):
    s,src,p=setup
    s.set_analysis('f',src['asset_id'],{'segments':[{'id':'new','start':1,'end':2,'text':'new content'}]})
    with pytest.raises(Conflict):s.create_pack('f','c','2026-10-20',p['payload'],[src['id']])
    assert s.packs('f','c',published_only=True)==[]


def test_analysis_change_revokes_every_day_using_the_same_file(setup):
    s,src,p=setup
    tomorrow=s.add_source('f','c','2026-10-21','message','lesson.mp4',b'original','video/mp4')
    payload={k:v for k,v in p['payload'].items() if k!='source_fingerprint'}
    other=s.create_pack('f','c','2026-10-21',payload,[tomorrow['id']])
    s.publish('f',p['id'],p['revision'],'reviewer',receipt(p),date_confirmed=True)
    s.publish('f',other['id'],other['revision'],'reviewer',receipt(other),date_confirmed=True)
    s.set_analysis('f',src['asset_id'],{'segments':[]})
    assert all(s.pack('f',item['id'])['status']=='revoked' for item in (p,other))
    with s.db() as db:
        keys={r[0] for r in db.execute("SELECT job_key FROM jobs WHERE kind='compose' AND state='queued'")}
    assert {'c:2026-10-20','c:2026-10-21'}<=keys
