#!/usr/bin/env python3
"""补全 20260810 增量批次的后半段：内容标签/证件脱敏/女儿判定/分类/命名。
默认 dry-run，加 --apply 才写库。"""
import json, os, re, sqlite3, sys, collections
from datetime import datetime, timedelta

ARCH='/Volumes/别动小爷的SSD/影像档案'
R=ARCH+'/99_影像检索与报告'
DB=f'{R}/影像数据库.sqlite'
IMPORT=os.environ.get('BUBU_BATCH','增量导入20260810')
CONF, MAYBE = 0.55, 0.60

# 英文视觉标签 → 中文（严格对齐历史 auto_tags 词表，阈值 0.20）
MAP = {
 'child':'儿童','baby':'婴儿','crowd':'人群',
 'outdoor':'户外','sky':'天空','blue_sky':'天空','cloudy':'天空',
 'document':'文档','screenshot':'屏幕',
 'bedding':'住宅','housewares':'住宅','interior_room':'住宅','furniture':'住宅','cabinet':'住宅',
 'plant':'植物','tree':'植物','flower':'花卉','food':'美食','restaurant':'餐厅','cake':'蛋糕',
 'vehicle':'车辆','car':'汽车','aircraft':'飞机','airplane':'飞机','train':'火车',
 'building':'建筑','structure':'建筑','computer':'电脑','laptop':'电脑',
 'phone':'手机','mobile_phone':'手机','beach':'海边','sea':'海边','ocean':'海边',
 'night':'夜景','sunset':'日落','snow':'雪景','mountain':'山景','cat':'猫','dog':'狗',
}
ORDER=['文字图片','文档','屏幕','户外','天空','儿童','婴儿','植物','汽车','车辆','建筑','电脑',
       '美食','海边','人群','住宅','夜景','餐厅','日落','猫','雪景','手机','花卉','狗','蛋糕',
       '飞机','山景','火车']

def luhn(s):
    d=[int(c) for c in s][::-1]; t=0
    for i,x in enumerate(d):
        if i%2: x*=2; x-=9 if x>9 else 0
        t+=x
    return t%10==0

ID_W=[7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2]; ID_C='10X98765432'
def valid_id(s):
    if not re.fullmatch(r'\d{17}[\dXx]', s): return False
    return ID_C[sum(int(a)*b for a,b in zip(s[:17],ID_W))%11]==s[17].upper()

def sensitive_scan(text):
    """返回 (document_type, sensitive, has_valid_id)。证件号本身绝不外传/不入文件名。"""
    t=text or ''
    ids=[m for m in re.findall(r'(?<!\d)\d{17}[\dXx](?!\d)', t) if valid_id(m)]
    cards=[m for m in re.findall(r'(?<!\d)\d{16,19}(?!\d)', t) if luhn(m) and not valid_id(m)]
    dt=''
    if ids or ('身份证' in t and ('公民身份' in t or '签发机关' in t)): dt='身份证'
    elif cards or '银行' in t and re.search(r'\d{4}\s?\d{4}\s?\d{4}', t): dt='银行卡'
    elif '驾驶证' in t: dt='驾驶证'
    elif '病历' in t or '门诊' in t and '医院' in t: dt='病历'
    elif '快递' in t or '运单' in t: dt='快递单'
    elif '订单' in t and '金额' in t: dt='订单'
    sens = 1 if (ids or cards or dt in ('身份证','银行卡','驾驶证','病历')) else 0
    return dt, sens, 1 if ids else 0

def exif_gps(path):
    """从原片 EXIF 读经纬度。纯本地解析，不做任何网络请求。"""
    try:
        from PIL import Image
        e = Image.open(path).getexif()
        g = e.get_ifd(0x8825)
        if not g: return None
        def dms(v, ref):
            d = float(v[0]) + float(v[1])/60 + float(v[2])/3600
            return -d if ref in ('S','W') else d
        if 2 in g and 4 in g:
            return dms(g[2], g.get(1,'N')), dms(g[4], g.get(3,'E'))
    except Exception:
        return None
    return None

content={x['file']:x for x in json.load(open('/tmp/bubu_incr/content.json'))}
bubu={x['file']:x for x in json.load(open('/tmp/bubu_incr/bubu_faces.json'))}
for x in json.load(open('/tmp/bubu_incr/bubu_vframes.json')):
    bubu[os.path.splitext(x['file'])[0]]=x     # 视频帧按去扩展名的基名索引

con=sqlite3.connect(DB); con.row_factory=sqlite3.Row
rows=con.execute("SELECT uuid, original_name, captured_at, kind, primary_final_path FROM assets WHERE import_name=?",(IMPORT,)).fetchall()

plan=[]
for r in rows:
    name=r['original_name']; stem=os.path.splitext(name)[0]
    is_video = name.lower().rsplit('.',1)[-1] in ('mp4','mov','m4v')
    c = content.get(name) or content.get(stem+'.jpg') or {}
    b = bubu.get(name) or bubu.get(stem) or {}
    labels=c.get('labels',''); ocr=c.get('ocr','') or ''
    faces=c.get('faces',0)
    lab={}
    for part in labels.split(';'):
        if ':' in part:
            k,v=part.rsplit(':',1)
            try: lab[k]=float(v)
            except ValueError: pass
    tags=set()
    for k,v in lab.items():
        if v>=0.20 and k in MAP: tags.add(MAP[k])
    if ocr.strip(): tags.add('文字图片')
    auto=';'.join([t for t in ORDER if t in tags])
    dtype,sens,hasid=sensitive_scan(ocr)

    bp=b.get('bestPos',-1)
    if 0<=bp<=CONF: dstat='已确认'
    elif 0<=bp<=MAYBE: dstat='相关待确认'
    else: dstat='待确认'

    shot = lab.get('document',0)>=0.5 and lab.get('screenshot',0)>=0.5
    if dstat=='已确认' or dstat=='相关待确认':
        topic='女儿'; cat=('02_视频/01_女儿' if is_video else '01_照片/01_女儿')
    elif shot and faces==0:
        topic='截图'; cat=('02_视频/80_抖音小红书等下载' if is_video else '01_照片/80_截图与网络图片')
    elif faces>0:
        topic=('人物视频' if is_video else ('家庭人物' if faces>=3 else '人物'))
        cat=('02_视频/02_家庭记录' if is_video else '01_照片/02_家庭与人物')
    else:
        topic=('日常视频' if is_video else '日常'); cat=('02_视频/05_日常与其他' if is_video else '01_照片/04_日常生活')

    # 文件名标签（对齐历史）：布布优先 → 视觉标签至多 3 个 → 无标签时用主题兜底词。
    # 敏感证件走「敏感证件_类型」，绝不写入证件号本身（安全规则）。
    parts=[]
    if dstat=='已确认': parts.append('布布')
    if sens:
        parts.append('敏感证件')
        if dtype: parts.append(dtype)
    else:
        for t in ORDER:
            if t in tags and t != '文字图片' and len(parts) < (4 if dstat=='已确认' else 3):
                parts.append(t)
    if not parts:
        parts=[{'日常':'日常','截图':'截图','日常视频':'日常视频','人物视频':'人物视频',
                '家庭视频':'家庭视频','人物':'人物','家庭人物':'家庭人物','女儿':'布布',
                '地点照片':'地点','地点视频':'地点视频'}.get(topic, '日常')]
    dt=datetime.strptime(r['captured_at'],'%Y-%m-%d %H:%M:%S')
    ext=name.rsplit('.',1)[-1].lower()
    newstem='_'.join([dt.strftime('%Y%m%d_%H%M%S')]+parts+[r['uuid'][:8]])
    gps = exif_gps(os.path.join(ARCH, r['primary_final_path'])) if not is_video else None
    plan.append(dict(gps=gps, uuid=r['uuid'], name=name, faces=faces, auto=auto, labels=labels,
                     ocr=ocr, dtype=dtype, sens=sens, hasid=hasid, dstat=dstat,
                     topic=topic, cat=cat, stem=newstem, ext=ext,
                     newrel=f"{cat}/{dt.strftime('%Y/%m')}/{newstem}.{ext}"))

print('计划条目', len(plan))
print('\n── daughter_status ──')
for k,v in collections.Counter(p['dstat'] for p in plan).most_common(): print(f'  {v:4d}  {k}')
print('── topic ──')
for k,v in collections.Counter(p['topic'] for p in plan).most_common(): print(f'  {v:4d}  {k}')
print('── proposed_category ──')
for k,v in collections.Counter(p['cat'] for p in plan).most_common(): print(f'  {v:4d}  {k}')
print('── GPS ──')
print('  可补回坐标:', sum(1 for p in plan if p['gps']))
print('── 敏感/证件 ──')
print('  sensitive:', sum(p['sens'] for p in plan), ' 含有效身份证号:', sum(p['hasid'] for p in plan))
for k,v in collections.Counter(p['dtype'] for p in plan if p['dtype']).most_common(): print(f'  {v:4d}  {k}')
print('── 标签词频 Top12 ──')
c=collections.Counter()
for p in plan:
    for t in p['auto'].split(';'):
        if t: c[t]+=1
for k,v in c.most_common(12): print(f'  {v:4d}  {k}')
print('\n── 命名样例 ──')
for p in plan[:3]+[x for x in plan if x['dstat']=='已确认'][:4]+[x for x in plan if x['sens']][:2]:
    print('  ', p['newrel'])
json.dump(plan, open('/tmp/bubu_incr/enrich_plan.json','w'), ensure_ascii=False)

if '--apply' not in sys.argv:
    print('\n[dry-run] 未写库。加 --apply 执行。'); sys.exit(0)

cur=con.cursor()
cur.execute('BEGIN IMMEDIATE')
for p in plan:
    cur.execute("""INSERT INTO asset_content_index(uuid,ocr_text,document_type,sensitive,auto_tags,
        visual_labels,indexed_at,index_version,error,document_side,contains_valid_id_number)
        VALUES(?,?,?,?,?,?,?,?,'','',?)
        ON CONFLICT(uuid) DO UPDATE SET ocr_text=excluded.ocr_text,document_type=excluded.document_type,
        sensitive=excluded.sensitive,auto_tags=excluded.auto_tags,visual_labels=excluded.visual_labels,
        indexed_at=excluded.indexed_at,index_version=excluded.index_version,
        contains_valid_id_number=excluded.contains_valid_id_number""",
        (p['uuid'],p['ocr'],p['dtype'],p['sens'],p['auto'],p['labels'],
         datetime.now().isoformat(timespec='seconds'),'incr-20260810',p['hasid']))
    cur.execute("""UPDATE assets SET face_count=?, daughter_status=?, topic=?, proposed_category=?,
        proposed_stem=? WHERE uuid=?""",
        (p['faces'],p['dstat'],p['topic'],p['cat'],p['stem'],p['uuid']))
    if p['gps']:
        cur.execute("UPDATE assets SET latitude=?, longitude=?, has_gps=1 WHERE uuid=?",
                    (p['gps'][0], p['gps'][1], p['uuid']))
con.commit()
print('\n已写入数据库：内容索引 %d 条，assets 更新 %d 条' % (len(plan), len(plan)))
