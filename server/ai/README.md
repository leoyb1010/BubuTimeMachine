# 布布时光机 · AI 伴生服务

自托管 FastAPI，App 端 `BubuAIService` 调用本服务，本服务再调 LLM（默认 DeepSeek，OpenAI 兼容协议）。
换模型 = 改本服务 `.env`，App 一行不改。

## 环境要求

- **Python ≥ 3.9**（代码刻意保持 3.9 兼容：Pydantic 模型一律 `Optional[...]` 写法，勿改成 `X | None`）
- 依赖见 `requirements.txt`；语音转写可选装 `faster-whisper`

## 启动

```bash
cp .env.example .env   # 填 DEEPSEEK_API_KEY 与 AI_API_KEY（必填，fail-closed）
./start_ai.sh          # 自动建 venv、装依赖、起 uvicorn（默认 :8000）
```

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

## 可靠照片与 SSD 摄取

1. iPhone 只在用户点“收好”后建立批次；未确认的系统相册素材不会上传。
2. iOS 26.4+ 由 PhotoKit background upload extension 在锁屏/切 App/断网后继续；旧系统安全回退前台导入。
3. mini 写入 `INTAKE_STAGING_ROOT`，逐文件校验大小和 SHA-256；半成品绝不进入 PocketBase。
4. 全批完成后，PocketBase loopback hook 在一个事务里创建 Entry 与全部 Media；重放同一 batch 只返回原记录。
5. `scan_ssd_inbox.py` 只读扫描 `BUBU_INBOX_ROOT`，不移动、不改名、不删除源文件；候选必须回到 iPhone 确认。
6. 每次 SSD 扫描会先读取 PocketBase `contentHash` 与 staging 历史 hash 做跨来源去重；事实库不可读时整次延期。
7. 已提交的中转原片立即清理，失败/取消批次超过 7 天由扫描任务清理；manifest 与哈希审计信息保留到批次过期。

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
