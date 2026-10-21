"""PocketBase family sessions for learning, separate from maintenance capabilities.

The browser receives only an HttpOnly cookie. Every protected request refreshes
PocketBase identity and reads current family children; no authorization cache.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
import secrets
from typing import Callable

import httpx
from fastapi import HTTPException, Request

SESSION_COOKIE = 'bubu_learning_session'
SESSION_SECONDS = 7 * 24 * 60 * 60


def _members(name: str) -> set[str]:
    return {part.strip() for part in os.environ.get(name, '').split(',') if part.strip()}


@dataclass(frozen=True)
class FamilyScope:
    user_id: str
    family_id: str
    children: list[dict]
    can_review: bool

    def require_child(self, child_id: str | None) -> str:
        """Resolve an omitted child or reject any child outside the fresh scope."""
        if child_id is None:
            if not self.children:
                raise HTTPException(403, '请先关联孩子资料。')
            return self.children[0]['id']
        if child_id not in {child['id'] for child in self.children}:
            raise HTTPException(403, '没有访问这个孩子的权限。')
        return child_id

    def require_review(self) -> None:
        if not self.can_review:
            raise HTTPException(403, '当前账号没有核对和发布课程的权限。')


def require_csrf(request: Request) -> None:
    """Custom header is required for cookie/unauthenticated writes, never URL tokens."""
    if request.method not in {'POST', 'PUT', 'PATCH', 'DELETE'}:
        return
    authorization = request.headers.get('authorization', '')
    if authorization.lower().startswith('bearer ') and authorization[7:].strip():
        return
    if request.headers.get('x-bubu-learning') != '1':
        raise HTTPException(403, '请从家庭学习页面发起操作。')


class PocketBaseAuthenticator:
    def __init__(self, client_factory: Callable | None = None):
        self.client_factory = client_factory or (lambda: httpx.Client(timeout=5, trust_env=False, follow_redirects=False))

    @property
    def base_url(self) -> str:
        return (os.environ.get('PB_BASE_URL', '') or '').strip().rstrip('/') or 'http://127.0.0.1:8090'

    def _verify_token_shape(self, token: str) -> None:
        if not isinstance(token, str) or not token or len(token) > 8192 or any(not 33 <= ord(c) <= 126 for c in token):
            raise HTTPException(401, '请登录家庭账号。')
        for name in ('AI_API_KEY', 'SCHOOL_VISION_TOKEN'):
            configured = os.environ.get(name, '')
            if configured and secrets.compare_digest(token.encode(), configured.encode()):
                raise HTTPException(401, '请使用家庭账号登录。')

    def _record_scope(self, data: dict, client: httpx.Client, token: str) -> FamilyScope:
        record = data.get('record')
        if not isinstance(record, dict):
            raise HTTPException(401, '登录信息无效，请重新登录。')
        user_id, family = record.get('id'), record.get('familyId')
        if not isinstance(user_id, str) or not user_id or not isinstance(family, str) or not family.strip():
            raise HTTPException(403, '账号尚未绑定家庭。')
        if len(user_id) > 128 or len(family) > 128 or user_id not in _members('AI_ALLOWED_PB_USER_IDS'):
            raise HTTPException(403, '当前账号没有访问学习服务的权限。')
        configured = {os.environ.get(name, '').strip() for name in (
            'LEARNING_FAMILY_ID', 'INTAKE_FAMILY_ID', 'SEMANTIC_FAMILY_ID',
            'WEEKLY_REPORT_FAMILY_ID', 'SOUND_RING_FAMILY_ID') if os.environ.get(name, '').strip()}
        if len(configured) > 1:
            raise HTTPException(503, '服务配置暂不可用，请联系管理员。')
        if configured and family not in configured:
            raise HTTPException(403, '账号不属于这个家庭。')
        children, seen = [], set()
        for page in range(1, 11):
            response = client.get(self.base_url + '/api/collections/childprofile/records',
                headers={'Authorization': 'Bearer ' + token},
                params={'filter': 'familyId = ' + json.dumps(family, ensure_ascii=False), 'page': page, 'perPage': 200})
            self._check_response(response)
            try:
                body = response.json()
                items, pages = body['items'], int(body.get('totalPages', 1))
                if not isinstance(items, list) or pages > 10:
                    raise ValueError()
            except (ValueError, TypeError, KeyError, AttributeError):
                raise HTTPException(503, '暂时无法读取孩子资料。') from None
            for child in items:
                if not isinstance(child, dict) or child.get('familyId') != family:
                    continue
                if child.get('isDeleted') or child.get('deletedAt') or child.get('deleted'):
                    continue
                identifier = child.get('localId') or child.get('id')
                if isinstance(identifier, str) and identifier and len(identifier) <= 128 and identifier not in seen:
                    seen.add(identifier)
                    children.append({'id': identifier, 'name': str(child.get('name') or '孩子')[:100]})
            if page >= pages:
                break
        configured_child = os.environ.get('LEARNING_CHILD_ID', '').strip()
        if configured_child:
            # Keep historical profiles intact. The configured learning child
            # must first survive the current PB family/deletion checks above.
            children = [child for child in children if child['id'] == configured_child]
            if not children:
                raise HTTPException(503, '学习孩子配置暂不可用，请联系管理员核对。')
        reviewer_name = 'LEARNING_REVIEWER_USER_IDS' if 'LEARNING_REVIEWER_USER_IDS' in os.environ else 'INTAKE_ALLOWED_PB_USER_IDS'
        return FamilyScope(user_id=user_id, family_id=family, children=children,
                           can_review=user_id in _members(reviewer_name))

    @staticmethod
    def _check_response(response: httpx.Response) -> None:
        if response.status_code in {429, 500, 502, 503, 504}:
            raise HTTPException(503, '登录服务暂忙，请稍后再试。')
        if response.status_code != 200:
            raise HTTPException(401, '登录已失效，请重新登录。')

    def verify(self, token: str) -> tuple[FamilyScope, str]:
        self._verify_token_shape(token)
        try:
            with self.client_factory() as client:
                response = client.post(self.base_url + '/api/collections/users/auth-refresh',
                                       headers={'Authorization': 'Bearer ' + token})
                self._check_response(response)
                try:
                    data = response.json()
                    renewed = data.get('token') or token
                except (ValueError, AttributeError):
                    raise HTTPException(401, '登录信息无效，请重新登录。') from None
                self._verify_token_shape(renewed)
                scope = self._record_scope(data, client, renewed)
                return scope, renewed
        except httpx.HTTPError:
            raise HTTPException(503, '暂时连接不到登录服务，请稍后重试。') from None

    def authenticate(self, request: Request, *, optional: bool = False) -> FamilyScope | None:
        authorization = request.headers.get('authorization')
        if authorization is not None:
            if not authorization.lower().startswith('bearer '):
                raise HTTPException(401, '请使用家庭账号登录。')
            token = authorization[7:].strip()
        else:
            token = request.cookies.get(SESSION_COOKIE)
        if not token:
            if optional and authorization is None:
                return None
            raise HTTPException(401, '请登录家庭账号。')
        require_csrf(request)
        scope, renewed = self.verify(token)
        request.state.learning_token = renewed
        return scope

    def login(self, identity: str, password: str) -> tuple[FamilyScope, str]:
        try:
            with self.client_factory() as client:
                response = client.post(self.base_url + '/api/collections/users/auth-with-password',
                                       json={'identity': identity, 'password': password})
                if response.status_code in {429, 500, 502, 503, 504}:
                    raise HTTPException(503, '登录服务暂忙，请稍后再试。')
                if response.status_code != 200:
                    raise HTTPException(401, '账号或密码不正确。')
                try:
                    token = response.json()['token']
                except (ValueError, TypeError, KeyError):
                    raise HTTPException(401, '登录信息无效，请重新登录。') from None
            # Login has the same allowlist/family/child verification as native Bearer.
            return self.verify(token)
        except httpx.HTTPError:
            raise HTTPException(503, '暂时连接不到登录服务，请稍后重试。') from None
