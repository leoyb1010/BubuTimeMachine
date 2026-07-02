# 布布时光机 · iOS 第二轮 Review + 下一轮升级计划

> 日期：2026-07-02 ｜ 只看 iOS（不含鸿蒙）｜ 基线：`main`@`136cdc6` + 一轮未提交的大升级（55 个 iOS 文件改动）
> 内容：① 上轮修复核验 ② 本轮新发现的 bug ③ 小组件高级化专章 ④ 下一轮迭代方案
> 本文档只做审查与规划，未改动任何业务代码。

---

## 0. 先说结论

**好消息**：上一轮的升级质量很高。
- **编译恢复了**：`clean build` + `clean test` 全绿，**32 个测试全部通过**（上一轮的 P0-0 Widget 编译阻断已修好——`GrowthMeasurementExtractor` 抽成了独立文件 `App/GrowthMeasurementExtractor.swift` 并加进了 Widget target）。
- 上轮计划的核心项基本都动过手了（同步游标、删除队列、称谓枚举、健康输入框、定位 continuation…共 55 个 iOS 文件有改动）。

**这轮要处理的**：
1. **几处上轮修复留下的收尾缺口 + 新引入的边界问题**（见 §2）。
2. **桌面小组件**——你说得对，现在的完成度是"能用、干净"，但离"漂亮、高级"还有明显距离。核心问题是**照片没当主角、材质是廉价的白卡片堆叠、缺深色/tinted 适配、点了没反应（无 deep link / 无交互）**。这是下一轮最值得做、投入产出比最高的一块（见 §3）。

> ⚠️ **提交纪律提醒**：这 55 个 iOS 改动 + 服务端改动目前**全在工作区未提交**。建议先把这轮升级按功能拆成几个中文 commit 落袋，再开始下一轮——否则一旦出问题很难回退定位。

---

## 1. 上轮修复核验（哪些真修好了）

基于对当前工作区代码的实读：

| 上轮问题 | 状态 | 证据 |
|---|---|---|
| P0-0 Widget 编译阻断 | ✅ 已修 | 新增 `App/GrowthMeasurementExtractor.swift`，`project.yml` widget sources 已含；clean build 绿 |
| P0-1 同步游标格式 | ✅ 已改 | `PocketBaseClient.swift` + `PocketBaseClientSyncQueryTests.swift` 都有改动，测试通过 |
| P1-1 删除队列 | 🟡 已扩展 | `PendingDeletion.swift`、`SyncEngine.swift`、各 UI 调用点均有改动——**需确认是否已覆盖全部集合**（见 §2-A） |
| P1-8 定位 continuation | ✅ 已改 | `LocationService.swift` 有改动 |
| 称谓枚举统一 | 🟡 已改 | `Enums.swift`、`ServerConfig.swift`、`MembersView.swift`、`AccountView.swift` 均改动——需确认旧数据兼容 |
| 健康备注输入框消失 | ✅ 已改 | `HealthRecordSheet.swift` 有改动 |
| MediaViewer 主线程解码 | 🟡 已改 | `MediaViewer.swift` 有改动——需确认异步化后无翻页竞态 |
| 录音 LiveActivity 孤儿 | 🟡 已改 | `VoiceComponents.swift`、`BubuLiveActivity.swift` 有改动 |
| TabBar 遮挡二级页 | 🟡 已改 | `RootTabView.swift` 有改动——需确认覆盖所有二级页 |
| Dynamic Type（适老化） | ⚠️ 待确认 | `BubuTheme.swift` 有改动，但需核实是否全量改为 `relativeTo:` / `.system(.body)` |

> 🟡 = 改了但要复验缺口；⚠️ = 关键项，务必确认。因为改动全部未提交、无独立 commit 说明，建议下一轮开工前先自己 `git diff` 逐块确认这些 🟡/⚠️ 项的完成度。

---

## 2. 本轮新发现 / 待复验的问题

> 这些来自对本轮改动文件的静态审查。因为改动量大且未提交，标注了每条的确认方式。

### A. 同步层（改动最大，最需盯）
- **【复验】删除队列是否真覆盖全集合**：上轮计划要求 Media/Comment/VoiceNote/FamilyMember/Milestone/TimeCapsule 全部接入 `PendingDeletion`。改动点分散在 `EntryDetailView`/`MembersView`/`MilestoneSheets`/`CapsuleHomeView`，需逐个确认：① 都走了队列而非只删本地；② 各 `mergeRemoteXxx` 插入前都查了删除队列**防复活**（上轮只有疫苗有这个检查）。**建议补一个 SyncEngine 单测**：删除→拉取，确认不复活。
- **【复验】游标三处格式一致性**：游标改造后，"推送时写入 `clientUpdatedAt` 的格式" vs "拉取 filter 的格式" vs "服务端 date 字段存储格式" 必须三者一致（都是空格分隔 `yyyy-MM-dd HH:mm:ss.SSS'Z'`）。只改了 filter 没改推送写入 = 依然错位。核对 `PocketBaseClient` 里 `addSyncTimestamp` / `syncTimestampString` 两处。
- **【复验】冲突比较的空值边界**：若冲突策略改成了"比较 `clientUpdatedAt`"，要处理老数据 `clientUpdatedAt` 为 nil 的情况（迁移前的记录），否则 nil 参与比较会走错分支。

### B. 仍未接线 / 半成品（上轮可能没顾上）
- **胶囊倒计时灵动岛**：`BubuLiveActivity.swift` 改了（过期 Range 崩溃应已修），但 `BubuActivityController.startCapsuleCountdown` 是否被真正调用过要确认——不接线就还是死功能。
- **`heroMode` 照片背景**：确认首页是否真的读取并渲染了 `heroBackgroundFileName`（上轮的首页主题接线项）。
- **死代码清单**：`BubuMeshHero` / `BubuCountUp` / `ThumbnailProvider.prefetch` / 生日图标联动——若这轮没接线就明确删掉，别留着让注释说谎。

### C. 小组件数据层（读代码确认的真实问题）
- **`BubuWidgetData.swift:183` 缺缩略图时回退读原图，上限 18MB/张**：`systemLarge` 的时光款会同时加载 3 张照片（`BubuPhotoStrip`），若都走原图回退，3×最高 18MB 叠加 avatar 会逼近 WidgetKit ~30MB 内存红线 → 渲染进程被杀 → **小组件显示空白**。建议：回退上限降到 2–3MB，且只认 thumbnail 目录、原图不回退（宁可显示占位）。
- **`idNumber` 依赖 App Group 快照**：`SharedDefaults` 里若 `idNumber` 缺失会回退到 `defaultIDNumber`（`BUBU20240522`）——换个孩子/新装未同步时 widget 显示错号。确认 `SharedWidgetSnapshot.make` 是否总是写入正确的 idNumber。

---

## 3. 桌面小组件高级化专章（下一轮重点）

### 3.1 现状诊断（我逐行读了 `BubuWidgets.swift`）
**已有的**：3 款 widget（身份卡 / 今日时光 / 成长一览）× 3 尺寸（S/M/L）；头像用 ImageIO 降采样（好）；按天零点刷新（省电，对）；暖色马卡龙渐变背景；生日倒计时数字用 `contentTransition(.numericText())`。工程底子是干净的。

**"廉价感"具体来自哪里**（这是你说"可以更高级"的症结）：
1. **照片始终是配角**。三款里照片要么是小圆头像、要么是固定尺寸的"瓷砖"（`BubuPhotoTile`），从不作为整卡背景铺满。而 2026 年最高级的家庭类 widget（Apple「精选回忆」、Day One）都是**整图出血 + 渐变蒙版压字**——让孩子的脸占满整个小组件，才有"相框"的情感重量。
2. **材质是"白色半透明卡片叠卡片"**。`BubuInfoChip`/`BubuMetricPill` 全是 `.white.opacity(0.66)` 的小圆角块堆在渐变上，信息密度高但视觉碎、层次浅。高级感来自**克制**：大留白 + 一个主信息 + 一行次要信息，而不是塞满 4 个 pill。
3. **字号字重太均匀**。大量 `weight(.black)`，缺乏"一个巨大数字 + 极小说明"的戏剧性对比（Widgetsmith 高级款的核心手法）。
4. **完全没有深色 / tinted / 锁屏适配**。iOS 18+ 桌面有"深色""染色(tinted)"两种渲染模式，当前渐变背景在 tinted 模式下会被系统单色化成一坨、白卡片全糊。且**没有 accessory 系列**（锁屏 / StandBy 完全缺席）。
5. **点了没反应**。widget 没有 `.widgetURL` / `Link`——点身份卡应跳身份卡页、点时光应跳时光轴、点成长应跳成长曲线。这是"高级"最廉价的一分：让它可点。

### 3.2 下一轮小组件升级方案（按投入产出排序）

#### 🥇 第一优先：三件立刻显质感的事（改动小、效果大）
1. **整图沉浸版式**（今日时光 & 身份卡 L）：照片 `scaledToFill` 铺满整卡 → 底部叠 `LinearGradient(.black.opacity(0→0.6))` 蒙版 → 白字信息压在渐变上。参考 Apple「精选回忆」。小尺寸只留"名字 + 年龄/日期"一行，别塞 pill。
2. **深色 + tinted 双模式适配**：
   - 用 `@Environment(\.widgetRenderingMode)` 分支：`.fullColor` 走现在的彩色版；`.accented` / `.vibrant` 时改成"单色友好"版式（去渐变、用 `.widgetAccentable()` 标记主色区、文字走系统 vibrant）。
   - 背景用 `AccessoryWidgetBackground()`（锁屏）和对深色友好的低饱和渐变。
3. **加 deep link**：整卡包 `.widgetURL(URL(string: "bubu://identity"))`，App 里 `onOpenURL` 路由到对应 tab/页。三款各指一处。

#### 🥈 第二优先：补齐尺寸家族（覆盖更多桌面场景）
4. **锁屏 accessory 系列**（`.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline`）：
   - Circular：生日倒计时环（`Gauge` 或 `ProgressView(.circular)`），中间"天数"。
   - Rectangular：一行"布布 · 1岁7个月 · 第578天"。
   - Inline：锁屏顶部"🎂 还有 12 天生日"。
   - 这是家长最高频看一眼的位置，现在完全空缺。
5. **StandBy 夜间模式**（横屏充电时）：iOS 17+ 桌面 widget 在 StandBy 会放大显示，需确认整图版式在放大下不糊——用 `.systemMedium` 的整图版即可自动适配，但要测 tinted 夜光模式（红光单色）。

#### 🥉 第三优先：交互式 & 智能化（iOS 17+ App Intents）
6. **交互式快速记录**（`Button(intent:)`）：中尺寸右下角一个"＋ 记一笔"按钮，用 App Intent 直接拉起快速记录（`BubuRecordControl` 已有 Control 骨架，可复用 Intent）。点一下就能记，不用先开 App——这是"高级家庭 App"的标志性体验。
7. **智能轮播 / 相关性**（`TimelineProvider` 的 `relevance` 或换 `AppIntentConfiguration`）：
   - 生日前 7 天，身份卡自动切成"生日倒计时"强调态。
   - "那年今日"有内容时，时光款自动优先显示历史同期照片（情感杀伤力最大的一个点，且数据已有）。
8. **可配置 widget**（`AppIntentConfiguration` + `WidgetConfigurationIntent`）：长按编辑让用户选"显示哪个孩子 / 显示头像还是最近照片 / 主题色"。为将来多娃做准备。

#### 视觉体系统一（配合上面做）
- 定义一套 **widget 专用的深色友好色板**（现在的 `WidgetPalette` 只有浅色版），并抽出"整图+蒙版"和"卡片"两种基础版式组件，三款复用。
- 照片款统一走 **thumbnail-only + 2MB 上限**（修 §2-C 内存红线）。
- 加 `.widgetAccentable()` 到主数字/头像描边，让 tinted 模式有重点。

### 3.3 小组件升级验收标准
- [ ] 浅色 / 深色 / tinted(染色) 三种桌面模式下都不糊、可读；
- [ ] 锁屏三款 accessory 正常渲染；
- [ ] 点击每款跳转到正确页面；
- [ ] `systemLarge` 时光款加载 3 图不超内存红线（真机加桌面验证不空白）；
- [ ] 生日前 7 天身份卡进入强调态；
- [ ] （若做交互）桌面点"＋记一笔"能直接拉起记录。

---

## 4. 下一轮 iOS 迭代方案（小组件之外）

> 按"上线价值 / 情感价值 / 工程量"综合排序。

### 4.1 稳固数据（上线前应清）
- 把本轮 55 个改动**拆成独立 commit** + 跑一遍 §2 的复验清单，确认删除防复活、游标三处一致、冲突空值边界都对。
- 补 **SyncEngine 单测**（删除防复活 / 同日增量拉取 / 字段清空往返 / context 未 attach 不推游标）——这是数据安全最薄弱的测试区。
- **上传改后台 URLSession + 断点续传**（现为前台，弱网大视频易失败）。

### 4.2 情感体验（差异化，最该投入的地方）
- **"那年今日"升级为首页高光 + 通知 + 小组件**（现在藏得深）。数据已有，接通就是杀手锏。
- **封存胶囊仪式动画**（现在开信有三幕、封信只有"咔哒"——不对称）。复用已有的 `BubuBurst` + 盖章触觉。
- **"这是第一次吗"改自定义卡片**（现在是系统 alert，高光时刻配系统弹窗最浪费）。
- **成长绘本用真实关联照片**（现在是占位渐变），里程碑本就关联 Entry，接通即"翻旧相册"。
- **成长电影配乐**（Ken Burns 做得细但全程静音，`BubuSound` 体系已有素材）。

### 4.3 适老化收尾（"姥姥能用"）
- 确认 Dynamic Type 全量落地（§1 ⚠️ 项），并在最大字号档做布局降级测试（四宫格→单列）。
- 加深 `secondaryText` 对比度（现约 2.6:1，AA 要 4.5:1）。
- 所有删除/编辑操作给**可见按钮**（现在多靠长按，老人发现不了）。
- 相册查看器补**分享 / 保存到系统相册**（家庭 App 第一刚需——发家族群）。

### 4.4 系统能力（iOS 原生集成，锦上添花）
- **App Intents / Siri**：`BubuRecordControl` 已有 Control 骨架，补齐"嘿 Siri 给布布记一笔"。
- **Spotlight 索引**：让记录能在系统搜索里搜到。
- **Controls（控制中心 / Action Button）**：一键记录（骨架已在）。
- **PDF 年册导出**（`YearbookExporter` 已有，改后台渲染避免主线程冻结）。

---

## 5. 建议执行顺序

| 阶段 | 内容 | 说明 |
|---|---|---|
| **0** | 拆 commit + 跑 §2 复验清单 | 先把这轮成果落袋、确认没留隐患 |
| **1** | 小组件高级化第一优先（整图版式 + 深色/tinted + deep link） | 你的重点，改动小效果大 |
| **2** | 小组件 accessory 系列 + 交互式记录 | 补齐家族 + 标志性交互 |
| **3** | "那年今日"三端打通 + 封存仪式 + 第一次卡片 | 情感差异化 |
| **4** | 适老化收尾 + 相册分享 + 后台上传 | 上线体验合格线 |
| **5** | Siri / Spotlight / 年册 | 系统能力锦上添花 |

**每阶段出口**：`xcodegen generate` → clean build + clean test 全绿 → 模拟器种子截图核验 → 中文 commit。

---

## 附：这轮我实际做了什么（为什么可信）
- 实测跑了 `clean build` + `clean test`：**BUILD/TEST SUCCEEDED，32 测试全过**（确认上轮 P0-0 编译阻断已解除）。
- 完整读了小组件三个文件（`BubuWidgets.swift` 842 行 / `BubuWidgetData.swift` / `BubuLiveActivity.swift`）+ App Group 数据层，§3 的诊断是逐行读出来的，不是泛泛而谈。
- 核对了 55 个 iOS 改动文件清单，据此定位上轮修复的落地情况与待复验缺口。
