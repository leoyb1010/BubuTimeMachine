# BubuTimeMachine 下一轮升级计划（Wave N · 规划版）

> 性质：**纯计划，本轮不实施任何代码改动。**
> 基线：GitHub main `53ed705`（Wave M 全量落地 + 复验修复后的版本）。
> 输入：本轮复验与排查的全部结论（见 §0 验证证据），原方案遗留 P2 项，及落地过程中新发现的观察项。

---

## 0. 本轮复验结论（计划的事实基础）

### 0.1 验证矩阵（全部通过）

| 验证项 | 方式 | 结果 |
|---|---|---|
| 单元测试 | `xcodebuild test`，前后两轮独立运行 | 22/22 通过 × 2 |
| 服务端 `/parse-natural-capture` 行为 | 离线测试脚本（monkeypatch LLM，Python 3.9 实跑），覆盖正常拆条/敏感强确认/脏 domain 降级/坏日期/坏置信度/空输出/空输入/LLMError→502 | 18/18 通过 |
| 运行时冒烟 | 模拟器安装启动（`-uitest-seed`）+ 截图 | 身份卡、AI 输入条、照片统计（只算照片）、新 Schema 启动迁移均正常，无崩溃 |
| 疫苗旧数据迁移 E2E | 全新容器注入旧打卡 → 启动 → 直查 SwiftData SQLite | 3 条旧打卡全部转为 VaccineRecord（doseId/剂次/source=migration 正确） |
| 迁移幂等性 | 二次启动后复查 | 仍 3 条，无重复迁移 |
| 静态扫描 | 残留引用（classify(entryId:)/UploadQueue/Self.childProfileDTO）、git 与远端一致性 | 全部干净 |

### 0.2 排查发现并已修复的问题（`53ed705`）

1. **Python 3.9 兼容崩溃（真 bug）**：新增 Pydantic 模型用了 `str | None`（PEP 604），3.9 服务器 import 即崩；已改回与全文件一致的 `Optional[...]`。`py_compile` 查不出此类问题，是行为测试抓到的。
2. **清洗逻辑过于激进**：LLM 返回非法 `confidence`（如 `"abc"`）或非法日期会丢弃整条记录；已改为「能抢救就抢救」——置信度归 0（客户端会强制人工确认）、日期置空重试，仅彻底无法构造才丢弃。

### 0.3 复验中确认的观察项（未修，转入本计划）

| 编号 | 观察 | 去向 |
|---|---|---|
| O1 | `PhotoWallView` 已无任何入口（首页改进相册后成孤儿视图） | §2.4 |
| O2 | 疫苗「取消打卡」的远端删除是一次性 best-effort，离线时取消可能在下轮拉取复活（60s 游标重叠窗口/新设备场景） | §2.1 |
| O3 | 客户端 `JSONDecoder.iso8601` 不容忍小数秒；服务端若回带微秒的日期会整包解析失败（目前服务端不带，属防御性） | §2.3 |
| O4 | 录音中切走页面不会自动停止录音 | §2.3 |
| O5 | 相册/照片墙的 album 列表在每次 body 求值时全量重算，照片上千张后可能掉帧 | §2.4 |
| O6 | 成长曲线同一月龄多条结构化记录会产生重复图表点 id（沿袭旧实现的模式） | §2.4 |
| O7 | ReviewSheet 保存时未确认的敏感项被静默跳过（按钮文案"保存 N 条"可见但不够醒目） | §2.2 |
| O8 | 手动疫苗打卡 injectedAt 取「排期日与今天的较早者」，无法补录真实接种日期/医院 | §2.5 |
| O9 | 外部验证基建缺失：本轮服务端行为测试脚本在 /tmp，迁移 E2E 为手工流程，均未固化进仓库 | §4 |

---

## 1. 上线前置（运维/人工操作，不写代码，优先级最高）

这些不做，Wave M 的新能力在真实环境是半瘫的：

1. **PocketBase 建表**（管理后台，5 分钟）：
   - `vaccinerecords`：localId(text,unique)、vaccineName(text)、doseId/doseLabel/hospital/injectionSite/reaction/note(text,可选)、injectedAt(date)、sourceRaw(text)、clientUpdatedAt(date)
   - `growthmeasurements`：localId(text,unique)、measuredAt(date)、heightCm/weightKg/headCircumferenceCm(number,可选)、note(text,可选)、sourceRaw(text)、clientUpdatedAt(date)
   - `childprofile` 增加 `avatar`(file) 字段
   - 三者的 list/view/create/update 规则照抄 `healthrecords` 现有规则
2. **AI 服务重启**：`server/ai` 拉新代码重启 FastAPI；服务器 Python ≥3.9 均可（已验证 3.9）。
3. **curl 验收**：用方案里的 6 个样例打 `/parse-natural-capture`，外加空字符串、纯表情两个健壮性样例（预期 200 + 空 items + warnings）。
4. **真机回归**：按仓库 `UPGRADE_PLAN_WAVE_M.md` §5 清单过一遍，重点：多图缩放、断网重试、两台设备头像互通、语音转写闭环、疫苗迁移（升级安装而非全新安装）。
5. **发版注意**：无新增权限声明需求（麦克风已有）；记得 bump build number。

---

## 2. 下一轮 P1 代码计划（按收益/风险排序）

### 2.1 删除同步通用化（tombstone / 删除队列）——本轮最重要的架构补课
- **问题**（O2）：当前全工程只有「软删除 isArchived」（Entry）和「一次性远端 delete」（VaccineRecord 取消打卡、TimeCapsule），离线删除会丢失删除意图。
- **方案建议**：新增轻量 `PendingDeletion` SwiftData 模型（collection、remoteId、createdAt），SyncEngine 每轮先消费删除队列再推数据；成功才移除队列项。优先只接 VaccineRecord，验证后推广到 TimeCapsule。
- **不建议** deletedAt 墓碑字段方案：要改每个 collection 的 schema 和拉取过滤，侵入面大。
- 验收：飞行模式取消打卡 → 恢复网络 → 远端记录被删；另一设备拉取后同步消失。

### 2.2 ReviewSheet 编辑能力 v2
- 字段级编辑：日期（DatePicker）、标题（TextField）、数量类字段（喝水 ml、身高体重数值）。
- 未确认敏感项在点「保存」时给一次明确提示（"还有 1 条需要确认的记录不会保存"），而非静默跳过（O7）。
- 低置信（<0.6）item 默认折叠 + 手动选分类下拉。

### 2.3 NaturalCapture 健壮性小包
- 客户端日期解码容错：自定义 `dateDecodingStrategy`（先标准 ISO 再带小数秒重试），消除 O3。
- `NaturalCaptureBar.onDisappear` 自动 `recorder.cancel()`（O4）。
- 解析请求防抖/防重复提交；超过 8s 给「还在听布布说…」进度文案。
- MockAIService 假解析样例扩到 6 个验收场景，保证离线演示完整。

### 2.4 相册与图表打磨
- album 计算 memoize：用 `@State` 缓存 + 以 `entries.count`/最新 `happenedAt` 为失效键（O5）。
- `PhotoWallView` 退役决策（O1）：建议直接删除，「全部照片」相册已覆盖其功能；或保留为 AlbumDetailView 的薄壳。二选一，不要留孤儿。
- GrowthCurve 同月多点：取该月最新一条，图表点 id 改 `(month, source)` 复合（O6）。
- 相册详情大库分页（fetchLimit + 滚动加载），千张照片不卡。

### 2.5 疫苗体验补全
- 打卡改弹「快速补录」sheet：日期默认今天、可选医院/反应/备注（O8）；长按仍可一键完成。
- 「其他疫苗记录」支持滑动删除（走 2.1 的删除队列）。
- 迁移记录（note 含"待确认"）在 UI 上加淡色「日期待确认」角标，点击可修正日期。

### 2.6 身份卡 v2（小而美）
- 点头像翻面：背面显示血型/性别/完整 ID/出生医院（字段已有）。
- 生日月自动挂小蛋糕徽章，与 AppIconManager 的生日图标联动。

---

## 3. P2 中期计划（下下轮，先不动）

1. **自定义相册**：`PhotoAlbum`/`PhotoAlbumItem` 模型 + PB `photoalbums`/`photoalbumitems`，支持新建、加照片、封面、收藏、家庭同步（原方案 §5.6 设计仍有效）。
2. **高光瞬间相册**：aiTags/里程碑/FirstTime 关联命中自动聚合。
3. **GrowthMeasurement 手动录入**：体检页一键记身高体重头围表单；WHO 百分位接近 P3/P97 时仅显示「建议下次体检咨询医生」的克制文案——不诊断。
4. **语音长按即说**：press-and-hold 模式 + 实时波形（复用 `VoiceComponents.WaveformView`）。
5. **导出链路升级**：ArchiveExporter/YearbookExporter 纳入疫苗与成长数据（年册加一页"长大的数字"）。
6. **SSE 长连**：用 PocketBase realtime 真订阅替代 8 秒轮询；同时删除现已无人消费的 `subscribeRealtime` 或正式接入。
7. **多孩支持探索**：全工程审计 `profiles.first` 假设（约十余处），评估改造成本后再决策。
8. **AI 月报**：复用 movie-narration 模式按月生成「布布本月小结」。

---

## 4. 工程与质量基建（与 P1 并行，建议尽早）

1. **把本轮手工验证固化为自动化**（O9）：
   - 服务端：`/tmp/bubu_server_test.py` 整理为 `server/ai/tests/test_parse.py`（pytest），连同 `requirements-dev.txt` 入库。
   - 客户端：新增 XCTest——`NaturalCaptureDTO` 解码容错（未知 domain/坏日期）、`NaturalCaptureRouter` 各 domain 落库断言（内存 ModelContainer）、疫苗迁移幂等单测、`PocketBaseClient` 上传响应文件名解析。
2. **CI**：GitHub Actions（macos runner）：`xcodegen generate` + build + test + pytest，PR 必绿后合并。
3. **部署文档**：server/ai README 注明 Python ≥3.9、依赖 pin（fastapi/pydantic/httpx/python-multipart/faster-whisper 可选）。
4. **可观测**：`/parse-natural-capture` 把 warnings 计数打进日志（每日 unparseable 率），LLM 输出漂移早发现。

---

## 5. 风险与依赖

| 风险 | 影响 | 缓解 |
|---|---|---|
| PB 未建表先用新功能 | 疫苗/成长/头像同步软失败提示 | §1 先做；发版说明里写清 |
| 删除队列设计不当 | 同步状态机复杂化 | 先只接 VaccineRecord 小范围验证（§2.1） |
| LLM 输出漂移 | 解析质量随模型更新波动 | §4.4 监控 + 固定 6 样例回归集 |
| 大照片库性能 | 相册/照片墙掉帧 | §2.4 memoize + 分页，上千张实测 |
| 多孩改造范围失控 | 牵动全工程 | 仅做审计与估算，单独立项（§3.7） |

---

## 6. 建议执行节奏

- **迭代 A**（一次会话可完成）：§1 全部（人工）→ §2.1 删除队列 → §2.2 ReviewSheet v2 → §2.3 健壮性包 → §2.4 相册打磨。出口：build+test 全绿 + 删除同步 E2E 通过。
- **迭代 B**：§2.5 疫苗补录 → §2.6 身份卡 v2 → §4.1-4.2 测试与 CI。出口：CI 上全绿。
- **P2（§3）**：迭代 A/B 验收后按价值重排再启动。

> 提醒：执行任何一条前，先跑 Phase 0 基线（`xcodegen generate` + build + test）确认起点干净，与 Wave M 流程一致。
