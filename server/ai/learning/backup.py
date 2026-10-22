"""Export a consistent learning snapshot with originals and derived evidence."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import sqlite3
import tempfile

RESOURCE_NAME = re.compile(r'[a-f0-9]{64}\.(jpg|m4a)')


def _sha256(path: Path) -> str:
    checksum=hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda:source.read(1024*1024),b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def _copy_verified(original: Path, final: Path, expected_hash: str) -> None:
    """An interruption or mutation must never truncate the previous good backup."""
    if final.is_symlink():raise ValueError('备份目标文件不能是软链接')
    # Unchanged evidence stays as is (it may be a hard link shared with an older daily copy).
    if final.is_file() and _sha256(final)==expected_hash:return
    final.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    fd,name=tempfile.mkstemp(prefix='.copy-',suffix='.tmp',dir=final.parent)
    os.close(fd);staging=Path(name)
    try:
        shutil.copyfile(original,staging)
        if _sha256(staging)!=expected_hash:raise ValueError('学习证据复制校验失败')
        staging.chmod(0o600)
        with staging.open('rb') as handle:os.fsync(handle.fileno())
        os.replace(staging,final)
    finally:
        staging.unlink(missing_ok=True)


def _references(value):
    if isinstance(value,dict):
        for key,item in value.items():
            if key in {'audio_resource','image_resource','resource'} and isinstance(item,str) and item:
                if not RESOURCE_NAME.fullmatch(item):raise ValueError('派生证据引用无效')
                yield item
            elif isinstance(item,(dict,list)):
                yield from _references(item)
    elif isinstance(value,list):
        for item in value:yield from _references(item)


def backup(source: Path, destination: Path):
    source=Path(source).resolve(strict=True)
    destination=Path(destination)
    if destination.is_symlink():raise ValueError('学习备份目录不能是软链接')
    destination=destination.resolve()
    if destination==source or destination.is_relative_to(source) or source.is_relative_to(destination):
        raise ValueError('学习备份源与目标必须彼此独立')
    database=source/'learning.sqlite'
    if database.is_symlink() or not database.is_file():raise ValueError('学习状态库不存在或路径异常')
    destination.mkdir(parents=True,exist_ok=True,mode=0o700)
    sentinel=destination/'.bubu-learning-backup'
    if sentinel.is_symlink() or (destination/'manifest.json').is_symlink():
        raise ValueError('学习备份标记或清单不能是软链接')
    if not sentinel.exists():
        if any(destination.iterdir()):raise ValueError('学习备份目标非空且没有专用标记')
        with sentinel.open('x') as handle:handle.write('bubu-learning-v1\n')
        sentinel.chmod(0o600)
    if sentinel.read_text()!='bubu-learning-v1\n':raise ValueError('学习备份标记无效')
    with tempfile.TemporaryDirectory(prefix='bubu-learning-backup-') as tmp:
        snapshot=Path(tmp)/'learning.sqlite'
        expected_resources=set()
        with sqlite3.connect(database.as_uri()+'?mode=ro',uri=True) as src,sqlite3.connect(snapshot) as target:
            src.backup(target)
            if target.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise ValueError('学习库完整性检查失败')
            assets=target.execute('SELECT path,hash FROM assets').fetchall()
            tables={row[0] for row in target.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            for table in ('packs','analyses','analysis_history'):
                if table not in tables:continue
                for family,payload in target.execute('SELECT family_id,payload FROM '+table):
                    folder=hashlib.sha256(family.encode()).hexdigest()[:24]
                    expected_resources.update((folder,name) for name in _references(json.loads(payload)))
        for relative,sha in assets:
            original=(source/relative).resolve(strict=True)
            if not original.is_relative_to(source/'originals'):raise ValueError('学习原件路径异常')
            final=destination/relative
            if not final.resolve().is_relative_to(destination):raise ValueError('备份原件路径异常')
            _copy_verified(original,final,sha)
        derived=source/'derived';copied_resources=set()
        if derived.is_symlink():raise ValueError('派生产物目录异常')
        if derived.exists():
            for directory in derived.iterdir():
                if directory.is_symlink() or not directory.is_dir() or not re.fullmatch(r'[a-f0-9]{24}',directory.name):
                    raise ValueError('派生产物家庭目录异常')
                for original in directory.iterdir():
                    if original.is_symlink() or not original.is_file():raise ValueError('派生产物路径异常')
                    # A running/crashed worker's private staging file is not evidence.
                    if original.name.startswith('.resource-') and original.suffix=='.tmp':continue
                    if not RESOURCE_NAME.fullmatch(original.name):raise ValueError('派生产物编号异常')
                    final=destination/original.relative_to(source)
                    if not final.resolve().is_relative_to(destination):raise ValueError('备份派生产物路径异常')
                    _copy_verified(original,final,original.stem)
                    copied_resources.add((directory.name,original.name))
        if expected_resources-copied_resources:
            raise ValueError('学习快照引用的原声或图片证据缺失，未发布此备份')
        # Commit the database only after every file it references is present.
        _copy_verified(snapshot,destination/'learning.sqlite',_sha256(snapshot))
        manifest=Path(tmp)/'manifest.json'
        # completed_at makes every successful run visible (status reads this file's mtime as backup_at).
        manifest.write_text(json.dumps({'schema':1,'assets':len(assets),'sqlite_integrity':'ok',
                                        'completed_at':datetime.now(timezone.utc).isoformat(timespec='seconds')}))
        _copy_verified(manifest,destination/'manifest.json',_sha256(manifest))
    return {'assets':len(assets)}

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--destination',type=Path,required=True)
    args=parser.parse_args();backup(args.source,args.destination)
