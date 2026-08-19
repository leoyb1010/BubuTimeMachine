#!/usr/bin/env python3
"""阶段3：对本批跑端侧 Vision——内容识别（分类/OCR/人脸）+ 布布身份识别。
参考集自动从档案库已确认的女儿照片抽取；人脸特征只在内存比对，不落盘不外发。"""
import os, sys, json, sqlite3, subprocess, random, glob
ARCH='/Volumes/别动小爷的SSD/影像档案'
DB=f'{ARCH}/99_影像检索与报告/影像数据库.sqlite'
BIN=os.path.dirname(os.path.abspath(__file__))+'/bin'
BATCH=sys.argv[1] if len(sys.argv)>1 else os.environ.get('BUBU_BATCH','')
W='/tmp/bubu_incr'; os.makedirs(W, exist_ok=True); os.makedirs(W+'/vframes', exist_ok=True)

con=sqlite3.connect(DB); con.row_factory=sqlite3.Row
rows=con.execute('SELECT uuid, primary_final_path FROM assets WHERE import_name=?',(BATCH,)).fetchall()
photos=[]; videos=[]
for r in rows:
    p=os.path.join(ARCH, r['primary_final_path'])
    (videos if p.lower().rsplit('.',1)[-1] in ('mp4','mov','m4v') else photos).append(p)
print(f'本批 照片 {len(photos)} / 视频 {len(videos)}')

# 视频取 1/3 处一帧参与识别
frames=[]
for v in videos:
    stem=os.path.splitext(os.path.basename(v))[0]; out=f'{W}/vframes/{stem}.jpg'
    if not os.path.isfile(out):
        try:
            d=subprocess.run(['ffprobe','-v','quiet','-show_entries','format=duration',
                '-of','default=nw=1:nk=1',v],capture_output=True,text=True,timeout=60).stdout.strip()
            t=str(max(0.0, min(float(d or 3)/3, 60)))
            subprocess.run(['ffmpeg','-v','quiet','-ss',t,'-i',v,'-frames:v','1','-q:v','3',
                            out,'-y'],timeout=120)
        except Exception: pass
    if os.path.isfile(out): frames.append(out)
print(f'视频取帧 {len(frames)}')

def run(binary, lists, out):
    with open(f'{W}/list.txt','w') as f: f.write('\n'.join(lists))
    with open(out,'w') as o:
        subprocess.run([f'{BIN}/{binary}', f'{W}/list.txt'], stdout=o, check=True)

# 内容识别（分类 + OCR + 人脸）
run('analyze', photos+frames, f'{W}/content.json')
print('内容识别完成')

# 布布识别：参考集 = 档案库已确认女儿照片（近两年）；负样本 = 家庭与人物
pos=sorted(glob.glob(f'{ARCH}/01_照片/01_女儿/*/*/*.jpg')+glob.glob(f'{ARCH}/01_照片/01_女儿/*/*/*.jpeg')
           +glob.glob(f'{ARCH}/01_照片/01_女儿/*/*/*.heic'))
neg=sorted(glob.glob(f'{ARCH}/01_照片/02_家庭与人物/*/*/*.jpg')+glob.glob(f'{ARCH}/01_照片/02_家庭与人物/*/*/*.jpeg'))
pos=[p for p in pos if '/2026/' in p or '/2025/' in p][-400::3][:260]   # 取近期长相
neg=neg[::max(1,len(neg)//200)][:200]
if not pos: sys.exit('参考集为空：档案库里没有已确认的女儿照片')
for name, lst in (('pos',pos), ('neg',neg)):
    with open(f'{W}/{name}.txt','w') as f: f.write('\n'.join(lst))
with open(f'{W}/q_photos.txt','w') as f: f.write('\n'.join(photos))
with open(f'{W}/q_frames.txt','w') as f: f.write('\n'.join(frames))
print(f'参考集 正{len(pos)} 负{len(neg)}')
for q, out in (('q_photos', 'bubu_faces.json'), ('q_frames', 'bubu_vframes.json')):
    if not open(f'{W}/{q}.txt').read().strip():
        open(f'{W}/{out}','w').write('[]'); continue
    with open(f'{W}/{out}','w') as o:
        subprocess.run([f'{BIN}/bubuface', f'{W}/pos.txt', f'{W}/neg.txt', f'{W}/{q}.txt'],
                       stdout=o, stderr=subprocess.DEVNULL, check=True)
n=sum(1 for x in json.load(open(f'{W}/bubu_faces.json')) if 0<=x['bestPos']<=0.60)
print(f'布布识别完成：照片命中 {n}')
