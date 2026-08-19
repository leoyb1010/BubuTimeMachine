#!/usr/bin/env python3
"""生成本批缩略图（420 长边，与历史一致）并把 572 条追加进检索网页数据。
历史条目原样保留，只追加本批。"""
import os, json, sqlite3, subprocess, shutil
from datetime import datetime
ARCH='/Volumes/别动小爷的SSD/影像档案'; R=f'{ARCH}/99_影像检索与报告'
DB=f'{R}/影像数据库.sqlite'
con=sqlite3.connect(DB); con.row_factory=sqlite3.Row
rows=con.execute("""SELECT a.*, c.ocr_text, c.document_type, c.document_side, c.sensitive,
                    c.contains_valid_id_number, c.auto_tags
                    FROM assets a LEFT JOIN asset_content_index c ON c.uuid=a.uuid
                    WHERE a.import_name=:b""", {'b': os.environ.get('BUBU_BATCH','增量导入20260810')}).fetchall()
print('本批', len(rows))

from PIL import Image
made=0; failed=0
cur=con.cursor()
for r in rows:
    uuid=r['uuid']; rel=f"缩略图/{uuid[:2].upper()}/{uuid}.jpg"
    out=os.path.join(R, rel)
    if os.path.isfile(out):
        cur.execute('UPDATE assets SET thumbnail_relative_path=? WHERE uuid=?',(rel,uuid)); continue
    os.makedirs(os.path.dirname(out), exist_ok=True)
    src=os.path.join(ARCH, r['primary_final_path'])
    try:
        if r['primary_final_path'].lower().rsplit('.',1)[-1] in ('mp4','mov','m4v'):
            subprocess.run(['ffmpeg','-v','quiet','-ss','1','-i',src,'-frames:v','1',
                            '-vf','scale=420:-1','-q:v','4',out,'-y'],check=True,timeout=90)
        else:
            im=Image.open(src); im.draft('RGB',(840,840)); im=im.convert('RGB')
            im.thumbnail((420,420)); im.save(out,'JPEG',quality=82)
        cur.execute('UPDATE assets SET thumbnail_relative_path=? WHERE uuid=?',(rel,uuid))
        made+=1
    except Exception:
        failed+=1
con.commit()
print('缩略图新建 %d，失败 %d' % (made, failed))

# 追加进检索数据
path=f'{R}/影像数据.json'
shutil.copy2(path, f'{R}/清理记录/影像数据_增量前_{datetime.now():%Y%m%d_%H%M%S}.json')
d=json.load(open(path))
have={i['u'] for i in d['items']}
add=0
for r in rows:
    if r['uuid'] in have: continue
    isv = r['primary_final_path'].lower().rsplit('.',1)[-1] in ('mp4','mov','m4v')
    d['items'].append({
        'u': r['uuid'], 'd': r['captured_at'], 't': '视频' if isv else '照片',
        'duration': r['duration'] or 0.0, 'n': r['original_name'],
        'display': r['proposed_stem'], 'bytes': r['original_bytes'] or 0,
        'w': r['width'] or 0, 'h': r['height'] or 0, 'loc': '', 'locF': '',
        'da': r['daughter_status'], 'f': r['face_count'] or 0, 'adjusted': 0,
        'flags': r['review_flags'] or '', 'c': r['proposed_category'],
        'topic': r['topic'], 'source': '增量导入20260810', 'people': '',
        'ocr': (r['ocr_text'] or '')[:2000], 'doc': r['document_type'] or '',
        'docSide': r['document_side'] or '', 'hasIdNumber': r['contains_valid_id_number'] or 0,
        'sensitive': r['sensitive'] or 0,
    }); add+=1
d['generated_at']=datetime.now().isoformat(timespec='seconds')
d['items'].sort(key=lambda x: x['d'] or '')
tmp=path+'.tmp'
json.dump(d, open(tmp,'w'), ensure_ascii=False, separators=(',',':'))
os.replace(tmp, path)
print('检索数据追加 %d 条，现共 %d 条' % (add, len(d['items'])))
