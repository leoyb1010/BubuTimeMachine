# 影像增量工作流（photo-archive）

把新导出的照片/视频一条命令走完：**去重归档 → 端侧识别布布 → 有意义命名 → 缩略图 → 检索网页 → 进时光**。

## 部署位置

运行在 Mac mini 上（不在 App 里）：

| 项 | 路径 |
|---|---|
| 脚本部署目录 | `/Users/leo/BubuTimeMachineServer/photo-archive/` |
| Python 解释器 | `/Users/leo/BubuTimeMachineServer/releases/v2.8.0-candidate/server/ai/.venv/bin/python`（仅 to_timeline.py 需要，其余用系统 python3） |
| 配置来源 | 同上目录的 `.env`（INTAKE_* / PB_* 凭证，**不入仓**） |
| 影像档案库 | `/Volumes/别动小爷的SSD/影像档案/` |
| 索引数据库 | `影像档案/99_影像检索与报告/影像数据库.sqlite` |

## 编译识别工具（首次部署或改了 Swift 源码后）

```bash
cd /Users/leo/BubuTimeMachineServer/photo-archive/bin
swiftc -O Analyze.swift -o analyze
swiftc -O BubuFace.swift -o bubuface
```

二进制不入仓（每台机器自行编译）。

## 使用

```bash
bubu-incr [待导入目录] [--dry-run] [--no-timeline]
```

默认待导入目录：`影像档案/00_导入暂存/iPhone_待导入`

## 六个阶段

| 脚本 | 职责 |
|---|---|
| `stage1_ingest.py` | 扫描去重（SHA256 比对 media_files 全表）→ 收进 90_待确认 → 登记 assets/media_files。跳过 `._` AppleDouble 与隐藏文件。批次名 `增量导入YYYYMMDD_HHMMSS`（带时分秒防同日混批），落盘到 `/tmp/bubu_incr/batch.txt` 供后续阶段读取 |
| `vision_pass.py` | 端侧 Vision：图像分类 + 中英 OCR + 人脸检测（`bin/analyze`）；布布身份识别（`bin/bubuface`），参考集自动从 `01_照片/01_女儿` 近两年照片抽取，负样本取 `02_家庭与人物` |
| `enrich.py` | 英文视觉标签→中文 auto_tags（阈值 0.20，词表对齐历史 3 万条）；证件识别（身份证校验位 + 银行卡 Luhn）置 sensitive；判定 daughter_status；决定 topic/proposed_category；生成 proposed_stem；EXIF 补 GPS |
| `relocate.py` | 从 90_待确认 移入正式分类目录 + 改成有意义文件名；写回滚映射 CSV 到 `重命名记录/` |
| `thumbs_web.py` | 生成 420px 缩略图（HEIC 走 sips，视频走 ffmpeg）；追加条目进 `影像数据.json`（历史条目原样保留） |
| `to_timeline.py` | 布布素材按 90 分钟间隔聚成事件批次 → 复用既有 intake staging + loopback commit hook → PocketBase Entry+Media。台账 `整理报告/已推送时光.json` 防重复推送 |

## 关键约定（改动前必读）

- **时间戳**：导出文件名里的时间是 **UTC**，本地 = +8。`assets.captured_at` 一律存**本地时间**并写 `timezone='Asia/Shanghai'`，与历史 3 万条一致。
- **文件名格式**：`YYYYMMDD_HHMMSS_[地点]_[布布]_[视觉标签…]_[UUID前8位].ext`，无标签时用主题兜底词（日常/截图/日常视频）。敏感证件用 `敏感证件_身份证`，**证件号绝不写入文件名或网页**。
- **布布识别阈值**：0.55（实测校准：召回 67%、他人误判 0/80；对照组最低距离 0.595）。0.55–0.60 记为「相关待确认」。
- **人脸特征只在内存比对**，不落盘、不上传、不进任何数据库。
- **源文件只读**：待导入目录的文件只复制，不移动/改名/删除。
- **可回滚**：每次归档写重命名映射 CSV，每次运行前自动备份数据库到 `清理记录/`。

## 已知未完成

- 语义索引（`语义索引/vectors.npy`、`数据/语义向量.js`）停留在 2026-07-22，新批次不进语义搜索；标签/时间/分类筛选正常。
