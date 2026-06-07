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
  # 示例：每晚把数据盘 rsync 到备份盘（配合 crontab / launchd）
  rsync -a --delete /Volumes/BubuSSD/pb_data/ /Volumes/BubuBackup/pb_data/
  ```

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
   - 在 `_superusers` 之外，到 **Settings → Auth** 确认开启邮箱登录；
     家庭三人共用**一个登录账户**即可（如 `family@bubu.local`），App 端用它鉴权。
     > 简化：家庭内不做隐私墙，一个账户全家共享；隐私靠 Tailscale 内网保证。

集合一览（已由迁移自动创建）：
`entries / media / comments / voicenotes / milestones / firsttimes / voicememos / members / childprofile`
每个集合都有 `localId`（客户端 UUID）做幂等去重——多设备/重试不会重复。

---

## 三、部署 AI 服务

```bash
cd server/ai
cp .env.example .env          # 填入 DEEPSEEK_API_KEY（已预填你的 key）
./start_ai.sh                 # 首次自动建 venv 装依赖并启动
```

- 默认模型：`deepseek-v4-flash`（首选）→ `deepseek-v4-pro`（兜底）。
- 健康检查：`curl http://localhost:8000/health`
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
2. **AI 服务**：填 `http://<mac的tailscale-ip>:8000`，打开「启用真实 AI」。

配置好后：
- 三台 iPhone 的记录会自动汇到一起（离线照常用，联网自动同步）。
- AI 工坊从 Mock 变为真实 DeepSeek。

---

## 五、开机自启（可选）

用 `launchd` 让两个服务随 Mac 开机启动。示例 plist 思路：
- `~/Library/LaunchAgents/com.bubu.pocketbase.plist` → 执行 `start_pocketbase.sh`
- `~/Library/LaunchAgents/com.bubu.ai.plist` → 执行 `start_ai.sh`

`launchctl load` 后即可常驻。

---

## 安全须知

- **不要把 `.env` 和 `pocketbase` 二进制、`pb_data/` 提交到 git**（已在 `.gitignore` 排除）。
- DeepSeek API 走云端：只发送**文字**（记录摘要），从不上传照片，降低隐私暴露。
  若要完全不出家门，可把 `llm.py` 的 base_url 指向本地 Ollama。
