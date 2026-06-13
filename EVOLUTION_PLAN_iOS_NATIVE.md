# 布布时光机 · iOS 系统级集成 + 动效/UI 升级评估（v2）

> 评估文档（**只评估，不动代码**）。读完决定是否进化、从哪开始。
> 基线：`worktree-perf-and-fixes` 分支（已含 120Hz/背景/性别血型/缩放转场修复）。
> 目标：iOS 26 · Swift 6 严格并发 · SwiftData · 自托管 PocketBase。
>
> **v2 修订**：根据 Apple 官方框架定位重排架构 ——
> **App Intents 是底座**（动作/实体开放给 Siri/Spotlight/Shortcuts/Widgets/Controls/Action Button），
> **WidgetKit 是统一框架**（桌面小组件 + Live Activities + Controls 都在它名下），
> 不再把 App Intents 当某个阶段的附属品。

---

## 0. 架构心智模型（v2 核心修订）

上一版把 App Intents 当「阶段 3 的低成本附加项」是**错的**。正确的分层是：

```
┌─────────────────────────────────────────────────────────────┐
│  系统入口层（曝光面）                                          │
│  Siri · Spotlight · 快捷指令 · 桌面/锁屏小组件 · 灵动岛       │
│  · 控制中心 Controls · Action Button · App Clip               │
└───────────────▲─────────────────────────────────────────────┘
                │ 全部通过↓
┌───────────────┴─────────────────────────────────────────────┐
│  ★ App Intents 底座（AppIntent / AppEntity / AppShortcut）   │
│    把「记录此刻」「布布年龄」「开始录音」等动作&实体          │
│    一次定义，所有系统入口复用                                 │
└───────────────▲─────────────────────────────────────────────┘
                │ 读/写↓
┌───────────────┴─────────────────────────────────────────────┐
│  ★ 共享数据层（App Group）                                    │
│    SwiftData store + MediaStore 迁到 group. 容器              │
│    + 无 UI 依赖的纯写入层 EntryWriter（Intent 后台落库）      │
└──────────────────────────────────────────────────────────────┘
```

**两条底座必须先修**：① App Group 共享数据；② App Intents + 无 UI 写入层。
修完之后，上层每个系统入口都是「薄薄一层壳」，复用同一套 intent，成本骤降。

---

## 1. 现状扫描（决定计划的关键事实）

### 1.1 已具备
| 能力 | 位置 | 复用点 |
|---|---|---|
| 年龄计算 | `AgeCalculator.swift` | 小组件/Siri/灵动岛核心数字 |
| 布布档案 | `FamilyMember.swift`(ChildProfile) | 身份卡、Spotlight 实体 |
| 时间胶囊解锁日 | `TimeCapsule.unlockAt` | Live Activity 倒计时 |
| 里程碑 | `Milestone.isAchieved` | 进度小组件 |
| **干净的记录写入路径** | `CaptureModel.swift:88-178` | `Entry()→insert→save`，**可抽成无 UI 的 EntryWriter 供 Intent 调用** ✅ |
| 录音 `elapsed`(可观察) | `AudioRecorder.swift:14` | 录音中 Live Activity ✅ |
| 20+ 吉祥物表情 | `BubuExpression.swift` | 全系统入口的情绪化呈现 |
| 本地通知授权/排程 | `ReminderScheduler.swift` | 与 Live Activity 联动 |

### 1.2 缺地基（必补）
| 缺口 | 影响 | 严重度 |
|---|---|---|
| **无 App Group** | 所有系统 extension 读不到数据 | 🔴 阻断 |
| store/MediaStore 在 `.documentDirectory` | 同上，需迁 `group.` 容器 + 历史数据迁移 | 🔴 阻断 |
| **无 App Intents 层** | Siri/小组件交互/Controls/Action Button 全无法接 | 🔴 底座 |
| 记录写入与 UI(CaptureModel/@MainActor) 耦合 | Intent 后台落库需抽无 UI 写入层 | 🟠 |
| 无 Widget/Activity/Control target | `project.yml` 仅 app+test | 🟠 |
| Info.plist 无 `NSSupportsLiveActivities` | 灵动岛前置 | 🟠 |
| 账号=邮箱密码+角色(UserDefaults) | App Clip 无法便捷登录 → 只能匿名轻量记录后认领 | 🟠（影响 App Clip 形态） |

---

## 2. 系统入口逐项评估（按性价比排序）

> 每项标注：价值 / 成本 / 前置 / 风险。成本已计入「底座就绪后」。

### 2.1 🥇 App Intents 底座本身 —— 先建，杠杆最大
**做什么**：定义核心 intent 与实体，一次实现多处复用：
- `RecordMomentIntent`（记录此刻，可带预填文字/照片）—— 复用于 Siri、小组件按钮、Controls、Action Button、快捷指令。
- `BubuAgeIntent`（布布多大了）—— Siri 直接念。
- `StartVoiceMemoIntent` / `StopVoiceMemoIntent` —— 配合录音 Live Activity。
- `ChildProfileEntity`（AppEntity）—— 让布布成为 Spotlight 可检索实体。
- `AppShortcutsProvider` —— 预置短语，免用户手动配快捷指令。

**价值**：极高（一次写，6+ 入口复用）。**成本**：中（含抽 EntryWriter）。**前置**：§3.1 App Group。**风险**：中（后台写库的并发与 save 失败处理；与 SyncEngine 不能并发写）。

### 2.2 🥈 WidgetKit · 桌面/锁屏小组件
- `.systemSmall` 身份卡 / `.systemMedium` 那年今日 / `.systemLarge` 成长墙。
- `.accessoryCircular` 生日倒计时环 / `.accessoryRectangular` 锁屏年龄行。
- **交互按钮**直接挂 `RecordMomentIntent`（iOS 17+ 交互小组件）。

**价值**：极高（每日高频触点、App Store 门面）。**成本**：中。**前置**：§3.1 + §2.1。**风险**：低（TimelineProvider 按天刷新，不耗电；**禁止**在 widget 内跑动画循环）。

### 2.3 🥈 WidgetKit · Live Activities + 灵动岛
两个天然「正在发生」场景：
- **录音中**（复用 `AudioRecorder.elapsed`）：紧凑态 🎙️+时长，展开态波形+停止按钮（接 `StopVoiceMemoIntent`）。**强实用**。
- **时间胶囊倒计时**（复用 `unlockAt`）：临近解锁起 Live Activity，锁屏/灵动岛用 `Text(timerInterval:)` 系统自走倒计时，**零耗电**、叙事高光。

**价值**：高。**成本**：中高（ActivityKit 生命周期+UI 约束）。**前置**：§3.1 + Info.plist `NSSupportsLiveActivities`。**风险**：中（活跃时长上限 8h/总 12h；需真机验证；未授权要降级）。

### 2.4 🥉 WidgetKit · Controls（控制中心 / 锁屏 / Action Button）
- 一个「记录布布」Control，放控制中心、锁屏、Action Button，一键拉起记录。
- 复用 `RecordMomentIntent`，几乎零增量成本。

**价值**：中高（Action Button 机型一键直达）。**成本**：低。**前置**：§2.1。**风险**：低。

### 2.5 App Clips（线下/即时场景）—— 需先定义场景
App Clip 价值取决于**有没有线下分发场景**。布布是私密家庭记录类，天然分享面窄，需先想清楚用例，否则投入产出比低。

**可能的用例**：
- 月龄照打卡点 / 早教机构活动二维码 → 扫码用 App Clip 留一条「今天布布在 XX」，**匿名记录、回家用完整 App 认领**。
- 家庭成员快速参与：长辈扫码留一句话/一张照片，不必装完整 App。

**约束**：账号是邮箱密码（§1.2），App Clip 不便登录 → 只能做**匿名轻量写入 + 延后认领**，需服务端配合一个「临时投稿」通道。
**价值**：中（取决于场景）。**成本**：高（独立 target + 10MB 限制 + 认领流程 + 服务端改动）。**建议**：**暂缓**，等核心系统集成完成、且确有线下场景再做。

### 2.6 其它（择机）
| 特性 | 价值 | 备注 |
|---|---|---|
| Spotlight 索引（CSSearchableItem/AppEntity） | 中高 | 让「布布」「里程碑」在系统搜索可达，随 §2.1 实体顺带做 |
| StandBy 充电大字年龄 | 低 | 适老化，低成本 |
| Apple Intelligence 配图 | 中 | 「布布的故事」AI 插画，受设备限制 |
| TipKit 新功能引导 | 中 | 适老化定位友好 |

---

## 3. 实施分阶段计划（v2）

### 阶段 0 · 双底座 🔴 必做前置（建议独立 PR）

**0A — App Group 共享数据**
1. 开 App Group `group.com.bubu.timemachine`，加到主 App + 各 extension entitlements。
2. SwiftData `ModelConfiguration` 改 `groupContainer:`；**写一次性历史 store 迁移**（旧沙盒→共享容器，幂等+可回滚+真机灰度）。
3. MediaStore 目录迁共享容器，搬运历史照片/缩略图。
4. 抽 `BubuShared`（模型只读视图 + AgeCalculator），app 与 widget 共用。

**0B — App Intents 底座**
1. 抽 **`EntryWriter`**：无 UI、可在 extension 进程内拿共享 `ModelContext` 直接 `Entry()→insert→save` 的纯写入层（从 `CaptureModel` 提炼，App 内仍走 CaptureModel 调它）。
2. 定义 `RecordMomentIntent` / `BubuAgeIntent` / `StartVoiceMemoIntent` / `StopVoiceMemoIntent`。
3. 定义 `ChildProfileEntity`（AppEntity）+ `AppShortcutsProvider` 预置短语。
4. 处理并发：Intent 写库与 SyncEngine 不并发写（串行化/标脏后交由下一轮同步）。

> 0A 与 0B 有先后：0A 先（拿到共享容器），0B 的 EntryWriter 依赖共享 ModelContext。

### 阶段 1 · 桌面/锁屏小组件（WidgetKit）
- 新增 `BubuWidgets` extension target；`TimelineProvider` 按天 + 生日/里程碑事件刷新。
- 5 个 family；交互按钮挂阶段 0B 的 `RecordMomentIntent`。

### 阶段 2 · Live Activities + 灵动岛
- Info.plist 加 `NSSupportsLiveActivities`。
- 先**录音中**（自包含、实用），再**时间胶囊倒计时**（高光）。

### 阶段 3 · Controls（控制中心/锁屏/Action Button）
- 基于阶段 0B intent，几乎零增量。

### 阶段 4 · Spotlight / Siri 打磨
- AppEntity 索引、AppShortcut 短语调优、Siri 念年龄。

### 阶段 5 · 动效/UI 第二轮（见 §4，可与任意阶段并行）

### （暂缓）App Clip
- 待核心完成 + 确有线下场景再评估，需服务端「匿名投稿+认领」通道。

---

## 4. 动效 / UI 第二轮升级

> 第一轮已解决卡顿根因。第二轮聚焦高级感，原则不变：**交互驱动 > 持续动画，可打断 > 播完等待，widget 内零动画循环**。

### 4.1 动效
| 项 | 升级 | 价值 | 成本 |
|---|---|---|---|
| 里程碑点亮 | 粒子/彩带 + `.symbolEffect(.bounce)` + 吉祥物 cheer 联动 | 高 | 中 |
| 年龄数字 | 「第N天」每日 +1 滚动；加载从 0 卷到当前 | 中高 | 低 |
| 记录保存成功 | `.sensoryFeedback` + 吉祥物 yeah 弹跳，统一完成感 | 中 | 低 |
| 身份卡翻面 | 高光扫过 + haptic 序列 | 中 | 低 |
| 相册查看器 | 捏合跟手缩放 + 共享元素 zoom 扩展到相册 | 中 | 中 |
| SF Symbols | 全面 `.symbolEffect` 替代静态图标 | 中 | 低 |
| Liquid Glass | 主 CTA 用 iOS 26 `.interactive` 触摸折射 | 中 | 低 |
| 同步状态 | 强化 `bubuFloating` 拟人同步动画 | 中 | 低 |

### 4.2 UI
| 项 | 评估 |
|---|---|
| 动态字体/适老化 | 最大字号（姥姥模式）全 App 不破版，硬指标 |
| 深色模式 | 全页对比度复核 |
| 空状态 | 吉祥物表情做有温度的空状态 |
| 首页信息密度 | 卡片偏多，评估可折叠/个性化排序 |
| 小组件↔App 视觉同源 | 同色板/圆角/字体 token 复用 |

---

## 5. 风险与注意事项
1. **数据迁移（阶段 0A）头号风险** —— 动到所有用户本地数据，独立 PR + 备份 + 幂等 + 回滚 + 真机灰度。
2. **后台写库并发（0B）** —— Intent 写与 SyncEngine 写串行化，避免冲突；save 失败要有兜底。
3. **隐私** —— 小组件/锁屏会被旁人看到照片姓名，需「锁屏隐藏敏感信息」开关。
4. **耗电** —— 系统计时（`Text(timerInterval:)`）+ 按天刷新；**widget/Activity 内禁跑动画循环**（勿重蹈第一轮覆辙）。
5. **降级** —— 未授权 Live Activity / 未加小组件 / 未配 Siri 时，主流程零影响。
6. **真机验证** —— 灵动岛/Action Button/帧率本机测不准，需 ProMotion 真机。

---

## 6. 建议进化顺序

```
阶段0A 共享数据(App Group+迁移)   ← 必做、独立PR、最高风险
  └ 阶段0B App Intents底座(+EntryWriter)  ← 底座，杠杆最大
       ├ 阶段1 桌面/锁屏小组件      ← 性价比最高、门面
       ├ 阶段2 灵动岛(录音→胶囊)    ← 高光、需真机
       ├ 阶段3 Controls/Action Button ← 零增量
       └ 阶段4 Spotlight/Siri 打磨
阶段5 动效/UI 第二轮              ← 可并行、逐项交付
(暂缓) App Clip                   ← 待线下场景明确
```

**最小有感闭环**：阶段 0A + 0B + 小尺寸身份卡 + 生日倒计时环 + 一个 `RecordMomentIntent`（同时点亮 Siri/小组件按钮/Action Button）。一次把「每天看到布布长大」+「一键记一笔」都接通系统级入口。

---

## 7. 工作量粗估（底座就绪后，不含数据迁移测试周期）
| 阶段 | 粗估 | 独立交付 |
|---|---|---|
| 0A 共享数据+迁移 | 大（含测试） | 是 |
| 0B App Intents 底座+EntryWriter | 中 | 是 |
| 1 小组件（5 family） | 中 | 是 |
| 2 灵动岛（录音+胶囊） | 中高 | 分两次 |
| 3 Controls/Action Button | 小 | 是 |
| 4 Spotlight/Siri 打磨 | 小 | 是 |
| 5 动效/UI 第二轮 | 中（拆细） | 逐项 |
| App Clip（暂缓） | 高（含服务端） | 独立 |

> 本机无法做真机帧率/灵动岛/Action Button 验证，相关阶段交付后需你 ProMotion 真机实测。
