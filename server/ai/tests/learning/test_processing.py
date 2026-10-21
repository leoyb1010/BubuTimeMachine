from pathlib import Path
import hashlib
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from learning.processing import MediaProcessor, ProcessingUnavailable, clip_parameters


def test_question_clip_is_exact_source_segment_not_introduction():
    source={'hash':'a'*64,'analysis':{'duration':73,'segments':[
        {'id':'intro','start':0,'end':4,'text':'Hello everyone'},
        {'id':'question','start':19.5,'end':21.36,'text':'What is it?'}]}}
    params=clip_parameters(source,'question')
    assert params=={'start':19.5,'end':21.36,'text':'What is it?'}
    with pytest.raises(ValueError):clip_parameters(source,'missing')


def test_source_must_still_match_its_hash_before_processing(tmp_path):
    path=tmp_path/'source.mp4';path.write_bytes(b'changed')
    with pytest.raises(ProcessingUnavailable):MediaProcessor.verify_file(path,'a'*64)


def test_segments_over_source_duration_cannot_be_cut():
    src={'analysis':{'duration':3,'segments':[{'id':'q','start':2,'end':8,'text':'what'}]}}
    with pytest.raises(ValueError):clip_parameters(src,'q')

def processor(tmp_path):
    from types import SimpleNamespace
    return MediaProcessor(SimpleNamespace(root=tmp_path),SimpleNamespace(root=tmp_path))


def test_partial_derived_file_from_crash_is_repaired_atomically(tmp_path):
    p=processor(tmp_path)
    original=tmp_path/'valid.jpg';original.write_bytes(b'complete resource')
    sha=hashlib.sha256(original.read_bytes()).hexdigest()
    family_dir=tmp_path/'derived'/hashlib.sha256(b'f').hexdigest()[:24]
    family_dir.mkdir(parents=True);(family_dir/(sha+'.jpg')).write_bytes(b'partial')
    name,_=p._save('f',original,'.jpg')
    assert p.resource_path('f',name).read_bytes()==b'complete resource'


def test_probe_rejects_nonfinite_duration(tmp_path,monkeypatch):
    p=processor(tmp_path)
    monkeypatch.setattr(p,'_run',lambda *args,**kwargs:'{"format":{"duration":"NaN"},"streams":[]}')
    with pytest.raises(ProcessingUnavailable):p.probe(tmp_path/'video.mp4')


def test_transcript_rejects_nonfinite_coverage(tmp_path,monkeypatch):
    import json
    p=processor(tmp_path);p.transcriber=tmp_path/'transcribe';p.transcriber.touch()
    def run(args,*rest):Path(args[2]).write_text(json.dumps({'duration':float('inf'),'segments':[]}));return ''
    monkeypatch.setattr(p,'_run',run)
    with pytest.raises(ProcessingUnavailable):p.transcribe(tmp_path/'video.mp4','en-US')


def test_oversized_image_does_not_bypass_pixel_limit_through_ffmpeg(tmp_path,monkeypatch):
    from types import SimpleNamespace
    from PIL import Image
    p=processor(tmp_path);p.store.asset_path=lambda *args:tmp_path/'image.jpg'
    class HugeImage:
        width=100_000_001;height=1
        def __enter__(self):return self
        def __exit__(self,*args):return False
    monkeypatch.setattr(Image,'open',lambda *args:HugeImage())
    calls=[];monkeypatch.setattr(p,'_run',lambda *args,**kwargs:calls.append(args))
    with pytest.raises(ProcessingUnavailable):p.frame('f',{'id':'a','mime':'image/jpeg'})
    assert calls==[]

def test_oversized_derived_output_is_never_published(tmp_path,monkeypatch):
    import learning.processing as module
    p=processor(tmp_path);original=tmp_path/'large.m4a';original.write_bytes(b'too much output')
    monkeypatch.setattr(module,'MAX_DERIVED_BYTES',5)
    with pytest.raises(ProcessingUnavailable):p._save('f',original,'.m4a')
    directory=tmp_path/'derived'/hashlib.sha256(b'f').hexdigest()[:24]
    assert list(directory.iterdir())==[]

def test_probe_keeps_video_duration_separate_from_full_audio_duration(tmp_path,monkeypatch):
    import json
    p=processor(tmp_path)
    metadata={'format':{'duration':'176.234694'},'streams':[{'codec_type':'video','duration':'176.125','width':640,'height':360},{'codec_type':'audio','duration':'176.234694'}]}
    monkeypatch.setattr(p,'_run',lambda *args,**kwargs:json.dumps(metadata))
    info=p.probe(tmp_path/'song.mp4')
    assert info['duration']==176.234694
    assert info['video_duration']==176.125


def test_visual_samples_do_not_seek_into_audio_only_tail(tmp_path,monkeypatch):
    p=processor(tmp_path);original=tmp_path/'source.mp4';original.write_bytes(b'evidence')
    p.store.asset=lambda *args:{'id':'a','mime':'video/mp4','hash':hashlib.sha256(b'evidence').hexdigest()}
    p.store.asset_path=lambda *args:original
    p.store.asset_sources=lambda *args:[{'language':'en-US'}]
    p.bridge.lookup_hash=lambda *args:None
    p.bridge.complete_json=lambda *args:{'material_kind':'song'}
    monkeypatch.setattr(p,'probe',lambda *args:{'duration':176.234694,'video_duration':176.125,'has_audio':True,'has_video':True})
    monkeypatch.setattr(p,'transcribe',lambda *args:{'segments':[],'processed_duration':176.14512471655328})
    sampled=[]
    def frame(family,asset,at):
        if at>175.7:raise ProcessingUnavailable('seek beyond final decodable frame')
        sampled.append(at);return 'frame.jpg'
    monkeypatch.setattr(p,'frame',frame)
    monkeypatch.setattr(p,'resource_path',lambda *args:original)
    result=p.analyze('f','a')
    assert len(sampled)==8 and min(sampled)>=0 and max(sampled)<=175.7
    assert result['coverage']['audio_total_seconds']==176.234694
    assert result['coverage']['audio_processed_seconds']==176.14512471655328
