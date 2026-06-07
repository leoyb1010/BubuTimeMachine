# 布布时光机 · BubuTimeMachine

> 真正的用户，是未来 18 岁的布布。
> 一切技术决策都要回答：30 年后，这些数据还能被她完整地读到、看到、听到吗？

原生 iOS App（SwiftUI + SwiftData），为家庭记录孩子成长、传承一生。离线优先、隐私至上、自托管。

## 当前进度

已完成 **M0 地基** 与 **M1 本地闭环**（不依赖任何后端，离线全功能可用）：

- ✅ Xcode 工程（xcodegen 生成）+ SwiftData ModelContainer（全部 8 个实体）
- ✅ `AppEnvironment` 依赖容器（DI）+ `APIClient` / `AIService` 协议 + Mock 实现
- ✅ `ServerConfig` 设置页：可填 Base URL + 连接测试 + 身份切换
- ✅ `CaptureHomeView` 超大主按钮（适老）+ `PhotosPicker` 选片/选视频
- ✅ 选片即写入 SwiftData（`syncState=.local`），`MediaStore` 存沙盒 + 生成缩略图
- ✅ `TimelineView` 用 `@Query` 按 `happenedAt` 倒序、按「年-月」分段展示
- ✅ 设计系统 `BubuTheme`（柔和色板 / 大字号 / 圆角 / 口语文案）+ `BigButton` + 仪式动画

灵魂功能（里程碑 / AI 工坊 / 时间胶囊）已留占位页与协议接口，待逐个深入。

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
