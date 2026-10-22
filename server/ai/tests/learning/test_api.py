"""Offline HTTP/auth contract tests. All PB requests use MockTransport."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from learning.api import install_learning
from learning.auth import PocketBaseAuthenticator, SESSION_COOKIE
from learning.store import Missing, Conflict

class FakeService:
    def __init__(self, tmp): self.tmp=tmp; self.calls=[]
    def context(self,s): return {'user':{'id':s.user_id,'can_review':s.can_review},'children':s.children,'default_child':s.require_child(None)}
    def days(self,s,child,start,end): self.calls.append(('days',s.family_id,child));return {'days':[]}
    def packs(self,s,child,day): return {'items':[]}
    def pack(self,s,pid):
        if pid=='missing': raise Missing('private internal path /secrets')
        if pid=='conflict': raise Conflict('secret version token')
        if pid=='invalid': raise ValueError('password=do-not-echo')
        return {'id':pid}
    def publish(self,s,*args): self.calls.append(('publish',args));return {'status':'published'}
    def save_attempt(self,s,body): self.calls.append(('attempt',body));return body
    def source_file(self,s,sid): return self.tmp/'media.wav','audio/wav'
    def resource(self,s,pid,name): return self.tmp/'media.wav','audio/wav'
    def __getattr__(self,name):
        if name not in {'sources','exclude','regenerate','update_segments','reviews','attempts','media_analysis','timeline_search','courses','course','delete_course','create_course','retry_course'}: raise AttributeError(name)
        def forward(scope,*args):
            self.calls.append((name,args))
            return {'method':name}
        return forward

@pytest.fixture
def setup(tmp_path,monkeypatch):
    monkeypatch.setenv('AI_ALLOWED_PB_USER_IDS','mom,grandma')
    monkeypatch.setenv('LEARNING_REVIEWER_USER_IDS','mom')
    monkeypatch.setenv('INTAKE_FAMILY_ID','family-a')
    monkeypatch.setenv('AI_API_KEY','maintenance-key')
    monkeypatch.setenv('SCHOOL_VISION_TOKEN','school-only-key')
    for key in ('SEMANTIC_FAMILY_ID','WEEKLY_REPORT_FAMILY_ID','SOUND_RING_FAMILY_ID','LEARNING_FAMILY_ID','LEARNING_CHILD_ID'):monkeypatch.delenv(key,raising=False)
    state={'user':'mom','family':'family-a','calls':0,'password_ok':True,'child_token':None}
    state['children']=[{'id':'pbchild','localId':'child-local','name':'布布','familyId':'family-a'},
                       {'id':'foreign','localId':'other-child','name':'外家','familyId':'family-b'}]
    def pb(request):
        state['calls']+=1
        if request.url.path.endswith('/auth-with-password'):
            if not state['password_ok']: return httpx.Response(400,json={'message':'password supersecret invalid'})
            return httpx.Response(200,json={'token':'pb-token','record':{'id':state['user'],'familyId':state['family']}})
        if request.url.path.endswith('/auth-refresh'):
            if request.headers.get('Authorization') not in ('Bearer pb-token','Bearer refreshed-token'):return httpx.Response(401,json={})
            return httpx.Response(200,json={'token':'refreshed-token','record':{'id':state['user'],'familyId':state['family']}})
        state['child_token']=request.headers.get('Authorization')
        assert request.url.path.endswith('/childprofile/records')
        pages=state.get('child_pages',[state['children']])
        return httpx.Response(200,json={'items':pages[int(request.url.params['page'])-1],'totalPages':len(pages)})
    app=FastAPI();service=FakeService(tmp_path);(tmp_path/'media.wav').write_bytes(b'0123456789')
    install_learning(app,lambda:service)
    app.state.learning_auth=PocketBaseAuthenticator(client_factory=lambda:httpx.Client(transport=httpx.MockTransport(pb),timeout=5,trust_env=False))
    with TestClient(app,base_url='https://family.test') as client:yield client,state,service

BEARER={'Authorization':'Bearer pb-token'}
CSRF={'X-Bubu-Learning':'1'}

def test_index_public_and_native_cookie(setup):
    client,state,_=setup
    assert client.get('/learning').status_code==200
    assert client.get('/learning/api/context').status_code==401
    response=client.get('/learning?child=child-local',headers=BEARER)
    assert response.status_code==200
    cookie=response.headers['set-cookie']
    assert 'HttpOnly' in cookie and 'Secure' in cookie and 'Path=/learning' in cookie and 'SameSite=strict' in cookie
    context=client.get('/learning/api/context').json()
    assert context['children']==[{'id':'child-local','name':'布布'}]
    assert state['child_token']=='Bearer refreshed-token'

def test_revocation_rereads_pb_and_allowlist(setup,monkeypatch):
    client,state,_=setup
    assert client.get('/learning/api/context',headers=BEARER).status_code==200
    before=state['calls'];state['family']='family-b'
    assert client.get('/learning/api/context').status_code==403
    assert state['calls']>before
    state['family']='family-a';monkeypatch.setenv('AI_ALLOWED_PB_USER_IDS','someoneelse')
    assert client.get('/learning/api/context').status_code==403

def test_maintenance_and_school_keys_never_become_family_session(setup):
    client,state,_=setup
    for key in ('maintenance-key','school-only-key'):
        response=client.get('/learning/api/context',headers={'Authorization':f'Bearer {key}'})
        assert response.status_code==401
        assert 'Max-Age=0' in response.headers.get('set-cookie','')
        assert SESSION_COOKIE not in client.cookies
    assert state['calls']==0

def test_csrf_and_child_guard(setup):
    client,_,service=setup
    client.get('/learning',headers=BEARER)
    assert client.delete('/learning/api/courses/c1').status_code==403
    assert client.delete('/learning/api/courses/c1',headers=CSRF).status_code==200
    service.calls.clear()
    assert client.get('/learning/api/days?child_id=other-child&start=2026-10-01&end=2026-10-21').status_code==403
    assert not service.calls
    assert client.get('/learning/api/days?child_id=child-local&start=2026-10-01&end=2026-10-21').status_code==200

def test_reviewer_enforced_and_native_without_csrf(setup):
    client,state,_=setup
    body={'revision':2,'confirmations':[{'activity_id':'a1','digest':'digest','verified':True}],'date_confirmed':True}
    assert client.post('/learning/api/packs/p1/publish',headers=BEARER,json=body).status_code==200
    state['user']='grandma'
    assert client.post('/learning/api/packs/p1/publish',headers=BEARER,json=body).status_code==403

def test_login_logout_and_password_not_echoed(setup):
    client,state,_=setup
    assert client.post('/learning/api/session',json={'identity':'mom','password':'secret'}).status_code==403
    state['password_ok']=False
    response=client.post('/learning/api/session',headers=CSRF,json={'identity':'mom','password':'secret'})
    assert response.status_code==401 and 'supersecret' not in response.text
    state['password_ok']=True
    assert client.post('/learning/api/session',headers=CSRF,json={'identity':'mom','password':'secret'}).status_code==200
    assert client.get('/learning/api/context').status_code==200
    assert client.delete('/learning/api/session',headers=CSRF).status_code==204
    assert client.get('/learning/api/context').status_code==401

def test_safe_errors_json_limit_and_file_range(setup):
    client,_,_=setup
    for identifier,status in [('missing',404),('conflict',409),('invalid',422)]:
        response=client.get('/learning/api/packs/'+identifier,headers=BEARER)
        assert response.status_code==status
        assert not any(x in response.text for x in ('/secrets','secret version','do-not-echo'))
    response=client.post('/learning/api/attempts',headers={**BEARER,'Content-Type':'application/json'},content='x'*300000)
    assert response.status_code==413
    response=client.get('/learning/api/sources/source1/file',headers={**BEARER,'Range':'bytes=2-5'})
    assert response.status_code==206 and response.content==b'2345'
    assert response.headers['cache-control']=='no-store'
    assert "script-src 'self'" in response.headers['content-security-policy']

def test_attempt_requires_family_child(setup):
    client,_,_=setup
    body={'id':'attempt1','child_id':'other-child','pack_id':'p1','activity_id':'a1','kind':'speak'}
    assert client.post('/learning/api/attempts',headers=BEARER,json=body).status_code==403
    body['child_id']='child-local'
    assert client.post('/learning/api/attempts',headers=BEARER,json=body).status_code==200


def test_chunked_json_limit_and_invalid_json_are_safe(setup):
    client,_,_=setup
    headers={**BEARER,'Content-Type':'application/json'}
    response=client.post('/learning/api/attempts',headers=headers,content=iter([b'x'*150000,b'y'*150000]))
    assert response.status_code==413
    for payload in ('{bad', '{"id":NaN}', '[]'):
        assert client.post('/learning/api/attempts',headers=headers,content=payload).status_code==422


def test_missing_reviewer_configuration_fails_closed(setup,monkeypatch):
    client,_,_=setup
    monkeypatch.delenv('LEARNING_REVIEWER_USER_IDS',raising=False)
    monkeypatch.delenv('INTAKE_ALLOWED_PB_USER_IDS',raising=False)
    assert client.get('/learning/api/context',headers=BEARER).json()['user']['can_review'] is False
    monkeypatch.setenv('INTAKE_ALLOWED_PB_USER_IDS','mom')
    assert client.get('/learning/api/context',headers=BEARER).json()['user']['can_review'] is True
    monkeypatch.setenv('LEARNING_REVIEWER_USER_IDS','')
    assert client.get('/learning/api/context',headers=BEARER).json()['user']['can_review'] is False


def test_all_service_adapters_and_media_paths(setup):
    client,_,service=setup
    root='/learning/api/'
    gets=[
        ('packs?child_id=child-local&date=2026-10-21',None),
        ('sources?child_id=child-local&date=2026-10-21','sources'),
        ('reviews?child_id=child-local&period=month&date=2026-10-21','reviews'),
        ('attempts?child_id=child-local','attempts'),
        ('media/media1/analysis','media_analysis'),
        ('timeline/search?query=玉米&kind=video&start=2026-10-01&end=2026-10-21&order=asc&limit=10','timeline_search')]
    for path,method in gets:
        response=client.get(root+path,headers=BEARER)
        assert response.status_code==200
        if method: assert response.json()['method']==method
    assert ('media_analysis',('media1',False)) in service.calls
    assert ('timeline_search',('玉米','video','2026-10-01','2026-10-21','asc',10)) in service.calls
    assert client.post(root+'media/media1/analysis/retry',headers=BEARER,json={}).status_code==200
    assert ('media_analysis',('media1',True)) in service.calls
    assert client.post(root+'packs/p1/exclude',headers=BEARER,json={'revision':2,'activity_id':'a1'}).status_code==200
    assert client.post(root+'packs/p1/regenerate',headers=BEARER,json={}).status_code==200
    body={'revision':2,'segments':[{'id':'s1','start':1,'end':2,'text':'Corn.'}],'school_date':'2026-10-21','date_confirmed':True}
    assert client.patch(root+'sources/s1/segments',headers=BEARER,json=body).status_code==200
    response=client.get(root+'packs/p1/resources/clip.wav',headers={**BEARER,'Range':'bytes=0-2'})
    assert response.status_code==206 and response.content==b'012'


def test_csp_no_cors_and_query_validation(setup):
    client,_,_=setup
    response=client.get('/learning/web/app.js')
    assert response.status_code==200 and "connect-src 'self'" in response.headers['content-security-policy']
    assert 'access-control-allow-origin' not in response.headers
    response=client.get('/learning/api/timeline/search?limit=999999&kind=bad',headers=BEARER)
    assert response.status_code==422 and '999999' not in response.text


def test_configured_child_limits_scope_after_paginated_family_validation(setup,monkeypatch):
    client,state,service=setup
    historical=[{'id':'profile'+str(n),'localId':'old-child-'+str(n),'name':'历史资料'+str(n),'familyId':'family-a'} for n in range(7)]
    current={'id':'current-profile','localId':'configured-child','name':'布布','familyId':'family-a'}
    state['child_pages']=[historical,[current]]
    monkeypatch.setenv('LEARNING_CHILD_ID','configured-child')
    response=client.get('/learning/api/context',headers=BEARER)
    assert response.status_code==200
    assert response.json()['children']==[{'id':'configured-child','name':'布布'}]
    assert response.json()['default_child']=='configured-child'
    assert client.get('/learning/api/days?child_id=old-child-0&start=2026-10-01&end=2026-10-21').status_code==403
    assert not service.calls
    assert client.get('/learning/api/days?start=2026-10-01&end=2026-10-21').status_code==200
    assert service.calls==[('days','family-a','configured-child')]


@pytest.mark.parametrize('configured',['other-child','nonexistent-child','pbchild'])
def test_configured_child_must_be_a_live_family_local_id(setup,monkeypatch,configured):
    client,_,service=setup
    monkeypatch.setenv('LEARNING_CHILD_ID',configured)
    response=client.get('/learning/api/context',headers=BEARER)
    assert response.status_code==503
    assert configured not in response.text
    assert not service.calls


@pytest.mark.parametrize('deleted', [{'isDeleted':True},{'deletedAt':'2026-10-21'},{'deleted':True}])
def test_deleted_configured_child_never_falls_back_to_historical_copy(setup,monkeypatch,deleted):
    client,state,_=setup
    state['children'][0].update(deleted)
    state['children'].append({'id':'old-profile','localId':'old-child','name':'旧资料','familyId':'family-a'})
    monkeypatch.setenv('LEARNING_CHILD_ID','child-local')
    assert client.get('/learning/api/context',headers=BEARER).status_code==503


def test_unconfigured_child_preserves_multiple_family_profiles(setup):
    client,state,_=setup
    state['children'].append({'id':'second-profile','localId':'second-child','name':'另一份资料','familyId':'family-a'})
    response=client.get('/learning/api/context',headers=BEARER)
    assert response.status_code==200
    assert [child['id'] for child in response.json()['children']]==['child-local','second-child']
    assert response.json()['default_child']=='child-local'


def test_old_native_query_only_selects_public_shell_not_old_child_resources(setup,monkeypatch):
    client,state,_=setup
    state['children'].append({'id':'old-profile','localId':'old-child','name':'历史资料','familyId':'family-a'})
    monkeypatch.setenv('LEARNING_CHILD_ID','child-local')
    assert client.get('/learning?child=old-child',headers=BEARER).status_code==200
    context=client.get('/learning/api/context').json()
    assert context['children']==[{'id':'child-local','name':'布布'}]
    assert client.get('/learning/api/packs?child_id=old-child&date=2026-10-21').status_code==403
    assert client.get('/learning?child=old-child',headers={'Authorization':'Bearer invalid-token'}).status_code==401


def test_course_upload_is_multipart_reviewer_only_and_not_capped_like_json(setup):
    client,state,service=setup
    received={}
    def create_course(scope,child,day,title,kind,language,files,total_files=0):
        received.update(total_files=total_files,child=child,day=day,title=title,kind=kind,language=language,
                        files=[(name,mime,Path(path).read_bytes()) for name,path,mime in files])
        return {'id':'course-1'}
    service.create_course=create_course
    big=b'v'*(300*1024)
    form={'school_date':'2026-10-21','title':'Fruit words','kind':'teaching'}
    upload=[('files',('words.mov',big,'video/quicktime')),('files',('card.jpg',b'card','image/jpeg'))]
    response=client.post('/learning/api/courses',data=form,files=upload,headers={**BEARER,**CSRF})
    assert response.status_code==200 and response.json()=={'id':'course-1'}
    assert received['child']=='child-local' and received['files'][0]==('words.mov','video/quicktime',big)
    state['user']='grandma'
    assert client.post('/learning/api/courses',data=form,files=upload,headers={**BEARER,**CSRF}).status_code==403


def test_course_files_can_follow_one_per_request(setup):
    client,state,service=setup
    added=[]
    service.add_course_file=lambda scope,cid,name,path,mime:added.append((cid,name,mime,Path(path).read_bytes())) or {'id':cid}
    response=client.post('/learning/api/courses/course-1/files',files={'file':('card.jpg',b'card','image/jpeg')},headers={**BEARER,**CSRF})
    assert response.status_code==200 and added==[('course-1','card.jpg','image/jpeg',b'card')]
    state['user']='grandma'
    assert client.post('/learning/api/courses/course-1/files',files={'file':('x.jpg',b'x','image/jpeg')},headers={**BEARER,**CSRF}).status_code==403


def test_family_feature_routes_scope_reviewer_and_errors(setup):
    client,state,service=setup
    class Feature:
        def __init__(self,name):self.name=name
        def __getattr__(self,method):
            def call(scope,*args):
                service.calls.append((self.name,method,args))
                if args and args[0]=='missing':raise Missing('secret path')
                if method=='audio':return service.tmp/'media.wav','audio/mp4'
                if method=='preview':return service.tmp/'media.wav','image/jpeg'
                return {'items':[],'feature':self.name}
            return call
    root='/learning/api/'
    assert client.get(root+'memories?date=2026-10-22',headers=BEARER).status_code==503
    for name in ('online_timeline','memories','firsts','monthly','voices','recognition'):
        setattr(service,name,Feature(name))
    for path,expected in [('online-timeline?person=姥姥&query=海边',('online_timeline','feed')),
                          ('online-timeline/people',('online_timeline','people')),
                          ('online-timeline/items?ids=a,b',('online_timeline','items')),
                          ('online-timeline/highlights?date=2026-10-22',('online_timeline','highlights')),
                          ('memories?date=2026-10-22',('memories','memories')),('firsts?status=all',('firsts','list')),
                          ('monthly',('monthly','list')),('voices',('voices','list')),
                          ('recognition/candidates?limit=5',('recognition','candidates'))]:
        response=client.get(root+path,headers=BEARER)
        assert response.status_code==200,path
        assert service.calls[-1][:2]==expected
    assert service.calls[0][2][-2]=='姥姥' and service.calls[0][2][-1] is False and service.calls[0][2][0]=='海边'
    assert client.get(root+'memories',headers=BEARER).status_code==200 and len(service.calls[-1][2][0])==10
    assert client.get(root+'voices/v1/audio',headers=BEARER).headers['content-type']=='audio/mp4'
    assert client.get(root+'recognition/f1/preview',headers=BEARER).status_code==200
    assert client.get(root+'firsts?status=bogus',headers=BEARER).status_code==422
    assert client.post(root+'firsts/f1/confirm',headers=BEARER,json={}).status_code==200
    assert client.post(root+'firsts/missing/dismiss',headers=BEARER,json={}).status_code==404
    assert client.post(root+'recognition/f1',headers=BEARER,json={'decision':'maybe'}).status_code==422
    response=client.post(root+'recognition/f1',headers=BEARER,json={'decision':'no'})
    assert response.status_code==200 and service.calls[-1]==('recognition','decide',('f1','no'))
    state['user']='grandma'
    assert client.post(root+'recognition/f1',headers=BEARER,json={'decision':'yes'}).status_code==403
    assert client.post(root+'firsts/f1/confirm',headers=BEARER,json={}).status_code==403
    assert client.get(root+'firsts',headers=BEARER).status_code==200

def test_226_routes_contract_reviewer_and_csrf(setup):
    client,state,service=setup
    class Feature:
        def __init__(self,name):self.name=name
        def __getattr__(self,method):
            def call(scope,*args):
                service.calls.append((self.name,method,args,scope.user_id))
                if args and args[0]=='missing':raise Missing('secret path')
                if method=='delete_comment':return None
                return {'feature':self.name,'method':method}
            return call
    root='/learning/api/'
    assert client.get(root+'status',headers=BEARER).status_code==503
    for name in ('status','ask','words','places','social','recognition'):
        setattr(service,name,Feature(name))
    fid='a'*24
    for path,expected in [('status',('status','status',())),('words',('words','words',())),
                          ('places',('places','places',())),
                          ('events?start=2025-01-01&end=2025-12-31',('places','events',('2025-01-01','2025-12-31'))),
                          ('events',('places','events',(None,None))),
                          ('recognition/history?limit=7',('recognition','history',(7,))),
                          ('social/recent?limit=5',('social','recent',(5,))),
                          ('online-timeline/%s/social'%fid,('social','social',(fid,)))]:
        response=client.get(root+path,headers=BEARER)
        assert response.status_code==200,path
        assert service.calls[-1][:3]==expected,path
    assert client.post(root+'ask',headers=BEARER,json={'question':'她第一次去海边是什么时候？'}).status_code==200
    assert service.calls[-1][:3]==('ask','ask',('她第一次去海边是什么时候？',))
    for bad in ({'question':''},{'question':'x'*201},{'q':'x'}):
        assert client.post(root+'ask',headers=BEARER,json=bad).status_code==422
    body={'decisions':[{'id':fid,'decision':'yes'},{'id':'b'*24,'decision':'no'}]}
    assert client.post(root+'recognition/batch',headers=BEARER,json=body).status_code==200
    assert service.calls[-1][:3]==('recognition','batch',([{'id':fid,'decision':'yes'},{'id':'b'*24,'decision':'no'}],))
    assert client.post(root+'recognition/batch',headers=BEARER,json={'decisions':[{'id':'x','decision':'yes'}]}).status_code==422
    assert client.post(root+'recognition/batch',headers=BEARER,json={'decisions':[{'id':fid,'decision':'yes'}]*51}).status_code==422
    assert client.post(root+'recognition/'+fid,headers=BEARER,json={'decision':'undo'}).status_code==200
    assert service.calls[-1][:3]==('recognition','decide',(fid,'undo'))
    # Family members who cannot review may still comment and heart; batch decisions stay reviewer-only.
    state['user']='grandma'
    assert client.post(root+'recognition/batch',headers=BEARER,json=body).status_code==403
    response=client.post(root+'online-timeline/%s/comments'%fid,headers=BEARER,json={'text':'好可爱'})
    assert response.status_code==200 and service.calls[-1]==('social','comment',(fid,'好可爱'),'grandma')
    assert client.post(root+'online-timeline/%s/comments'%fid,headers=BEARER,json={'text':'x'*301}).status_code==422
    assert client.post(root+'online-timeline/%s/heart'%fid,headers=BEARER,json={'on':True}).status_code==200
    assert service.calls[-1][:3]==('social','heart',(fid,True))
    assert client.post(root+'online-timeline/%s/heart'%fid,headers=BEARER,json={'on':'yes'}).status_code==422
    response=client.delete(root+'online-timeline/%s/comments/c1'%fid,headers=BEARER)
    assert response.status_code==204 and service.calls[-1][:3]==('social','delete_comment',(fid,'c1'))
    assert client.delete(root+'online-timeline/missing/comments/c1',headers=BEARER).status_code==404
    # Cookie sessions need the CSRF header for these writes too.
    client.get('/learning',headers=BEARER)
    assert client.post(root+'online-timeline/%s/comments'%fid,json={'text':'hi'}).status_code==403
    assert client.post(root+'online-timeline/%s/comments'%fid,headers=CSRF,json={'text':'hi'}).status_code==200

def test_brain_routes_return_503_when_library_slots_are_exhausted(setup,monkeypatch):
    import threading
    from learning import api
    client,_,service=setup
    class Feature:
        def __getattr__(self,method):
            return lambda scope,*args:{'items':[]}
    service.places=Feature();service.status=Feature()
    slots=threading.BoundedSemaphore(1);slots.acquire()
    monkeypatch.setattr(api,'BRAIN_SLOTS',slots)
    response=client.get('/learning/api/places',headers=BEARER)
    assert response.status_code==503 and response.json()['detail']=='家里的服务器暂时读不到素材库，请稍后重试。'
    assert client.get('/learning/api/status',headers=BEARER).status_code==200  # status never waits for the library
    slots.release()
    assert client.get('/learning/api/places',headers=BEARER).status_code==200
