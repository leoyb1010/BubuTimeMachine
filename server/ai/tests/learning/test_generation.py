from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from learning.store import LearningStore
from learning.processing import MediaProcessor

class Bridge:
    root=Path('/unused')
    def __init__(self,good):self.good=good;self.calls=[]
    def complete_json(self,system,content,schema):
        self.calls.append(list(content))
        return self.good if len(self.calls)==2 else {'title':'invalid','material_kind':'teaching','activities':[{}]}

class Processor(MediaProcessor):
    def audio(self,family,source,segment):return {'audio_resource':'a'*64+'.m4a','audio_hash':'a'*64}
    def frame(self,family,asset,at=0):return 'b'*64+'.jpg'

def setup(tmp_path):
    store=LearningStore(tmp_path/'state')
    source=store.add_source('f','c','2026-10-20','video','lesson.mp4',b'evidence','video/mp4')
    store.set_analysis('f',source['asset_id'],{'material_kind':'teaching','duration':10,'segments':[
        {'id':'corn','start':1,'end':2,'text':'Corn.'},{'id':'pumpkin','start':5,'end':6,'text':'Pumpkin.'}]})
    def clip(segment,role):return {'source_id':source['id'],'segment_id':segment,'role':role}
    valid={'title':'听老师说','material_kind':'teaching','activities':[{'id':'a','kind':'listen_choice','title':'找玉米','concept':'corn',
        'instruction':'听一听','prompt':clip('corn','cue'),'answer':clip('corn','answer'),
        'choices':[{'id':'c','label':'Corn','evidence':clip('corn','cue')},{'id':'p','label':'Pumpkin','evidence':clip('pumpkin','cue')}],
        'correct_choice':'c'}]}
    return store,source,valid

def test_invalid_model_reply_is_repaired_once_from_validation_evidence(tmp_path):
    store,source,valid=setup(tmp_path);bridge=Bridge(valid)
    result=Processor(store,bridge).compose('f',[source])
    assert len(bridge.calls)==2
    assert 'validation_errors' in bridge.calls[1][-1]['text']
    assert result['activities'][0]['prompt']['text']=='Corn.'
    assert store.packs('f','c')==[] # Compose itself never publishes or persists invalid content.

def test_repeated_invalid_reply_stops_after_two_calls(tmp_path):
    store,source,valid=setup(tmp_path);bridge=Bridge({'invalid':'reply'})
    with pytest.raises(ValueError):Processor(store,bridge).compose('f',[source])
    assert len(bridge.calls)==2 and store.packs('f','c')==[]
