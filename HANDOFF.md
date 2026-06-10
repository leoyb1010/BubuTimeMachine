# 布布时光机 · 交接文档（HANDOFF）

> 给「接手这个项目的下一段对话 / 下一个 AI」看的恢复文档。
> 新会话开始时，先读完本文件，即可无损接着干，不需要翻历史对话。

---

## 0. 一句话

原生 iOS App（SwiftUI + SwiftData），为女儿「布布」记录成长、传承一生。
离线优先、隐私至上、自托管。真正的用户是未来 18 岁的布布。

- **仓库路径**：`/Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine`
- **工程管理**：xcodegen（改 `project.yml` 后必须重跑 `xcodegen generate`）
- **环境**：Xcode 26 / Swift 6（严格并发，默认 MainActor 隔离）/ iOS 18+ 部署目标
- **规模**：68 个 Swift 文件 + 10 个后端文件，约 7300 行 Swift

---

## 1. 怎么验证（每次改完都要做）

```bash
cd /Users/leoyuan/Desktop/leoworkspace/BubuTimeMachine

# 1) 重新生成工程（改了 project.yml 或增删文件后）
xcodegen generate

# 2) clean build（增量构建会缓存误报，验证一律用 clean）
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  clean build 2>&1 | grep -E ": error:|BubuTimeMachine.*: warning:|BUILD SUCCEEDED|BUILD FAILED" | sort -u

# 目标：BUILD SUCCEEDED，零 error 零 warning
```

模拟器跑起来 + 截图（GUI 无法脚本点击，用 DEBUG 启动参数直达页面）：

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData/BubuTimeMachine-*/Build/Products/Debug-iphonesimulator -name "BubuTimeMachine.app" -maxdepth 1 | head -1)
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null
xcrun simctl install "iPhone 17 Pro" "$APP"
xcrun simctl launch "iPhone 17 Pro" com.bubu.timemachine -uitest-seed -uitest-settings
sleep 4
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/shot.png
```

**DEBUG 启动参数**（仅 DEBUG 编译有效，定义在 `App/BubuTimeMachineApp.swift` 与 `RootTabView.swift`）：
- `-uitest-seed`：注入布布档案 + 成员 + 4 条记录 + 里程碑 + 2 封时间胶囊，并跳过引导
- `-uitest-tab N`：直达第 N 个 tab（0记录/1时光轴/2里程碑/3AI工坊/4时间胶囊）
- `-uitest-settings` / `-uitest-voice` / `-uitest-export`：直达对应页面

> 截图后建议 `xcrun simctl uninstall "iPhone 17 Pro" com.bubu.timemachine` 清掉，
> 保证真机/用户首次运行能看到全新引导。

---

## 2. 架构地图（关键文件）

```
BubuTimeMachine/
├── App/
│   ├── BubuTimeMachineApp.swift   @main：Schema 装配 + DEBUG 种子 + RootView(引导/主界面切换)
│   ├── AppEnvironment.swift       ★ DI 容器(@Observable @MainActor)。按配置动态装配 Mock vs 真实
│   └── RootTabView.swift          5 Tab 导航
├── Models/                        11 个 @Model（SwiftData，唯一真相源）
│   └── Enums / AgeCalculator      Mood/Relation/SyncState + 年龄计算（全 App 年龄展示来源）
├── Services/
│   ├── Networking/
│   │   ├── APIClient.swift        ★ 协议。MockAPIClient(默认) / PocketBaseClient(真实)
│   │   ├── PocketBaseClient.swift  REST 鉴权/幂等CRUD/multipart上传带进度/轮询Realtime
│   │   ├── DTOs.swift             EntryDTO 等传输对象（与 @Model 解耦）
│   │   └── ServerConfig.swift     设置持久化：服务器地址/家庭账户/AI开关/提醒开关
│   ├── AI/
│   │   ├── AIService.swift        ★ 协议。MockAIService(默认) / BubuAIService(真实，调 FastAPI)
│   ├── Sync/SyncEngine.swift      ★ 双向同步：本地未同步推送 + 远端拉回合并(localId 去重)
│   ├── Media/                     MediaStore(沙盒) / PhotoAnalyzer(EXIF+地理+Vision) /
│   │                             AudioRecorder/Player / ArchiveExporter(全量HTML导出)
│   ├── Security/                  CapsuleCrypto(AES-GCM) / CapsuleVault(时间胶囊封存)
│   └── ReminderScheduler.swift    那年今日每日本地通知
├── Features/                      按页面组织（View + 局部 @Observable Model）
│   ├── Capture/  Timeline/  Milestones/  AIStudio/  Capsule/
│   ├── Settings/  (含 ChildProfile/Members/Theme/VoiceArchive/Export)
│   └── Onboarding/
└── DesignSystem/  BubuTheme / ThemeManager / 组件库

server/                           自托管后端（详见 server/README.md）
├── pocketbase/migrations/        集合定义（JS 迁移，9 集合 + localId 幂等）
└── ai/                           FastAPI + DeepSeek（main.py/llm.py/transcribe.py）
```

**核心设计原则（改代码必须遵守）**：
1. **离线优先**：SwiftData 是唯一真相源，UI 只读本地；网络是后台同步层，断网全功能可用
2. **接口先行**：网络/AI 全是 protocol，Mock 与真实实现可热切换，UI 不依赖具体后端
3. **现代并发**：全程 `async/await` + `@Observable` + `@MainActor`，禁止 Combine/ObservableObject
4. **隐私至上**：AI 走自托管、只发文字不传图；时间胶囊端到端加密；无第三方分析
5. **适老化**：姥姥能用 = 验收标准（大按钮、口语文案、无密码切身份）

---

## 3. 已完成（Wave A–H，全部 clean build 零错误零警告）

- **核心闭环**：记录此刻(仪表盘首页) / 时光轴(按月分段) / 里程碑成就墙 / AI工坊(4能力) / 时间胶囊(AES-GCM)
- **账户系统**：家庭多成员(无密码切身份) + 首启引导 + 布布档案
- **专属能力**：6 套主题 + 自定义首页背景 + 端侧图片分析(EXIF/地理/Vision标签) + 心情标签 +
  语音记录 + 家人合奏(多视角补充) + 详情可编辑可补充
- **AI 工坊(4)**：第一人称日记(打字机动效) / 年度成长电影(Ken Burns 放映) / 家人合奏 / 成长报告(Charts)
- **Wave H**：
  - PocketBaseClient + 双向 SyncEngine（三台 iPhone 自动汇合，离线自动补传）
  - BubuAIService 接 DeepSeek（`v4-flash` 首选 / `v4-pro` 兜底）
  - 成长之声（按岁归档声音，可转写）
  - 全量档案导出（静态 HTML + 媒体包 + zip 分享，永久离线可读）
  - 那年今日每日提醒 + 上传后 AI「这是第一次吗」确认弹窗
  - `server/` 后端脚手架（PocketBase 迁移 + FastAPI + 启动脚本 + 部署文档）

---

## 4. 2026-06-10 深度 review 后的落地（重要，新会话必读）

- **安全**：`.env.example` 的真实 DeepSeek key 已清除（需在 DeepSeek 控制台吊销旧 key！）；
  FastAPI 全业务路由要求 `X-API-Key`（fail-closed）+ 按 IP 限流；CORS 全关。
  App 默认服务器/AI 地址为空、AI 默认关闭（此前默认指向作者私人域名，已纠正）。
  ServerConfig 新增 `aiAPIKey`（Keychain），设置页有「AI 访问密钥」字段。
- **时间胶囊 P0 修复**：v1 密钥派生用 `timeIntervalSince1970`（含亚秒），同步 ISO 截断后
  永久解不开。v2 改用规范化 ISO 字符串派生 + "BTC2" 魔数前缀，旧 blob 兼容解密；
  SyncEngine 不再用远端覆盖已存在胶囊的 unlockAt。回归测试在 `BubuTimeMachineTests/`。
  文案上时间胶囊定位为「仪式感时间锁」，不再宣称端到端加密（密钥材料随记录同步）。
- **同步 v2**：分页拉全量（不再受 500 条上限）；按集合持久化增量游标（UserDefaults
  `bubu.sync.cursor.*`，失败不推进，留 60 秒重叠余量）；token 复用 + 401 自动重登
  （不再每周期密码登录）；拉回的 Media/VoiceNote/Comment/VoiceMemo 缺失文件每轮限量下载落地；
  去掉 subscribeRealtime 的 8 秒重复轮询，同步循环 30 秒，进后台 `stopPolling()` 省电。
- **其它**：那年今日通知改预排未来 7 天（每天内容各自正确）；savePhoto 按文件头嗅探
  HEIC/PNG 真实扩展名；删除事件 FeedEventKind 新增 `entryArchived`；
  GrowthMoviePlayer 用 ImageIO 降采样 + 邻片预载 + 平移；CeremonyAnimation 加触觉反馈，
  两处都尊重 reduceMotion。

## 5. 未做 / 可继续（按价值排序）

1. **真 E2E 时间胶囊**：随机密钥 + iCloud Keychain 同步 + 打印恢复码。
2. **成长电影真实成片**：现为前端 Ken Burns 幻灯片 + AI 旁白。真实 ffmpeg 服务端合成 MP4 未做。
3. **Realtime 长连**：可接 SSE EventSource，替代 30 秒轮询（接入点在 SyncEngine.connectAndSync 尾部注释处）。
4. **后台上传**：现为前台 URLSession。可换 background URLSession + 断点续传（UploadQueue 有骨架）。
5. **冲突解决**：现策略是"本地已 synced 才接受远端覆盖"。多端并发编辑同一条的合并策略可细化。
6. **产品向**：桌面 Widget（年龄 + 那年今日）/ PDF 年册导出 / SpeechAnalyzer 端侧转写替代 Whisper 服务。

---

## 6. 自托管部署（用户侧，三步）

详见 `server/README.md`。简版：
1. **PocketBase**：从 github releases 下载 macOS(arm64) 二进制放 `server/pocketbase/`，
   `./start_pocketbase.sh /Volumes/你的SSD/pb_data`，后台建管理员 + 一个家庭登录账户。
2. **AI 服务**：`cd server/ai && cp .env.example .env`，填自己的 DEEPSEEK_API_KEY +
   生成 AI_API_KEY（`openssl rand -hex 24`）→ `./start_ai.sh`。
3. **App 设置页**：填两个 Tailscale 地址（:8090 和 :8000）+ 家庭账户 + AI 访问密钥，开「启用真实 AI」。

硬件：Mac mini + 外接 SSD 作数据盘 + 第二块盘做备份（单盘=单点故障，存的是布布的一生）。
网络：Tailscale 内网，无需公网 IP/域名/暴露端口。

---

## 7. 给接手者的提醒

- **clean build 才可信**：增量构建经常缓存出"找不到类型/重复声明"的误报，验证一律 clean。
- **改 project.yml 后必须 `xcodegen generate`**，否则新增文件不进工程。
- **不要把 `server/ai/.env`、PocketBase 二进制、`pb_data/` 提交 git**（已在 `.gitignore`）。
- **每个独立功能改完就 commit**，commit message 用中文写清楚做了什么（仓库历史风格如此）。
- **GUI 无法脚本点击**（macOS 辅助功能权限受限），验证页面渲染靠 DEBUG 启动参数直达 + 截图。
