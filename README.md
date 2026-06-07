# 布布时光机 · BubuTimeMachine

> 真正的用户，是未来 18 岁的布布。
> 一切技术决策都要回答：30 年后，这些数据还能被她完整地读到、看到、听到吗？

原生 iOS App（SwiftUI + SwiftData），为家庭记录孩子成长、传承一生。离线优先、隐私至上、自托管。

## 当前进度

已完成 **完整的离线体验层**（不依赖任何后端，全功能本地可用）。核心闭环 + 六大专属能力：

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

**Wave E · AI 工坊（Mock 可玩，留真 LLM 接口）**
- ✅ 第一人称日记（父母视角 → 布布口吻）
- ✅ 年度成长电影：分阶段生成流程 + **真实可播放**的 Ken Burns 幻灯片（缩放平移 + 交叉淡入 + 旁白字幕）
- ✅ 家人合奏 / 成长洞察（漏记的「第一次」提醒）

**Wave F · 主题与首页仪表盘**
- ✅ 6 套主题配色 + 首页背景（主题渐变 / 布布照片）
- ✅ 首页成长仪表盘：年龄实时计数 + 统计卡 + 那年今日 + 最近精选

**Wave G · 时间胶囊（端到端加密）**
- ✅ 写信（文字 + 语音）给未来的布布，设解锁时间（明年今天 / 6·12·18 岁生日快捷项）
- ✅ AES-GCM 加密封存，密钥由解锁时间派生——篡改时间无法解出
- ✅ 倒计时锁定列表（未到期只显示倒计时），到期「庄重开启」仪式动画 + 解密读信

成长之声 / 后端同步（PocketBase）/ 真实 AI（FastAPI）为后续阶段，协议与加密原语已就绪。

## 工程原则

| 原则 | 落地 |
|---|---|
| 离线优先 | SwiftData 唯一真相源，UI 只读本地，断网全功能可用 |
| 现代并发 | 全程 `async/await` + `@Observable` + `@MainActor`，无 Combine/ObservableObject |
| 隐私至上 | AI 走自托管 FastAPI；时间胶囊 AES-GCM 端到端加密；无第三方分析 |
| 数据可迁移 | 媒体原文件 + 结构化数据双备份，可一键导出全量档案（规划中） |
| 适老化一等公民 | 姥姥能用 = 验收标准 |
| 接口先行 | 网络/AI 能力均为 protocol，先 Mock 后实现，UI 不依赖具体后端 |

## 构建运行

```bash
# 安装项目生成器（一次）
brew install xcodegen

# 生成 Xcode 工程
cd BubuTimeMachine
xcodegen generate

# 编译并运行（命令行）
xcodebuild -project BubuTimeMachine.xcodeproj -scheme BubuTimeMachine \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# 或直接 open BubuTimeMachine.xcodeproj 用 Xcode 运行
```

要求：Xcode 26+、iOS 18+ 部署目标。`project.pbxproj` 由 `project.yml` 生成，**修改工程配置请改 `project.yml` 后重跑 `xcodegen generate`**。

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

## 后续路线（按计划书）

- **M2 上传同步**：部署 PocketBase（Mac）+ Tailscale，实现 `PocketBaseClient` + `UploadQueue` 后台分片上传 + `SyncEngine` 状态收敛
- **M3 AI 归类**：FastAPI 服务（EXIF/视觉打标/事件聚类/"这是第一次吗"），结果回写时光轴自动重排
- 之后：时间胶囊 → 成长之声 → 第一人称日记 → 家人合奏 → 年度成长电影
