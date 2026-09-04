# 布布时光机 · 全面审计与升级方案

> 日期：2026-09-04
> 基线：`main` @ `e5fb5f4` / iOS 2.12.2（已 `xcodegen generate`，本机 clean build 零 error 零 warning）
> 方法：五路并行专项审计（架构与数据层 / 同步与后端 / 交互动效 / 安全隐私 / 测试与多端），
> 全部结论已由主审二次独立复核，未采信任何未经代码或命令证实的说法。
> 复核中已修正两条被高估的结论（见 §1.7、§6.3）。
> 约束：本文只做审计与方案，**未修改任何工程代码**。

---

## 落地状态（2026-09-04 当天更新）

本文写完后当天即执行。**已落地的部分见下；未落地的三项是用户明确决定不做或延后的。**
发布版本：**v2.13.0**。全程 clean build 零 error 零 warning，全量测试通过。

| 章节 | 状态 |
|---|---|
| §1.1 版本化 Schema | ⚠️ **部分**：真修复（16 个类冻结进 V1 命名空间）需单独排期。已补上真正的护栏——`StoreMigrationTests` 用一份真实装机数据验证「升级后打得开」，并删掉了那份照抄必然 abort 的 V2 模板 |
| §1.2 autodate 迁移未进仓库 | ✅ 0015 幂等兜底 + 守卫测试改正向 |
| §1.3 启动迁移覆盖活库 | ✅ 打不开的库不参与比较；只在目标确认为空时才替换 |
| §1.4 降级后诱导重建档案 | ✅ 全屏挡页 + 数据库原样导出 |
| §1.5 AI 自己打开 | ✅ 改成 `?? false` + 开关旁写明外发目的地 |
| §1.6 主干红 + CI 不拦 warning | ✅ 修好那条只在 CI 上失败的 UI 测试；加零警告门禁与 iPad 回归 |
| §1.7 家庭隔离 fail-open | ✅ 0018：先加字段守卫、再回填、确认无残留才收紧 |
| §1.8 胶囊版本降级伪造 | ✅ `cryptoVersion` + 只升不降 + 回归测试钉住漏洞与修复 |
| §1.9 家人补充永久丢失 | ✅ 三处补 `holdCursorForCurrentPull` |
| §1.10 删除被复活 | ✅ `activeRecordFields` 加 `defaultIsDeleted` |
| §2.1 全仓零索引 | ✅ Entry / HealthRecord / FeedEvent；用加索引**之前**的基线实测仍能打开 |
| §2.2 启动期全表扫 | ✅ 提醒调度移出关键路径 + 扫描窗口上界。首页分年循环有界（≤18 次）且已有索引，保持原样 |
| §2.4 大文件上传 | ⏸ **用户决定暂不排期** |
| §2.5 offset 翻页跳记录 | ✅ 改 keyset 翻页，墓碑同走 |
| §2.6 拉取故障不可见 | ✅ 记录失败原因、时间戳不再空跳、红字无条件显示、状态文案不再撒谎 |
| §2.7 SyncEngine 拆分 | ⏸ 未做。属重构，本轮优先修正确性 |
| §2.8 测试打在已踩过的坑 | ⚠️ **部分**：补了 store 迁移、胶囊降级、分享脱敏、幼儿园口径共 4 组；SyncEngine 本体行为测试仍缺（需先抽纯函数） |
| §2.9 鸿蒙端 | ⏸ **用户决定暂不跟进** |
| §3.3 幼儿园 T0 五项 | ✅ 全部 |
| §3.4 T1-1 作品扫描 | ✅ 文稿相机 + 端侧中文 OCR |
| §3.4 T1-2 通知单 OCR | ⏸ 未做（OCR 能力已就位，差一个「抽事件+日期→建提醒」的确认流） |
| §3.4 T1-3 布布的朋友 | ⏸ 未做 |
| §4.1 三条最高性价比 | ✅ 全部 |
| §4.2 体验断点 | ✅ 12 项中 11 项；左滑删除受工具链限制（`#if compiler(>=6.4)`）仍不可用 |
| §4.3 可爱度 | ✅ 11 项中 9 项；`savedToast` 提成公共组件、加载态吉祥物化未做 |
| §4.4 适老化 | ⏸ **用户决定不做**（姥姥模式维持只读定位）。仅顺手把大图查看器三个出口从 40pt 放大到 44pt |
| §5.1 `@Generable` | ✅ 删掉整个手写 JSON 解析 |
| §5.2 幼儿园系统能力 | ✅ 文稿相机 + 中文 OCR；PencilKit / Live Text 未接 |
| §5.3 系统级可爱 | ⚠️ **部分**：`phaseAnimator` / `drawOn` / `numericText` / `visualEffect` 已接；`GlassEffectContainer` 形变未做 |
| P1-3 恢复码进剪贴板 | ✅ 限定本机 + 60 秒过期；分享改成可打印纸条 |
| P1-4 导出留明文残留 | ✅ 打包后即删 + 启动清历史残留 |
| P1-5 生物识别锁 | ⏸ 未做 |
| P1-6 分享带 GPS | ✅ 照片先抹位置再分享（含回归测试）；视频如实按原文件 |

### 下一轮最该做的三件（按价值）

1. **版本化 Schema 真修复**（§1.1）。护栏已经有了，但机制本身还是装饰性的。
2. **SyncEngine 抽纯函数 + 补行为测试**（§2.7 + §2.8）。2082 行目前只被一个常量断言碰到。
3. **大文件上传换 background session**（§2.4）。用户本轮明确不排，但它是「视频永远传不上去」的根因。

---

## 0. 一页结论

### 0.1 这个产品现在的真实水位

工程质量明显高于个人项目平均线，有几处甚至高于商业团队：

| 维度 | 实测证据 |
|---|---|
| 第三方依赖 | iOS 端 **0**。无 SPM / CocoaPods / xcframework |
| 单元测试 | 实跑 `xcodebuild test` → **161 通过 / 0 失败 / 1 跳过 / 28 套件**。HANDOFF 宣称的数字属实，无虚报 |
| 加密 | 时间胶囊 BTC2/BTC3 **固定密文向量同时钉在 iOS 与鸿蒙**，跨端跨语言真契约 |
| 日志 | 全仓 0 处 NSLog；30 处 `privacy: .public` 逐条核对，**无 token / 密码 / 恢复码 / 姓名 / GPS** |
| 权限面 | 五个 target 的 entitlements 各只有一条 App Group。无 ATS 放宽、无多余能力 |
| 并发 | Swift 6 严格并发下，**无一处把 `@Model` 对象送出 MainActor** |
| DEBUG 后门 | 全部 `-uitest-*` 入口正确包在 `#if DEBUG` 内，Release 不含 |
| 服务端 | 鉴权真 fail-closed；SSRF 三重校验；无命令注入；CORS 全关 |

### 0.2 但有一个贯穿全仓的系统性模式：**「做了，但没接上」**

这是本次审计最重要的发现。它不是能力不足，是接线不足。逐条都有代码证据：

| 建好的能力 | 没接上的部分 |
|---|---|
| `BubuSchemaV1: VersionedSchema` | `models` 返回**活模型类**，不是快照 → 版本化等于没做（§1.1） |
| PocketBase autodate 修复 | **migration 0011 从未进仓库**，只活在生产 mini 上 → 换机即复现「同步从未成功」（§1.2） |
| `MigrationBackups/` 自动备份 | 全仓**零读取点**，无恢复入口，用户看到的就是「数据没了」（§1.3） |
| `BubuStoreHealth.loadFailed` | 唯一消费方在设置页往下滚三屏，首页照常邀请「记第一笔」（§1.4） |
| `bubuIOS27TimelineActions` 左滑删除 | `#if compiler(>=6.4)` 在 Swift 6.0 下走 `else self` → **今天等于不存在**（§4.2） |
| `BubuSound.Effect.birthday` + `sfx-birthday.caf` | 全仓**零 `play` 调用**（§4.3） |
| `CeremonyAnimation`（注释写「里程碑 / 人生第一次」） | 只接了里程碑**一处**；「第一次」确认只是插条数据关掉 alert（§4.3） |
| `BubuPressableStyle` | 首页 14 个可点卡片全用 `.buttonStyle(.plain)`，按下去毫无反应（§4.2） |
| 20 个布布表情资产 | `.travel` / `.bath` **零引用**；其余 18 个**全部静态渲染**，无一处动画（§4.1） |
| `APIError.fileTooLarge` | 全仓**无抛出点**，96MB 软上限只出提示不拦截（§2.4） |
| GitHub Actions CI | **不拦 warning**；且 `main` 已红 5 天无人处理（§1.6） |
| `.refreshable` | **全仓 0 处**。下拉刷新这个最强本能，四个主页面全无响应（§4.2） |

**这个诊断是好消息**：接线的改动量远小于建设，且大多是单文件、单行级别。

### 0.3 三件必须在 9 月 9 日前定下来的事

1. **修 §1 的 P0**。其中「AI 会自己打开并把布布的记录发往 DeepSeek」（§1.5）与产品第一原则直接冲突，两行可修。
2. **接受一个约束**：§1.1 未解决前，**新功能只能加 optional 字段，不能新增 `@Model` 实体**。这条约束直接决定了 §3 幼儿园方案的形态。
3. **认清内容模型正在过期**：118 条里程碑预设、今日一问的三个分桶，全部是为 0–3 岁设计的。布布 9 月 9 日入园，产品的数据来源假设（家长全天在场）当天失效（§3.1）。

---

## 1. 必须先修（P0）

按修复顺序排列，不按发现顺序。前三条改动都很小且不动 schema，可以立刻发。

### 1.1 版本化 Schema 是装饰性的，且逃生舱已知走不通

`BubuTimeMachine/App/BubuSchema.swift:28-34`

```swift
static var models: [any PersistentModel.Type] {
    [Entry.self, Media.self, Milestone.self, ...]   // ← 引用「活」模型类，不是快照
}
```

`BubuSchemaV1.models` 指向的是工程里当前的 16 个类。类改一个字段，所谓的「V1 历史快照」就跟着变——它根本不是快照。配合 `:45-52` 的 `stages: []`，实际生效的仍然是 SwiftData 的隐式轻量迁移。

**更关键的是文件自己已经承认逃生舱是坏的**（`:39-44`）：

> V1/V2 引用同一批模型类时，两个版本的实体形状完全相同而版本号不同，迁移器直接 abort（真机已验证）。

而文件底部「【下一次改模型必读】」的 V2 模板（`:54-79`）照抄就会撞上这个已知失败。**下一个会话若照着模板做，必然翻车。**

**失败场景**：任何一次改名 / 改类型 / Optional→非 Optional / 删字段 → `ModelContainer` 构造抛错 → `BubuTimeMachineApp.swift:58` 的 catch 兜住 → 全家所有设备升级后打开是空 App。磁盘数据还在，但功能性全损，必须等新版本才能救。

**修复**：在 `BubuSchemaV1` 命名空间里**真正复制一份**当前 16 个类的定义（`enum BubuSchemaV1 { @Model final class Entry {…} }`），让 V1 冻结、V2 用活类，`stages` 填 `.lightweight(V1→V2)`。做不到就至少先补一个 CI 测试：把一份旧版 store 塞进测试 bundle，验证新版能打开。现在连这个测试都没有。

**同时要做**：把文件底部那段会失败的模板改掉或标注「此模板未经验证，直接照抄会 abort」，防止下个会话踩雷。

### 1.2 autodate 修复从未进仓库，换机即复现「云端同步从未成功」

`server/pocketbase/migrations/` 里 **`1700000011` 整个号段缺失**（0010 直接跳 0012）。全仓 `autodate` 零命中。

`server/pocketbase/migrations/1700000012_add_automation_collections.js:3` 自己写着：

> 0012：生产 mini 已有历史 0011_add_autodate_fields.js，绝不能复用同一迁移序号。

修复只活在 `mac-mini-cortex` 的运行时目录里，而 `server/.gitignore:4` 恰好把 `pocketbase/pb_migrations/` 排除了。

**失败场景**：换机器、重装、或跑 `server/ops/restore-drill.sh` 恢复演练后，`start_pocketbase.sh:46` 用的是受 git 管理的 `--migrationsDir` → `GET /api/collections/entries/records?sort=updated` 立刻 400 → **原样复现 2026-07 那次「同步从未成功过一次」**。

且即便在 mini 上，0012 之后新建的 `automation_jobs` / `derived_artifacts` / `families` / `users` 四个集合**从来没有过 autodate**。

**守卫测试是反向的**：`server/ai/tests/test_ops_contracts.py:42` 只断言「0011 号别重复」，没有一条要求它存在。所以 CI 全绿也测不出来。

**修复**：从 mini 取回该 migration 提交进仓库；补一条 0015 给后四个集合加 autodate；守卫测试改成正向断言（每个 `new Collection` 都能在某迁移里找到 created/updated）。

### 1.3 启动迁移可能用几个月前的旧 store 覆盖正在用的库

`BubuTimeMachine/App/StorageMigrator.swift:175-197`

```swift
guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
    return StoreStats(childProfiles: 0, entries: 0, …, fileBytes: fileBytes)   // ← 打不开 = 当成空库
}
```

打分公式（`:39-45`）：`childProfiles × 1_000_000 + entries × 10_000 + …`

**失败场景 A（瞬时打不开）**：当前 App Group store 因任何原因 `sqlite3_open_v2` 失败（被别的进程持锁、`-shm` 建不出来），destination 的 score 塌成 `fileBytes/1024`。旧沙盒里那个只有 1 条 ChildProfile 的 legacy store score ≥ 1,000,000，稳赢 → `:100-111` 触发 `copyStoreTrio(replacingExisting: true)` → **删掉当前 store 三件套换成旧的**。

**失败场景 B（WAL 未 checkpoint）**：`inspectStore` 只读主 db 文件。SwiftData 走 WAL，最近写入可能还在 `-wal` 里 → destination 被系统性低估，legacy（早已冻结）被系统性高估。

这条判断**每次启动都跑**——`:96` 的 `storeDoneKey` 守卫会被 `storeNeedsRepair` 短路。

`backupStoreTrio`（`:236-255`）确实先备份到 `MigrationBackups/<时间戳>/`，所以不是永久丢失。**但全仓对 `MigrationBackups` 零读取点**（已 grep 确认），没有恢复入口、不通知用户。用户视角就是：「布布这半年的记录全没了」。

**修复**：`inspectStore` 打不开必须让 `makeCandidate` 返回 `nil`；`storeNeedsRepair` 收紧成只在 `destination == nil` 时成立——一次性迁移本来就该是「目标已存在就永不替换」。

### 1.4 store 打不开后降级，但照常收记录，退出即全丢

`BubuTimeMachine/App/BubuTimeMachineApp.swift:58-69` 降级到内存容器的思路是对的（远好过 `fatalError`），但降级之后没有任何写入拦截：

- `hasCompletedOnboarding` 存在 UserDefaults，与 store 无关 → 引导不重放
- 用户看到「已建档但一条记录都没有」的首页 → `CaptureHomeView.swift:88-89` 走空态，界面写着**「记第一笔」**，主动邀请从头开始
- 唯一提示埋在 `SettingsView.swift:132-140`，要往下滚三屏
- `BubuStoreHealth.loadFailed` 全仓只有这一处消费方（已 grep 确认），**没有任何 save 路径检查它**

**失败场景**：升级后打不开 → 妈妈以为数据没了，重建档案记了一整天 → 退出全丢。更糟的是若这期间同步跑通一轮，假的 ChildProfile / FamilyMember 会被推上服务器，污染全家其它设备。

**修复**：`loadFailed` 时在 `RootView` 最外层挡一张全屏说明页，只留「导出旧数据 / 退出」，不进主界面。

### 1.5 AI 会自己打开：配好同步的那一刻，布布的记录开始流向 DeepSeek

**这是与产品第一原则冲突最直接的一条。**

`BubuTimeMachine/Services/Networking/ServerConfig.swift:210-215`

```swift
let packagedFamilyAI = !initialAIBaseURL.isEmpty
    && URL(string: initialBaseURL) != nil
    && !initialAccountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    && !initialAccountPassword.isEmpty
self.aiEnabled = UserDefaults.standard.object(forKey: Self.aiEnabledKey) as? Bool
    ?? packagedFamilyAI
```

`aiEnabled` 的 `didSet`（`:89-91`）是唯一持久化点，而 **Swift 在 `init` 内赋值不触发 `didSet`** → 这个兜底值永不落盘，每次冷启动重新求值。

`initialAIBaseURL` 出厂即非空（`project.yml:50` 硬编码 `BUBU_DEFAULT_AI_BASE_URL`）。于是：**用户为了同步填完家庭账号密码 → 下次启动 AI 开关自己变成开**，用户从未碰过「让 AI 帮忙写故事」那个开关。

外发终点是 `server/ai/llm.py:23-24` → `https://api.deepseek.com/chat/completions`。`/ask` 把孩子真名 + 最多 40 条记录的日期、年龄、正文原样拼进 prompt；`/parse-natural-capture` 的 `_SENSITIVE_DOMAINS`（`main.py:1205`）说明**疫苗与症状文本同样走这条路**。

与现有文案直接冲突：`SettingsView.swift:67` 写「不上传照片或家庭资料」，全 App 无一处提到 DeepSeek。CLAUDE.md 写的是「AI 默认关闭、数据外发必须用户显式开启」。

**修复（两行）**：`init` 里把兜底值显式写回 UserDefaults，或直接改成 `?? false`；并在 AI 开关下方补一句「开启后，记录文字会经家中服务器转发给 DeepSeek 云端模型」。

### 1.6 main 已经红了 5 天

```
gh run list → 33249793376  failure  修复并升级布布身份卡 v2.12.2  2026-08-29
```

失败点：

```
BubuTimeMachineUITests.swift:105: error: testSpotlightPrivacyToggleCanBeReversed :
XCTAssertEqual failed: ("Optional("0")") is not equal to ("Optional("1")")
```

本机跑同一条命令是 `TEST SUCCEEDED`（161 通过），**只在 CI 的模拟器上失败**。这是典型的 UI 测试时序/环境差异，但没人看，所以 v2.12.2 是带着红 CI 发的。

同时 `.github/workflows/ci.yml:59-65` 是 `clean test | tail -120`，**只看退出码不看 warning**。「零 error 零 warning」目前完全靠人在本机手工 grep 维持，一个带 warning 的 PR 能顺利合进 main。

**修复**：先让 main 变绿（修或临时隔离那条 UI 测试）；`project.yml` 加 `SWIFT_TREAT_WARNINGS_AS_ERRORS`，或 CI 步骤加一条 warning grep 门禁。这是全仓最便宜的纪律补丁。

> 附带澄清：审计中曾怀疑 `actions/checkout@v7` 是笔误导致 CI 从未运行。**已核实为误判**——CI 历史有多次 success，checkout 步骤正常。

### 1.7 家庭隔离规则 fail-open（**但这是已知的临时兼容，不是疏漏**）

`server/pocketbase/migrations/1700000009_family_access_soft_delete_files.js:10`

```js
const familyRule = '@request.auth.id != "" && (@request.auth.familyId = "" || familyId = "" || familyId = @request.auth.familyId)'
```

两个 OR 分支都是放行。配合 `:97` 的 `users.updateRule = 'id = @request.auth.id'`（记录级规则，不限制字段，`familyId` 只是普通 TextField），任何已登录用户可以把自己的 `familyId` 改成 `""`，即刻对全部 14 张业务表拥有全库读写。

**复核后的定级调整**：该文件头部注释明确写着这是刻意的升级兼容（「老数据 familyId 为空仍可被已登录用户读取，避免升级后把历史记录锁死」「后续可在数据回填完成后进一步收紧规则」）。当前是**单家庭 + Tailscale 内网 + 已关公开注册**的部署，外人无法登录，所以**今天不可被利用**。

但「后续收紧」从写下那天起就没做过。**只要多开一个亲戚账号，它立刻变成 P0。** 建议在 §3 幼儿园功能引入更多家庭成员之前先收口。

**修复**：`users.updateRule` 收成 `id = @request.auth.id && @request.body.familyId = familyId`；确认历史数据 `familyId` 回填完成后，把 `familyId = ""` 这一支从 `familyRule` 删掉。

### 1.8 时间胶囊可被版本降级伪造

`Services/Security/CapsuleVault.swift:82-96` 的 `unseal` 完全按 blob 头部魔数分派版本，`Models/TimeCapsule.swift` **没有任何 `cryptoVersion` 字段**，本地无从判断这封信原本是哪一版封的。

v2 密钥 = `SHA256(canonicalISO(unlockAt) | capsule.id | 常量)`，而 `unlockAt` 和 `id` 都是 PocketBase 上的**明文字段**。

**攻击场景**：拿到数据库或备份的人，用两个公开字段自行派生 v2 密钥、封一段自己写的正文、加 `BTC2` 前缀替换服务器上的 blob。换机后 SyncEngine 拉回本地，`unseal` 认魔数解密成功——密钥公开时 AES-GCM 的完整性校验形同虚设。**布布 18 岁打开的是攻击者写的信，界面无任何异常。**

这是对产品核心承诺的完整性打击。

**修复零功能损失**：`TimeCapsule` 加 `cryptoVersion: Int = 3`（additive optional，安全），`unseal` 在 `cryptoVersion >= 3` 时拒绝一切非 `BTC3` blob。产线已无 v2/v1 生产者（唯一 `vault.seal` 调用点在 `#if DEBUG` 内）。

### 1.9 家人补充与语音留言会在特定时序下永久丢失

`Services/Sync/SyncEngine.swift:1694` / `:1712`

```swift
guard let entry = try? context.fetch(entryDescriptor).first else { return false }
```

两处 `return false` 都**没有**置 `holdCursorForCurrentPull = true`——而同文件 `mergeRemoteMedia:1497-1499` 做了（已对照确认）。游标推进（`:1057-1071`）只看 `dto.serverUpdatedAt`，不看 merge 返回值。

**失败场景**：某轮 entries 批次网络抖动失败（游标不动），comments 批次成功 → 父 Entry 尚未落库 → comment 返回 false，但 comments 游标照样推到本轮最大 updated → 下一轮 entries 落库了，可这条家人补充已在游标之后，**这台设备永远拉不到**。语音留言同理。

**修复**：两处各加一行 `holdCursorForCurrentPull = true`。顺带 `mergeRemoteFirstTime:1594` 父记录找不到时静默 `item.entry = nil`，也该同样处理。

### 1.10 媒体的 multipart PATCH 无条件把删除翻活

`Services/Networking/PocketBaseClient.swift:798-800`

```swift
private func activeRecordFields(_ fields: [String: String]) async -> [String: String] {
    var result = fields
    if result["isDeleted"] == nil { result["isDeleted"] = "false" }   // 无条件
```

对比同文件 `:786` 的 JSON 路径 `activeRecordJSON(_:defaultIsDeleted:)` 有参数、只在 POST 时注入，注释还专门写了「PATCH 不默认注入 isDeleted=false：内容更新不应把 tombstone 翻活」。但两个 `multipartUpload`（`:854`、`:891`）在 `existingId != nil` 走 PATCH 时仍然过 `activeRecordFields`。

**失败场景**：妈妈删掉一张糊照片 → 服务器 `isDeleted=true`；爸爸手机上这条 Media 处于 `.failed`，或点了「重新上传全部」（`SyncEngine.swift:202`）→ 爸爸的 PATCH 把 `isDeleted` 写回 false → **照片在全家复活**。comments / voicenotes / voicememos / timecapsules / 头像全部同一条路径。

**修复**：`activeRecordFields` 加 `defaultIsDeleted: Bool` 参数，两个调用点传 `existingId == nil`。

---

## 2. 结构性问题（P1）

### 2.1 全仓零索引，十年后所有按时间的查询都是全表扫

`grep -rn "#Index\|#Unique"` 全仓 **0 命中**。除 16 个 `@Attribute(.unique) var id: UUID` 外，`happenedAt` / `createdAt` / `isArchived` / `recordedAt` 全部无索引。

`Features/Timeline/TimelineView.swift:70-75` 的 `fetchLimit = 200` 只限制**返回**行数。`ZHAPPENEDAT` 没索引，SQLite 必须扫完全部行并排序才知道哪 200 条排最前。

**修复**：`Entry` 加 `#Index<Entry>([\.happenedAt], [\.createdAt], [\.isArchived, \.happenedAt])`，`HealthRecord` 加 `recordedAt`。**注意：加索引本身是 schema 变更，必须排在 §1.1 之后。**

### 2.2 启动路径上有两处主线程全表扫

**a) 那年今日提醒**（`Services/ReminderScheduler.swift:46-51`）：无 `fetchLimit` 的全表 `fetch`，在 `AppEnvironment.swift:126` 的 `bootstrap` 里**同步**调用。5 万条 = 5 万个 SwiftData 对象在 MainActor 上物化再逐条分桶。这是启动路径上最重的一次操作，直接顶启动看门狗。

**b) 首页那年今日**（`CaptureHomeView.swift:884-900`）：按出生年到今年**逐年 fetch**，主线程同步。布布 10 岁时是 10 次。

**修复**：a) 改窄查询或至少加 `propertiesToFetch`；b) 整段挪到后台或改成一次日期区间查询。

### 2.3 十几处无上限 `@Query`

按暴露程度：`HealthHomeView:9`、`FamilyFeedView:9-12`（四张全表同屏）、`GrowthReportView:9-11`、`BubuQAView:9-13`、`ExportView:9-18`（九张全表，进页即触发）、`AlbumHomeView:8`、`GrowthMovieView:12`、**`SimpleTimelineView:9`（姥姥模式主界面）**、`PhotoFrameView:11`、`YearbookView:8-9`。

首页（`fetchLimit = 12`）和时光页（分页 200）已处理过——说明这个模式是知道的，只是没铺开。

### 2.4 大文件上传：无退避、无续传、被挂起即整包作废

- `SyncEngine.swift:878-925` 失败只置 `.failed`，无 attempt 计数、无冷却；`:321-322` 连上就把 `consecutiveFailures` 清零 → 800MB 视频传给 500MB 上限的服务端，**每 30 秒整包重传一次，永不退避**。蜂窝网一小时几十 GB。
- `APIError.fileTooLarge` 有定义、有文案，**全仓无抛出点**。96MB 软上限只出提示不拦截。
- `PocketBaseClient.swift:859/:909` 用的是 `URLSession(configuration: .default)`；带 `waitsForConnectivity` 的 `fileTransferSession`（`:26-32`）**只用于下载**。传 300MB 视频到 30% 按 Home → 约 30 秒后进程挂起 → 回前台从 0% 重来。

**修复**：Media 加 `failedAttempts` + `nextRetryAt` 指数退避（additive）；push 前比对服务端上限，超限抛 `fileTooLarge`；上传换 background URLSession。

### 2.5 offset 翻页 + 可变排序键，全量首同步会静默跳记录

`PocketBaseClient.swift:684-695` 用 `page` 递增，`sort=updated` 升序。新设备首次同步 2000 条时，若另一台手机编辑了前面某条，那条 `updated` 跳到最后一页 → 其后所有行整体上移 → **页边界处恰好有一条被跳过**，且其 updated 早于游标，永远补不回来。

**修复**：改 keyset 翻页——每页把 `since` 推到本页最后一条的 updated，循环到空页，不用 `page=N`。

### 2.6 拉取端的永久 400 完全不可见

`SyncEngine.swift:1045-1048` 的 `batch.failed` 只置 `softFailureThisRun`，**不调 `recordFailure`**；`:321-322` 在 `pushLocal()`/`pullRemote()` **之前**就把 `connectionState` 置 `.online`——ping + auth 成功就算这轮成功。`SyncCenterView.swift:110` 的红字条件是 `lastFailureReason != nil && pendingCount > 0`，纯拉取故障时 `pendingCount == 0`，**永不显示**，状态卡显示绿勾「全部同步好了」。

**这正是 2026-07 那次故障能静默几个月的机制。§1.2 若复发，还是看不见。**

**修复**：`fetchBatch` 把非 404 的 4xx 判为硬失败并 `recordFailure`；`lastSyncedAt` 只在本轮全部集合成功时刷新；SyncCenter 去掉 `pendingCount > 0` 条件。

### 2.7 SyncEngine 2082 行：职责过载，但拆分边界已经写在 MARK 里

不建议大重构。可安全先拆两块（纯函数、零依赖、能单测）：

1. **游标层**（`:52-127`）——纯 UserDefaults + 纯函数。它是历史事故的核心，独立后能单测。
2. **DTO 映射层**（`:1773-2082`，约 310 行）——全是 `static func makeDTO/apply`，零状态零 async，直接搬成 `SyncMapping.swift`。

拆时唯一不能动的是 `pullRemote:1017-1032` 的**合并顺序**（media 依赖 entry 已落库），代码里已注明。

### 2.8 测试覆盖打在「已踩过的坑」，不是「风险最高的模块」

- **SyncEngine 2082 行，全仓测试只触及一个常量** `pushBatchCap`。`remoteEntryWins`（LWW 裁决）、`apply()` 游标推进、`setCursor` 只进不退、`removeLocals/keepIfDirty`——**零行为测试**。根因是结构性的：全是 `private` + `@MainActor` 实例方法。`SyncBackoff` 已示范「抽成 nonisolated 纯函数就能测」，但只抽了退避这一处。
- **没有采集覆盖率**：`xccov` 报 `No coverage data`，scheme 未开。
- **iPad 横屏 UI 测试从未在自动化里跑过**：`BubuTimeMachineUITests.swift:77` 的 `XCTSkipUnless(idiom == .pad)`，而 CI 的模拟器选择（`ci.yml:51-57`）过滤 `'iPhone'`。
- **`AgeCalculator` 的 10 个测试测不到时区**：用 `Calendar.current` 造日期又用 `Calendar.current` 断言，自洽因而与时区无关。真实缺口是四个方法全用 `Calendar.current.startOfDay`——生日在 UTC+8 录入、飞到 UTC-5 打开会整体位移一天，桌面小组件和表盘一起错。
- **`PhotoAnalyzer.swift:85-100` 解析 EXIF 没设 `timeZone`**：同一张照片在不同时区导入得到不同 `happenedAt`，可能跨日 → 归错月、年龄标错。184 行，测试引用 0。
- **弱断言样本**：`ShareCardTests.swift:52-60` 测试名承诺「卡面不含年龄」，唯一断言是 `image.size.height > 0`——年龄真被画上去照样绿。分享卡是**唯一会离开这个家的产物**，这正是最该验的隐私点。

**需要纠正一个常见预设**：`CapsuleCrypto` 跨版本解密和 `ArchiveExporter` **不是**盲区，反而是全仓覆盖最扎实的两块（三代版本 + 跨端固定向量 + 路径穿越防护 + SHA 重算篡改检测）。

### 2.9 鸿蒙端：不拖慢 iOS，是因为它已经掉队

| | 版本 |
|---|---|
| iOS `project.yml` | **2.12.2** |
| 鸿蒙 `app.json5` / `ServerConfig.ets:11` | **2.11.0** |
| `PARITY_MATRIX.md` 基准 | **iOS 2.11.0** |

`harmony/tests/VersionParity.test.mjs:9` 这条测试的名字叫「统一追平 iOS 2.11.0」，断言硬编码 `'2.11.0'`——它验的是「鸿蒙自己前后一致」，不是「追上 iOS」。**差两个小版本，CI 全绿。**

33,817 行 ArkTS，177 个测试全绿，但：

```
assert 总数:                    783
assert.ok(源码.includes(...)):  715   ← 91%
真正 import 执行生产模块的文件:   7 / 88
```

91% 的断言是把 `.ets` 源码当文本 grep。把实现改坏、保留那行字符串，测试照绿。

`PARITY_MATRIX.md` 的 27 项里 25 项是「已实现待追平」——写完了但没在真机验过。

**这不是要求现在处理，是要求明确决策**：继续跟随（需要真机 + 补真执行的测试），还是明说冻结在 2.11.0。现状是「宣称跟随、实际掉队、CI 检测不出」，最坏的那种。

---

## 3. 幼儿园升级（9 月 9 日）

### 3.1 先说清楚问题是什么

这不是「加一个幼儿园页面」的需求。是**产品的数据来源假设在 9 月 9 日当天失效**。

**现在**：家长与布布几乎全天在一起 → 家长观察到一切 → App 记录家长的观察。

**9 月 9 日起**：布布在园 8:00–17:00，约占清醒时间的 60%。**家长只能看到 40%，而且是最平淡的那 40%（早上赶时间、晚上准备睡觉）。**

三个直接后果：

1. **记录量会断崖下跌。** 家长记录他们看见的东西。不做干预的话，2026 年 9 月起会是布布档案里最薄的一段——恰恰是她人生开始变得最有意思的时候。

2. **出现产品接不住的新载体**：老师的口头反馈、纸质通知单（有日期、会忘）、**作品（画和手工，物理上必然会丢）**、同学和老师的名字（布布天天讲，家长记不住）。

3. **「第一次」库整体过期。** 118 条预设分 12 类，全部是 0–3 岁发育项，**零幼儿园相关**（已 grep 确认全仓只有 3 处无关命中）。`DailyQuestion` 的 37 月+ 桶只有 **8 题**，日轮换 = **8 天一循环**。

### 3.2 一条必须遵守的技术约束

§1.1 未解决前：**只能加 optional 字段，不能新增 `@Model` 实体。**

依据：`Media` 追加 `remoteThumbURL` / `contentHash` 的先例证明 additive optional 走自动轻量迁移是安全的（`BubuSchema.swift:39-44` 有实践记录）。而新增 `@Model` 会改动 `BubuSchemaV1.models` 这个「快照」，撞上已知的 abort。

下面的方案全部按这条约束设计。

### 3.3 T0 · 开学前 5 天（零或极小 schema 变更）

#### T0-1 入园日与「上学第 N 天」

- `ChildProfile` 加 `var schoolStartDate: Date?`（**唯一的新字段，additive optional**）
- `AgeCalculator` 加 `daysSinceSchool(start:at:)`，与现有 `daysSinceBirth` 并列
- 开学前显示「距离上幼儿园还有 N 天」，9 月 9 日当天变成「上幼儿园第 1 天」
- 显示位：首页问候行、身份卡背面（正好替换 §4.3 说的那串 UUID）、时光轴月份头

**为什么值得**：18 岁的布布会想知道第一天什么样。这是一次性的、不可重来的。改动约 1 字段 + 1 函数 + 3 处显示。

#### T0-2 放学一问（`DailyQuestion` 加幼儿园桶）

零 schema 变更，纯常量数组（`Features/Capture/DailyQuestion.swift`）。

- 现 `child` 桶 8 题、8 天循环，且不是幼儿园语境
- 加 `kindergarten` 桶约 24 题，选桶依据从「月龄」改为「是否已入园 + 入园后天数」
- **关键设计**：问题问的是**布布本人**，家长照着问、记录她的原话。18 年后最值钱的是她三岁时怎么说话，不是家长的转述
- 通知触发时间从固定改成放学后（约 17:30）

示例题：「今天谁和你一起玩？」「老师教了什么歌，唱一句？」「今天午饭吃了什么，好吃吗？」「今天有小朋友不开心吗？」「今天你帮了谁？」

#### T0-3 幼儿园里程碑包（`Milestone.presets` 加一个分类）

零 schema 变更，纯常量数组。12 条：

第一天上幼儿园 / 第一次不哭着进园 / 第一次自己午睡 / 第一次交到好朋友 / 第一次被老师表扬 / 第一次上台表演 / 第一次自己吃完一整碗 / 第一次自己穿脱鞋 / 第一次当值日生 / 第一次带作品回家 / 第一次说想去幼儿园 / 第一次讲幼儿园发生的事

> ⚠️ **必须先修 §1 的里程碑去重再加**：`AppEnvironment.swift:200-229` 的 `normalizeMilestonePresets` 在**每次启动**按标题硬删重复项，且不在 `DataMigrationRunner` 的一次性框架里（对比 `:108` 那批带 done 标记的迁移）。加新预设前先把它并进一次性框架。

#### T0-4 入园查验预防接种证（纯 View，零 schema 变更）

入园查验接种证在国内是强制环节。数据**已经全在库里**：`VaccineSchedule` 有 22 剂、覆盖到 72 月龄（含 36 月龄流脑 AC 与 72 月龄白破加强），`VaccineRecord` 结构完整。

缺的只是一个视图：「截至今日应种 X 剂 / 已记录 Y 剂 / 缺 Z 剂」+ 缺的列出来 + 可截图给保健医。

> ⚠️ 这张图会离开设备，**必须走脱敏路径**。参考 `ShareCard`（`ImageRenderer` 重渲染，EXIF 天然剥离）而不是原文件分享。

#### T0-5 一页纸给老师（纯 View + 脱敏分享）

老师真正需要的：小名、过敏源、用药、紧急联系电话、可接送人。这些散落在 `ChildProfile` / `FamilyMember` / `HealthRecord` 的标签里，缺的是「对外一页」。

> ⚠️ 同样必须脱敏。**顺带澄清一条 CLAUDE.md 的误记**：审计已确认 `ChildProfile` **根本没有身份证字段**，身份卡上的 `No.BUBU20240522` 是装饰性假号（`SharedDefaults.swift:54`）。CLAUDE.md「截图含身份证」的说法与代码不符，建议一并更正。

### 3.4 T1 · 开学后两周（真正解决「看不见的 9 小时」）

#### T1-1 作品扫描 —— 本轮最高价值

`VNDocumentCameraViewController` 自动裁边去畸变（**已在本机 iOS 26 SDK 通过类型检查**）。拍一张画 → 自动裁正 → 存成 Entry + Media，用 `Media.aiTags` 打「作品」标（**复用现有字段，零 schema 变更**）。

配 `RecognizeTextRequest` 中文 OCR（同样已验证）读出老师写在画上的字和日期。

**为什么是最高价值**：幼儿园三年会产生几百张画和手工，物理上一定会丢、会皱、会被当垃圾扔掉。这是唯一能留下来的方式，且 18 年后无可替代。

#### T1-2 通知单 OCR → 提醒

拍通知 → OCR → 端侧模型抽「事件名 + 日期 + 要带什么」→ 建提醒。

**必须家长确认后才写**（项目铁律：AI 不自动写事实）。现有 `NaturalCaptureReviewSheet` 的确认流可以直接复用。

#### T1-3 布布的朋友

布布会天天讲「今天和乐乐玩了」，家长记不住乐乐是谁。

**在约束下的做法**：`Entry` 加 `var mentionedNames: [String]?`（additive optional），从记录里抽名字聚合成列表。**不新增 `@Model`。**

18 年后：「你三岁最好的朋友叫乐乐」——这是别的 App 给不了的。

### 3.5 明确不做

**接送打卡、缴费记录、请假条、老师聊天存档。**

理由：产品第一原则是「真正的用户是未来 18 岁的布布」。这些对 18 岁的布布价值为零，是给家长的行政工具。做了会把「一本会生长的家庭档案」稀释成「幼儿园管理 App」——那是完全不同的产品，且市面上已经很多。

判据很简单：**这条记录，18 岁的布布会想看吗？** 会 → 做；不会 → 不做。

---

## 4. 更丝滑、更好用、更可爱

按「感知强度 ÷ 改动量」排序。所有 API 已在本机 iOS 26 SDK + Swift 6 通过 `swiftc -typecheck` 验证。

### 4.1 最高性价比的三条

#### ① 让布布动起来 —— 改 1 个文件，37 处受益

`DesignSystem/Components/BubuMascotBadge.swift` 现在是纯静态 `Image` + 描边。全仓 **37 处**调用它，**没有一处有动画**。20 个表情资产，全是死的。

全仓现代动效 API 用量实测：

```
phaseAnimator        0        matchedGeometryEffect  0
keyframeAnimator     0        Canvas                 0
visualEffect         0        GlassEffectContainer   0
ScrollPosition       0        draggable/dropDestination 0
sensoryFeedback      1        scrollTransition       2
```

在 `BubuMascotBadge` 里加约 25 行 `phaseAnimator`（呼吸 + 偶尔歪头），`reduceMotion` 时整段禁用：

```swift
enum Alive: CaseIterable { case rest, breatheIn, tilt }

Image(resolved.assetName)
    .phaseAnimator(Alive.allCases) { view, phase in
        view.scaleEffect(phase == .breatheIn ? 1.035 : 1)
            .rotationEffect(.degrees(phase == .tilt ? 2.5 : 0), anchor: .bottom)
    } animation: { phase in
        switch phase {
        case .rest:      .easeInOut(duration: 1.6)
        case .breatheIn: .easeInOut(duration: 1.4)
        case .tilt:      .spring(response: 0.5, dampingFraction: 0.6)
        }
    }
```

**一个文件，全 App 37 个位置同时活过来。这是本轮投入产出比最高的一条。**

#### ② 缩略图淡入 —— 改 1 行，每一张图受益

`DesignSystem/Components/MediaThumbnail.swift:16-32` 是 `if let image {…} else {placeholder}` 直接替换，无过渡。相册一屏 90 格、时光轴每张封面、首页最近时光都走这个组件——**滚动时满屏方块闪跳**。

加一行：

```swift
.animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: image != nil)
```

#### ③ 下拉刷新 —— 全仓 0 处

`.refreshable` 在整个仓库**一次都没用过**（已 grep 确认）。首页刷新只由 `onAppear` + `didBecomeActive` 触发，同步状态藏在页面最底部。用户下拉——最强的「我要最新的」本能——纹丝不动。

首页和时光轴各加 3 行，系统自带下拉动画与触觉。

### 4.2 让它更好用

| # | 问题 | 位置 | 修法 |
|---|---|---|---|
| 1 | 首页 14 个可点卡片零按压反馈，包括「记录此刻」主按钮 | `CaptureHomeView.swift` 14 处 `.buttonStyle(.plain)` | 换成已有的 `BubuPressableStyle()`，组件自带 `reduceMotion` |
| 2 | 点照片看大图是硬切黑幕，看不出点的是哪张 | `EntryDetailView:180` / `AlbumDetailView:36` / `SimpleTimelineView:77` | 照抄本仓已有写法：`matchedTransitionSource` + `navigationTransition(.zoom)`。首页→详情已经这么做了 |
| 3 | 左滑删除**在当前工具链下被整段编译掉** | `BubuIOS27Compatibility.swift:34-53`，`#if compiler(>=6.4)` 在 Swift 6.0 走 `else self` | 短期用 TipKit 提示「长按有菜单」（项目已用 TipKit）。不建议为此把 ScrollView 改 List |
| 4 | 大图查看器不能下滑退出，出口是右上角 40×40 的 X | `MediaViewer.swift:94-103` | 加 `DragGesture`，约 20 行。姥姥模式看大图走的正是这页 |
| 5 | 记录面板下滑关闭 = **静默丢内容** | `QuickCaptureSheet.swift:134-137`，重开时 `startQuickCapture()` 清空全部草稿 | 加 `.interactiveDismissDisabled(model.canSave)`。本仓录音中已有同类保护可抄 |
| 6 | 四处破坏性操作无确认无触觉无撤销：**时间胶囊**、里程碑、记录内照片/语音、疫苗 | `CapsuleHomeView:221` / `MilestoneSheets:219` / `EntryDetailView:192,374` / `VaccineView:202` | 套用 `HealthHomeView:315-335` 那套（alert + 触觉 + toast），组件全现成。删胶囊建议再加一层输入名字确认 |
| 7 | 同一个「删除记录」，时光轴有撤销、详情页没有 | `TimelineView:700` vs `EntryDetailView:579` | 统一 |
| 8 | 切 Tab 无触觉 | `RootTabView.swift:75` | 一行 `.bubuSensoryFeedback(.selection, trigger: selection)` |
| 9 | 追加照片/视频全程无进度，大视频几十秒疑似卡死 | `EntryDetailView.swift:493-530`，整个文件零 `ProgressView` | 对齐 `TodayPhotosSheet:520-531` 的写法 |
| 10 | 首页「记录此刻」**出现两次**，副标题还不一样 | `CaptureHomeView.swift:783`「照片、语音、文字一起收好」+ `RootTabView.swift:221`「照片、声音和一句话一起收好」 | 删掉内联那张卡——它正是计划文档要求收进底部附件的那个 |
| 11 | 「功能搬家」提示卡仍常驻首页 | `CaptureHomeView.swift:85` 的 `BubuMovedHint` | 计划文档已明确要求删除（「已经有 TipKit，不需再存一套」） |
| 12 | 首页底部 `Spacer(minLength: 150)` 硬编码；时光轴底部为 0 | `CaptureHomeView.swift:98` vs `TimelineView.swift` | 同一个系统 inset 两种处理。统一到一个共享常量或交给系统 |

### 4.3 让它更可爱

| # | 断层 | 位置 | 修法 |
|---|---|---|---|
| 1 | **完成引导零仪式** —— 全 App 第一印象最平的一刻 | `OnboardingView.swift:206-251`，`finish()` 只有一次淡入 | `CeremonyAnimation` / `BubuBurst` / `BubuSound` 全现成，一处没接。顺带：引导**只有「继续」没有「返回」**，生日填错要重装 |
| 2 | **生日音效做了从没播过** | `BubuSound.swift:22` 定义 `.birthday` + `sfx-birthday.caf` 资产，全仓零 `play` 调用 | 一行 |
| 3 | **`CeremonyAnimation` 只用了 1/2 处** | 唯一调用点 `MilestonesHomeView.swift:92`。而组件注释写的是「里程碑 / **人生第一次**」 | 「第一次」确认路径 `CaptureHomeView.swift:509-525` 现在只是插条数据关掉 alert。这是 AI 识别出的「布布人生第一次」，产品最感人的时刻之一，现在处理得像填表 |
| 4 | **`.travel` / `.bath` 是死资产**，`.angry` / `.sport` 曝光概率≈0 | 已 grep 确认零引用 | `.sleeping` → `HealthHomeView:63-89` 哄睡计时卡（现在用裸 emoji 😴）；`.travel` → 带地点的记录角标；`.bath` → 洗澡类 |
| 5 | 「家人在一起」页的空状态是**一行灰字** | `FamilyFeedView.swift:193` | 与产品调性差距最大的一处。Story / Feed / PhotoFrame / Onboarding / Share **全域零吉祥物** |
| 6 | 7 处裸 `ContentUnavailableView` 系统灰字 | `FirstPersonDiaryView:61`（同文件 `:43` 就有吉祥物）、`FamilyEnsembleView:37`、`MediaViewer:337`（把解码错误当空态渲染，还没有重试） | 用已有的 `BubuEmptyIllustration` |
| 7 | 空状态只指路不给按钮，且**指错方向** | `TimelineView.swift:447-456` 写「点**上面**的记录此刻」，但这一页上面没这个按钮，它在底部附件 | 抄 `CaptureHomeView:958-988` 和 `CapsuleHomeView:179-200`，那两处写得很好 |
| 8 | 保存成功的庆祝只在首页看得到 | `CaptureHomeView.swift:1120-1137` 的 `savedToast`（贴纸 + 迸射 + 触觉 + 音效）是全 App 手感最好的一刻，但只挂在首页 | 提成 DesignSystem 组件，详情页与姥姥模式复用 |
| 9 | **里程碑保存失败仍然放庆祝音效** | `MilestoneSheets.swift:269-277`，`play(.milestone)` 与 `try? context.save()` 同层 | 用户看到庆祝、数据没落盘。这直接损伤「仪式感」本身的可信度 |
| 10 | 身份卡背面印着一串 UUID | `BubuIdentityCard.swift:239-252`，「FULL ID」+ `uuidString` | 这张卡整体做得很好（学生证质感、镜面高光、翻面触觉、无障碍齐全），翻到背面看见机器码人设瞬间碎。换成小名 / 星座 / 上学第 N 天（正好接 §3.3 T0-1） |
| 11 | 20+ 处裸 `ProgressView()` 无文案 | 最该改：`ShareCardSheet:83`、`PhotoFrameView:76`、`QuickCaptureSheet:145` | 全仓最好的加载态是 `FirstPersonDiaryView:161-171`（`.thinking` + `bubuFloating()` + 「我在想，怎么把这一天讲给未来的自己听……」）。`bubuFloating()` 和 `BubuSkeleton` 都写好了，AIStudio 之外几乎没人用 |

### 4.4 适老化：声称与实际的差距

「姥姥模式支持最大字号」目前**只对三个大按钮成立**：

- `BubuTimeMachineApp.swift:460-462` 给简单模式放到 `accessibility5`
- 但 `BubuTheme.swift:224-237` 的 `scaled()` 用**自己**的 `maxContentSizeCategory = .accessibilityLarge`（AX2）夹取，且注释已承认它不受 `.dynamicTypeSize()` 影响
- `SimpleModeView` / `SimpleTimelineView` 全部调 `scaled()` **不带 `cap:`**，实际停在 AX2——**比声称的 AX5 低三档**
- 全仓唯一传 `cap: elderCap`（AX4）的只有 `BubuBigActionButton.swift:69,80,84` 三行

三处把字号夹到无障碍档以下（对 AX1–AX5 用户零响应）：`TodayPhotosSheet:147`（xxLarge）、`CaptureHomeView:664`（xxxLarge，首页顶栏）、`BubuIdentityCard:67`。

低于 44×44 的真实可点元素：`CaptureHomeView:653` 首页唯一进设置的入口 **42×42**；`MediaViewer:80/88/100` 三个 **40×40**（姥姥看大图的唯一出口）；`HealthHomeView:290-306` 编辑与删除各 **38×38** 且间距仅 8pt（破坏性操作紧挨常规操作）；`NaturalCaptureReviewSheet:171-181` **≈18pt**，全仓最小。

**姥姥模式的真实能力边界**：能拍照、录音、只读浏览。**不能**写文字、不能从相册选图、不能删改（拍糊一张零补救）、**不能记喂养/睡眠/健康**——而这恰恰是长辈日常带娃最高频的动作。退出是单向门：一点即走无确认，要回来必须去设置页找 Toggle，正是姥姥做不到的那步。

`SimpleTimelineView.swift:9-11` 的 `@Query` 无 `fetchLimit`，十年档案会在姥姥手机上一次性加载。

**幼儿园相关性**：入园后接送大概率落到长辈身上，姥姥模式的使用频率会上升。建议至少补「能记喂养/睡眠」和「删掉刚拍错的那张」。

---

## 5. 可吸收的新能力

`docs/GITHUB_IOS_CAPABILITY_RESEARCH_2026-08-29.md` 已经把第三方库调研得很完整，不重复。这里只补它**没覆盖的系统框架**，全部已在本机通过 `swiftc -typecheck`（iOS 26 SDK / Swift 6）。

### 5.1 立刻可用且能删代码的：`@Generable` 结构化输出

`Services/AI/OnDeviceNaturalParser.swift` 现在的做法是：让端侧模型输出 JSON 文本，再用 80 行「宽容解码」剥 ```json 围栏、`JSONSerialization`、逐字段 best-effort 映射，解不出返回 `nil`（功能静默失效）。

**全仓 `@Generable` 用量为 0**——而这正是 Foundation Models 用来消灭这类解析的机制。约束解码保证输出必然合 schema：

```swift
@Generable
struct ParsedRecord {
    @Guide(description: "记录领域", .anyOf(["water","meal","sleep","symptom","growth","timeline"]))
    var domain: String
    @Guide(description: "简短标题，不超过12字")
    var title: String
    @Guide(description: "句子里明确出现的毫升数；没有就留空")
    var amountML: Int?
}

let r = try await session.respond(to: text, generating: ParsedBatch.self)
```

**收益**：删掉整个 `decode` 函数（80 行 → 约 15 行），且消除「模型多输出一个字就整条失效」的失败模式。`.anyOf` 在解码层面就锁死了 domain 取值，比 prompt 里写规则可靠。

这也是计划文档 §6.3 明确要求过、但尚未落地的一条。

### 5.2 幼儿园直接要用的（已验证）

| 能力 | API | 用途 |
|---|---|---|
| 文稿扫描 | `VNDocumentCameraViewController` | 作品自动裁边去畸变（§3.4 T1-1） |
| 中文 OCR | `RecognizeTextRequest`（新 Vision Swift API） | 通知单日期抽取、老师写在画上的字 |
| 实时取景扫描 | `DataScannerViewController` | 对准通知单即读 |
| 儿童涂鸦 | `PKCanvasView` + `PKInkingTool(.crayon)` | iPad 上布布自己画，直接存成时光 |
| 图中取字 | `ImageAnalyzer` / Live Text | 老照片、奖状里的字可选可搜 |

这五个全仓用量均为 **0**。

### 5.3 让「可爱」有系统级支撑（已验证）

| 效果 | API | 现状 |
|---|---|---|
| 吉祥物呼吸/歪头 | `phaseAnimator` | 0 处（§4.1 ①） |
| 图标描边生长（里程碑点亮） | `symbolEffect(.drawOn)` | SF Symbols 7，0 处。1 行 |
| 图标形变替换 | `.symbolEffect(.replace.magic(fallback:))` | 0 处 |
| 数字滚动（年龄、天数、计数） | `contentTransition(.numericText())` | 仅 2 处，该有约 10 处 |
| 记录球 → 编辑器形变 | `GlassEffectContainer` + `glassEffectID` | **0 处**，而计划文档点名要用 |
| 首页背景微视差 | `visualEffect` + `frame(in:.scrollView)` | 0 处。3 行，「高级感」提升最大的一处 |

### 5.4 明确不建议

- 不为动效引入 Lottie / Pow。上面全部是系统 API，零依赖姿态是这个项目的资产。
- 不引第二个图片缓存库。
- 不做 TCA 全量重写。§2.7 已给出可安全先拆的两块。

---

## 6. 执行顺序

### 6.1 立刻（不动 schema，可当天发）

1. §1.5 AI 自动开启 —— **两行**，与产品第一原则冲突
2. §1.9 家人补充丢失 —— **两行** `holdCursorForCurrentPull = true`
3. §1.10 删除被复活 —— `activeRecordFields` 加一个参数
4. §1.3 / §1.4 启动迁移覆盖 + 降级模式挡页
5. §1.6 让 main 变绿 + CI 加 warning 门禁
6. §1.2 把 autodate migration 提交进仓库 + 守卫测试改正向

### 6.2 开学前（9 月 9 日）

7. §3.3 T0-1 ~ T0-5 五项。除 `schoolStartDate` 一个 optional 字段外全是常量数组和纯 View
8. §4.1 三条（吉祥物动起来 / 缩略图淡入 / 下拉刷新）——改动小、感知强、当天可见
9. §4.2 #10 #11（删掉重复的「记录此刻」和常驻搬家提示）

### 6.3 开学后两周

10. §1.1 版本化 Schema 真修复 + 旧 store 打开的回归测试。**这是所有 schema 变更的前置**
11. §2.1 加索引（必须在 10 之后）
12. §3.4 T1-1 作品扫描 —— 本轮最高价值功能
13. §1.8 胶囊 `cryptoVersion` + §1.7 家庭规则收口（**在引入更多家庭成员之前**）
14. §2.6 让拉取故障可见 —— 否则 §1.2 复发还是看不见

### 6.4 需要你决策，不建议我替你定

- **鸿蒙端**（§2.9）：继续跟随，还是明说冻结在 2.11.0？现状「宣称跟随、实际掉队两个版本、CI 检测不出」是最坏的一种。
- **姥姥模式**（§4.4）：入园后长辈接送频率上升，是补齐到能记喂养/睡眠，还是维持只读定位？
- **§2.4 大文件上传**：现在是前台 URLSession + 无退避。改 background URLSession 是一整块工作，要不要排进这一轮？

---

## 附：本次审计中被证伪或需要更正的说法

诚实记录，避免以讹传讹：

1. **`CapsuleCrypto` 和 `ArchiveExporter` 不是测试盲区**，反而是全仓覆盖最扎实的两块。
2. **CI 的 `actions/checkout@v7` 不是笔误**，历史有多次 success，checkout 步骤正常。
3. **`ChildProfile` 没有身份证字段**，身份卡上的编号是装饰性假号。CLAUDE.md「截图含身份证」的说法与代码不符，建议更正。
4. **里程碑去重的严重度低于初判**：`milestoneRank` 里随天数增长的那一项被 19 天封顶，只在「达成状态、备注、自定义标记全都相同」的近乎重复项之间打平。真正的问题是「每次启动跑一次无上限硬删」这个形状，不是「胜负会漂移」。
5. **首页首屏渲染没有性能问题**：实测热启动 1–2 秒内出内容。首次安装后的冷启动曾出现 4 秒白屏，属安装后首次建库，非常态。
6. **同步的时钟漂移/时区不是问题**：过滤字段与推进依据同为服务器时钟，`syncTimestampString` 固定 UTC + `en_US_POSIX`。真正的漏窗口是 §1.9 和 §2.5，不是时钟。
