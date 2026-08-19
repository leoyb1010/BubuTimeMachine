#!/usr/bin/env python3
"""阶段1：把待导入目录里的新素材扫描去重后收进档案库待确认区并登记入库。
只读源目录（不移动不删除用户的原始文件），SHA256 与全库比对，已存在的直接跳过。"""
import os, sys, uuid, shutil, sqlite3, hashlib, subprocess, collections
from datetime import datetime

ARCH='/Volumes/别动小爷的SSD/影像档案'
DB=f'{ARCH}/99_影像检索与报告/影像数据库.sqlite'
SUPPORTED={'.jpg':'photo','.jpeg':'photo','.heic':'photo','.heif':'photo','.png':'photo',
           '.gif':'photo','.webp':'photo','.dng':'photo',
           '.mov':'video','.mp4':'video','.m4v':'video'}
NS=uuid.UUID('8c7191cc-2b65-46ff-a376-2623f89c50e0')

def sha256(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for blk in iter(lambda: f.read(1<<20), b''): h.update(blk)
    return h.hexdigest()

def local_capture(path, ext):
    """本地拍摄时间。EXIF/容器元数据优先，取不到退回文件修改时间。
    注意：视频容器 creation_time 是 UTC，必须 +8 转本地，否则整批差 8 小时。"""
    if ext in ('.mp4','.mov','.m4v'):
        try:
            out=subprocess.run(['ffprobe','-v','quiet','-show_entries',
                'format_tags=creation_time','-of','default=nw=1:nk=1',path],
                capture_output=True, text=True, timeout=60).stdout.strip()
            if out:
                dt=datetime.strptime(out[:19],'%Y-%m-%dT%H:%M:%S')
                return dt.timestamp()+8*3600 and datetime.fromtimestamp(
                    dt.replace(tzinfo=None).timestamp()).timestamp()+0 or None
        except Exception: pass
        try:
            from datetime import timedelta
            dt=datetime.strptime(out[:19],'%Y-%m-%dT%H:%M:%S')+timedelta(hours=8)
            return dt
        except Exception: pass
    else:
        try:
            from PIL import Image
            e=Image.open(path).getexif()
            v=e.get(36867) or e.get(306)
            if v: return datetime.strptime(str(v)[:19],'%Y:%m:%d %H:%M:%S')
        except Exception: pass
    return datetime.fromtimestamp(os.path.getmtime(path))

def main(inbox, apply=False):
    if not os.path.isdir(inbox): sys.exit(f'待导入目录不存在: {inbox}')
    con=sqlite3.connect(DB); con.row_factory=sqlite3.Row
    known={r[0] for r in con.execute('SELECT sha256 FROM media_files WHERE sha256<>""')}
    import_name='增量导入'+datetime.now().strftime('%Y%m%d_%H%M%S')
    found=[]; skipped=collections.Counter()
    for dp,dns,fns in os.walk(inbox):
        dns[:]=[d for d in dns if not d.startswith('.')]
        for fn in sorted(fns):
            if fn.startswith('.'): skipped['隐藏/资源叉']+=1; continue   # exFAT 的 ._ 伴生文件
            ext=os.path.splitext(fn)[1].lower()
            if ext not in SUPPORTED: skipped['不支持的类型']+=1; continue
            p=os.path.join(dp,fn)
            d=sha256(p)
            if d in known: skipped['已在档案库']+=1; continue
            known.add(d)
            found.append((p, fn, ext, d))
    print(f'待导入目录: {inbox}')
    print(f'新素材 {len(found)} 个')
    for k,v in skipped.most_common(): print(f'  跳过 {k}: {v}')
    os.makedirs('/tmp/bubu_incr', exist_ok=True)
    if not found or not apply:
        if found and not apply: print('\n[dry-run] 未写入。加 --apply 执行。')
        return found
    cur=con.cursor(); n=0
    for p, fn, ext, d in found:
        u=str(uuid.uuid5(NS, d)).upper()
        dt=local_capture(p, ext)
        kind=0 if SUPPORTED[ext]=='photo' else 1
        sub='01_照片/90_待确认' if kind==0 else '02_视频/90_待确认与待清理'
        rel=f"{sub}/{dt.strftime('%Y/%m')}/{dt.strftime('%Y%m%d_%H%M%S')}_{d[:8].upper()}{ext}"
        dst=os.path.join(ARCH, rel)
        if os.path.exists(dst):
            base,e2=os.path.splitext(rel); rel=f'{base}_{u[:4]}{e2}'; dst=os.path.join(ARCH, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(p, dst)                       # 复制，不动用户源文件
        w=h=0
        if kind==0:
            try:
                from PIL import Image
                w,h=Image.open(dst).size
            except Exception: pass
        cur.execute("""INSERT OR IGNORE INTO assets(uuid,kind,captured_at,original_name,
            original_bytes,width,height,import_name,timezone,face_count,daughter_status,
            proposed_category,topic,review_flags,primary_final_path,has_gps,exact_duplicate)
            VALUES(?,?,?,?,?,?,?,?,'Asia/Shanghai',0,'待确认',?,'','新增待处理',?,0,0)""",
            (u,kind,dt.strftime('%Y-%m-%d %H:%M:%S'),os.path.basename(rel),
             os.path.getsize(dst),w,h,import_name,sub,rel))
        cur.execute("""INSERT OR REPLACE INTO media_files(relative_path,uuid,sha256,bytes,
            extension,edited,exact_duplicate,proposed_relative_path,final_relative_path,move_status)
            VALUES(?,?,?,?,?,0,0,?,?,'moved')""",
            (rel,u,d,os.path.getsize(dst),ext.lstrip('.'),rel,rel))
        n+=1
    con.commit()
    open('/tmp/bubu_incr/batch.txt','w').write(import_name)
    print(f'已收进待确认区并登记 {n} 个（import_name={import_name}）')
    return found

if __name__=='__main__':
    inbox=sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('--') \
          else f'{ARCH}/00_导入暂存/iPhone_待导入'
    main(inbox, '--apply' in sys.argv)
