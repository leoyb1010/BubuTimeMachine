"""Explicit opt-in wiring. Importing the API never starts polling or model calls."""
from functools import lru_cache
import os
from pathlib import Path
from fastapi import HTTPException
from .brain_bridge import BrainBridge
from .brain_sync import BrainSyncService, PocketBaseTimelineWriter
from .processing import MediaProcessor
from .store import LearningStore


def enabled(name):
    return os.environ.get(name,'').strip().lower() in {'1','true','yes','on'}


def required(name):
    value=os.environ.get(name,'').strip()
    if not value:raise RuntimeError('学习服务配置不完整：'+name)
    return value


@lru_cache(maxsize=1)
def components():
    if not enabled('LEARNING_ENABLED'):
        raise HTTPException(503,'家庭学习尚未启用。')
    family,child=required('LEARNING_FAMILY_ID'),required('LEARNING_CHILD_ID')
    if child=='__media_analysis__':raise RuntimeError('孩子编号不能使用内部保留值')
    store=LearningStore(Path(required('LEARNING_STATE_DIR')))
    bridge=BrainBridge(Path(required('LEARNING_BRAIN_ROOT')),
                       python_executable=required('LEARNING_BRAIN_PYTHON'))
    processor=MediaProcessor(store,bridge)
    from memory_query import PocketBaseMemoryStore
    pocketbase=PocketBaseMemoryStore()
    timeline=None
    if enabled('LEARNING_TIMELINE_ENABLED'):
        writer=PocketBaseTimelineWriter(family,required('LEARNING_AUTHOR_USER_ID'),
                                       required('LEARNING_AUTHOR_ROLE'),store=pocketbase)
        timeline=BrainSyncService(bridge,store,writer,family,child,required('LEARNING_SUBJECT_ID'))
    return store,bridge,processor,pocketbase,timeline,family,child


@lru_cache(maxsize=1)
def get_service():
    from .service import LearningService
    store,bridge,processor,pocketbase,timeline,family,child=components()
    return LearningService(store,processor,brain_sync=timeline,pocketbase=pocketbase)


def create_worker():
    from .worker import LearningWorker
    store,bridge,processor,pocketbase,timeline,family,child=components()
    inbox=os.environ.get('LEARNING_INBOX','').strip()
    return LearningWorker(store,bridge,processor,family=family,child=child,
                          since_day=required('LEARNING_SINCE_DATE'),
                          inbox=Path(inbox) if inbox else None,timeline=timeline,pocketbase=pocketbase)
