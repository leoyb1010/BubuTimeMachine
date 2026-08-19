#!/usr/bin/env python3
"""把档案库里已判定为布布的素材，按事件批次推进「时光」（PocketBase Entry+Media）。
复用既有 intake staging + loopback commit hook：去重与幂等闸全部沿用，不新造协议。
默认 dry-run；--apply 执行；--limit N 只做前 N 批（首次验证用）。"""
import os, sys, json, uuid, shutil, sqlite3, tempfile, hashlib, collections
from datetime import datetime, timedelta
from pathlib import Path

AI='/Users/leo/BubuTimeMachineServer/releases/v2.8.0-candidate/server/ai'
sys.path.insert(0, AI)
for line in open(f'{AI}/.env'):                      # 载入既有配置（不打印任何值）
    line=line.strip()
    if line and not line.startswith('#') and '=' in line:
        k,v=line.split('=',1); os.environ.setdefault(k, v.strip().strip('"').strip("'"))

import httpx
from intake_staging import IntakeStagingStore, IntakeItem

ARCH='/Volumes/别动小爷的SSD/影像档案'
DB=f'{ARCH}/99_影像检索与报告/影像数据库.sqlite'
LEDGER=f'{ARCH}/99_影像检索与报告/整理报告/已推送时光.json'
GAP=timedelta(minutes=90)
MIME={'jpg':'image/jpeg','jpeg':'image/jpeg','heic':'image/heic','png':'image/png',
      'mp4':'video/mp4','mov':'video/quicktime','m4v':'video/x-m4v'}

owner_ids=[x.strip() for x in os.environ.get('INTAKE_ALLOWED_PB_USER_IDS','').split(',') if x.strip()]
if not owner_ids: sys.exit('INTAKE_ALLOWED_PB_USER_IDS 未配置')
OWNER=owner_ids[0] if owner_ids[0].startswith('pb:') else 'pb:'+owner_ids[0]
FAMILY=os.environ['INTAKE_FAMILY_ID']

done=set(json.load(open(LEDGER))) if os.path.isfile(LEDGER) else set()
con=sqlite3.connect(DB); con.row_factory=sqlite3.Row
rows=con.execute("""SELECT a.uuid,a.captured_at,a.primary_final_path,a.original_bytes,a.proposed_stem,
                    m.sha256 FROM assets a LEFT JOIN media_files m ON m.uuid=a.uuid
                    WHERE a.daughter_status IN ('已确认','相关待确认')
                      AND a.import_name=:b
                    ORDER BY a.captured_at""", {'b': os.environ.get('BUBU_BATCH','增量导入20260810')}).fetchall()
items=[r for r in rows if r['uuid'] not in done]
print('布布素材 %d，未推送 %d' % (len(rows), len(items)))

batches=[]
for r in items:
    dt=datetime.strptime(r['captured_at'],'%Y-%m-%d %H:%M:%S')
    if batches and dt-batches[-1][-1][1] <= GAP: batches[-1].append((r,dt))
    else: batches.append([(r,dt)])
print('聚成 %d 个时光批次' % len(batches))
limit=int(sys.argv[sys.argv.index('--limit')+1]) if '--limit' in sys.argv else len(batches)
batches=batches[:limit]
for b in batches:
    print('  %s  %d 个素材' % (b[0][1].strftime('%Y-%m-%d %H:%M'), len(b)))
if '--apply' not in sys.argv:
    print('\n[dry-run] 未推送。加 --apply 执行。'); sys.exit(0)

store=IntakeStagingStore()
commit_key=os.environ['INTAKE_COMMIT_KEY']
pb=os.environ.get('PB_BASE_URL','http://127.0.0.1:8090').rstrip('/')
pushed=[]
for b in batches:
    bid=uuid.uuid4().hex                      # hook 要求 [A-Za-z0-9_-]{8,128}
    entry_local=str(uuid.uuid4())
    first=b[0][1]
    entry={'local_id':entry_local,'happened_at':first.isoformat(),'author_role':'爸爸',
           'note':'','title':'','location_name':'','source':'ssd-archive-incr'}
    ii=[]
    for r,dt in b:
        ext=r['primary_final_path'].rsplit('.',1)[-1].lower()
        ii.append(IntakeItem(asset_key=r['uuid'], file_name=os.path.basename(r['primary_final_path']),
                             media_type='video' if ext in ('mp4','mov','m4v') else 'photo',
                             captured_at=dt.isoformat(), expected_size=0,
                             expected_mime=MIME.get(ext,'application/octet-stream'),
                             resource_role='display', asset_group_id=r['uuid']))
    store.create_batch(bid, OWNER, FAMILY, entry, ii)
    staged=0
    for r,dt in b:
        src=os.path.join(ARCH, r['primary_final_path'])
        digest=r['sha256']
        if not digest:
            h=hashlib.sha256()
            with open(src,'rb') as f:
                for blk in iter(lambda: f.read(1<<20), b''): h.update(blk)
            digest=h.hexdigest()
        with tempfile.NamedTemporaryFile(delete=False,
                dir=str(store.root), suffix=os.path.splitext(src)[1]) as tf:
            tmp=Path(tf.name)
        shutil.copyfile(src, tmp)
        store.stage_file(bid, r['uuid'], tmp, digest, os.path.getsize(src))
        staged+=1
    manifest=store.begin_commit(bid, OWNER)
    resp=httpx.post(pb+'/api/bubu/intake/commit', json=manifest,
                    headers={'X-Bubu-Intake-Key':commit_key}, timeout=300, trust_env=False)
    if resp.status_code not in (200,201):
        print('  ✗ %s commit 失败 %s' % (first.strftime('%m-%d %H:%M'), resp.status_code)); continue
    eid=str((resp.json() or {}).get('entry_id') or '')
    store.finish_commit(bid, OWNER, eid)
    pushed += [r['uuid'] for r,_ in b]
    print('  ✓ %s  %d 个 → Entry %s' % (first.strftime('%m-%d %H:%M'), staged, eid[:12]))

done |= set(pushed)
os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
json.dump(sorted(done), open(LEDGER,'w'))
print('本次推送 %d 个素材，累计 %d' % (len(pushed), len(done)))
