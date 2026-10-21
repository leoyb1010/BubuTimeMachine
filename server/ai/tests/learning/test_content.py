from pathlib import Path
import sys
import pytest
from pydantic import ValidationError
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from learning.models import Draft, ground_draft

def clip(segment,role='cue'):
    return {'source_id':'s1','segment_id':segment,'role':role}

def draft():
    return {'title':'今天的课','material_kind':'teaching','activities':[{
        'id':'a1','kind':'listen_choice','title':'找玉米','concept':'en:corn','instruction':'听老师原声',
        'prompt':clip('corn'), 'answer':clip('corn','answer'),
        'choices':[{'id':'corn','label':'corn','evidence':clip('corn')},
                   {'id':'pumpkin','label':'pumpkin','evidence':clip('pumpkin')}], 'correct_choice':'corn'}]}

SOURCES={'s1':{'hash':'a'*64,'analysis':{'duration':73,'segments':[
    {'id':'intro','start':.7,'end':3.6,'text':'Hello everyone, it is teacher Abby.'},
    {'id':'corn','start':13.3,'end':14.1,'text':'Corn.'},
    {'id':'pumpkin','start':44,'end':44.9,'text':'Pumpkin.'}]}}}

def test_grounded_prompt_uses_teacher_segment_not_intro():
    p=ground_draft(Draft.model_validate(draft()),SOURCES)
    assert p['activities'][0]['prompt']['start']==13.3
    assert p['activities'][0]['prompt']['text']=='Corn.'

def test_instruction_cannot_be_a_prompt_role():
    d=draft();d['activities'][0]['prompt']['role']='instruction'
    with pytest.raises(ValidationError):Draft.model_validate(d)

def test_unknown_segment_and_fabricated_choice_fail():
    d=draft();d['activities'][0]['prompt']['segment_id']='invented'
    with pytest.raises(ValueError):ground_draft(Draft.model_validate(d),SOURCES)
    d=draft();d['activities'][0]['choices'][0]['label']='carrot'
    with pytest.raises(ValueError):ground_draft(Draft.model_validate(d),SOURCES)

def test_care_images_are_not_quizzes():
    d=draft();d['material_kind']='care'
    with pytest.raises(ValidationError):Draft.model_validate(d)

def test_role_change_or_extra_script_cannot_escape_schema():
    d=draft();d['activities'][0]['script']='fetch(secret)'
    with pytest.raises(ValidationError):Draft.model_validate(d)

def test_color_answer_preserves_the_complete_teacher_answer():
    import copy
    sources=copy.deepcopy(SOURCES)
    sources['s1']['analysis']['segments'] += [
        {'id':'qcolor','start':29.5,'end':32.2,'text':'What color is the corn?'},
        {'id':'colors','start':34.4,'end':36.6,'text':'Yellow and green.'},
        {'id':'other','start':66.1,'end':68.5,'text':'Orange and green.'}]
    d=draft();a=d['activities'][0]
    a.update(kind='color_choice',prompt=clip('qcolor','question'),answer=clip('colors','answer'),correct_choice='yes',choices=[
        {'id':'yes','label':'yellow','evidence':clip('colors'),'color':'#ffff00'},
        {'id':'no','label':'orange and green','evidence':clip('other'),'color':'#ffaa00'}])
    with pytest.raises(ValueError):ground_draft(Draft.model_validate(d),sources)
