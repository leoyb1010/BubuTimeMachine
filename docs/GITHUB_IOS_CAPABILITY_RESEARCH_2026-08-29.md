# 布布时光机 iOS × GitHub 高热度项目能力调研

> 调研日期：2026-08-29
> 对象：iOS `main` / 2.11.0，以家庭长期档案、照片原片、语音、端侧隐私 AI、同步可靠性为主。
> 边界：本文只做调研与采纳建议，**没有修改任何工程代码**。
> 数据口径：Star、推送时间、Release 与许可证来自 GitHub 实时 API；Star 是当日快照，不等于质量担保。

## 一、先说结论

布布时光机已经是一个重原生、强私有化的 iOS 项目：SwiftUI + SwiftData + PhotoKit 后台上传扩展 + PocketBase + Widget/Watch/App Intents。当前不缺“能用的 UI 库”，缺的是几个经过大规模项目验证的工程能力。

建议按下列顺序吸收：

1. **立即吸收：调试可观测与回归证据**
   - `Pulse` 仅接 Debug/TestFlight 内网日志，并严格脱敏。
   - `swift-snapshot-testing` 覆盖主题、深色、大字号、Widget、分享卡、胶囊和同步状态。
   - `swift-async-algorithms` 用在 SSE、同步事件、照片候选和通知的 debounce/throttle/merge，少造轮子。

2. **小范围 POC：照片和语音核心能力**
   - `Nuke` 只接管远端缩略图/查看器，验证预取、合并请求、可恢复下载和解码内存。
   - `Queryable` 验证 MobileCLIP 端侧自然语言照片搜索，向量作为可删除派生数据。
   - `FluidAudio` 与 `Argmax OSS / WhisperKit` 做同机对比，主看中文转写、VAD、说话人区分、耗电和峰值内存。

3. **只学系统设计，不拷贝代码**
   - 从 `Immich` 学照片状态机、缩略图优先、Live Photo 资源分组和后台备份。
   - 从 `Ente` 学端到端加密、恢复码演练、去重和私密共享。
   - 从 `Nextcloud iOS` 学后台传输、大文件分块、断点恢复和离线文件状态。
   - 这三个项目都是 GPL/AGPL，不应直接复制进当前未声明开源许可证的仓库。

4. **明确不做**
   - 不把整个项目重写成 TCA。
   - 不用 Realm/GRDB 整体替换 SwiftData。
   - 不同时引入 Nuke 和 Kingfisher。
   - 不为了动效就引入 Lottie/Pow/AudioKit 整套依赖。
   - 不把脸部特征、照片向量、网络 Token 或家庭密码打进日志和同步。

## 二、候选项目总览

| 项目 | Star | 最近活跃证据 | 许可证 | 与布布的匹配度 | 建议 |
|---|---:|---|---|---|---|
| [Immich](https://github.com/immich-app/immich) | 112,892 | 2026-08-29 仍提交；稳定版 v3.1.0 | AGPL-3.0 | 照片/原片/人脸/搜索/自托管高度匹配 | **架构必读，不拷代码** |
| [Ente](https://github.com/ente-io/ente) | 28,552 | 2026-08-29 活跃；photos-v1.3.61 | AGPL-3.0 | 加密家庭照片和恢复机制高度匹配 | **架构必读，不拷代码** |
| [Nextcloud iOS](https://github.com/nextcloud/ios) | 2,493 | 2026-08-29 活跃；v34.1.4 | GPL-3.0 | 后台传输/离线/大文件强 | **研究传输层** |
| [Queryable](https://github.com/mazzzystar/Queryable) | 2,978 | 2026-03-29 最近提交 | MIT | 本机 MobileCLIP 照片搜索直接匹配 | **POC 优先** |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 2,708 | 2026-08-23 活跃；v0.15.6 | Apache-2.0 | 中文 ASR/VAD/说话人区分/TTS | **POC 优先** |
| [Argmax OSS / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) | 6,343 | 2026-08-13 活跃；v1.1.0 | MIT | 端侧语音转写成熟 | **与 FluidAudio 对比** |
| [Supertonic](https://github.com/supertone-inc/supertonic) | 13,734 | 2026-07-24 活跃 | MIT | 端侧多语言 TTS，绘本/成长电影有价值 | **后续 POC** |
| [Nuke](https://github.com/kean/Nuke) | 8,658 | 2026-08-24 活跃；v13.2.0 | MIT | 远程图片缓存/预取/恢复下载高匹配 | **小范围试接** |
| [Pulse](https://github.com/kean/Pulse) | 7,152 | 2026-08-15 活跃；v5.2.3 | MIT | 同步/弱网调试直接命中 | **Debug 立即接** |
| [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing) | 4,324 | 2026-08-24 活跃；v1.19.4 | MIT | 主题/Widget/分享卡/大字号回归 | **Tests 立即接** |
| [Swift Async Algorithms](https://github.com/apple/swift-async-algorithms) | 3,705 | 2026-08-09 活跃；v1.1.5 | Apache-2.0 | 同步事件合并和节流高匹配 | **小步接入** |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 8,625 | 2026-08-08 活跃；v7.11.1 | MIT | 可靠 SQLite/迁移/观察强 | **学方法，不换 SwiftData** |
| [TCA](https://github.com/pointfreeco/swift-composable-architecture) | 14,892 | 2026-08-28 活跃；v1.26.2 | MIT | 复杂状态机/测试强 | **学 reducer，不全量重写** |
| [Swift Navigation](https://github.com/pointfreeco/swift-navigation) | 2,289 | 2026-08-28 活跃；v2.11.1 | MIT | 状态驱动导航直接对应多层路由 | **比全量 TCA 更值得小试** |
| [AudioKit](https://github.com/AudioKit/AudioKit) | 11,445 | 2026-07-26 活跃；v5.7.2 | MIT | 声音年轮/分析/离线渲染 | **AVFoundation 不足时再引** |
| [Pow](https://github.com/EmergeTools/Pow) | 4,373 | 2026-04-13 发布 v1.0.6 | MIT | 里程碑庆祝/微交互可用 | **低优先，不必为此加包** |

## 三、值得吸收的具体能力

### 1. Immich：把媒体同步做成显式状态机

Immich README 明确展示了移动端自动备份、选择相册、后台备份、Live Photo/Motion Photo、人脸与 CLIP 搜索。

布布应吸收：

- 将媒体状态统一为：`discovered → thumbReady → originalQueued → uploading → remoteVerified → localReady`。
- 照片、Live Photo 主图、paired video、缩略图用 `assetGroupID + resourceRole` 组成一个资产，展示只选 display resource，开放档案保留全部资源。
- 同步中心同时展示“缩略图可用”与“原片已验证”，不用一个 `synced` 概括全部状态。
- 在原片之外建立可删除派生层：缩略图、识别标签、向量、预览码率均能重建。

不应吸收：

- 不照搬 Immich 的 Flutter/TypeScript 客户端。
- 不复制 AGPL 代码到本项目。
- 不让“照片管理”反客为主，布布的主体仍是家庭时光和成长叙事。

### 2. Ente：胶囊与家庭档案的密钥生命周期

Ente 主打端到端加密、私密共享、家庭计划、后台上传、人脸和语义搜索。

布布应吸收：

- 恢复码不只是一个设置页，而是可验证的灾备流程：生成、纸面备份、新机试解、定期演练。
- 文件上传前按明文 hash 去重，但服务器不应获得可反推家庭内容的全局指纹。
- 将“加密胶囊”和“开放档案”纳入同一恢复演练，确保不依赖当前 App 和当前服务器。
- 家庭成员共享应有明确的密钥与撤销边界，不能只靠客户端自报 `authorRole`。

### 3. Nextcloud iOS：大文件传输和离线资源

布布应吸收：

- 原片传输使用真正的后台 `URLSession`、任务 ID 持久化、App 重启后重绑 delegate。
- 大视频使用分块/断点协议，每块独立重试，最终服务器合并后再标记完整。
- 离线状态必须由文件存在、大小、hash 和服务器状态共同决定，不能仅看 `localFileName != nil`。
- 上传队列要有电池、Wi-Fi、磁盘、热状态约束和可观察的失败原因。

不建议直接加 `TUSKit`：当前仅 245 Star，且需服务器同时实现 tus 协议。对布布更实际的路线是保留 PocketBase，为大文件增加自有分块上传端点和最终 hash 验证。

### 4. Queryable：照片语义搜索默认留在本机

Queryable 使用 Apple MobileCLIP，在 iPhone 上为照片编码向量，再用自然语言查照片；README 明确强调离线和隐私。

布布应吸收：

- 文字搜索仍然走当前本地索引；画面搜索优先端侧 MobileCLIP，家庭 AI 服务只是可选加速/跨设备索引。
- 图像向量只保存于派生数据库，带有 `modelVersion + assetHash`，模型升级可分批重建。
- 索引调度必须受充电、低电量、温度、前台活跃约束，不应首次启动立刻扫 2000+ 原片。
- “认布布”与语义搜索分库：人脸 embedding 是高敏感数据，默认不同步、不导出。

风险：Queryable 仓库是 MIT，但不能仅凭仓库许可证就假定外部模型权重可随 App 重分发；模型需单独核对授权和 App Store 包体策略。

### 5. FluidAudio / Argmax OSS：端侧语音能力选型

`FluidAudio` 是近期增长快的 Swift/Core ML 项目，覆盖 iOS/macOS 的 ASR、VAD、说话人日志、speaker embedding 和 TTS，并明确有中文模型。`Argmax OSS` 包含 WhisperKit，是更成熟的 Apple Silicon 端侧转写路线。

布布的 POC 应用真实家庭语音做以下比较：

- 30 秒、3 分钟、30 分钟中文音频的首字延迟与总耗时。
- 大人+孩子重叠、方言、哭笑、背景电视下的错字率。
- 峰值内存、ANE/CPU 占用、电量与温度。
- 模型下载、版本切换、断网和存储不足的降级。
- 输出要保留时间码和置信度，低置信度不直接写入家庭事实。

初步倾向：

- 需要中文+说话人区分：先测 `FluidAudio`。
- 只需成熟转写：先测 `WhisperKit`。
- 最终依然保留当前系统 Speech/家庭服务回退，不把任一个大模型设为唯一路径。

### 6. Supertonic：绘本和成长电影的本地旁白

Supertonic 当前 13.7k Star，提供 Swift/iOS 路线和 31 语言 TTS，强调全端侧无云请求；模型为 99M 参数。

适合：

- 成长绘本“讲给布布听”。
- 成长电影本地预览旁白。
- 离线长辈模式语音播报。

不适合现在直接加入正式包：需先核对中文声音自然度、模型文件分发、首次下载、存储和 App Review 文案。

### 7. Nuke：只接管远程预览管线

Nuke README 列出了内存/磁盘缓存、解码与处理、请求合并、优先级、预取、可恢复下载、Progressive JPEG、HEIF/WebP/GIF、SwiftUI 和 async/await。

建议试接边界：

- 只用于 PocketBase 远程缩略图、相邻照片预取和全屏查看器。
- 本地原片仍由 `MediaStore/ThumbnailProvider` 管理，不把家庭档案的文件所有权交给缓存库。
- 为受保护 URL 做自定义 `DataLoader`，每次请求仍走当前 token 刷新和同源校验。
- 试点验收：2000 张照片快滑、弱网、token 过期、内存告警、原图/缩略图不串页。

Nuke 与 Kingfisher 只选一个。Kingfisher Star 更高（24,395），但对当前项目，Nuke 的 `ImagePipeline + async/await + prefetch + resumable download` 更贴合已有结构。

### 8. Pulse：让同步失败不再是“{}”

Pulse 可在真机内查看 `URLSession` 请求与日志，数据默认保存本机，适合 QA/TestFlight 上报问题。

接入底线：

- 只在 Debug/内部 TestFlight 启用，Release 默认不编译 PulseUI。
- 记录前清除 `Authorization`、Cookie、账号、密码、恢复码、文件 token、原始照片 URL 中的敏感查询参数。
- 对媒体 body 仅记大小/hash 摘要/耗时/状态，不保存实际字节。
- 为同步轮次生成 trace ID，串起鉴权、推、拉、下载、合并和最终 pendingCount。

### 9. SnapshotTesting：把“真机看着不对”提前到 CI

建议建立固定截图矩阵：

- iPhone 标准宽度 + 小屏，浅色/深色，标准/最大字号，减少动态。
- 首页：空库、有照片、原片排队、同步失败、生日月。
- 时光：文字、横图、竖图、视频、语音、跨年分组。
- Widget：有/无缩略图，照片丢失，大字号。
- 分享卡、年册 PDF 首页、胶囊锁定/开启、成长报告。

图像快照不替代功能 UI Test；左右滑、逐层返回、后台恢复仍要用状态断言和真机证据。

### 10. Swift Async Algorithms：减少自制轮询与竞态

适用点：

- SSE 远端事件 `debounce`，防止一张照片的多个资源事件触发多轮全同步。
- `merge` 前台激活、手动同步、SSE、网络恢复、后台任务等信号。
- `throttle` Widget/手表快照刷新和同步进度 UI。
- 用结构化并发取代长生命 `Task` + 手写 sleep/retry 组合。

引入前应先把当前 `SyncEngine` 触发器列成表，只替换有明确竞态/重复触发的部分，不为了“现代化”改全项目。

### 11. GRDB：用在派生队列，不用来推翻事实库

GRDB 强项是 WAL、健壮并发、迁移、事务和 ValueObservation。布布已经用 SwiftData 存家庭事实，同时 `PhotoIntakeStore` 已用 SQLite 存可重建的上传队列。

建议：

- 先学 GRDB 的迁移、事务、WAL 和观察测试方法，补强当前 SQLite 队列。
- 如果队列 SQL/观察复杂度持续上升，再评估仅为 `PhotoIntakeStore` 引入 GRDB。
- 不将 Entry/Media/Health/Capsule 从 SwiftData 迁到 GRDB；这会同时破坏 Widget、App Intent、Watch 与现有迁移链。

### 12. TCA / Swift Navigation：吸收状态机，拒绝大重写

最适合借鉴 reducer 思路的流程：

- 同步中心：idle/connecting/authenticating/pushing/pulling/downloading/partial/failed/online。
- 新机恢复：server discovery/login/family verification/fact pull/thumb ready/original backfill/done。
- 胶囊：draft/sealed/syncing/locked/unlockable/unsealed/recoveryFailed。
- 成长电影：draft/submitting/queued/rendering/downloading/ready/failed/resumable。

推荐方式：先用项目内 enum + 纯函数写状态迁移测试；若 SwiftUI 导航仍持续出现状态漂移，小范围试 `swift-navigation`。不建议将 200+ 个现有 Swift 文件全量迁入 TCA。

### 13. AudioKit / Pow：有需要才引

- `AudioKit` 适合声音年轮的波形、频谱、音量归一化、音频混合和本地预览渲染。但当前 AVFoundation 能做的不要重做，先用单一缺口 POC 证明价值。
- `Pow` 可用于里程碑点亮、亲亲反应、胶囊开启的小范围 change effect。布布已有自己的 BubuMotion/BubuSound，仅当自研代码难以稳定达到相同效果时才加包。

## 四、建议的采纳路线

### Wave A：先建证据链（低风险，高回报）

1. Debug-only Pulse + 统一脱敏器。
2. SnapshotTesting 基线：首页、时光、Widget、分享卡、胶囊、成长。
3. 为同步轮次建 trace ID 和状态转移测试。
4. 把“源码 includes”测试降级为辅助，主门禁改为纯状态机+临时 PocketBase+真机 UI。

### Wave B：媒体体感和后台可靠性

1. 用 Immich/Nextcloud 的思路整理媒体状态机和大文件续传协议。
2. Nuke 仅试点远程缩略图+全屏相邻预取。
3. 2000+ 照片、弱网、token 过期、杀进程、磁盘不足五组验收。
4. 完成一次“新机只登录 → 先出缩略图 → 原片全部验证”恢复演练。

### Wave C：端侧隐私 AI

1. Queryable/MobileCLIP 小样本 POC：200/2000/20000 张照片。
2. FluidAudio vs WhisperKit 中文转写基准。
3. 如果本地旁白有明确价值，再测 Supertonic。
4. 所有模型都支持可选下载、版本指纹、删除和服务端回退。

### Wave D：精细化（只在证明有价值后）

1. Swift Async Algorithms 收敛同步/事件竞态。
2. 小范围 Swift Navigation 试点。
3. AudioKit/Pow 单点 POC，不进行全局架构换血。

## 五、可量化的采纳门槛

| 能力 | 采纳前必须证明 |
|---|---|
| Nuke | 2000+ 照片快滑内存/掉帧明显优于现有管线；受保护 URL 不泄 token |
| MobileCLIP | 2000 张首次建索耗时/耗电可控；中文家庭查询 Top-10 准确率有明确收益 |
| FluidAudio/WhisperKit | 中文家庭语音错字率、延迟、内存、电量都达标；低信心不写事实 |
| Supertonic | 中文声音足够自然；模型按需下载；不显著拉高 App 冷启动与存储 |
| Pulse | 敏感字段自动脱敏测试全绿；Release 不包调试 UI；媒体 body 不落盘 |
| SnapshotTesting | CI 可稳定重现，快照差异不受时区/字体/随机 ID 污染 |
| 大文件续传 | 杀 App/断网/切 Wi-Fi/过期 token 后从已完成块继续；最终原片 hash 一致 |

## 六、最终推荐清单

### 可以进入下一轮技术计划

1. Pulse（Debug-only）
2. SnapshotTesting（Tests-only）
3. Swift Async Algorithms（仅同步/事件触发器）
4. Nuke（远程预览 POC）
5. Queryable/MobileCLIP（端侧照片搜索 POC）
6. FluidAudio vs Argmax OSS（语音 POC）

### 只进入设计参考库

1. Immich
2. Ente
3. Nextcloud iOS
4. GRDB.swift
5. TCA / Swift Navigation
6. AudioKit / Pow

### 现阶段不建议

- Realm 替换 SwiftData：迁移风险远大于收益。
- Alamofire 替换 URLSession：解决不了当前同步语义、原子合并和恢复问题。
- Kingfisher + Nuke 同时引入：能力重叠。
- 全量 TCA 重写：交付风险高、用户价值低。
- 直接复制 Immich/Ente/Nextcloud 代码：许可证边界不允许。

## 七、参考链接

- [Immich](https://github.com/immich-app/immich)
- [Ente](https://github.com/ente-io/ente)
- [Nextcloud iOS](https://github.com/nextcloud/ios)
- [Queryable](https://github.com/mazzzystar/Queryable)
- [FluidAudio](https://github.com/FluidInference/FluidAudio)
- [Argmax OSS / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)
- [Supertonic](https://github.com/supertone-inc/supertonic)
- [Nuke](https://github.com/kean/Nuke)
- [Kingfisher](https://github.com/onevcat/Kingfisher)
- [Pulse](https://github.com/kean/Pulse)
- [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing)
- [Swift Async Algorithms](https://github.com/apple/swift-async-algorithms)
- [GRDB.swift](https://github.com/groue/GRDB.swift)
- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
- [Swift Navigation](https://github.com/pointfreeco/swift-navigation)
- [AudioKit](https://github.com/AudioKit/AudioKit)
- [Pow](https://github.com/EmergeTools/Pow)
