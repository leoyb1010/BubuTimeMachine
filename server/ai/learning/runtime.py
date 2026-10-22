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
def create_features():
    """Online timeline plus the features built on it; empty without a configured person."""
    store,bridge,processor,pocketbase,timeline,family,child=components()
    subject=os.environ.get("LEARNING_SUBJECT_ID","").strip()
    if not subject:return {}
    from .online_timeline import OnlineTimeline, SemanticGateway
    from .memories import Memories
    from .firsts import Firsts
    from .monthly import Monthly
    from .voices import Voices
    from .recognition import Recognition
    born=os.environ.get("LEARNING_SUBJECT_BIRTH_DATE","").strip() or None
    gateway=SemanticGateway(bridge.root/'data/gateway-private.json',
                            os.environ.get('LEARNING_GATEWAY_URL','').strip() or 'http://127.0.0.1:8878')
    online=OnlineTimeline(bridge,processor,store,family,child,subject,born=born,semantic=gateway)
    firsts=Firsts(online)
    return {'online_timeline':online,'memories':Memories(online),'firsts':firsts,
            'monthly':Monthly(online,bridge,firsts),'voices':Voices(online,bridge,processor),
            'recognition':Recognition(bridge,online)}


FEATURES=('online_timeline','memories','firsts','monthly','voices','recognition')


@lru_cache(maxsize=1)
def get_service():
    from .service import LearningService
    store,bridge,processor,pocketbase,timeline,family,child=components()
    service=LearningService(store,processor,brain_sync=timeline,pocketbase=pocketbase)
    # Without a configured person these routes answer 503; courses keep working.
    features=create_features()
    for name in FEATURES:setattr(service,name,features.get(name))
    return service


def create_worker():
    from .worker import LearningWorker
    store,bridge,processor,pocketbase,timeline,family,child=components()
    return LearningWorker(store,bridge,processor,family=family,child=child,pocketbase=pocketbase,
                          subject=os.environ.get("LEARNING_SUBJECT_ID","").strip() or None,
                          features=create_features())
