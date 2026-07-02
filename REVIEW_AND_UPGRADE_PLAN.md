# 布布时光机 · 全面 Review + 上线升级计划（给 Opus 执行版）

> 生成日期：2026-07-02 ｜ 基线：`main` @ `136cdc6` ｜ 目标版本：v1.2.0 → **v2.0（可交付全家使用）**
> 覆盖：iOS（148 Swift 文件 / ~2.4 万行）+ 鸿蒙（122 ets 文件 / ~2.7 万行）+ 服务端（PocketBase + FastAPI）
> 本文档由 4 路并行深度 review（iOS 核心层 / iOS UI 层 / 鸿蒙端 / 服务端）+ 主控独立复核汇总而成。
> **本文档只做审查与规划，未改动任何业务代码。**

---

## 0. TL;DR（最重要的三句话）

1. **当前 `main` 分支编译不过，无法出包上线。** 提交 `136cdc6` 让 `SharedDefaults.swift` 引用了 `GrowthMeasurementExtractor`，而这个类型定义在 `Features/` 目录、不在 Widget extension 的 target 里 → Widget target 编译失败 → 整个工程 `BUILD FAILED`。**这是 P0-0，第一件要修的事。**
2. **有一条隐蔽的 P0 同步 bug 会静默丢多设备数据**：增量拉取游标用了带 `T` 的 ISO8601 格式，和 PocketBase date 字段的空格格式做字符串比较不兼容，导致"另一台设备当天写入的内容"经常拉不回来。**iOS 和鸿蒙两端都中招。** 这解释了项目里为什么已经攒了 `debugForceUploadAllLocalDataToCloud` 这类补救工具。
3. **账户与后端还不具备"给全家用"的安全底线**：家庭码只在客户端校验、PocketBase 默认开放注册、所有集合"登录即全权 + 可删全家数据"、备份是 `rsync --delete` 镜像（勒索/误删会一夜同步进备份盘）。**账户系统 + 后端加固是上线前的硬门槛，不是可选项。**

> 视觉与动效底子其实不错（马卡龙风格完成度高、reduceMotion 纪律好、加密胶囊三幕开启动画是亮点）。真正拖后腿的是：**一条致命的适老化短板（全 App 零 Dynamic Type + 低对比小字号）**、**一批"做了没接线"的死功能**、以及**同步一致性缺陷**。

---

## 1. 上线阻断项（P0，必须先清零，缺一不可上线）

### P0-0 编译阻断：Widget target 找不到 `GrowthMeasurementExtractor`
- **文件**：`BubuTimeMachine/App/SharedDefaults.swift:169,174`
- **根因**：`SharedDefaults.swift` 同时属于主 App 和 `BubuWidgetsExtension` 两个 target（见 `project.yml` 的 Widget sources 列表）。`136cdc6` 在其中新增了对 `GrowthMeasurementExtractor.value(.height/.weight, from:)` 的调用，但该 `enum` 定义在 `Features/Health/GrowthMeasurementBackfill.swift`，Widget target 只包含 `Models/` + 少数 `App/*.swift` + `EntryWriter.swift`，看不到 `Features/`。
- **现象**：`clean build` 报 `cannot find 'GrowthMeasurementExtractor' in scope`（主控已实测复现，`main` 与 `HEAD~1` 之间由此提交引入）。
- **修复（三选一，推荐 A）**：
  - **A（推荐）**：把 `GrowthMeasurementExtractor` 从 `GrowthMeasurementBackfill.swift` 抽到一个 target-中立的小文件（如 `App/GrowthMeasurementExtractor.swift` 或 `Models/`），并在 `project.yml` 的 Widget sources 里加上它，`xcodegen generate`。
  - B：在 `SharedDefaults` 里内联一份轻量的身高体重提取逻辑（Widget 只需读数值，不需要完整回填器）。
  - C：把 `SharedDefaults` 里用到该提取器的两行改成从已算好的 `SharedWidgetSnapshot` 字段读，不在 SharedDefaults 里现算。
- **验收**：`xcodebuild ... clean build` + `clean test` 全绿（零 error 零 warning），Widget 预览可渲染。
- **另注**：工作区当前有一批**未提交**的"里程碑去重修复"改动（`AppEnvironment.swift` +290 行等），处于半成品状态、也编译不过。修 P0-0 前先决定这批改动是接着完成、还是 stash——不要和 P0-0 混在一起提交。

### P0-1 同步游标格式不兼容 → 多设备当日变更静默漏拉（**数据"丢失"**）
- **文件**：`Services/Networking/PocketBaseClient.swift:585,415`（iOS）；`harmony/entry/src/main/ets/services/APIClient.ets:106,126,195`（鸿蒙，**同一 bug**）
- **根因**：客户端用 `ISO8601DateFormatter` 生成游标 `2026-07-02T03:33:20Z`（`T` 分隔），拼进 filter `(clientUpdatedAt>'…T…Z')`。服务端 `clientUpdatedAt` 是 PocketBase **date 字段**（`migrations/1700000002` 用 `new DateField`），落库格式是 `2026-07-02 03:33:20.000Z`（**空格分隔**），且 PocketBase 的 filter 日期是**按字符串比较**的。`'T'(0x54) > ' '(0x20)`，导致与游标同一 UTC 日的记录被判为"不大于游标"整批排除。60 秒 overlap 补不回这个差异。
- **现象**：另一台设备当天写入的记录，只有本机"当天首次拉取"之前发生的才拉得到，之后写入的永久漏掉。这正是项目里出现 `debugForceUploadAllLocalDataToCloud` / `DebugCloudReconciler` 的原因。
- **修复**：filter 字面量改用 PocketBase 落库格式 `yyyy-MM-dd HH:mm:ss.SSS'Z'`（空格分隔，UTC）。iOS 和鸿蒙都要改。**补一条针对真实 PocketBase 的集成测试**（覆盖"同一 UTC 日内 A 写、B 拉"）。
- **依据**：PocketBase discussion #2931 / #5439 / issue #602（ISO8601 带 T 保存 OK 但 filter 拉不到）。

### P0-2 家庭码仅客户端校验 + PocketBase 默认开放注册 → 任何人可注册并读删全家数据
- **文件**：`Services/Networking/AccountService.swift:15,63-70`（`familyCode = "YUANCHENXI"` 硬编码，仅 UI 校验）；`ServerConfig.swift:101`（默认服务器地址随源码公开）；`server/pocketbase/migrations/1700000000_init_collections.js`（所有集合规则 `@request.auth.id != ""`，含 deleteRule；从未收紧 users 集合的 createRule）
- **攻击场景**：仓库/URL/家庭码全公开 → 任何人 `POST /api/collections/users/records` 自注册 → 登录即通过所有集合规则 → 读取、篡改、**批量删除**孩子全部照片/视频/健康/疫苗/胶囊。若按 README 走 Cloudflare Tunnel，攻击面是整个互联网。
- **修复（服务端为主）**：
  1. 新增迁移把 PocketBase `users` 集合 `createRule` 置为 `null`（仅超管建号，家庭场景够用）；家庭码校验若要保留，挪到服务端注册 hook。
  2. 轮换已泄露的家庭码。
  3. PocketBase 监听地址从 `0.0.0.0` 收敛到 Tailscale 网卡 IP 或 `127.0.0.1` + `tailscale serve`（顺带拿到 HTTPS）。
  4. 见 §4 账户体系：改成"关注册 + 家庭隔离"。

> **P0 验收出口**：编译全绿；两台真机在同一 UTC 日内互相写入能在 30 秒内互相拉到；关闭公开注册后陌生 URL 无法注册；`clean test` 通过。

---

## 2. 数据一致性缺陷（P1，上线前强烈建议全清，这些会慢慢吃掉家庭记忆）

> 这一组 9 条缺陷共同解释了"为什么数据偶尔重复/丢失、为什么需要手动重传工具"。它们不是独立小 bug，是**同步层三类系统性缺陷**：删除不同步、字段清空不同步、冲突无时间戳。

### P1-1 删除只做了疫苗一个集合，其余全部只删本地（换机/重装即"复活"）
- **文件**：`Services/Sync/SyncEngine.swift:274-304`（`PendingDeletion` 仅接入 `vaccinerecords`）；调用点：`EntryDetailView.swift:478,487`（照片/语音只删本地）、`MembersView.swift:89`（成员）、`MilestoneSheets.swift:253`（自定义里程碑）、`CapsuleHomeView.swift:201-204`（胶囊 `Task { try? await delete }` 即发即弃，离线/失败即永久丢删除意图）、`EntryDetailView.swift:230`（取消"亲一下"反应，且 1 分钟内会被 `mergeRemoteComment` 重新插回，`mergeRemoteVaccine:1031` 有防复活检查、comment 没有）。
- **修复**：把 Media / Comment / VoiceNote / FamilyMember / Milestone / TimeCapsule 全部接入 `PendingDeletion` 队列；各 `mergeRemoteXxx` 在插入前先查删除队列防复活。**鸿蒙端已移植 `processPendingDeletions` 骨架**（`SyncEngine.ets:188,209`），但同样只接了部分集合，需对齐。

### P1-2 可选字段置 nil 永不上行，还会被拉取"弹回"
- **文件**：`Services/Networking/PocketBaseClient.swift:674-681`（所有 `xxxBody` 都是 `if let v { body["X"]=v }`）+ `SyncEngine.swift:1188-1191`
- **现象**：清空字段（如取消里程碑达成 `happenedAt=nil`）时 PATCH 不带该 key，PB 保留旧值；而 `clientUpdatedAt` 被刷新 → 60s overlap 内本机再拉 → `apply(dto)` 把旧值写回 → "取消达成"一分钟内自动还原。影响所有可选字段（note/title/detail/医院/反应…）。
- **修复**：清空字段显式发送 `""`/`NSNull`，或 body 恒定包含全部字段。

### P1-3 冲突策略是"最后推送者赢"而非"最后编辑者赢"
- **文件**：`Services/Sync/SyncEngine.swift:239-254,862-867`（`mergeRemoteEntry` 只判 `syncState==.synced`，从不比较 `editedAt`/`clientUpdatedAt`）
- **现象**：A 离线改了记录，B 随后改同一条并已同步；A 联网推送会用**更旧**内容覆盖服务器与 B。家庭多人补写同一条时静默丢内容。
- **修复**：push 前比较远端 `clientUpdatedAt`/`editedAt`，较旧一方走字段级合并或提示冲突。

### P1-4 同步任务生命周期竞态 → 并发双同步 + 远端重复记录
- **文件**：`Services/Sync/SyncEngine.swift:66-72,157-172`（`setClient` 取消并置空 `syncTask`，但旧 Task 体内不检查 `Task.isCancelled`，跑完执行 `syncTask=nil` 会清掉新任务句柄 → 下轮再起第三个任务）
- **触发**：同步进行中改服务器设置/账号（`reloadServices`）。两个循环同时 `findRecord→POST` 同一 media（localId 无 unique 索引兜底）→ **创建重复远端记录**。
- **修复**：任务完成时仅当 `self.syncTask === 当前任务` 才置空；循环内检查取消；**服务端给 localId 建 unique index**（见 P1-10）。

### P1-5 pull 游标无条件推进，但 merge 可能跳过记录 → 静默丢更新（主控独立复核）
- **文件**：`Services/Sync/SyncEngine.swift:759-776`（`pull` 拉取成功即 `setCursor(started)`）配合 `mergeRemoteEntry:864`（`if entry.syncState==.synced` 才应用）、`mergeRemoteMedia:891`（本地找不到父 Entry 直接 `return` 丢弃）
- **现象**：某条远端记录当时因本地有草稿被跳过 / media 的父 entry 尚未落地被丢弃，但游标已越过它 → 除非该记录再次被远端更新，否则永不再拉回。新设备首次全量、乱序拉取时尤甚。
- **修复**：merge 被跳过/父对象缺失时，不把该批次游标推到最新（或对被跳过项单独重试队列）；media 找不到父 entry 时暂存待父到达后补挂，而非丢弃。

### P1-6 大文件整体读入内存下载（视频可 500MB）→ 多设备补拉易 OOM
- **文件**：`Services/Networking/PocketBaseClient.swift:261-270`（`downloadFile` 用 `URLSession.shared.data`）+ `SyncEngine.swift:786-807`（每轮最多连续 8 个）+ `:797`（photo 分支还全尺寸 `UIImage(data:)`）
- **修复**：改 `URLSession.download(for:)` 落盘再移动；缩略图用已有的 `ThumbnailProvider.downsample`（ImageIO 降采样）。**上传同样应改后台 URLSession + 断点续传**（HANDOFF 里 UploadQueue 有骨架）。

### P1-7 首次全量拉取 O(N²)：每条记录都全量存库 + 全表统计 + Widget 重载
- **文件**：`Services/Sync/SyncEngine.swift:759-776,877,919,1012,1027-1028`（每 merge 都 `context.save()`；`mergeRemoteEntry/Milestone/ChildProfile/Health` 每条调 `refreshWidgetSnapshot`；`SharedDefaults.totalEntryCount/totalPhotoCount` 是全表 fetch 再 `.count`；`mergeRemoteHealth` 每条跑一次 `GrowthMeasurementBackfill.run` 全量扫描）
- **现象**：几百条记录首轮同步明显卡死 UI，`WidgetRefresher.reload` 每条一次会耗尽 WidgetKit 刷新预算。
- **修复**：批量 merge 后统一 save/刷新一次；计数改 `fetchCount`。

### P1-8 定位权限 continuation 被覆盖 → 泄漏 + 调用方永久挂起
- **文件**：`Services/Location/LocationService.swift:40-44`（`.notDetermined` 分支直接赋值 `permissionContinuation`，不像 `requestOneShotLocation:65` 先 resume 旧的）
- **触发**：并发请求定位（快速点两次"带上地点"）→ 第一个 `await` 永不返回。
- **修复**：赋值前 `permissionContinuation?.resume(returning: false)`。

### P1-9 疫苗降级路径破坏删除链 → 记录可复活
- **文件**：`Services/Sync/SyncEngine.swift:503-515,1337-1353` + `VaccineView.swift:226-228`
- **现象**：服务器缺 `vaccinerecords` 集合时疫苗降级写 healthrecords 并标 `.synced` 但 `remoteId=nil` → 删除时 `if let remoteId` 不成立 → 不入删除队列 → 远端 healthrecords 副本永存 → 任何设备拉到会经 `backfillVaccineIfNeeded` 把疫苗重新造出来。
- **修复**：降级成功也记 fallback remoteId，或删除时同步删 healthrecords 副本。

### P1-10（服务端）localId 唯一索引实际不存在 + 全库零索引
- **文件**：`server/pocketbase/migrations/1700000000_init_collections.js:16-17`（`unique:true` 在 PocketBase v0.23+ 被静默忽略，唯一性必须用集合 `indexes`）
- **现象**：README 宣称的"localId 幂等去重"服务端根本没约束；重试/并发创建同 localId 会产生重复且数据库拦不住（放大 P1-4）；每次增量按 `clientUpdatedAt`、关联按 `entryLocalId` 都是全表扫描。
- **修复**：新增迁移为每个集合补 `CREATE UNIQUE INDEX idx_x_localId ON x (localId)` + `clientUpdatedAt`/`entryLocalId`/`happenedAt` 普通索引；**补索引前先清一遍已有重复**。

> **鸿蒙互通专项（主控独立复核）**：v2 胶囊两端加密已对齐（BTC2 魔数 + 整秒 UTF-8 ISO 派生，AES-GCM `nonce||ct||tag` 布局一致，可互解）。**但 v1 历史 blob 两端不互通**：iOS 用 `"\(Double)"` 格式化整秒得 `"1749859200.0"`，鸿蒙模板串 `${number}` 得 `"1749859200"`（无 `.0`）→ v1 密钥材料不同 → 派生密钥不同。鸿蒙是新装无 v1 数据，实际影响有限，但若日后从 iOS 迁 v1 胶囊会解不开，建议鸿蒙 v1 派生补 `.0` 兼容或统一改 v2 重封存。

---

## 3. 服务端安全与容灾（上线前硬门槛）

> 这套系统存的是"孩子的一生"，备份和访问控制应按**不可再生数据**对待。

| 级别 | 问题 | 文件 | 修复 |
|---|---|---|---|
| **P0** | 开放注册 + 登录即全权（见 P0-2） | `init_collections.js` / `start_pocketbase.sh:29` | 关注册；监听收敛到 Tailscale/127.0.0.1 |
| **P1** | 备份是 `rsync -a --delete` 镜像热 SQLite | `README.md:24-27` | DB 用 PocketBase 内置 backups（cron+一致性 zip）或 litestream；媒体 rsync 去掉 `--delete` 或加 `--backup-dir`；至少一份异地/离线加密副本（3-2-1）；写恢复演练步骤并每季度演练 |
| **P1** | 冷启动重放迁移必失败（`timecapsules` 被重复创建） | `1700000001_add_timecapsules.js:8-28` | 加存在性判断（照抄 `1700000006` 的 `safeFind`），做一次"空目录冷启动"演练 |
| **P1** | 单账号 + 全开 deleteRule + 无回收站 → 一台失窃手机可不可逆清空全家 | `init_collections.js` 各 deleteRule | `deleteRule` 收紧为 `null`，删除走"标记 isDeleted"软删 + 定期清理；配合非镜像备份 |
| **P2** | file 字段未 `protected` → 知 URL 即免鉴权下载 | `init_collections.js:53,72,…,210` | 敏感 file 字段（healthrecords、`timecapsules.encryptedBlob`）改 `protected:true`，客户端用 PB file token |
| **P2** | API Key 失败尝试不限流 + `/health` 是验证 oracle + 非常数时间比较 | `ai/main.py:80-89,142-150` | `_check_rate` 提到 key 校验前；`secrets.compare_digest`；401 记日志 |
| **P2** | `/transcribe` 先整体读入内存再判大小；无请求体/文本长度上限 | `ai/main.py:412-429` | 先看 `Content-Length` 拒绝、分块读累计限额；note/text 加 `max_length` |
| **P2** | 限流桶清理逻辑失效，公网长跑慢性内存泄漏 | `ai/main.py:74-77` | 清理条件改"最后时间戳超 60s 的桶一并删" |
| **P2** | `ai/.env` 权限 644（同机他账户可读）+ 全链路明文 HTTP | — | `chmod 600 ai/.env`；`tailscale serve` 拿 HTTPS。**历史扫描：git 无泄露，`.env.example` 干净，`.env` 未被跟踪** |
| **P2** | 胶囊 `unlockAt`/`isLocked` 服务端不强制，可提前取/覆盖销毁 | `init_collections.js:199-213` | `viewRule` 加 `unlockAt <= @now`；已锁定记录 `updateRule/deleteRule` 置 `null` |

**服务端其它 bug**：`llm.py:38-43` 兜底重试吞真实错误（401/402/429 全被抹平）；`main.py` 从未 `logging.basicConfig` → INFO 日志实际从不输出；回填硬编码上限 5000 条；v0.23+ 下所有集合缺 `created`/`updated` autodate 字段（无审计线索）；`server/README.md` 集合清单/接口表过时；`start_pocketbase.sh:22` `cp` 只增不删旧迁移；media↔entries 是裸文本 `entryLocalId` 非 relation（删 entry 留孤儿文件）；venv 基于已 EOL 的 Python 3.9，依赖全 `>=` 不锁版本，PocketBase 版本未固定（迁移要求 v0.23+）。

---

## 4. 账户体系升级（"给全家用"的核心改造）

**现状**：三人共用一个 PocketBase 账户 + 本地角色切换；`members` 只是展示卡、与 `users` 无关联；`authorRole` 全由客户端自报（任何人可伪造他人署名，见 P1 的"奶奶被署名成妈妈"bug）。

**目标架构：关注册 + 家庭组隔离（推荐 B-2b 家庭多账号共享布布，贴合多人记录现状）**

| 步骤 | 服务端 | 客户端 |
|---|---|---|
| 1. 关注册 | `users.createRule = null`，超管建号或邀请制 | 注册页改"用邀请/家庭码申请" |
| 2. 家庭组 | 新建 `families` 集合；`users` 加 `family` relation | Onboarding：注册/登录 → 加入或创建家庭 |
| 3. 数据隔离 | 全部业务集合规则从 `@request.auth.id != ""` 改 `@request.auth.id != "" && family = @request.auth.family`；create 规则加 `@request.body.family = @request.auth.family` | 同步层无需大改（隔离在服务端） |
| 4. 真实署名 | `authorRole` 改 `author` relation → users，createRule 强制 `@request.body.author = @request.auth.id` | 署名读 `author.role`，不再本地自报 |
| 5. 删除/更新收紧 | 按"作者本人或家长角色"限制 | — |
| 6. 存量迁移 | 现有共享数据 backfill 归属到默认家庭 | 一次性迁移提示 |

**配套客户端修复**：
- **称谓枚举统一**（P1）：`FamilyRole` 只有爸/妈/姥姥三种，`Relation` 有 7 种，`currentRole ?? .mama` 有损回落 → 奶奶/爷爷/姥爷记录被署名成妈妈。统一成一个称谓枚举，或 `currentRole` 直接存原始字符串。
- 密码长度校验对齐 PocketBase（客户端 ≥6，PB 默认 ≥8，6-7 位注册 400 被误报成"用户名已注册"）：`AccountService.swift:59`。
- 找回密码（PocketBase `request-password-reset`）、Token 刷新已部分有、登出清 Keychain。

---

## 5. 设计 / UI / 动效升级

### 5.1 P0 适老化（"姥姥能用=验收标准"目前不成立）
- **全 App 零 Dynamic Type**：`BubuTheme.Font` 全用 `Font.system(size:)` 固定字号（`BubuTheme.swift:109-115`），全项目 288 处硬编码、0 处 `relativeTo/@ScaledMetric`。姥姥调大系统字体后 App 内文字纹丝不动；大量正文只有 9.5–12.5pt（四宫格、TabBar 标签 10/9pt）。
  - **修复**：`Font.system(size:weight:design:)` 全改 `.system(.body/.title, design:.rounded).weight(...)` 或补 `relativeTo:`；`@ScaledMetric` 缩放图标/行高；`accessibility` 档位做布局降级（四宫格→单列）。
- **对比度不足**：`secondaryText #A98D82` 压 `cream #FFF7F1` ≈ 2.6:1（AA 要 4.5:1）却承载大多数说明文字；`BubuStoryView` 白字压 butter/peach 渐变 <2:1。加深 secondaryText 一档、渐变白字加描边。
- **可见的操作控件**：删除只靠长按（不可发现）；健康记录完全不可编辑（`HealthHomeView.recordRow` 无入口，疫苗页却有——标准不一）。所有破坏性/编辑操作要有可见按钮。

### 5.2 P1 UI 功能失效（做了但不工作 / 明显可复现错误）
| 问题 | 文件 | 现象 |
|---|---|---|
| 首页完全忽略主题系统 | `CaptureHomeView.swift:34,159-176` | `theme` 硬编码珊瑚色、hero 背景硬编码 hex；切 8 套主题 / 设"照片做首页背景"首页毫无变化；`heroMode`/`BubuMeshHero` 只写不读 |
| `.preferredColorScheme(.light)` 强制首页浅色 | `CaptureHomeView.swift:114` | 深色模式下切首页整窗变浅、来回闪变 |
| `swipeActions` 挂在 ScrollView/LazyVStack 上无效 | `TimelineView.swift:126-130`、`CapsuleHomeView.swift:80-102` | 时光轴/胶囊滑动删除是死代码，唯一入口是长按 |
| 胶囊到点解锁时从界面消失 | `CapsuleHomeView.swift:19-33,90-110` | `TimelineView(.periodic)` 只包 lockedSection，body 不重算 → 解锁瞬间胶囊凭空消失（仪式感最强时刻丢失） |
| 家庭动态每条记录显示两遍 | `FamilyFeedView.swift:16-23` | 持久化 FeedEvent + 现场合成重复 |
| 全屏查看器主线程全尺寸解码 + 每帧新建 AVPlayer | `MediaViewer.swift:104-137` | 翻大相册掉帧 + 内存尖峰；未用已有的 `ThumbnailProvider(.detail)` |
| 录音中关面板 → 灵动岛 Live Activity 永不结束 | `AudioRecorder.swift:58,77` + VoiceRecorderBar | 4 处宿主缺 `onDisappear` 兜底（NaturalCaptureBar 有） |
| 奶奶/爷爷记录被署名成妈妈 | `Enums.swift`+`ServerConfig.swift:23-25` | 见 §4 称谓枚举 |
| 备注输入框打第一个字就消失 | `HealthRecordSheet.swift:438-445` | `if draft.detail.isEmpty { TextField }` 条件翻转移除输入框 |
| 名字每键入一字全量落库+Widget 重建+reload | `ChildProfileView.swift:72-81` | 打字卡 + 烧光 WidgetKit 刷新预算 |
| 悬浮 TabBar 遮挡所有二级页底部 | `RootTabView.swift:11-54` | 详情/设置/相册底部内容被永久遮住，且编辑中可被点走 |
| 胶囊倒计时 Live Activity 过期即崩 | `BubuLiveActivity.swift:84` | `Text(timerInterval:)` 过期构造非法 Range；接线前必须 `now...max(now,unlock)` |

### 5.3 动效体系评估
**亮点（保留）**：Token 化早（BubuMotion 五曲线 + BubuHaptics 六语义 + BubuSound，动效-触觉-声音成对）；胶囊开启三幕制（破封→回溯→展信，可跳过、reduceMotion 定格）；里程碑 CeremonyAnimation；身份卡 3D 翻面；`contentTransition(.numericText)`；reduceMotion 覆盖 11 文件。

**缺口（升级）**：
1. **仪式不对称**：开胶囊有三幕、封胶囊只有"咔哒"一声；点亮里程碑有全屏卡、记录保存只有 toast；"这是布布的第一次吗"用**系统 alert**（高光时刻配系统弹窗最浪费）。→ 补封蜡盖章动画、"第一次"改自定义吉祥物卡片。
2. **常驻动画违背自家纪律**：`BubuSparkle`(repeatForever) 散在首页/里程碑/故事的滚动区，星盘 12 颗 blur 光晕 + 胶囊阴影半径逐帧重绘 → 页面永不 idle、耗电。→ 改 `TimelineView(.periodic)` 低频离散或静态。
3. **入场动效只有时光轴有**；`BubuCountUp` 写完没用（统计四宫格适合）。
4. **转场断层**：`navigationTransition(.zoom)` 只用在首页/时光轴→详情；相册→查看器、里程碑→编辑、故事→阅读器都是默认转场。
5. **成长电影全程静音**（Ken Burns 做得细但无配乐）；星盘新星点亮无专属"新星升起"差分动画（新旧星统一 pop）。

### 5.4 信息架构
- 记录入口有 5 个（底栏+、dock、四宫格今日一问、AI 悬浮球、QuickCapture 内嵌一句话），对"姥姥"主线是选择过载。→ 合并为一个记录入口，进入后再分"拍/说/写"；首页压缩为 身份卡 + 一个大记录键 + 最近时光。
- 胶囊藏在魔法屋三级、与低频功能同级；临近解锁只在胶囊页内有呼吸光。→ 胶囊升级或首页露出倒计时卡 + 通知 + 灵动岛（UI 已写好只差接线）。
- 相册查看器**没有分享/保存到系统相册**（家庭 App 第一刚需——发家族群），也没有删除、没有"查看所属记录"。
- 时光轴无年份快速跳载、无按心情/成员过滤（数据都有）。

---

## 6. 鸿蒙端专项

- **同步 P0（游标格式）同样存在**：`APIClient.ets:106,126,195` 用 `toISOString()`（带 T），需同 iOS 一起改空格格式。
- **删除队列已移植骨架**（`SyncEngine.ets:188,209,1373`），但同 iOS 一样只接了部分集合，需对齐全集合。
- **v2 胶囊两端可互解**（已验证）；**v1 历史 blob 不互通**（见 §2 末尾），鸿蒙新装无 v1 数据，低风险。
- **功能对齐度**：AIStudio/AlbumDetail/BubuStoryReader/Timeline/VaccineQuickLog 等仍有 ComingSoon/占位（`grep` 命中 7 个 view 文件），需逐一确认是"占位待接"还是"已完成"。
- **鸿蒙系统能力**：服务卡片（≈iOS 小组件）已做（`BubuFormAbility`）；实况窗（≈灵动岛）/ InsightIntent（≈App Intents）仍 ⬜；跨设备流转、原子化服务未用——家庭多设备场景下"手机拍→平板看"的流转值得评估。

---

## 7. 工程与质量基建

- **测试覆盖缺口**（现有 5 个测试只覆盖加解密/图片嗅探/查询拼接/NaturalCapture/反应/疫苗迁移）。最需补：
  1. **SyncEngine**（最高优先）：内存 ModelContainer + Mock APIClient，回归"同日增量拉取"（直接覆盖 P0-1）、删除防复活、字段清空往返、并发编辑冲突、context 未 attach 时游标不推进。
  2. PocketBaseClient 日期编解码 + 针对真实 PB 的 filter 格式集成冒烟。
  3. StorageMigrator（数据安全最关键路径，目前 0 覆盖）。
  4. AgeCalculator（2/29、月末、生日当天、跨时区）。
  5. 服务端：鉴权 fail-closed、限流、`/transcribe`。
- **CI**：`.github/workflows/ci.yml` 已有 iOS build+test（macos-26 / Xcode 26）+ AI 服务端测试。**修 P0-0 后确保 CI 变绿**，并把"同日增量拉取"回归测试纳入 CI 门禁。
- **可观测性**（服务端≈零）：AI 服务加 `logging.basicConfig`（文件+轮转）；写 5 分钟级探活脚本（curl `:8090/api/health` + `:8000/health` + `df` 阈值）经 ntfy/Bark 推手机；PocketBase 备份成败纳入通知。
- **部署运维**：给出真实两份 LaunchAgent plist（`KeepAlive` + 日志路径）；固定并记录 PocketBase 版本；Python 升 3.11+ 并锁依赖；网络统一 `tailscale serve`。

---

## 8. 建议执行顺序（给 Opus 的分阶段清单）

> 每个阶段结束统一出口：`xcodegen generate` → `clean build` + `clean test` 全绿（零 error 零 warning）→ 模拟器种子截图核验 → 中文 commit 说清做了什么。

### 阶段 0 · 解除上线阻断（1 天内，最高优先）
- [ ] P0-0 修 Widget 编译（抽 `GrowthMeasurementExtractor` 到 target-中立文件 + 改 `project.yml`）
- [ ] 决定未提交的"里程碑去重"半成品：接着完成 or `git stash`
- [ ] P0-1 同步游标改空格格式（iOS + 鸿蒙）+ 补集成测试
- [ ] P0-2 服务端关注册 + 监听收敛 + 轮换家庭码

### 阶段 1 · 数据一致性（上线前必做）
- [ ] P1-1 全集合删除队列 + 防复活（iOS + 鸿蒙对齐）
- [ ] P1-2 字段清空显式上行
- [ ] P1-3 冲突改"最后编辑者赢"（比较 clientUpdatedAt）
- [ ] P1-5 游标推进与 merge 跳过解耦 + media 缺父暂存
- [ ] P1-10 服务端补 localId unique index + 常用索引（先清重复）
- [ ] P1-4 同步任务生命周期竞态修复
- [ ] P1-8 定位 continuation 修复｜P1-9 疫苗降级删除链

### 阶段 2 · 后端加固 + 账户体系
- [ ] 备份改内置 backups/litestream + 去镜像 + 异地副本 + 恢复演练
- [ ] 冷启动迁移幂等（timecapsules 重复创建）
- [ ] deleteRule 收紧 + 软删 + 回收站
- [ ] 账户：关注册 + families 隔离 + author relation 真实署名 + 存量迁移
- [ ] 称谓枚举统一（修奶奶被署名成妈妈）

### 阶段 3 · 适老化 + 性能（体验合格线）
- [ ] Dynamic Type 全量改造 + 对比度加深 + 可见操作控件
- [ ] 首页主题接线（读 `env.theme` + heroMode 照片背景）+ 去掉强制浅色
- [ ] 首页/查看器性能三件套（fetchCount + fetchLimit + 同步状态条隔离；查看器走 ThumbnailProvider + AVPlayer 生命周期）
- [ ] 大文件下载/上传改后台落盘 + 断点续传
- [ ] 修 P1 UI 失效清单（swipeActions/双份动态/输入框消失/TabBar 遮挡/录音孤儿）

### 阶段 4 · 仪式感与打磨（差异化）
- [ ] 封存胶囊盖章动画 + "第一次"自定义卡片替换系统 alert
- [ ] 胶囊灵动岛接线（先修过期 Range 崩溃）+ 首页临近解锁倒计时卡
- [ ] 相册查看器加分享/保存系统相册/删除/查看所属记录
- [ ] 清理常驻 repeatForever 动画 + 补入场/转场动效 + 成长电影配乐
- [ ] 星盘新星差分动画｜成长绘本用真实关联照片｜时光轴筛选/跳载
- [ ] 死代码清单接线或删除（heroMode/meshHero/prefetch/生日图标/BubuCountUp/ComingSoon）

### 阶段 5 · 鸿蒙对齐 + 工程基建
- [ ] 鸿蒙全集合删除对齐 + 占位功能补齐 + 系统能力（实况窗/流转）评估
- [ ] 测试补齐（SyncEngine/StorageMigrator/AgeCalculator/服务端鉴权）纳入 CI 门禁
- [ ] 服务端可观测性（日志+探活+磁盘告警）+ LaunchAgent 自启 + 版本固定

---

## 附录 A · P2 清单（体验劣化 / 边界，随阶段顺手清）

**iOS 核心层**：`connectAndSync` 早于 `attach(context:)` 时游标空推进（`SyncEngine:759`）；`CapsuleRecovery` iCloud Keychain 未同步时生成第二份恢复码 + wordList 实为 260 词且 `lotus` 重复；`VaccineLegacyMigrator` 迁移标记先行、save 吞错；`PhotoAnalyzer` EXIF 按当前时区解析（旅行照偏移）；`AgeCalculator` 2/29 与生日当天倒计时错误；`ArchiveExporter` 静默缺文件 + `jsonEsc` 只转义 3 种字符会产非法 JSON（建议 JSONEncoder）；`remoteURL` 存绝对地址绑死主机名；`ModelContainer` 创建失败直接 `fatalError`（应进恢复模式）；`try? savePhoto` 磁盘满静默丢照片；YearbookExporter 主线程同步渲染 PDF。

**iOS UI 层**：搜索无防抖 + `sections` 强持全部 Entry；时光轴内层 LazyVStack 嵌套破坏懒加载；里程碑 sheet 与 fullScreenCover 竞争吞仪式；QuickCapture 关 sheet 同帧 present 相机；EntryDetail 标签 `Array(Set)` 乱序；身份卡头像每帧同步读盘；FirstPersonDiary typewriter 无取消串台；FamilyEnsemble 反应哨兵混入；MediaThumbnail 呼吸占位漏 reduceMotion；AudioPlayer "暂停"实为停止 + 会话不 deactivate；CaptureModel 主线程压缩 + toast 竞态；OnThisDay 空年份 CTA 未实现；GrowthReport 裸写 `.orange/.purple`；AppIconManager dusk 无图标映射 + 生日图标死代码；Widget 缺缩略图回退读原图逼近内存红线 + `idNumber` 全局硬编码 `BUBU20240522`；一批死代码/未接线（TimelineEntryCard/ComingSoon/BubuMeshHero/BubuCountUp/BirthdayCountdown/prefetch/胶囊灵动岛/生日图标）；时光轴首帧误显搜索空态。

**服务端**：见 §3 表格与其后段落。

---

## 附录 B · 已实测事实（供 Opus 信任本文档）
- `main`@`136cdc6` `clean build` **实测 BUILD FAILED**（P0-0，已定位到具体两行）；回退到 `5e578a0` **BUILD SUCCEEDED**，主控用它截了首页/里程碑/魔法屋/设置/深色模式 UI 核验。
- 鸿蒙 `hvigorw assembleHap` **实测 BUILD SUCCESSFUL**（clean 重建 8s，产物 HAP 正常）。
- 服务端历史密钥扫描：全部提交无泄露，`.env.example` 干净，`.env` 未被 git 跟踪（但含真实 key、权限 644）。
- P0-1 游标格式、P1-5 游标/merge 解耦、鸿蒙 v1 互通、鸿蒙游标同 bug——均由主控独立读代码复核确认。
