# 布布时光机 · 交接文档（HANDOFF）

> 给「接手这个项目的下一段对话 / 下一个 AI」看的恢复文档。
> 新会话开始时，先读完本文件，即可无损接着干，不需要翻历史对话。

---

## 0. 一句话

原生 iOS App（SwiftUI + SwiftData），为女儿「布布」记录成长、传承一生。
离线优先、隐私至上、自托管。真正的用户是未来 18 岁的布布。

- **仓库路径**：`/Users/leoyuan/Documents/Leo-布布时光机`
- **工程管理**：xcodegen（改 `project.yml` 后必须重跑 `xcodegen generate`）
- **环境**：Xcode 26 / Swift 6（严格并发，默认 MainActor 隔离）/ iOS 26.0、watchOS 11.0 部署目标
- **规模**（2026-09-04 实测）：主 App 约 190 个 Swift 文件 / 4.2 万行；单元测试 170+ 项 / 31 套件，另有 5 项 iPhone+iPad XCUITest。
- **当前版本**：v2.14.0
- **本轮交付证据**：`docs/RELEASE_2.14.0.md`；审计基线见 `docs/AUDIT_AND_UPGRADE_PLAN_2026-09-08.md`。

---

## 1. 怎么验证（每次改完都要做）

```bash
cd /Users/leoyuan/Documents/Leo-布布时光机

# 1) 重新生成工程（改了 project.yml 或增删文件后）
xcodegen generate

# 2) clean build（增量构建会缓存误报，验证一律用 clean）
# 注意：不要加 -sdk iphonesimulator——项目已有 watchOS target，强制 iOS SDK 会导致手表代码
# 编译失败（WatchKit 无法解析）。只用 -destination，让 xcodebuild 自动为每个 target 选 SDK。
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  clean build 2>&1 | grep -E ": error:|BubuTimeMachine.*: warning:|BUILD SUCCEEDED|BUILD FAILED" | sort -u

# 目标：BUILD SUCCEEDED，零 error 零 warning
```

模拟器跑起来 + 截图（GUI 无法脚本点击，用 DEBUG 启动参数直达页面）：

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData/BubuTimeMachine-*/Build/Products/Debug-iphonesimulator -name "BubuTimeMachine.app" -maxdepth 1 | head -1)
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null
xcrun simctl install "iPhone 17 Pro" "$APP"
xcrun simctl launch "iPhone 17 Pro" com.bubu.timemachine -uitest-in-memory -uitest-seed -uitest-settings
sleep 4
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/shot.png
```

**DEBUG 启动参数**（仅 DEBUG 编译有效，定义在 `App/BubuTimeMachineApp.swift` 与 `RootTabView.swift`）：
- `-uitest-seed`：注入布布档案 + 成员 + 记录 + 里程碑 + 时间胶囊，并跳过引导（`-uitest-seed-big` 再铺 400 条压测数据）
- `-uitest-in-memory`：UI 测试使用独立内存数据库，不读取或污染模拟器既有家庭档案。
- `-uitest-tab N`：直达第 N 个 tab —— **0 首页 / 1 时光 / 2 成长 / 3 魔法屋**。
  时间胶囊已并入魔法屋，iPhone 只有 4 个 Tab + 中央「记一笔」；N≥4 会被夹到 3（档案馆 tag 4 只在 Mac Catalyst 侧栏存在）
- 直达页面：`-uitest-simple` / `-uitest-capture` / `-uitest-timeline` / `-uitest-ai` / `-uitest-growth` /
  `-uitest-milestones` / `-uitest-story` /
  `-uitest-growth-curve` / `-uitest-report` / `-uitest-weekly-report` / `-uitest-movie` / `-uitest-diary` /
  `-uitest-capsule` / `-uitest-sound-ring` / `-uitest-settings` / `-uitest-advanced-settings` /
  `-uitest-voice` / `-uitest-export`

> 截图后建议 `xcrun simctl uninstall "iPhone 17 Pro" com.bubu.timemachine` 清掉，
> 保证真机/用户首次运行能看到全新引导。

---

## 2. 架构地图（关键文件）

```
BubuTimeMachine/
├── App/
│   ├── BubuTimeMachineApp.swift   @main：Schema 装配 + DEBUG 种子 + RootView(引导/主界面切换)
│   ├── AppEnvironment.swift       ★ DI 容器(@Observable @MainActor)。按配置动态装配 Mock vs 真实
│   ├── RootTabView.swift          原生 4 Tab + 底部记录附件；iPad sidebarAdaptable
│   └── BubuSearchEntities.swift   Spotlight/App Entity 索引 + 时光 deep link
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
├── Features/                      按页面组织（View + 局部 @Observable Model），共 16 个域
│   ├── Capture/(首页+记录面板)  Timeline/  Growth/  AIStudio/(魔法屋)  Milestones/
│   ├── Health/  Album/  Feed/  Story/  PhotoFrame/  NaturalCapture/  Capsule/  Share/
│   ├── Settings/  (含 ChildProfile/Members/Theme/VoiceArchive/Export/WidgetWallpaper)
│   ├── SimpleMode/(姥姥模式)
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

## 4B. 2026-09-04 全面审计后的落地（新会话必读）

完整审计与方案见 `docs/AUDIT_AND_UPGRADE_PLAN_2026-09-04.md`。已落地的部分：

**数据与安全（P0）**
- AI 开关不再自己打开。旧兜底「打包 AI 地址非空 + 账号密码非空 → 默认开」配合
  「Swift 在 init 内赋值不触发 didSet」，导致用户只要为同步填完账号密码，
  下次冷启动 AI 就自动开启并把记录原文发往 DeepSeek。现在没存过就是关。
- 同步三处丢数据修复：评论/语音留言/人生第一次在父记录未落库时不再丢游标；
  multipart 上传不再把已删除记录翻活；翻页改 keyset，全量首同步不再静默跳记录。
- 启动迁移不再可能用旧库覆盖活库（打不开的库不参与打分比较）；
  store 打不开时挡一张全屏说明页，不再诱导用户重建档案。
- 时间胶囊记住封存版本，v3 的信拒绝一切非 v3 blob（防降级伪造），版本号只升不降。
- 家庭隔离规则收紧（先回填再收紧）；分享照片先去掉 GPS；恢复码改成可打印纸条；
  导出不再在 tmp 留下一份份完整明文副本。
- autodate 迁移终于进了仓库（0015 幂等兜底），守卫测试改成正向断言。

**地基**
- ⚠️ **`BubuTimeMachineTests/StoreMigrationTests.swift` 是新的发版底线。**
  它用一份真实装机数据（`Fixtures/LegacyStore_v2.12.2.store`）以生产同款配置
  验证「升级后全家的数据还打得开」。**改任何 @Model 之前先跑它，它红了不要发版。**
- `BubuSchema.swift` 底部那份「照抄改名即可」的 V2 模板已删除——照抄必然 abort。
  换成事实描述：现阶段只允许加可选字段、带默认值字段和 `#Index`。
- 全仓第一次有了索引（Entry / HealthRecord / FeedEvent），加完用上面那份
  **加索引之前**生成的基线实测仍能无损打开。
- 端上自然语言解析改用 `@Generable` 约束解码，删掉整个手写 JSON 解析。

**幼儿园（布布 2026-09-09 入园）**
- ChildProfile 加 `schoolStartDate` / `allergies` / `medicalNotes`（均为 additive 可选）；
  FamilyMember 加 `contactPhone` / `canPickUpFromSchool`（刻意不进 DTO，只在本机）。
- 首页入园倒计时横幅、身份卡背面「上幼儿园第 N 天」、24 题幼儿园问答桶、
  12 条幼儿园里程碑、入园查验接种证、给老师的一页、作品扫描（文稿相机 + 中文 OCR）。
- **产品边界**：接送打卡、缴费、请假条这类家长行政工具刻意不做——
  判据是「这条记录，18 岁的布布会想看吗」。

**交互与动效**
- 吉祥物 `phaseAnimator` 呼吸（一个文件、37 处受益）、缩略图淡入、下拉刷新（此前全仓 0 处）、
  大图下滑退出、四处破坏性操作补确认与触觉、记录面板防误丢、切 Tab 触觉、
  首页去掉重复的「记录此刻」与常驻搬家提示、生日音效接上、「人生第一次」接上仪式动画。

**CI**
- 加了零警告门禁与 iPad 回归（iPad 用例此前因模拟器只选 iPhone 而从未真正跑过）。

## 5. 未做 / 可继续（按价值排序）

1. **真 E2E 时间胶囊**：随机密钥 + iCloud Keychain 同步 + 打印恢复码。
2. **成长电影真实成片**：现为前端 Ken Burns 幻灯片 + AI 旁白。真实 ffmpeg 服务端合成 MP4 未做。
3. **Realtime 长连**：可接 SSE EventSource，替代 30 秒轮询（接入点在 SyncEngine.connectAndSync 尾部注释处）。
4. **后台上传**：现为前台 URLSession。可换 background URLSession + 断点续传（UploadQueue 有骨架）。
5. **冲突解决**：现策略是"本地已 synced 才接受远端覆盖"。多端并发编辑同一条的合并策略可细化。
6. **产品向**：桌面 Widget（年龄 + 那年今日）/ PDF 年册导出 / SpeechAnalyzer 端侧转写替代 Whisper 服务。
7. **版本化 Schema 真修复**：把 16 个类的定义真正复制进 `BubuSchemaV1` 命名空间冻结成快照，
   V2 用活类，App 侧改用 typealias 指过去。涉及全工程模型引用，必须单独排期。
   在此之前只能加可选字段（见 CLAUDE.md 注意事项）。
8. **大文件上传**：仍是前台 URLSession + 无退避。改 background session + 断点续传是一整块工作。
9. **鸿蒙端**：停在 2.11.0，落后 iOS 两个小版本，且 91% 的断言是把源码当文本 grep。
   需要决策：继续跟随（要真机 + 补真执行的测试）还是明说冻结。
10. **姥姥模式**：仍是只读定位，不能记喂养/睡眠、不能删改。入园后长辈接送频率会上升。

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
