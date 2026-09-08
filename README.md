# 布布时光机 · BubuTimeMachine

> 真正的用户，是未来 18 岁的布布。
> 一切技术决策都要回答：30 年后，这些数据还能被她完整地读到、看到、听到吗？

原生 iOS（SwiftUI + SwiftData）与 HarmonyOS（ArkTS + ArkUI）双端工程，为家庭记录孩子成长、传承一生。离线优先、隐私至上、自托管。

> HarmonyOS 与 iOS 统一发布 2.14.0，同步、档案字段与加密保护共用后端契约；真实进度和边界见
> [`harmony/PARITY_MATRIX.md`](harmony/PARITY_MATRIX.md)，不再以“页面存在”代替完成。

## 当前进度

已完成 **完整的离线体验层**（不依赖任何后端，全功能本地可用）。核心闭环 + 六大专属能力：

**2.14 · 每一刻，都稳稳收好**

- 升级前自动备份；冻结旧模型并提供较早版本到 V2 的迁移路径。
- 双端稳定分页、保存失败保护、删除与文件清理顺序修复。
- 同步中心展示逐类核对结果；首页和记录页强化可读性。
- 鸿蒙补齐入园与健康备注同步、胶囊防降级和原生减少动态设置。
- 后端家庭隔离、备份恢复、通知服务及真实数据库集成门禁完成加固。
- 发布验收与回退边界见 [2.14.0 发布记录](docs/RELEASE_2.14.0.md)。

**2.13 · 幼儿园能力**
- ✅ 入园倒计时与「上幼儿园第 N 天」：与「来到世界第 N 天」并列，身份卡背面不再印 UUID
- ✅ 放学一问：24 题幼儿园语境题库，**问的是布布本人**，家长照着念、记她的原话
- ✅ 12 条幼儿园里程碑：第一天上幼儿园 / 第一次不哭着进园 / 第一次交到好朋友…
- ✅ 作品扫描：系统文稿相机自动裁边去畸变 + 端侧中文 OCR，把画和手工收进档案
- ✅ 入园查验接种证、给老师的一页：重新绘制的图片，只含必要字段，不带位置信息
- ⛔ 刻意不做：接送打卡、缴费、请假条——判据是「这条记录，18 岁的布布会想看吗」

**iOS / iPadOS 2.12**
- ✅ iOS 26 原生 Liquid Glass Tab、滚动收缩与“记录此刻”底部附件；iPad 自动切换系统侧栏
- ✅ iPad 多窗口、横竖屏、窄分屏、宽屏内容列与自适应网格；iPad Widget target 已开放
- ✅ SpeechAnalyzer / SpeechTranscriber 端侧转写，旧 SFSpeechRecognizer 与家庭 Whisper 分层兜底
- ✅ 可选的 Spotlight 时光实体索引，搜索结果通过 deep link 直达单条旧记录
- ✅ 首页限量查询 + SQLite COUNT/日期范围统计，不再随十几年数据量线性驻留
- ✅ XCUITest 覆盖 iPhone/iPad 根导航、快速记录、时光搜索与 iPad 横屏
- ✅ 2.12.2 身份卡回归修复：iPhone/iPad 首页恢复完整双面身份卡，材质、翻面、高光、触觉与无障碍同步升级

**地基**
- ✅ Xcode 工程（xcodegen）+ SwiftData ModelContainer（11 个实体）
- ✅ `AppEnvironment` 依赖容器（DI）+ `APIClient`/`AIService` 协议 + Mock 实现
- ✅ 设计系统 `BubuTheme` + `BigButton` + 仪式动画 + 波形/流式布局组件

**Wave A · 家庭账号系统**
- ✅ 首启引导三步（欢迎 → 布布生日 → 你是谁），温暖入场
- ✅ 家庭成员系统：增删改、头像 emoji、专属主题色、一键切换身份（无密码，适老）
- ✅ 布布档案：名字/生日/头像/出生地，生日驱动全局 `AgeCalculator`（X岁X月X天 / 来到世界第N天 / 距生日）

**Wave B · 端侧图片自动分析（零后端、隐私至上）**
- ✅ EXIF 提取拍摄时间 + GPS → `CLGeocoder` 反向地理编码出地名
- ✅ Apple `Vision` 框架场景分类 + 人脸计数 → 自动中文标签
- ✅ 保存时自动回填 Entry 的发生时间、地点、标签

**Wave C · 语音记录 + 详情可编辑/补充**
- ✅ `AudioRecorder`/`AudioPlayer`：录音 + 实时波形 + 播放
- ✅ 心情标签、语音记录随手记；已保存内容可改文字/时间/心情、可追加照片与语音
- ✅ 家人合奏：多成员对同一刻补充文字 + 语音，合成完整故事

**Wave D · 里程碑成就墙**
- ✅ 预设库（6 领域 24 项）一键添加 + 完全自定义
- ✅ 已点亮（高亮）/ 待点亮（灰）网格 + 进度环 + 达成仪式动画

**Wave E · AI 工坊（真实自托管 AI + 可验证降级）**
- ✅ 第一人称日记（父母视角 → 布布口吻）
- ✅ 年度成长电影：分阶段生成流程 + **真实可播放**的 Ken Burns 幻灯片（缩放平移 + 交叉淡入 + 旁白字幕）
- ✅ 家人合奏 / 成长洞察（漏记的「第一次」提醒）

**Wave F · 主题与首页仪表盘**
- ✅ 6 套主题配色 + 首页背景（主题渐变 / 布布照片）
- ✅ 首页成长仪表盘：年龄实时计数 + 统计卡 + 那年今日 + 最近精选

**Wave G · 时间胶囊（加密时间锁）**
- ✅ 写信（文字 + 语音）给未来的布布，设解锁时间（明年今天 / 6·12·18 岁生日快捷项）
- ✅ AES-GCM 加密封存（v2：密钥由规范化解锁时间派生，同步往返安全；兼容解开 v1 旧信）
- ✅ 倒计时锁定列表（未到期只显示倒计时），到期「庄重开启」仪式动画 + 解密读信
- ✅ v3 真 E2E：24 词家庭恢复码派生密钥，恢复码不随记录同步；兼容解开 v1/v2 旧信

**Wave H · 后端同步 + 真实 AI + 传承兜底**
- ✅ `PocketBaseClient`：REST 鉴权（token 复用 + 401 自动重登）+ 幂等 CRUD（localId 去重）+ 分页拉全量 + multipart 上传带进度
- ✅ 双向 `SyncEngine`：本地未同步推送 + 远端拉回（按集合持久化增量游标，失败不丢窗口）+ 远端媒体/语音自动下载落地——多设备也是真·离线优先
- ✅ AI 服务带 `X-API-Key` 鉴权 + 限流（fail-closed，不配 key 不服务）；App 默认不配置任何服务器、AI 默认关闭——数据外发必须用户显式开启
- ✅ `BubuAIService` 接 DeepSeek（v4-flash 首选 / v4-pro 兜底）：第一人称改写 / 旁白 / 归类 / 第一次识别 / 语音转写
- ✅ 成长之声：按岁归档布布的声音 + 家人对她说的话（声纹长卷，可转写）
- ✅ 全量档案导出：静态 HTML + 媒体包 + zip 分享——双击即看，永久离线可读
- ✅ 那年今日每日提醒 + 上传后 AI「这是第一次吗」确认弹窗
- ✅ 自托管后端脚手架 `server/`：PocketBase 集合迁移 + FastAPI（DeepSeek）+ 启动脚本 + 部署文档

## 工程原则

| 原则 | 落地 |
|---|---|
| 离线优先 | SwiftData 唯一真相源，UI 只读本地，断网全功能可用，联网自动同步 |
| 现代并发 | 全程 `async/await` + `@Observable` + `@MainActor`，无 Combine/ObservableObject |
| 隐私至上 | AI 走自托管 FastAPI（只发文字不传图）；时间胶囊 AES-GCM 端到端加密；Tailscale 内网；无第三方分析 |
| 数据可迁移 | 媒体原文件 + 结构化数据双备份，一键导出可离线打开的全量档案 |
| 适老化一等公民 | 姥姥能用 = 验收标准 |
| 接口先行 | 网络/AI 能力均为 protocol，真实实现与确定性降级解耦，UI 不依赖具体模型供应商 |

## 自托管部署

后端在 `server/` 目录，详见 [`server/README.md`](server/README.md)：
- **PocketBase**（数据库+文件+鉴权+同步）跑在 Mac mini + 外接 SSD，Tailscale 内网访问
- **FastAPI**（DeepSeek AI）独立服务，App 设置页填地址即可启用
- App 设置页：填服务器地址 + 家庭账户 → 多台手机自动同步；开启 AI → 启用自托管创作与检索能力

## 构建运行

### iOS

```bash
# 安装项目生成器（一次）
brew install xcodegen

# 生成 Xcode 工程
cd BubuTimeMachine
xcodegen generate

# 编译并运行（命令行）
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' clean build

# 单元测试（加密/格式嗅探等回归）
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# 或直接 open BubuTimeMachine.xcodeproj 用 Xcode 运行
```

要求：Xcode 26+、iOS/iPadOS 26.0+ 部署目标。`project.pbxproj` 由 `project.yml` 生成，**修改工程配置请改 `project.yml` 后重跑 `xcodegen generate`**。iOS 27 新交互使用编译器与系统双门禁；安装 Xcode 27 后走 shadow build 验证，不影响 Xcode 26 正式路径。

### HarmonyOS

```bash
cd harmony
./scripts/check-repository-hygiene.sh
./scripts/build-local.sh
```

要求：DevEco Studio 26.0.0+ 与 HarmonyOS API 26 SDK。构建默认生成 unsigned HAP；真机安装签名只保存在本机 DevEco 配置中，不得提交到 Git。

## 目录结构

```
BubuTimeMachine/
├── App/            # @main 入口、ModelContainer、AppEnvironment(DI)、RootTabView
├── Models/         # 8 个 @Model：Entry/Media/Milestone/FirstTime/TimeCapsule/VoiceMemo/Comment/GrowthMovie
├── Services/       # 协议先行：Networking(APIClient/Mock/ServerConfig) / AI / Sync / Media / Security
├── Features/       # 按页面：Capture / Timeline / Milestones / AIStudio / Capsule / Settings
├── DesignSystem/   # BubuTheme / BigButton / CeremonyAnimation / Components
└── Resources/      # Assets
```

## 当前发布路线

- iOS：继续以 App Store / TestFlight 实际发布证据为准。
- HarmonyOS：完成签名、旧版覆盖安装、跨端同步、权限/弱网/杀进程、服务卡片、Live View 和小艺意图真机验收。
- 任何平台都不以“源码存在”代替用户路径可运行；逐项证据见 [`harmony/PARITY_MATRIX.md`](harmony/PARITY_MATRIX.md)。
