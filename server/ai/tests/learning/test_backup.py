from pathlib import Path
import sys
import sqlite3
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from learning.store import LearningStore
from learning.backup import backup

def test_export_preserves_evidence_and_valid_database(tmp_path):
    store=LearningStore(tmp_path/'source')
    source=store.add_source('f','c','2026-10-20','input','card.jpg',b'evidence','image/jpeg')
    result=backup(store.root,tmp_path/'backup')
    assert result=={'assets':1}
    with sqlite3.connect(tmp_path/'backup/learning.sqlite') as db:
        assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    asset=store.asset('f',source['asset_id'])
    assert (tmp_path/'backup'/asset['path']).read_bytes()==b'evidence'

def test_backup_refuses_nested_or_unrelated_nonempty_target(tmp_path):
    store=LearningStore(tmp_path/'source')
    with pytest.raises(ValueError):backup(store.root,store.root/'nested')
    target=tmp_path/'existing';target.mkdir();(target/'user.txt').write_text('keep')
    with pytest.raises(ValueError):backup(store.root,target)
    assert (target/'user.txt').read_text()=='keep'

def test_backup_never_follows_manifest_symlink(tmp_path):
    store=LearningStore(tmp_path/'source')
    store.add_source('f','c','2026-10-20','input','card.jpg',b'evidence','image/jpeg')
    target=tmp_path/'backup';backup(store.root,target)
    outside=tmp_path/'unrelated.txt';outside.write_text('KEEP')
    (target/'manifest.json').unlink();(target/'manifest.json').symlink_to(outside)
    with pytest.raises(ValueError):backup(store.root,target)
    assert outside.read_text()=='KEEP'


def test_failed_copy_preserves_previous_good_backup_file(tmp_path,monkeypatch):
    import shutil
    store=LearningStore(tmp_path/'source')
    source=store.add_source('f','c','2026-10-20','input','card.jpg',b'evidence','image/jpeg')
    target=tmp_path/'backup';backup(store.root,target)
    asset=store.asset('f',source['asset_id']);original=store.asset_path('f',asset['id'])
    saved=target/asset['path'];normal_copy=shutil.copyfile
    def interrupted(src,dst,*args,**kwargs):
        if Path(src)==original:
            Path(dst).write_bytes(b'partial')
            raise OSError('simulated disk interruption')
        return normal_copy(src,dst,*args,**kwargs)
    monkeypatch.setattr(shutil,'copyfile',interrupted)
    with pytest.raises(OSError):backup(store.root,target)
    assert saved.read_bytes()==b'evidence'


def test_backup_refuses_missing_derived_evidence_referenced_by_snapshot(tmp_path):
    store=LearningStore(tmp_path/'source')
    source=store.add_source('f','c','2026-10-20','input','card.jpg',b'evidence','image/jpeg')
    store.set_analysis('f',source['asset_id'],{'frames':[{'time':0,'resource':'a'*64+'.jpg'}]})
    with pytest.raises(ValueError):backup(store.root,tmp_path/'backup')
    assert not (tmp_path/'backup/learning.sqlite').exists()

def test_backup_keeps_referenced_resources_but_skips_uncommitted_worker_staging(tmp_path):
    import hashlib
    store=LearningStore(tmp_path/'source')
    source=store.add_source('f','c','2026-10-20','input','card.jpg',b'evidence','image/jpeg')
    data=b'valid derived frame';name=hashlib.sha256(data).hexdigest()+'.jpg'
    directory=store.root/'derived'/hashlib.sha256(b'f').hexdigest()[:24];directory.mkdir(parents=True)
    (directory/name).write_bytes(data);(directory/'.resource-interrupted.tmp').write_bytes(b'partial')
    store.set_analysis('f',source['asset_id'],{'frames':[{'time':0,'resource':name}]})
    target=tmp_path/'backup';backup(store.root,target)
    assert (target/'derived'/directory.name/name).read_bytes()==data
    assert not (target/'derived'/directory.name/'.resource-interrupted.tmp').exists()
