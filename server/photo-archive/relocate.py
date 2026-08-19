#!/usr/bin/env python3
"""把 20260810 批次从 90_待确认 归入正式分类并改成有意义文件名。
写回滚映射 CSV（沿用历史「重命名记录」机制）。默认 dry-run。"""
import json, os, csv, sqlite3, sys, shutil, collections
from datetime import datetime

ARCH='/Volumes/别动小爷的SSD/影像档案'
R=f'{ARCH}/99_影像检索与报告'
DB=f'{R}/影像数据库.sqlite'
plan=json.load(open('/tmp/bubu_incr/enrich_plan.json'))
con=sqlite3.connect(DB); con.row_factory=sqlite3.Row
cur=con.cursor()
paths={r['uuid']: r['primary_final_path'] for r in
       con.execute("SELECT uuid, primary_final_path FROM assets WHERE import_name=?", (os.environ.get('BUBU_BATCH','增量导入20260810'),))}

moves=[]; problems=collections.Counter(); seen=set()
for p in plan:
    old=paths.get(p['uuid'])
    if not old: problems['无原路径']+=1; continue
    src=os.path.join(ARCH, old)
    if not os.path.isfile(src): problems['源文件不存在']+=1; continue
    dst_rel=p['newrel']
    if dst_rel in seen:                       # 同秒同标签重名兜底
        base,ext=os.path.splitext(dst_rel); dst_rel=f'{base}_{p["uuid"][8:12]}{ext}'
    seen.add(dst_rel)
    dst=os.path.join(ARCH, dst_rel)
    if os.path.exists(dst): problems['目标已存在']+=1; continue
    moves.append((p['uuid'], old, dst_rel, src, dst))

print('待归档 %d / 计划 %d' % (len(moves), len(plan)))
for k,v in problems.most_common(): print('  跳过:', k, v)
print('── 目标目录分布 ──')
for k,v in collections.Counter(os.path.dirname(m[2]) for m in moves).most_common(10):
    print(f'  {v:4d}  {k}')

if '--apply' not in sys.argv:
    print('\n[dry-run] 未移动文件。加 --apply 执行。')
    for _,o,n,_,_ in moves[:3]: print('  ', o, '→', n)
    sys.exit(0)

ts=datetime.now().strftime('%Y%m%d_%H%M%S')
mapping=f'{R}/重命名记录/影像重命名映射_{ts}.csv'
ok=0; failed=[]
with open(mapping,'w',newline='',encoding='utf-8') as f:
    w=csv.writer(f); w.writerow(['uuid','old_relative_path','new_relative_path','new_stem','batch'])
    for uuid,old,new,src,dst in moves:
        try:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(src, dst)
            # exFAT 资源叉伴生文件跟着走，避免在 90_待确认 留下孤儿
            ad_src=os.path.join(os.path.dirname(src), '._'+os.path.basename(src))
            if os.path.isfile(ad_src):
                shutil.move(ad_src, os.path.join(os.path.dirname(dst), '._'+os.path.basename(dst)))
            w.writerow([uuid, old, new, os.path.splitext(os.path.basename(new))[0], os.environ.get('BUBU_BATCH','增量导入20260810')])
            cur.execute('UPDATE assets SET primary_final_path=? WHERE uuid=?', (new, uuid))
            ok+=1
        except Exception as e:
            failed.append((old, type(e).__name__))
con.commit()
print('已归档 %d 个；失败 %d' % (ok, len(failed)))
for o,e in failed[:5]: print('  失败:', o, e)
print('回滚映射:', mapping)
