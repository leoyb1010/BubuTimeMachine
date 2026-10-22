"""Same-origin HTTP adapter for the learning service; no model output is executable."""
from __future__ import annotations

from collections import deque
from contextlib import contextmanager
import json
from pathlib import Path
import threading
import time
from typing import Callable, Literal

import mimetypes
import shutil
import tempfile

from fastapi import APIRouter, Depends, FastAPI, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .auth import FamilyScope, PocketBaseAuthenticator, SESSION_COOKIE, SESSION_SECONDS, require_csrf
from .models import Segment
from .store import Conflict, Missing

MAX_JSON_BYTES = 256 * 1024
BRAIN_UNAVAILABLE = '家里的服务器暂时读不到素材库，请稍后重试。'
# Routes that may touch the external library disk share a few of the 40 request
# threads; when those are all busy (or stuck) the rest of the service stays up.
BRAIN_SLOTS = threading.BoundedSemaphore(8)
COURSE_UPLOAD_PATH = '/learning/api/courses'
MAX_COURSE_FILE_BYTES = 256 * 1024 * 1024
MAX_COURSE_UPLOAD_BYTES = 8 * MAX_COURSE_FILE_BYTES
WEB_ROOT = Path(__file__).with_name('web')
CSP = ("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
       "img-src 'self'; media-src 'self'; connect-src 'self'; font-src 'self'; "
       "object-src 'none'; frame-src 'none'; frame-ancestors 'self'; base-uri 'none'; form-action 'self'")


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)


class Login(Input):
    identity: str = Field(min_length=1, max_length=300)
    password: str = Field(min_length=1, max_length=1024)


class Confirmation(Input):
    activity_id: str = Field(min_length=1, max_length=80)
    digest: str = Field(min_length=1, max_length=128)
    verified: Literal[True]


class Publish(Input):
    revision: int = Field(ge=1)
    confirmations: list[Confirmation] = Field(min_length=1, max_length=12)
    date_confirmed: bool


class Exclude(Input):
    revision: int = Field(ge=1)
    activity_id: str = Field(min_length=1, max_length=80)


class Segments(Input):
    revision: int = Field(ge=1)
    segments: list[Segment] = Field(min_length=1, max_length=500)
    school_date: str = Field(pattern=r'^\d{4}-\d{2}-\d{2}$')
    date_confirmed: bool


class Decision(Input):
    decision: Literal['yes', 'no', 'undo']


class BatchDecision(Input):
    id: str = Field(pattern=r'^[a-f0-9]{24}$')
    decision: Literal['yes', 'no']


class RecognitionBatch(Input):
    decisions: list[BatchDecision] = Field(min_length=1, max_length=50)


class Question(Input):
    question: str = Field(min_length=1, max_length=200)


class Comment(Input):
    text: str = Field(min_length=1, max_length=300)


class Heart(Input):
    on: bool


class Attempt(Input):
    id: str = Field(min_length=1, max_length=100, pattern=r'^[a-zA-Z0-9_-]+$')
    child_id: str = Field(min_length=1, max_length=128)
    pack_id: str = Field(min_length=1, max_length=100)
    activity_id: str = Field(min_length=1, max_length=80)
    kind: Literal['listen_choice', 'color_choice', 'sort', 'speak', 'music']
    choice: str | None = Field(default=None, max_length=80)
    run_id: str | None = Field(default=None, max_length=100)
    assistance: bool | None = None
    note: str | None = Field(default=None, max_length=500)


async def limited_json(request: Request) -> None:
    """Read a bounded stream before parsing, including chunked requests without a length."""
    if request.method not in {'POST', 'PUT', 'PATCH', 'DELETE'}:
        return
    size, chunks = 0, []
    async for chunk in request.stream():
        size += len(chunk)
        if size > MAX_JSON_BYTES:
            raise HTTPException(413, '请求内容过大，请缩小后重试。')
        chunks.append(chunk)
    if not size:
        request.state.learning_body = {}
        return
    if request.headers.get('content-type', '').split(';')[0].strip().lower() != 'application/json':
        raise HTTPException(415, '请求需要使用 JSON 格式。')
    try:
        def reject_constant(value):
            raise ValueError('Non-finite JSON constant')
        body = json.loads(b''.join(chunks), parse_constant=reject_constant)
        if not isinstance(body, dict):
            raise ValueError('Object required')
    except (ValueError, UnicodeDecodeError, RecursionError):
        raise HTTPException(422, '请求内容无效，请检查后重试。') from None
    request.state.learning_body = body


def _input(request: Request, model: type[Input]) -> Input:
    try:
        return model.model_validate(getattr(request.state, 'learning_body', {}))
    except ValidationError:
        raise HTTPException(422, '请求内容无效，请检查后重试。') from None


def _scope(request: Request) -> FamilyScope:
    return request.app.state.learning_auth.authenticate(request)


def _call(service_factory, method: str, *args):
    try:
        return getattr(service_factory(), method)(*args)
    except Missing:
        raise HTTPException(404, '内容不存在或已移除。') from None
    except Conflict:
        raise HTTPException(409, '内容已更新，请重新加载并核对当前版本。') from None
    except ValueError:
        raise HTTPException(422, '请求内容无效，请检查后重试。') from None


@contextmanager
def _brain_slot():
    if not BRAIN_SLOTS.acquire(timeout=2):
        raise HTTPException(503, BRAIN_UNAVAILABLE)
    try:
        yield
    finally:
        BRAIN_SLOTS.release()


def _timeline(service_factory, method: str, scope, *args):
    timeline = getattr(service_factory(), 'online_timeline', None)
    if timeline is None:
        raise HTTPException(503, '布布专属素材库尚未启用。')
    try:
        with _brain_slot():
            return getattr(timeline, method)(scope, *args)
    except Missing:
        raise HTTPException(404, '素材已不在布布专属库中。') from None
    except ValueError:
        raise HTTPException(422, '筛选条件无效，请检查后重试。') from None


def _feature(service_factory, name: str, method: str, scope, *args, brain: bool = True):
    """Family features built on the online timeline; 503 until a person is configured."""
    from .brain_bridge import BrainUnavailable
    feature = getattr(service_factory(), name, None)
    if feature is None:
        raise HTTPException(503, '布布专属素材库尚未启用。')
    try:
        if not brain:
            return getattr(feature, method)(scope, *args)
        with _brain_slot():
            return getattr(feature, method)(scope, *args)
    except Missing:
        raise HTTPException(404, '内容不存在或已移除。') from None
    except Conflict:
        raise HTTPException(409, '内容已更新，请重新加载。') from None
    except ValueError:
        raise HTTPException(422, '请求内容无效，请检查后重试。') from None
    except BrainUnavailable:
        raise HTTPException(503, BRAIN_UNAVAILABLE) from None


def _today() -> str:
    from datetime import datetime
    from zoneinfo import ZoneInfo
    return datetime.now(ZoneInfo('Asia/Shanghai')).date().isoformat()


def _file(result) -> FileResponse:
    path, mime = result
    path = Path(path)
    if not path.is_file():
        raise HTTPException(404, '素材不存在或已移除。')
    return FileResponse(path, media_type=mime, headers={'Cache-Control': 'no-store'})


def install_learning(app: FastAPI, service_factory: Callable) -> None:
    """Register routes without starting background jobs or reading deployment secrets."""
    app.state.learning_auth = PocketBaseAuthenticator()
    login_attempts: dict[str, deque] = {}
    login_lock = threading.Lock()

    @app.middleware('http')
    async def learning_headers(request: Request, call_next):
        if request.url.path != '/learning' and not request.url.path.startswith('/learning/'):
            return await call_next(request)
        length = request.headers.get('content-length')
        upload = request.method == 'POST' and (request.url.path == COURSE_UPLOAD_PATH or (
            request.url.path.startswith(COURSE_UPLOAD_PATH + '/') and request.url.path.endswith('/files')))
        limit = MAX_COURSE_UPLOAD_BYTES if upload else MAX_JSON_BYTES
        if length and (not length.isdecimal() or int(length) > limit):
            response = JSONResponse({'detail': '请求内容过大，请缩小后重试。'}, status_code=413)
        else:
            response = await call_next(request)
        # FastAPI's default validation body includes submitted values; don't echo them.
        if response.status_code == 422:
            response = JSONResponse({'detail': '请求内容无效，请检查后重试。'}, status_code=422)
        response.headers.update({'Cache-Control': 'no-store', 'Pragma': 'no-cache',
                                 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin',
                                 'Content-Security-Policy': CSP})
        if getattr(request.state, 'learning_logout', False) or response.status_code == 401:
            response.delete_cookie(SESSION_COOKIE, path='/learning', secure=True, httponly=True, samesite='strict')
        elif getattr(request.state, 'learning_token', None):
            response.set_cookie(SESSION_COOKIE, request.state.learning_token, max_age=SESSION_SECONDS,
                                path='/learning', secure=True, httponly=True, samesite='strict')
        return response

    @app.get('/learning', include_in_schema=False)
    @app.get('/learning/', include_in_schema=False)
    def learning_index(request: Request):
        # An expired cookie must not trap the user outside the login page. An
        # explicitly supplied native Bearer is still verified and never ignored.
        if request.headers.get('authorization') is not None:
            request.app.state.learning_auth.authenticate(request)
        # This is only the public shell. An older native build can carry a
        # historical profile ID; Web boot selects solely from verified context.
        # Every data/resource API keeps its own strict family/child checks.
        return FileResponse(WEB_ROOT / 'index.html', media_type='text/html')

    app.mount('/learning/web', StaticFiles(directory=WEB_ROOT), name='learning-web')
    router = APIRouter(prefix='/learning/api', dependencies=[Depends(limited_json)])

    @router.post('/session')
    def login(request: Request):
        require_csrf(request)
        body = _input(request, Login)
        # Public password auth gets a bounded per-client limiter independent of PB.
        key = request.client.host if request.client else 'unknown'
        now = time.monotonic()
        with login_lock:
            for old_key in list(login_attempts):
                while login_attempts[old_key] and login_attempts[old_key][0] < now - 60:
                    login_attempts[old_key].popleft()
                if not login_attempts[old_key]:
                    del login_attempts[old_key]
            if key not in login_attempts and len(login_attempts) >= 4096:
                raise HTTPException(429, '登录请求过多，请稍后再试。')
            bucket = login_attempts.setdefault(key, deque())
            if len(bucket) >= 10:
                raise HTTPException(429, '登录请求过多，请稍后再试。')
            bucket.append(now)
        scope, token = request.app.state.learning_auth.login(body.identity.strip(), body.password)
        request.state.learning_token = token
        return {'user': {'id': scope.user_id, 'can_review': scope.can_review}}

    @router.delete('/session', status_code=204)
    def logout(request: Request):
        require_csrf(request)
        request.state.learning_logout = True
        return Response(status_code=204)

    @router.get('/context')
    def context(scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'context', scope)

    @router.get('/days')
    def days(child_id: str | None = Query(None, max_length=128), start: str = Query(..., max_length=10),
             end: str = Query(..., max_length=10), scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'days', scope, scope.require_child(child_id), start, end)

    @router.get('/packs')
    def packs(child_id: str | None = Query(None, max_length=128), date: str = Query(..., max_length=10),
              scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'packs', scope, scope.require_child(child_id), date)

    @router.get('/packs/{pid}')
    def pack(pid: str, scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'pack', scope, pid)

    @router.get('/sources')
    def sources(child_id: str | None = Query(None, max_length=128), date: str = Query(..., max_length=10),
                scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'sources', scope, scope.require_child(child_id), date)

    @router.post('/packs/{pid}/publish')
    def publish(pid: str, request: Request, scope: FamilyScope = Depends(_scope)):
        scope.require_review(); body = _input(request, Publish)
        return _call(service_factory, 'publish', scope, pid, body.revision,
                     [item.model_dump() for item in body.confirmations], body.date_confirmed)

    @router.post('/packs/{pid}/exclude')
    def exclude(pid: str, request: Request, scope: FamilyScope = Depends(_scope)):
        scope.require_review(); body = _input(request, Exclude)
        return _call(service_factory, 'exclude', scope, pid, body.revision, body.activity_id)

    @router.post('/packs/{pid}/regenerate')
    def regenerate(pid: str, scope: FamilyScope = Depends(_scope)):
        scope.require_review()
        return _call(service_factory, 'regenerate', scope, pid)

    @router.patch('/sources/{sid}/segments')
    def update_segments(sid: str, request: Request, scope: FamilyScope = Depends(_scope)):
        scope.require_review(); body = _input(request, Segments)
        return _call(service_factory, 'update_segments', scope, sid, body.revision,
                     [segment.model_dump() for segment in body.segments], body.school_date, body.date_confirmed)

    @router.get('/reviews')
    def reviews(child_id: str | None = Query(None, max_length=128), period: Literal['week', 'month'] = 'week',
                date: str = Query(..., max_length=10), scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'reviews', scope, scope.require_child(child_id), period, date)

    @router.get('/attempts')
    def attempts(child_id: str | None = Query(None, max_length=128), start: str | None = Query(None, max_length=10),
                 end: str | None = Query(None, max_length=10), scope: FamilyScope = Depends(_scope)):
        # Optional yyyy-MM-dd window (Asia/Shanghai days, inclusive) for the weekly learning report.
        if start or end:
            return _call(service_factory, 'attempts', scope, scope.require_child(child_id), start, end)
        return _call(service_factory, 'attempts', scope, scope.require_child(child_id))

    @router.post('/attempts')
    def save_attempt(request: Request, scope: FamilyScope = Depends(_scope)):
        body = _input(request, Attempt)
        scope.require_child(body.child_id)
        return _call(service_factory, 'save_attempt', scope, body.model_dump(exclude_none=True))

    @router.get('/media/{media_id}/analysis')
    def media_analysis(media_id: str, scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'media_analysis', scope, media_id, False)

    @router.post('/media/{media_id}/analysis/retry')
    def retry_analysis(media_id: str, scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'media_analysis', scope, media_id, True)

    @router.get('/timeline/search')
    def timeline_search(query: str = Query('', max_length=500), kind: Literal['all', 'photo', 'video'] = 'all',
                        start: str | None = Query(None, max_length=10), end: str | None = Query(None, max_length=10),
                        order: Literal['asc', 'desc'] = 'desc', limit: int = Query(50, ge=1, le=100),
                        scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'timeline_search', scope, query, kind, start, end, order, limit)

    @router.get('/online-timeline')
    def online_timeline(query: str = Query('', max_length=500), kind: Literal['all', 'photo', 'video'] = 'all',
                        start: str | None = Query(None, max_length=10), end: str | None = Query(None, max_length=10),
                        order: Literal['asc', 'desc'] = 'desc', page: int = Query(1, ge=1, le=10000),
                        limit: int = Query(40, ge=1, le=100), person: str | None = Query(None, max_length=40),
                        collapse_bursts: bool = False, scope: FamilyScope = Depends(_scope)):
        return _timeline(service_factory, 'feed', scope, query, kind, start, end, order, page, limit, person,
                         collapse_bursts)

    @router.get('/online-timeline/people')
    def online_people(scope: FamilyScope = Depends(_scope)):
        return _timeline(service_factory, 'people', scope)

    @router.get('/online-timeline/items')
    def online_items(ids: str = Query(..., max_length=2000), scope: FamilyScope = Depends(_scope)):
        return _timeline(service_factory, 'items', scope, ids)

    @router.get('/online-timeline/highlights')
    def online_highlights(date: str | None = Query(None, max_length=10), scope: FamilyScope = Depends(_scope)):
        return _timeline(service_factory, 'highlights', scope, date or _today())

    @router.get('/memories')
    def memories(date: str | None = Query(None, max_length=10), scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'memories', 'memories', scope, date or _today())

    @router.get('/firsts')
    def firsts(status: Literal['candidate', 'confirmed', 'all'] = 'candidate', scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'firsts', 'list', scope, status)

    @router.post('/firsts/{fid}/confirm')
    def confirm_first(fid: str, scope: FamilyScope = Depends(_scope)):
        scope.require_review()
        return _feature(service_factory, 'firsts', 'confirm', scope, fid)

    @router.post('/firsts/{fid}/dismiss')
    def dismiss_first(fid: str, scope: FamilyScope = Depends(_scope)):
        scope.require_review()
        return _feature(service_factory, 'firsts', 'dismiss', scope, fid)

    @router.get('/monthly')
    def monthly(scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'monthly', 'list', scope)

    @router.get('/voices')
    def voices(scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'voices', 'list', scope)

    @router.get('/voices/{vid}/audio')
    def voice_audio(vid: str, scope: FamilyScope = Depends(_scope)):
        return _file(_feature(service_factory, 'voices', 'audio', scope, vid))

    @router.get('/recognition/candidates')
    def recognition_candidates(limit: int = Query(20, ge=1, le=100), scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'recognition', 'candidates', scope, limit)

    @router.get('/recognition/{fid}/preview')
    def recognition_preview(fid: str, scope: FamilyScope = Depends(_scope)):
        return _file(_feature(service_factory, 'recognition', 'preview', scope, fid))

    @router.post('/recognition/batch')
    def recognition_batch(request: Request, scope: FamilyScope = Depends(_scope)):
        scope.require_review(); body = _input(request, RecognitionBatch)
        return _feature(service_factory, 'recognition', 'batch', scope, [d.model_dump() for d in body.decisions])

    @router.get('/recognition/history')
    def recognition_history(limit: int = Query(50, ge=1, le=200), scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'recognition', 'history', scope, limit)

    @router.post('/recognition/{fid}')
    def recognition_decide(fid: str, request: Request, scope: FamilyScope = Depends(_scope)):
        scope.require_review(); body = _input(request, Decision)
        return _feature(service_factory, 'recognition', 'decide', scope, fid, body.decision)

    @router.get('/status')
    def status(scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'status', 'status', scope, brain=False)

    @router.post('/ask')
    def ask(request: Request, scope: FamilyScope = Depends(_scope)):
        body = _input(request, Question)
        return _feature(service_factory, 'ask', 'ask', scope, body.question)

    @router.get('/words')
    def words(scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'words', 'words', scope)

    @router.get('/places')
    def places(scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'places', 'places', scope)

    @router.get('/events')
    def events(start: str | None = Query(None, max_length=10), end: str | None = Query(None, max_length=10),
               scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'places', 'events', scope, start, end)

    @router.get('/social/recent')
    def social_recent(limit: int = Query(20, ge=1, le=100), scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'social', 'recent', scope, limit)

    @router.get('/online-timeline/{fid}/social')
    def item_social(fid: str, scope: FamilyScope = Depends(_scope)):
        return _feature(service_factory, 'social', 'social', scope, fid)

    @router.post('/online-timeline/{fid}/comments')
    def add_comment(fid: str, request: Request, scope: FamilyScope = Depends(_scope)):
        # Any family member may comment, not only reviewers; CSRF is enforced by _scope.
        body = _input(request, Comment)
        return _feature(service_factory, 'social', 'comment', scope, fid, body.text)

    @router.delete('/online-timeline/{fid}/comments/{cid}', status_code=204)
    def delete_comment(fid: str, cid: str, scope: FamilyScope = Depends(_scope)):
        _feature(service_factory, 'social', 'delete_comment', scope, fid, cid)
        return Response(status_code=204)

    @router.post('/online-timeline/{fid}/heart')
    def heart(fid: str, request: Request, scope: FamilyScope = Depends(_scope)):
        body = _input(request, Heart)
        return _feature(service_factory, 'social', 'heart', scope, fid, body.on)

    @router.get('/online-timeline/{fid}/preview')
    def online_preview(fid: str, size: Literal['thumb', 'card', 'large'] = 'thumb', scope: FamilyScope = Depends(_scope)):
        return _file(_timeline(service_factory, 'media', scope, fid, size))

    @router.get('/online-timeline/{fid}/original')
    def online_original(fid: str, scope: FamilyScope = Depends(_scope)):
        return _file(_timeline(service_factory, 'media', scope, fid, 'original'))

    @router.get('/courses')
    def courses(child_id: str | None = Query(None, max_length=128), start: str = Query(..., max_length=10),
                end: str = Query(..., max_length=10), scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'courses', scope, scope.require_child(child_id), start, end)

    @router.get('/courses/{cid}')
    def course(cid: str, scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'course', scope, cid)

    @router.post('/courses/{cid}/retry')
    def retry_course(cid: str, scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'retry_course', scope, cid)

    @router.delete('/courses/{cid}')
    def delete_course(cid: str, scope: FamilyScope = Depends(_scope)):
        return _call(service_factory, 'delete_course', scope, cid)

    @router.get('/sources/{sid}/file')
    def source_file(sid: str, scope: FamilyScope = Depends(_scope)):
        return _file(_call(service_factory, 'source_file', scope, sid))

    @router.get('/packs/{pid}/resources/{name}')
    def resource(pid: str, name: str, scope: FamilyScope = Depends(_scope)):
        return _file(_call(service_factory, 'resource', scope, pid, name))

    app.include_router(router)

    # Multipart uploads stream to disk; they skip the bounded JSON reader above.
    uploads = APIRouter(prefix='/learning/api')

    def _spool(upload: UploadFile, target: Path):
        name = Path((upload.filename or 'file').replace('\\', '/')).name[:180] or 'file'
        mime = (upload.content_type or '').split(';')[0].strip().lower()
        if mime in {'', 'application/octet-stream'}:
            mime = mimetypes.guess_type(name)[0] or ''
        with target.open('wb') as handle:
            shutil.copyfileobj(upload.file, handle, 1024 * 1024)
        if not 0 < target.stat().st_size <= MAX_COURSE_FILE_BYTES:
            raise HTTPException(413, '单个文件不能为空或超过 256 MB。')
        return name, target, mime

    @uploads.post('/courses')
    def create_course(request: Request, child_id: str | None = Form(None, max_length=128),
                      school_date: str = Form(..., pattern=r'^\d{4}-\d{2}-\d{2}$'),
                      title: str = Form(..., min_length=1, max_length=60),
                      kind: Literal['teaching', 'practice', 'song'] = Form(...),
                      language: Literal['en-US', 'zh-CN'] = Form('en-US'),
                      total_files: int = Form(0, ge=0, le=8),
                      files: list[UploadFile] = File(...), scope: FamilyScope = Depends(_scope)):
        scope.require_review()
        if not 1 <= len(files) <= 8:
            raise HTTPException(422, '每节课请上传1到8个文件。')
        with tempfile.TemporaryDirectory(prefix='bubu-course-upload-') as tmp:
            saved = [_spool(upload, Path(tmp) / str(index)) for index, upload in enumerate(files)]
            return _call(service_factory, 'create_course', scope, scope.require_child(child_id), school_date,
                         title, kind, language, saved, total_files)

    @uploads.post('/courses/{cid}/files')
    def add_course_file(cid: str, request: Request, file: UploadFile = File(...), scope: FamilyScope = Depends(_scope)):
        scope.require_review()
        with tempfile.TemporaryDirectory(prefix='bubu-course-upload-') as tmp:
            name, path, mime = _spool(file, Path(tmp) / 'file')
            return _call(service_factory, 'add_course_file', scope, cid, name, path, mime)

    app.include_router(uploads)
