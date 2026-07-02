# 布布时光机 · 自托管后端

> 真正的用户，是未来 18 岁的布布。数据存在自己家，传承一生。

两个独立服务，都跑在你的 Mac mini 上：

| 服务 | 作用 | 端口 |
|---|---|---|
| **PocketBase** | 数据库 + 文件存储 + 鉴权 + 实时订阅（三台 iPhone 同步的核心） | 8090 |
| **AI 服务（FastAPI）** | 第一人称改写 / 旁白 / 归类 / 第一次识别 / 语音转写（接 DeepSeek） | 8000 |

网络层用 **Tailscale**：Mac mini 和三台 iPhone 装上后组成私有内网，在外也能安全回家访问，无需公网 IP、无需域名、不暴露端口。

---

## 一、硬件与存储

- **Mac mini（任意一代均可）** 作为常驻服务器。
- **外接 SSD 作数据盘**：把 PocketBase 数据目录指向 SSD（照片视频是大头）。
  ```bash
  ./pocketbase/start_pocketbase.sh /Volumes/BubuSSD/pb_data
  ```
- **第二块盘做备份（重要！）**：单盘 = 单点故障，存的是布布的一生，必须定期备份。
  ```bash
  # 示例：只做日期快照，不用 --delete 覆盖历史备份
  SNAPSHOT="/Volumes/BubuBackup/pb_data_snapshots/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$SNAPSHOT"
  rsync -a /Volumes/BubuSSD/pb_data/ "$SNAPSHOT/"
  ```
  更推荐在 PocketBase 管理后台开启 **Settings → Backups** 定时备份，并把备份放到另一块盘或 S3 兼容存储。
  PocketBase 官方说明：内置 backup 会生成完整 `pb_data` ZIP 快照，生成期间服务会临时只读；大于 2GB 的数据目录建议改用 SQLite `.backup` + 文件增量备份策略。
  不要把 `rsync --delete` 镜像当唯一备份，否则误删、勒索或同步损坏会被原样复制到备份盘。

---

## 二、部署 PocketBase

1. 从 https://github.com/pocketbase/pocketbase/releases 下载 macOS(arm64) 版本，
   解压后把 `pocketbase` 可执行文件放到 `server/pocketbase/` 目录。
2. 启动（首次会自动应用 `migrations/` 里的集合定义）：
   ```bash
   cd server/pocketbase
   ./start_pocketbase.sh /Volumes/BubuSSD/pb_data
   ```
3. 打开 `http://<mac的tailscale-ip>:8090/_/`：
   - 创建**管理员账号**（你自己用）。
   - 在 `users` 集合里由超管创建每位家人的账号（如 `baba@bubu.family`、`mama@bubu.family`）。
     公开注册已由迁移关闭，App 端只负责登录。
   - 可选：在 `families` 集合创建家庭记录，并把每个 `users.familyId` 填成该家庭记录 id。
     老数据 `familyId` 为空时仍可读写，方便平滑升级；新客户端会自动写入 `authorUserId/familyId`。

集合一览（已由迁移自动创建）：
`users / families / entries / media / comments / voicenotes / milestones / firsttimes / voicememos / members / childprofile / healthrecords / timecapsules / vaccinerecords / growthmeasurements / feed_events`
每个业务集合都有 `localId`（客户端 UUID）做幂等去重，并有 `authorUserId/familyId/isDeleted/deletedAt` 用于身份追踪、家庭隔离准备和软删除。
`deleteRule` 默认锁给超管，客户端删除会写 tombstone，不再物理删除远端记录。

---

## 三、部署 AI 服务

```bash
cd server/ai
cp .env.example .env          # 填入你自己的 DEEPSEEK_API_KEY
openssl rand -hex 24          # 生成一个 AI_API_KEY，填进 .env，App 设置页填同一个
./start_ai.sh                 # 首次自动建 venv 装依赖并启动
```

- **鉴权是必须的（fail-closed）**：`.env` 不配 `AI_API_KEY` 时所有业务接口直接返回 503，
  防止把无鉴权服务误暴露到公网。所有请求需带 `X-API-Key` 头，App 端在设置页填写后自动携带。
- 生产环境优先使用 `server/ai/requirements.lock.txt` 的锁定依赖重建 venv；`requirements.txt` 只作为宽松维护约束。
- 内置按 IP 限流（默认 30 次/分钟，`AI_RATE_LIMIT_PER_MINUTE` 可调）；`/transcribe` 上限 50MB。
- 默认模型：`deepseek-v4-flash`（首选）→ `deepseek-v4-pro`（兜底）。
- 健康检查：`curl http://localhost:8000/health`（不带 key 只返回 ok，不泄露配置信息）。
- 语音转写为可选：需要时 `pip install faster-whisper` 并重启；未装时 `/transcribe` 返回 501，App 端会优雅降级。

接口：
| 方法 | 路径 | 用途 |
|---|---|---|
| POST | `/rewrite-first-person` | 父母视角 → 布布第一人称 |
| POST | `/classify` | 记录归类（标题/事件/地点/标签） |
| POST | `/detect-first-time` | "这是第一次吗"判断 |
| POST | `/movie-narration` | 年度成长电影旁白 |
| POST | `/transcribe` | 语音转写（可选） |
| GET | `/health` | 健康检查 |

---

## 四、App 端配置

打开 App → 设置：
1. **家里的服务器**：填 PocketBase 地址 `http://<mac的tailscale-ip>:8090`，点「连接测试」。
2. **AI 服务**：填 `http://<mac的tailscale-ip>:8000` + AI 访问密钥（即 `.env` 的 `AI_API_KEY`），打开「启用真实 AI」。

> App 出厂默认**不配置任何服务器、AI 默认关闭**——隐私至上，任何数据外发都必须你显式填地址。

配置好后：
- 三台 iPhone 的记录会自动汇到一起（离线照常用，联网自动同步）。
- AI 工坊从 Mock 变为真实 DeepSeek。

---

## 五、开机自启（可选）

用 `launchd` 让两个服务随 Mac 开机启动。示例 plist 思路：
- 复制 `server/ops/com.bubu.pocketbase.plist.example` 到 `~/Library/LaunchAgents/com.bubu.pocketbase.plist`，改成真实项目路径和 `pb_data` 路径。
- 复制 `server/ops/com.bubu.ai.plist.example` 到 `~/Library/LaunchAgents/com.bubu.ai.plist`，改成真实项目路径。
- 日志默认写到 `~/Library/Logs/BubuTimeMachine/`。

```bash
mkdir -p ~/Library/Logs/BubuTimeMachine
launchctl load ~/Library/LaunchAgents/com.bubu.pocketbase.plist
launchctl load ~/Library/LaunchAgents/com.bubu.ai.plist
server/ops/healthcheck.sh
```

`server/ops/healthcheck.sh` 会检查 PocketBase、AI 服务和数据盘剩余空间，可放进 crontab/launchd 后接 Bark、ntfy 或邮件通知。

---

## 安全须知

- **不要把 `.env` 和 `pocketbase` 二进制、`pb_data/` 提交到 git**（已在 `.gitignore` 排除）。
  `.env.example` 永远只放空占位符——真实 key 一旦推上 GitHub 就要立刻吊销重发。
- **公网暴露（Cloudflare Tunnel 等）务必三件套**：AI 服务的 `AI_API_KEY`、强密码的
  PocketBase 家庭账户、最好再加一层 Cloudflare Access。能用 Tailscale 内网就不要走公网。
- DeepSeek API 走云端：只发送**文字**（记录摘要），从不上传照片；语音转写在你自己的服务器本地跑。
  若要完全不出家门，可把 `llm.py` 的 base_url 指向本地 Ollama。
