# 布布时光机 · AI 伴生服务

自托管 FastAPI，App 端 `BubuAIService` 调用本服务，本服务再调 LLM（默认 DeepSeek，OpenAI 兼容协议）。
换模型 = 改本服务 `.env`，App 一行不改。

## 环境要求

- **Python ≥ 3.10，部署基线为 Python 3.11 / macOS arm64**。修复版本的 Starlette、AnyIO、
  python-multipart 和 Pillow 不再支持 Python 3.9，不能复用旧 3.9 venv。
- 运行时锁由 `uv pip compile` 生成：HTTP 用 `requirements.lock.txt`，语义推理用
  `requirements-semantic.lock.txt`（输入为 `requirements-semantic-runtime.txt`）。
  两份锁可以装进同一新环境；pytest 只在 `requirements-dev.txt`，不进入生产锁。
- 语音转写是可选能力，`faster-whisper` 不在默认锁中；安装 HTTP/语义环境不代表已启用转写。

## 启动

```bash
cp .env.example .env   # 填 DEEPSEEK_API_KEY 与 AI_API_KEY（必填，fail-closed）
./start_ai.sh          # 自动建 venv、装依赖、起 uvicorn（默认 :8000）
```

已有部署升级时，先在独立目录用 Python 3.11 创建新 venv，联合安装两份运行时锁（启用语义
搜索时），再以 `--no-deps` 安装固定 Apple MobileCLIP commit
`aecfb5453d022e9deff12f81a150ea8f35194baa`。不要复制旧 venv 的二进制包，或从 PyPI 安装同名
`mobileclip`。复用已核验的现有模型权重，不重复下载权重或扩展许可授权。新环境须通过测试、
API 冒烟及真实图片/文字编码检查，再切换服务；旧 release、venv 和配置保留作回滚。
Torch/torchvision 仍保留 2.8.0/0.23.0；这不是“整个 ML 依赖零漏洞”的声明：只允许加载固定、
可信且已验证 SHA-256 的模型文件，模型目录不能被上传接口或低权限账号改写，不接受用户提供
的 checkpoint、TorchScript 或 `.pt2` 程序。后续 ML 大版本升级需独立验证。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/rewrite-first-person` | 父母视角 → 布布第一人称日记 |
| POST | `/classify` | 记录的事件/地点/标签归类 |
| POST | `/detect-first-time` | 判断"是否人生第一次" |
| POST | `/movie-narration` | 年度成长电影旁白稿 |
| POST | `/parse-natural-capture` | 一句话 → 多条结构化记录（疫苗/成长/餐食/睡眠…）；LLM 输出服务端逐条清洗，敏感域强制 `needs_confirmation` |
| POST | `/transcribe` | 语音转写（需 faster-whisper） |
| POST | `/intake/batches` | 为用户已确认的一段时光建立持久上传批次 |
| PUT | `/intake/upload/{batch}/{asset}` | PhotoKit 能力令牌直传隔离暂存区 |
| GET | `/intake/candidates` | 读取 SSD 只读扫描产生的待确认事件 |
| POST | `/intake/confirm` | 家庭确认 SSD 候选并触发原子提交 |
| POST | `/intake/commit` | 重试一个已完整暂存的批次 |
| GET | `/weekly-report/latest` | 读取最新布布周报 |
| GET | `/weekly-report/history` | 读取最近一年的往期周报（含已归档） |
| POST | `/weekly-report/generate` | 幂等生成上一个完整自然周；证据不足不生成 |
| POST | `/weekly-report/archive` | 用户确认后只归档派生产物，不改事实集合 |
| GET | `/weekly-report/events` | 仅发送新周报 id 的 SSE，不承载家庭正文 |
| GET | `/sound-ring/latest` | 最新声音年轮草稿/成片 |
| GET | `/sound-ring/history` | 往期声音年轮 |
| POST | `/sound-ring/draft` | 从真实原声生成可核对素材清单，不渲染 |
| POST | `/sound-ring/render` | 家庭确认后异步渲染；失败可按同一 id 重试 |
| GET | `/sound-ring/status/{id}` | 查询渲染状态与带来源时间轴 |
| GET | `/sound-ring/file/{id}` | 鉴权下载 protected 成片 |
| POST | `/sound-ring/archive` | 只归档派生音频，不修改原声与照片 |
| GET | `/health` | 健康检查；带正确 `X-API-Key` 时附 `parse_stats`（解析 warnings 累计，监控 LLM 输出漂移） |

App 业务路由使用现有 PocketBase `Authorization: Bearer …` 登录态，并受
`AI_ALLOWED_PB_USER_IDS` 单家庭白名单与按用户限流保护；`X-API-Key` 只保留给 mini 本机维护任务。
PhotoKit 上传 URL 使用绑定 batch、asset、owner 和有效期的独立能力令牌，不能调用其他接口。

成长电影 `/movie/render` 必须使用 PocketBase 家庭登录：提交时按调用者权限读取
media 与关联 Entry，确认文件、家庭和删除状态后才允许服务账号下载。排队执行时再次检查
素材与账号家庭归属；用户 token 不写入任务。`/movie/status/{id}` 与 `/movie/file/{id}`
仅创建任务的同一账号可读（重新登录换 token 不影响）。维护 `X-API-Key` 不能制作或读取
家庭电影，其他维护接口不变；现有 App 的 Bearer 登录不需要新增配置。
旧 Harmony 2.15 源码仍以 `X-API-Key` 调电影接口，会被拒绝；本次未发布或验证鸿蒙升级，
不可通过重新开放维护 key 的素材权限绕过这一兼容边界。

## 可靠照片与 SSD 摄取

1. iPhone 只在用户点“收好”后建立批次；未确认的系统相册素材不会上传。
2. iOS 26.4+ 由 PhotoKit background upload extension 在锁屏/切 App/断网后继续；旧系统安全回退前台导入。
3. mini 写入 `INTAKE_STAGING_ROOT`，逐文件校验大小和 SHA-256；半成品绝不进入 PocketBase。
4. 全批完成后，PocketBase loopback hook 在一个事务里创建 Entry 与全部 Media；重放同一 batch 只返回原记录。
5. `scan_ssd_inbox.py` 只读扫描 `BUBU_INBOX_ROOT`，不移动、不改名、不删除源文件；候选必须回到 iPhone 确认。
6. 每次 SSD 扫描会先读取 PocketBase `contentHash` 与 staging 历史 hash 做跨来源去重；事实库不可读时整次延期。
7. 已提交的中转原片立即清理，失败/取消批次超过 7 天由扫描任务清理；manifest 与哈希审计信息保留到批次过期。

摄取请求会持续检查超时的 `committing` 批次，重启后即使第一次查询早于 5 分钟超时，
后续查询仍能恢复。提交全过程持有 staging 目录内的每批次 `flock`：只恢复超时且无人
持锁的批次，慢请求不被误回收；进程退出自动释放锁。不要手工删除正在使用的锁文件。

PocketBase 部署前必须先用全新临时 `pb_data` 跑原子提交集成测试：

```bash
POCKETBASE_BIN=/absolute/path/to/pocketbase \
python3 -m unittest server.pocketbase.tests.test_intake_commit -v
```

## 周日晚自动生成

`.env` 至少配置 `WEEKLY_REPORT_FAMILY_ID` 和 PocketBase worker 凭证。先手动运行
`./start_weekly_report.sh` 验证，再把 `server/ops/com.bubu.weekly-report.plist.example`
替换成绝对路径后交给 launchd。默认每周一 00:05 执行，确保自然周完整结束；重复执行命中同一个
`artifactKey`，不会生成两份。可选 ntfy 通知只发送“已生成”和产物 id，不发送家庭正文。

## 声音年轮

mini 需要 `ffmpeg` / `ffprobe`；macOS 自带 `say` 用中性系统声音念“接下来是 N 岁”的衔接语。
作品必须有至少约 3 分钟真实原声，最多约 8 分钟；不会用静音、AI 编故事或克隆布布声音凑时长。
流程固定为“素材清单 → 家庭确认 → 异步渲染 → 来源时间轴 → 归档”。服务重启或网络中断后，
失败状态仍保留在 PocketBase，可在 App 用同一作品 id 重试；临时渲染目录始终清理。

## 语义索引更新

PocketBase 的 `semantic_queue.pb.js` 与同目录 `semantic_jobs.js` 共同生成任务。
签名覆盖照片文件/角色/类型/标签/关联归属，以及 Entry 的标题、正文、第一人称文案、地点、
日期和删除状态；`updated`、`clientUpdatedAt`、尺寸等同步触碰不会重复排队。
每种实际输入使用稳定任务键，更正能排在正在运行的旧任务后面，worker 再读当前事实使索引收敛。
Entry 更新仅影响同家庭的关联媒体；删除、改为原片附件/音频或失去有效 Entry 关联会移除旧索引。

更新这条链路须将两个 hook 文件一起部署并重启 PocketBase，同时重启语义 worker。
单独更新本切片不需要重启 FastAPI；已有旧索引不会因此自动批量重建，历史修复应另行确认
`semantic_reconcile.py` 的预览与范围后再操作。

## 测试

```bash
pip install -r requirements-dev.txt
pytest tests -q                    # 标准跑法
python3 tests/test_parse.py        # 无 pytest 的环境直跑（自动 stub 缺失依赖）
```

## 验收样例（部署后跑一遍）

```bash
TOKEN=你的PocketBase登录token
for t in "6月20日布布打了麻腮风疫苗" "今天身高82cm体重10.6kg" \
         "中午吃了南瓜米糊半碗，下午喝水120ml" "昨晚9点睡早上7点醒" \
         "今天咳嗽，体温37.8" "第一次自己扶着沙发站起来了"; do
  curl -s -X POST localhost:8000/parse-natural-capture \
    -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
    -d "{\"text\":\"$t\",\"childName\":\"布布\",\"timezone\":\"Asia/Shanghai\",\"referenceDate\":\"$(date -Iseconds)\"}" | head -c 300; echo
done
```
