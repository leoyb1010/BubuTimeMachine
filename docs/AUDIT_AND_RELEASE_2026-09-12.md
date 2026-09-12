# 2026-09-12 全面审计、三轮修复与 2.15.0 上线记录

> 基线：`origin/main @ aaa624e`（2.14.0）。生产机 = 本机（后端），iOS 构建机 = Tailscale 上的开发 Mac。
> 本文是证据记录，不是计划；每一条"已修"都对应仓库提交与可复跑的测试或线上核验命令。

## 0. 结论

- 后端 2.15.0 已上线（`releases/v2.15.0-20260912`），迁移 0020 在生产库快照上排练通过后再切生产，上线前后各有一份完整备份；切换停机约 10 秒。
- iOS 2.15.0 (2026091201) 代码已提交并推送，模拟器 clean test 全绿（184 单元 + 5 UI，零源码告警）。真机覆盖安装受开发机钥匙串限制，需在开发机图形终端执行 `scripts/install-iphone-wifi.sh`（见 §6）。
- 五路独立审计（FastAPI / PocketBase / 运维部署 / iOS 同步与安全 / iOS 功能层）共提出 90 余条发现；第一轮修复了其中所有 P1 与大部分 P2，第二、三轮为对修复本身的对抗复审与线上回归。

## 1. 审计方法与覆盖

- 代码：五个并行审计代理分别覆盖 `server/ai`、`server/pocketbase`（含真实 0.39.2 二进制实测规则）、`server/ops` 与 launchd/备份/隧道、iOS `Services/Models/App`、iOS `Features/Widgets/Watch/project.yml`。
- 线上：只读检查 launchd 状态、日志、`_migrations`、规则、设置、`automation_jobs` 死信、备份戳、代理环境；未复制生产 `pb_data`，所有排练在 sqlite backup API 快照上进行。
- 测试基线（修复前）：后端 pytest 146、PocketBase 集成 6、iOS 184 单元 + 5 UI 全部通过。修复后：pytest 166、PocketBase 集成 12、iOS 184 + 5，harmony 合同测试 183。

## 2. 生产上已被证实的故障（修复前）

| 现象 | 根因 | 证据 |
|---|---|---|
| 语义 worker 自 8 月 7 日起每天崩一次（36 次） | superuser token 24h 过期后 PocketBase 回 403 而非 401，代码只在 401 重登 | `semantic-worker.err.log`；`_superusers` authToken.duration=86400 |
| 告警链路自 8 月 6 日起全部 502（171 次），备份过期 124h 无人知晓 | launchd 会话继承全局 `http_proxy` 且 `NO_PROXY` 为空，本机 ntfy 回环请求被送进代理 | `healthcheck.err.log`；`launchctl getenv http_proxy` |
| 周报/声音年轮证据窗口漂移 8 小时 | 过滤字面量用 ISO `T` 形式，PocketBase 按存储文本字符串比较 | 一次性 PB 实测：`>= '…T16:00:00+00:00'` 命中 0，`>= '… 16:00:00.000Z'` 命中 1 |
| worker 退避/租约失效（失败任务被立刻重领，三次即死信） | 同上，claim 过滤字面量格式 | 同上 |
| 46 条永久死信 | 36 张 HEIC（venv 无 pillow-heif）+ 10 段无缩略图视频，Pillow 打不开 | `automation_jobs` 按扩展名分组 |
| 摄取提交接口的"仅回环"守卫形同虚设 | Cloudflare 隧道从 127.0.0.1 进来，`realIP()` 在 trustedProxy 为空时就是 socket 地址 | 复现：带 `X-Forwarded-For` 的公网形态请求仍 201 |
| 删除 30 天后墓碑被整行真删，离线设备回来可把已删照片 POST 复活 | GC 假设"客户端离线超期会全量对账"，客户端没有该逻辑 | gc.pb.js + SyncEngine 无对应路径 |

## 3. 第一轮修复清单（提交 26eb5b5、03dfa5f）

### 后端 / PocketBase
- `pb_filter_datetime` 统一日期字面量；`filter_now` 用于 worker claim。
- 服务账号 401/403 均重新认证，到期前 5 分钟主动刷新；worker 主循环有错误边界与退避。
- 迁移 0020：禁止翻活墓碑、改写 `authorUserId`、改自己 `role`；同步热路径 `(familyId, updated, id)` 与 GC `(isDeleted, updated)` 索引；`trustedProxy=CF-Connecting-IP`；开启 `*:auth` 10/3s、`/api/batch`、`/api/files/token` 限流（刻意不限 `/api/` 总量与 `*:create`）。
- gc hook：墓碑行永久保留，只回收文件；新增 superuser 演练路由 `/api/bubu/ops/tombstone-gc`。
- semantic_queue hook：确定性 jobKey（记录+类型+文件/缩略图/角色），无关字段更新不入队；notify 只在进入死信时通知一次。
- intake_commit：socket 回环 + 无任何转发头才算本机；key 常量时间比较。`start_pocketbase.sh` 只导出 hook 需要的 8 个环境键。
- 摄取：校验失败不再卡在 `committing`，坏素材作废可重传；并发自动提交不再互相回滚。
- LLM：`finish_reason=length` 不再静默当结果、上游错误体不外泄、`complete_json` 非字典收口、小预算上调；`/transcribe` 放线程池；`PB_BASE_URL` 空值兜底；`X-API-Key` 按字节比较；`entry` 请求体 16KB 上限；每主体限流 30→60/min。
- worker：Pillow 解不开时 `sips` 转 HEIC、`ffmpeg`/`qlmanage` 抽视频帧（临时文件带原扩展名、Homebrew 路径兜底）。成片渲染改由服务账号下载受保护媒体。
- 运维：healthcheck/backup/周报通知的回环请求 `--noproxy`/`trust_env=False`，launchd 任务注入 `NO_PROXY`；healthcheck 增加外接盘挂载与剩余空间检查；`.credentials` 收紧为 700/600。

### iOS
- 同步字段补齐：`cryptoVersion`、`schoolStartDate`/`allergies`/`medicalNotes`、媒体 `width/height/durationSeconds/aiTags` 上行，拉回只增不清。
- 父记录未在服务器落地前不推送其媒体；「重传全部」只重传本机持有文件的媒体；七个集合补齐"await 期间被删 → 补墓碑不写回"守卫；人生第一次晚到父记录时补挂关联。
- 登录合并为单飞 + 凭据错误 30 秒冷却；429 视为瞬时并加长退避（与服务端新开的认证限流配套）。
- AI 未配置时「一句话记录」/转写/第一人称日记不再落到 Mock；模型数值非有限值不再触发 `Int` 崩溃。
- 时间胶囊换语音清掉旧内嵌音频；编辑到期信保留历史开启日期且不重新上锁。
- 体检编辑清空身高体重连带删派生测量；相框 await 后重新校验索引；全量导出对静态图抹 GPS/IPTC；锁屏小组件 `privacySensitive`；成片/年轮轮询 6 秒并按合同截断；AI 401/403 映射为鉴权错误。

## 4. 上线过程与证据

- 排练：生产库快照 → `migrate up`（0020 已应用、规则/索引/设置断言）→ 起 PB（新 hooks）→ 三个真实账号各自仍读到 191 条记录、匿名为空、翻活墓碑被拒 → GC 演练 purged=0 行数不变 → 新 AI 代码 `/openapi` 2.15.0、匿名 401、允许名单 2 人不变、`/health auth=true` → worker claim 与周报证据查询在真实 schema 上不报错。
- 上线：上线前完整备份戳 `20260912T043512Z`；逆序 bootout → 快照 → 显式迁移（entries 191 / media 2307 / users 3 / families 1 前后一致）→ 顺序 bootstrap，全部门禁通过；公网 `bubu-api`/`bubu-ai`/`bubu-ops` 三个健康端点 200。
- 上线后：46 条死信全部重排并在 5 分钟内索引完成（done 2263→2308）；健康检查退出 0；带代理环境变量模拟 PocketBase 宕机，告警成功写入本机 ntfy（12:36:58，用户手机会收到一条 `PocketBase health failed: http://127.0.0.1:1/api/health` 测试告警，可忽略）。

## 5. 第二、三轮（对抗复审与线上回归）

（见下文追加）

## 6. 真机覆盖安装

两台开发 Mac 在 SSH 会话下 `codesign` 均报 `errSecInternalComponent`（登录钥匙串对非交互会话不可用），因此无法远程产出签名真机包。已在仓库提供一键脚本，需在 **MacBook Pro 的图形终端** 执行：

```bash
cd ~/code/BubuTimeMachine && git pull && scripts/install-iphone-wifi.sh
```

脚本会自动挑选 `available (paired)` 的 iPhone、真机 Debug 构建、`codesign --verify`、`devicectl device install app` 覆盖安装并回读版本。前提：iPhone 与 Mac 同一 Wi-Fi、已配对。

## 7. 未做 / 留给下一轮

- iOS：通用 LWW 跳过时未应用远端版本（时钟偏移下本地编辑可能被静默丢弃）、对墓碑的本地编辑一轮后被覆盖、导入路径主线程解码、38 处 `try? save` 成功提示——需要更细的策略与真机验收，未在本轮盲改。
- 运维：SSH 隧道口令登录未关（系统设置需本人操作）、原片/镜像/本地 restic 仍在同一块 USB 盘、PocketBase 管理后台仍公网可达（建议 Cloudflare Access）、venv 仍寄居在 v2.8.0-candidate 目录。
- HarmonyOS：本轮仅同步版本号。
