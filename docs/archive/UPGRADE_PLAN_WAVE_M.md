# BubuTimeMachine 升级总方案 v2（代码核对版）

> 生成日期：2026-06-12
> 核对对象：GitHub `leoyb1010/BubuTimeMachine` HEAD（`ae0cbf1 修复故事页与备份卡文案换行`）
> 已验证：`BubuTimeMachine-main (1).zip` 与 GitHub HEAD **逐文件完全一致**，原方案（`BubuTimeMachine_Latest_Solution_UpgradePlan.md`）就是基于当前最新代码写的，没有版本错位。
> 本文档 = 原方案对照核实 + 全量代码 Review/Debug + 修订后的升级计划 + 可直接执行的升级代码指引，**可单独交给 Codex 执行，替代原方案文档**。

---

## 0. 结论摘要（TL;DR）

1. **原方案的 4 大问题判断基本全部成立**：黑屏根因 A/B/C、照片墙循环跳转、首页头部布局、疫苗 AppStorage、AI 缺口，均在当前代码中逐行确认（见 §1 对照表）。
2. **原方案有 1 条判断不成立**：§12.1 所说的「EntryDetailView 重复 syncNow」不存在——6 处 `syncNow()` 分属 6 个不同的用户操作，无需修改。
3. **原方案样例代码有 2 处编译错误 + 3 处健壮性问题**，直接照抄会编译失败或线上 500（见 §2.3，已在 §4 给出修正版代码）。
4. **本次 Review 新发现 7 个原方案没提到的问题**，其中 1 个建议升为 P1（每次上传泄漏一个 URLSession），2 个是 dead code 清理项（见 §2.2）。
5. 实施顺序维持原方案 5 个 Phase，但 Phase 1 增加 URLSession 泄漏修复，Phase 2 增加头像同步前置项（身份卡跨设备体验依赖它）。

---

## 1. 方案 ↔ 最新代码 逐条对照结果

| # | 原方案判断 | 实际代码位置 | 核对结论 |
|---|---|---|---|
| 1 | 黑屏根因 A：`ZoomableImageView` 只在 `updateUIView` 里布局一次，首帧 `bounds == .zero` 时直接 return，之后无人再触发布局 | `MediaViewer.swift:241-277`（`set(image:in:)` → `layoutImage` guard return；无 `layoutSubviews` 钩子） | ✅ 成立。SwiftUI 仅在状态变化时调 `updateUIView`，UIScrollView 自身 bounds 变化不会触发，黑屏风险真实存在 |
| 2 | 黑屏根因 B：`RemoteZoomableImage` 用 `URLSession.shared.data(from:)`，无 PocketBase 鉴权 | `MediaViewer.swift:195` | ✅ 成立。且 `PocketBaseClient.downloadFile(from:)`（`PocketBaseClient.swift:234-243`）确实已带 Bearer token + `withAuthRetry`，改调它即可 |
| 3 | 黑屏根因 C：上传完成后用**本地文件名**拼远端 URL | `PocketBaseClient.swift:256-258`（媒体）、`:425`（语音/胶囊等通用文件） | ✅ 成立，且比方案说的更严重：PocketBase 对上传文件**总是**追加随机后缀改名，所以这个 URL 几乎必然 404。⚠️ 补充事实：拉取链路是对的——`fetchMedia` 用服务端真实 `file` 字段拼 URL（`PocketBaseClient.swift:602-604`），`mergeRemoteMedia` 会在下一轮拉取时覆盖纠正（`SyncEngine.swift:683-687`）。所以症状集中在「上传设备在下一轮拉取前」这个窗口，以及拉取失败时。修复仍必要，但不必恐慌存量数据——多同步一轮即自愈 |
| 4 | 查看器无重试/诊断 | `MediaViewer.swift:173-179`（失败态只有一行文案） | ✅ 成立 |
| 5 | 照片墙点图进详情而非查看器 | `HomeDestinations.swift:33`（`NavigationLink(value: item.entry)`，依赖 `RootTabView.swift:13` 的 `navigationDestination(for: Entry.self)`） | ✅ 成立 |
| 6 | `totalPhotos` 把视频/音频也算进「张照片」 | `CaptureHomeView.swift:274-276`（`entry.media.count` 不分类型）；照片墙列表同样不过滤音频（`HomeDestinations.swift:12-16`） | ✅ 成立 |
| 7 | 首页头部是普通「头像+名字+年龄」 | `CaptureHomeView.swift:141-167`（`ageHeader`） | ✅ 成立 |
| 8 | 疫苗完成状态存 `@AppStorage` | `VaccineView.swift:11`（`bubu.vaccine.done` JSON 字符串） | ✅ 成立。不可同步、无日期、无医院/反应字段 |
| 9 | `classifyContent` 有实现但不在 `AIService` 协议 | `AIService.swift:5-13`（协议无此方法）、`BubuAIService.swift:50` | ✅ 成立，且**更糟**：全工程没有任何调用方（`classify(entryId:)` 也无人调用，且其真实实现固定返回空结果，见 `BubuAIService.swift:43-47`）。「AI 自动归类」目前是事实上的死功能 |
| 10 | 服务端无 `/parse-natural-capture` | `server/ai/main.py`（仅 rewrite/classify/detect-first-time/movie-narration/transcribe 5 个业务路由） | ✅ 成立。`llm.complete_json` 已存在可复用（`llm.py:45-47`） |
| 11 | §12.1「EntryDetailView.toggleReaction 附近疑有重复 syncNow」 | `EntryDetailView.swift:71,240,469,477,485,501` | ❌ **不成立**。6 处分别属于：完成编辑 / 切换反应 / 追加媒体 / 删媒体 / 删语音 / 删记录，每处一次，无重复调用，无需修改 |
| 12 | §12.2 `ChildProfileDTO` 不同步头像 | `DTOs.swift:80-88`（无 avatar / heroBackground 字段） | ✅ 成立。身份卡上线后，B 设备会永远显示默认布布形象。建议与 Phase 2 一起做（见 §4.8） |
| 13 | 身高体重目前靠文本模糊解析 | `GrowthCurveView.swift:55-59`（从 title/amountText/detail 里正则抽第一个数字） | ✅ 成立，`GrowthMeasurement` 结构化模型方向正确 |

**其他事实核验**（影响升级代码可行性的关键 API，全部存在、签名一致）：
`AppEnvironment.apiClient`（`AppEnvironment.swift:12`，方案中 `env.apiClient.downloadFile` 可用）、`HealthRecord` 的 `amountValue/amountUnit/amountText/reaction/temperatureCelsius/tags/startAt/endAt`（`HealthRecord.swift:13-21`）、`FeedEventKind.healthRecorded`（`FeedEvent.swift:43`）、`Entry(happenedAt:authorRole:note:)`、`AgeCalculator.ageDescription/daysSinceBirth`、`BubuDateFormat.shortDate`、`BubuMascotBadge(size:expression:)`、`bubuGlassSurface/bubuCardShadow`、`MediaThumbnail(media:mediaStore:cornerRadius:size:)`、`VoiceRecorderBar`/`AudioRecorder`/`transcribe`。

---

## 2. 代码 Review & Debug 发现

### 2.1 工程基线（写新代码前必须知道）

- `project.yml`：iOS 26.0、Swift 6.0、`SWIFT_STRICT_CONCURRENCY: complete`、**`SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`**、`SWIFT_APPROACHABLE_CONCURRENCY: YES`。
  → 所有新增类型默认 MainActor 隔离。**新增 DTO/网络模型请完全照抄 `DTOs.swift` 的写法**（plain struct + `Codable, Sendable`），新增 View/Router 不需要手写 `@MainActor`（默认即是），跨线程服务类参考 `BubuAIService` 的 `final class … @unchecked Sendable` 模式。
- 构建链：`xcodegen generate` → `xcodebuild -scheme BubuTimeMachine build` → 现有 4 个测试文件（CapsuleCrypto / CapsuleV3 / PocketBaseClientSyncQuery / Reaction）必须保持通过。
- 同步架构：上传走 `SyncEngine.pushMediaItem`（不是 `UploadQueue`）；拉取按集合独立游标；远端媒体由 `downloadMissingFiles` 每轮最多落地 8 个。

### 2.2 新发现的问题（原方案未覆盖）

| 编号 | 级别 | 问题 | 位置 | 修复建议 |
|---|---|---|---|---|
| R1 | **P1** | **每次上传泄漏一个 URLSession**：`multipartUpload` 两个重载各自 `URLSession(configuration:delegate:delegateQueue:)` 创建会话，但从不 `finishTasksAndInvalidate()`。URLSession 会强持有 delegate 直到显式 invalidate——批量上传照片/视频时，session + delegate 持续累积，内存与文件描述符缓慢上涨 | `PocketBaseClient.swift:456,493` | 上传完成后 `session.finishTasksAndInvalidate()`（见 §4.3 代码，已并入 Phase 1） |
| R2 | P2 | `UploadQueue` 是 dead code：`AppEnvironment.swift:53` 创建后无任何调用方，真实上传在 `SyncEngine.pushMediaItem` | `Services/Sync/UploadQueue.swift` | 删除文件 + `AppEnvironment` 两行；或留待 Phase 5 清理。不要再往里加逻辑 |
| R3 | P2 | `classify(entryId:)` + `classifyContent` 双双无调用方，且前者真实实现固定返回空 `AIClassification` | `BubuAIService.swift:43-61` | 本轮把 `classifyContent` 纳入协议（原方案 §6.4 已规划）；`classify(entryId:)` 从协议中删除或标记废弃，避免新人误用 |
| R4 | P3 | `subscribeRealtime` 轮询游标在 fetch **返回后**才取 `Date()`，长请求期间产生的变更可能被跳过；且只轮询 entries 一个集合 | `PocketBaseClient.swift:271-289` | 低风险（SyncEngine 主拉取有独立游标兜底）。改法：`since` 应在发起请求**前**取值。可放 Phase 5 |
| R5 | P3 | `VaccineView.dueText` 对「已完成且已过期」的剂次仍显示「建议尽快补种」 | `VaccineView.swift:71-76,115-117` | Phase 4 重写 VaccineView 时顺手修：isDone 时显示完成日期或 ✓ |
| R6 | P3 | `MediaThumbnail` 的「等待远端下载」呼吸动画只在 `onAppear` 启动；若 remoteURL 在视图出现后才到达，占位图不会闪烁（纯视觉） | `MediaThumbnail.swift:54-58` | `onChange(of: isAwaitingRemote)` 里补 `pulse = true`。可放 Phase 5 |
| R7 | P3 | 服务端 `_rate_buckets` 按 IP 无上限累积（公网长期运行内存缓慢增长）；`ping()` 走 `URLSession.shared` 无显式超时 | `server/ai/main.py:41`、`PocketBaseClient.swift:293-298` | 给 buckets 加简单清理（桶空则删 key）；ping 设 10s 超时。可放 Phase 5 |

另外两点**正面确认**（不需要改）：服务端鉴权是 fail-closed（未配 `AI_API_KEY` 直接 503，`main.py:55-64`）；`PocketBaseClient` 已带瞬时错误退避重试与软失败机制（commit `46fb695`），新增网络代码应复用同一模式。

### 2.3 原方案样例代码的问题（照抄会出事，已在 §4 修正）

| 编号 | 问题 | 后果 | 修正 |
|---|---|---|---|
| C1 | §6.9 `saveEntry` 写 `entry.aiSummary = item.title`，但 `Entry` 模型**没有 `aiSummary` 属性**（`Entry.swift` 只有 `title/note/firstPersonNote/...`） | 编译失败 | 改为 `entry.title = item.title`（§4.6.6） |
| C2 | §6.6 `NaturalCaptureBar` 用 `text.trimmed`，但 `String.trimmed` 是 `HealthRecordSheet.swift:577-581` 里的 **private extension**，外部不可见 | 编译失败 | 新增共享 `String+Bubu.swift` 扩展（§4.6.5） |
| C3 | §6.9 sleep 分支只把时长写进 `amountValue`，但 `HealthRecord` 本身就有 `startAt/endAt` 字段 | 丢数据，睡眠区间无法回放 | 解析 `start_at/end_at` ISO 字符串写入 `record.startAt/endAt`（§4.6.6） |
| C4 | §6.5 服务端 `NaturalParseResp(**data)` 直接构造：LLM 返回缺 `title/source_text` 等必填字段、或 `_extract_json` 兜底返回 `{}` 时，Pydantic `ValidationError` 会变成 500 | 线上偶发 500 | 先逐条清洗 items、再 try/except 构造，失败降级为空结果 + warning（§4.6.4） |
| C5 | §3.2 `ZoomingImageScrollView` 有重复行 `showsVerticalScrollIndicator`（方案自己已标注） | 无害但需删 | §4.1 已删 |
| C6 | §5.2 照片墙方案让查看器接收「photo+video」，但 `galleryMedia` 若含音频会出现可滑到的音频页 | 体验不一致 | §4.4 统一过滤为 photo/video |

---

## 3. 升级计划（修订版总表）

| 阶段 | 内容 | 相对原方案的变化 | 验收门槛 |
|---|---|---|---|
| **Phase 0** | 基线：`xcodegen generate` + build + 现有测试全绿；切分支 `feat/upgrade-wave-m` | 新增（防止把基线问题误判为新代码问题） | build & tests 通过 |
| **Phase 1（P0）** | ① 重写 `ZoomableImageView`（§4.1）② `RemoteZoomableImage` 走鉴权下载 + 重试（§4.2）③ 上传用服务端真实文件名 + **修 R1 session 泄漏**（§4.3）④ 照片墙点图直开查看器 + `totalPhotos` 只算照片（§4.4） | 并入 R1；明确根因 C 的「拉取自愈」事实，存量坏 URL 不需要数据修复脚本 | 原方案 §3.5 十条 + 回归 §10.1 |
| **Phase 2（P1）** | ① `BubuIdentityCard` + 替换 `ageHeader`（§4.5）② **ChildProfile 头像同步**（§4.8，新增前置）③ 系统相册 `SystemAlbum/AlbumHomeView/AlbumDetailView`（§4.4.3） | 头像同步提前：没有它，家人设备上的身份卡永远是默认形象，卡片升级价值减半 | 原方案 §4.4 + §5.7 |
| **Phase 3（P1）** | LLM 文字输入 MVP：服务端 `/parse-natural-capture`（§4.6.4）→ DTO/协议/实现（§4.6.1-3）→ `NaturalCaptureBar` + `ReviewSheet` + `Router`（§4.6.5-6）。疫苗暂存 `HealthRecord(.checkup)` + 强确认 | 修正 C1-C4；Mock 实现补齐（离线可开发预览） | 6 个样例可识别、敏感项强确认、AI 不可用有降级 |
| **Phase 4（P1）** | `VaccineRecord` + `GrowthMeasurement` 模型、AppStorage 迁移、`VaccineView`/`GrowthCurveView` 改读 SwiftData、PocketBase 两个新 collection + DTO + SyncEngine 接线（§4.7）；顺手修 R5 | 增加 Schema 注册与 PB 建表清单的精确位置 | 疫苗/身高体重经 AI 或手动保存后，本机可见 + 多端同步一致 |
| **Phase 5（P2）** | 语音一句话输入闭环、微动效、轻提示；清理 R2/R4/R6/R7；P2 自定义相册另行排期 | 把 dead code 清理归入此阶段 | 原方案 §10.5 |

每个 Phase 结束都必须：`xcodegen generate && xcodebuild -scheme BubuTimeMachine build` + 跑现有测试 + 手工过对应回归清单（§5），全绿才进入下一阶段。

---

## 4. 升级代码指引（修正版，可直接执行）

> 以下代码全部按当前仓库真实 API 核对过签名；与原方案不同之处已在注释或前文标注。原方案中未在此重复的部分（如 §5.3 系统相册的 `SystemAlbum` 定义、§6.8 ReviewSheet 完整 UI），按原方案执行即可，无编译障碍。

### 4.1 重写 `ZoomableImageView`（修黑屏根因 A）

替换 `BubuTimeMachine/DesignSystem/Components/MediaViewer.swift` 中现有 `ZoomableImageView` 及其 `Coordinator`（第 207-316 行）：

```swift
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let view = ZoomingImageScrollView()
        view.setImage(image)
        return view
    }

    func updateUIView(_ uiView: ZoomingImageScrollView, context: Context) {
        uiView.setImage(image)
    }
}

/// 关键修复：布局收敛到 layoutSubviews——首帧 bounds 为 0、旋转、分屏都能自愈，黑屏根因消除。
final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard lastImage !== image else {
            setNeedsLayout()
            return
        }
        lastImage = image
        imageView.image = image
        zoomScale = 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutImageIfNeeded()
    }

    private func layoutImageIfNeeded() {
        guard let image = imageView.image,
              bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }

        let fitScale = min(bounds.width / image.size.width,
                           bounds.height / image.size.height)
        let fittedSize = CGSize(width: image.size.width * fitScale,
                                height: image.size.height * fitScale)

        if zoomScale <= minimumZoomScale + 0.001 {
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            contentSize = fittedSize
        }
        centerImage()
    }

    private func centerImage() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal,
                                    bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 {
            setZoomScale(1, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let targetScale = min(2.8, maximumZoomScale)
        let rect = CGRect(x: point.x - bounds.width / targetScale / 2,
                          y: point.y - bounds.height / targetScale / 2,
                          width: bounds.width / targetScale,
                          height: bounds.height / targetScale)
        zoom(to: rect, animated: true)
    }
}
```

（已删除原方案中的重复行 `showsVerticalScrollIndicator`，浮点比较用 epsilon。）

### 4.2 `RemoteZoomableImage` 改走鉴权下载（修根因 B）

同文件，替换现有 `RemoteZoomableImage`（第 163-205 行），调用点 `photoPage` 里改为 `RemoteZoomableImage(remoteURL: remote)`：

```swift
private struct RemoteZoomableImage: View {
    @Environment(AppEnvironment.self) private var env

    let remoteURL: String
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(image: image)
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 42))
                    Text(errorText ?? "照片还没下载好")
                        .font(BubuTheme.Font.body)
                    Button("重试") { Task { await load() } }
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.16), in: Capsule())
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
        .task(id: remoteURL) { await load() }
    }

    @MainActor
    private func load() async {
        guard !remoteURL.isEmpty, image == nil else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let data = try await env.apiClient.downloadFile(from: remoteURL)
            guard let decoded = UIImage(data: data) else {
                errorText = "照片文件无法解码"
                return
            }
            image = decoded
        } catch {
            errorText = "照片下载失败，请稍后重试"
            #if DEBUG
            print("[MediaViewer] remote image failed:", remoteURL, error)
            #endif
        }
    }
}
```

> 说明：`AppEnvironment` 经 `.environment()` 注入根视图，`fullScreenCover` 内容自动继承，无需手动传递。`downloadFile` 自带 Bearer + 401 重登重试。

### 4.3 上传使用服务端真实文件名 + 修 R1 泄漏（修根因 C）

`BubuTimeMachine/Services/Networking/PocketBaseClient.swift`：

**① 新增返回结构：**

```swift
private struct UploadedFileResult: Sendable {
    let recordId: String
    let storedFileName: String
}
```

**② 媒体上传重载（`multipartUpload(_:token:onProgress:)`，约 464 行）——返回类型改 `UploadedFileResult`，并补 session 回收：**

```swift
    let delegate = UploadProgressDelegate(onProgress: onProgress)
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }   // R1：不回收会泄漏 session+delegate
    let (data, resp) = try await session.upload(for: req, fromFile: bodyURL)
    try Self.check(resp, data)
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = obj["id"] as? String else {
        throw APIError.server(500, "上传响应异常")
    }
    // PocketBase 会清洗并追加随机后缀改写文件名，必须以响应里的为准
    let storedFileName = (obj["file"] as? String) ?? file.fileName
    return UploadedFileResult(recordId: id, storedFileName: storedFileName)
```

**③ `uploadMedia`（247-267 行）改用真实文件名：**

```swift
    let result = try await self.withAuthRetry { token in
        try await self.multipartUpload(file, token: token) { progress in
            continuation.yield(.progress(progress))
        }
    }
    let urlStr = self.baseURL
        .appendingPathComponent("api/files/media/\(result.recordId)/\(result.storedFileName)")
        .absoluteString
    continuation.yield(.completed(remoteId: result.recordId, url: urlStr))
```

**④ 通用文件上传重载（`multipartUpload(collection:...)`，约 437 行）同样改造**：返回 `UploadedFileResult`，`storedFileName = (obj[fileField] as? String) ?? fileName`（注意这里字段名是动态的 `fileField`：`voiceFile`/`file`/`encryptedBlob`），同样加 `defer { session.finishTasksAndInvalidate() }`；`uploadGenericFile`（约 409 行）的 URL 拼接改用 `result.storedFileName`。

**⑤ 存量数据**：不需要修复脚本。错误 URL 会在下一轮 `pull("media")` 时被服务端真实 URL 覆盖（`SyncEngine.mergeRemoteMedia` → `apply(dto:)`）；只需在验收时确认同步一轮后远端图可开。

### 4.4 照片墙直开查看器 + 照片数修正

**① 替换 `HomeDestinations.swift` 的 `PhotoWallView`：**

```swift
// MARK: - 照片墙
/// 首页「张照片」统计卡的落地页：照片/视频三列网格，点开直接进全屏查看器。
struct PhotoWallView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]

    @State private var viewerRoute: MediaViewerRoute?

    private var items: [(media: Media, entry: Entry)] {
        entries.flatMap { entry in
            entry.media
                .filter { $0.type == .photo || $0.type == .video }   // 音频不进照片墙
                .sorted { $0.createdAt < $1.createdAt }
                .map { (media: $0, entry: entry) }
        }
    }

    private var galleryMedia: [Media] { items.map(\.media) }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                VStack(spacing: 16) {
                    BubuMascotBadge(size: 84, expression: .surprised)
                    Text("还没有照片\n回首页点「记录此刻」拍下第一张吧")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 120)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(items, id: \.media.id) { item in
                        Button {
                            viewerRoute = MediaViewerRoute(initialMediaID: item.media.id)
                        } label: {
                            MediaThumbnail(media: item.media, mediaStore: env.mediaStore, cornerRadius: 6, size: .grid)
                                .aspectRatio(1, contentMode: .fit)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .fullScreenCover(item: $viewerRoute) { route in
            MediaGalleryViewer(mediaItems: galleryMedia,
                               initialMediaID: route.initialMediaID,
                               mediaStore: env.mediaStore) {
                viewerRoute = nil
            }
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("布布的照片")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MediaViewerRoute: Identifiable {
    let initialMediaID: UUID
    var id: UUID { initialMediaID }
}
```

**② `CaptureHomeView.swift:274-276` 改：**

```swift
    private var totalPhotos: Int {
        entries.reduce(0) { total, entry in
            total + entry.media.filter { $0.type == .photo }.count
        }
    }
```

（若想连视频一起统计，把过滤改为 `!= .audio` 并把统计卡文案 `张照片` 改成 `张影像`。）

**③ Phase 2 的系统相册**按原方案 §5.3-5.5 执行（`SystemAlbum.swift` / `AlbumHomeView.swift` / `AlbumDetailView.swift` 三个新文件，V1 纯计算不建表），并把首页入口 `NavigationLink { PhotoWallView() }` 换成 `AlbumHomeView()`；`AlbumDetailView` 复用上面的 `MediaViewerRoute`（已声明为 internal，可跨文件用）。

### 4.5 首页身份卡

按原方案 §4.2-4.3 执行（`BubuIdentityCard.swift` 新增 + `ageHeader` 替换），所有引用的 API 均已核对存在。两个小修正：

1. 原方案 `daysText` 用了不存在的包装——直接用 `"第 \(AgeCalculator.daysSinceBirth(birthday: profile.birthday)) 天"`（签名 `daysSinceBirth(birthday:at:)`，`at` 有默认值，✅ 原方案写法本身可编译，此处仅确认）。
2. `NavigationLink { ChildProfileView() }` 保持原方案写法；身份卡内不要再嵌套别的 `Button`，避免手势冲突。

### 4.6 LLM 自然语言输入（修正版全链路）

#### 4.6.1 `NaturalCaptureDTO.swift`（新增）

按原方案 §6.3 原文执行（`NaturalCaptureRequest/Result/Item`、`NaturalCaptureDomain/Action`、`JSONValue`）——已核对：plain struct + `Codable, Sendable` 与现有 `DTOs.swift` 模式一致，在默认 MainActor 隔离下可正常编译。

#### 4.6.2 `AIService` 协议扩展

```swift
protocol AIService: Sendable {
    func ping() async throws -> Bool
    func classifyContent(note: String?, tags: [String], locationName: String?) async throws -> AIClassification
    func detectFirstTime(media: [Media]) async throws -> FirstTimeSuggestion?
    func transcribe(audioURL: URL) async throws -> String
    func rewriteFirstPerson(note: String, childName: String) async throws -> String
    func generateGrowthMovie(year: Int) async throws -> GrowthMovieJob
    func movieNarration(year: Int, childName: String, highlights: [String]) async throws -> String
    func parseNaturalCapture(_ request: NaturalCaptureRequest) async throws -> NaturalCaptureResult
}
```

> 与原方案差异：**删掉了 `classify(entryId:)`**——它无调用方且真实实现固定返回空（R3）。`BubuAIService` 中对应方法一并删除；如担心外部引用，先全局搜索确认（当前为零引用）。

#### 4.6.3 `BubuAIService.parseNaturalCapture`

按原方案 §6.4 原文执行（JSONEncoder `.iso8601` + POST `parse-natural-capture` + JSONDecoder `.iso8601`），`applyAuth`/`check`/`session` 均为现有私有成员，直接可用。

`MockAIService` 补齐（离线/预览必需）：

```swift
    func parseNaturalCapture(_ request: NaturalCaptureRequest) async throws -> NaturalCaptureResult {
        try? await Task.sleep(for: .milliseconds(500))
        let text = request.text
        var items: [NaturalCaptureItem] = []
        if text.contains("疫苗") {
            items.append(NaturalCaptureItem(
                domain: .vaccine, action: .create, title: "疫苗接种", note: nil, date: .now,
                fields: ["vaccine_name": .string("示例疫苗")], tags: [],
                confidence: 0.9, needsConfirmation: true, sourceText: text))
        } else if text.contains("喝水") {
            items.append(NaturalCaptureItem(
                domain: .water, action: .create, title: "喝水", note: nil, date: .now,
                fields: ["amount_ml": .number(120)], tags: [],
                confidence: 0.9, needsConfirmation: false, sourceText: text))
        } else {
            items.append(NaturalCaptureItem(
                domain: .timeline, action: .create, title: String(text.prefix(12)), note: text,
                date: .now, fields: [:], tags: [],
                confidence: 0.7, needsConfirmation: false, sourceText: text))
        }
        return NaturalCaptureResult(confidence: 0.85, items: items, warnings: [])
    }
```

（`NaturalCaptureItem` 需要一个全字段 memberwise init 可用——struct 默认即有；若 `id` 有默认值则按需省略。）

#### 4.6.4 服务端 `/parse-natural-capture`（修正 C4：清洗 + 降级，不再裸构造）

`server/ai/main.py` 新增（Pydantic 模型 `NaturalParseReq/ParsedNaturalItem/NaturalParseResp` 按原方案 §6.5 定义，路由改为下面的健壮版）：

```python
_ALLOWED_DOMAINS = {
    "vaccine", "growth", "meal", "snack", "supplement", "water", "sleep",
    "symptom", "checkup", "timeline", "milestone", "first_time", "unknown",
}
_SENSITIVE_DOMAINS = {"vaccine", "symptom", "supplement"}


def _sanitize_parse_result(data: dict, original_text: str) -> NaturalParseResp:
    """LLM 输出不可信：逐条清洗，坏字段降级，绝不让 ValidationError 变 500。"""
    warnings = [w for w in data.get("warnings", []) if isinstance(w, str)]
    items: list[ParsedNaturalItem] = []
    for raw in data.get("items", []):
        if not isinstance(raw, dict):
            continue
        domain = raw.get("domain")
        if domain not in _ALLOWED_DOMAINS:
            domain = "unknown"
            warnings.append("domain_coerced_unknown")
        try:
            item = ParsedNaturalItem(
                domain=domain,
                action=raw.get("action") if raw.get("action") in ("create", "update", "complete") else "create",
                title=str(raw.get("title") or "")[:60] or "未命名记录",
                note=raw.get("note") if isinstance(raw.get("note"), str) else None,
                date=raw.get("date"),
                fields=raw.get("fields") if isinstance(raw.get("fields"), dict) else {},
                tags=[t for t in (raw.get("tags") or []) if isinstance(t, str)][:8],
                confidence=float(raw.get("confidence") or 0.0),
                needs_confirmation=bool(raw.get("needs_confirmation", True)),
                source_text=str(raw.get("source_text") or original_text)[:200],
            )
        except Exception:  # noqa: BLE001  单条解析失败丢弃该条，不拖垮整个响应
            warnings.append("item_dropped_invalid")
            continue
        if item.domain in _SENSITIVE_DOMAINS:
            item.needs_confirmation = True  # 服务端兜底：敏感内容永远要确认
        items.append(item)
    try:
        overall = float(data.get("confidence") or 0.0)
    except (TypeError, ValueError):
        overall = 0.0
    return NaturalParseResp(confidence=overall, items=items, warnings=warnings)


@app.post("/parse-natural-capture", response_model=NaturalParseResp,
          dependencies=[Depends(require_api_key)])
def parse_natural_capture(req: NaturalParseReq):
    if not req.text.strip():
        return NaturalParseResp(confidence=0.0, items=[], warnings=["empty_text"])
    sys = ...   # 原方案 §6.5 的 system prompt 原文，照抄
    user = ...  # 原方案 §6.5 的 user prompt 原文，照抄
    try:
        data = llm.complete_json(sys, user, max_tokens=1200)
    except LLMError as e:
        raise HTTPException(status_code=502, detail=str(e))
    if not data:  # _extract_json 兜底返回 {} 时优雅降级，而不是空 200 迷惑客户端
        return NaturalParseResp(confidence=0.0, items=[], warnings=["llm_output_unparseable"])
    return _sanitize_parse_result(data, req.text)
```

服务端用 6 个样例 curl 验收（原方案 §6.5 列表），另加 2 个健壮性用例：空字符串、纯表情输入。

#### 4.6.5 共享字符串扩展（修正 C2）

新增 `BubuTimeMachine/DesignSystem/String+Bubu.swift`：

```swift
import Foundation

extension String {
    /// 去首尾空白与换行。全工程共享（HealthRecordSheet 里的 private 版本可顺手删除改用本扩展）。
    var bubuTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

`NaturalCaptureBar` 中 `text.trimmed` 全部替换为 `text.bubuTrimmed`，其余按原方案 §6.6 执行。放置位置维持原方案建议：首页 `ageHeader`（身份卡）下方、`saveHealthStrip` 上方；V1 不做全局 overlay。

#### 4.6.6 `NaturalCaptureRouter`（修正 C1、C3）

整体结构按原方案 §6.9，三处替换：

```swift
    // C1 修正：Entry 没有 aiSummary，标题写入 title
    private func saveEntry(_ item: NaturalCaptureItem) {
        let entry = Entry(happenedAt: item.date ?? .now,
                          authorRole: env.config.currentRole.rawValue,
                          note: item.note ?? item.title)
        entry.title = item.title
        entry.syncState = .local
        context.insert(entry)
        context.insert(FeedEvent(kind: .entryCreated,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "智能记录了一条时光：\(item.title)",
                                 targetLocalId: entry.id.uuidString))
    }
```

```swift
    // C3 修正：sleep 优先落 startAt/endAt（HealthRecord 自有字段），时长仅作兜底
    case .sleep:
        record.startAt = item.fields.isoDate("start_at")
        record.endAt = item.fields.isoDate("end_at")
        if record.startAt == nil, record.endAt == nil,
           let minutes = item.fields.double("duration_minutes") {
            record.amountValue = minutes / 60
            record.amountUnit = "小时"
        }
```

字段工具扩展（在原方案 §6.9 的 `Dictionary` 扩展上加一个方法）：

```swift
    func isoDate(_ key: String) -> Date? {
        guard let raw = string(key) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }
```

Phase 3 期间 `saveVaccine` 先落 `HealthRecord(.checkup)` + `tags: ["疫苗", vaccine_name]` + 强确认；Phase 4 切到 `VaccineRecord` 后保留一行兼容注释即可。`saveMilestone/saveFirstTime` 按现有模型 init（`Milestone(title:category:emoji:happenedAt:isCustom:)`、`FirstTime(what:happenedAt:)`）落库，置信度低于 0.6 一律降级为普通 `Entry`（原方案原则不变）。

`NaturalCaptureReviewSheet` 按原方案 §6.8 执行（`saveAll` 里 `try? context.save()` + `env.syncEngine.syncNow()` 均为现有 API）；`requiresHardConfirmation` 规则照原方案 §6.12。

### 4.7 疫苗 / 成长结构化（Phase 4）

1. **模型**：`VaccineRecord.swift`、`GrowthMeasurement.swift` 按原方案 §6.10/6.11 原文新增（字段与现有模型风格一致，无问题）。
2. **Schema 注册**（容易漏）：`BubuTimeMachineApp.swift:17-21` 的 `Schema([...])` 数组追加 `VaccineRecord.self, GrowthMeasurement.self`。
3. **迁移**：App 启动 `bootstrap` 流程里执行一次（伪代码照原方案 §6.10「旧数据迁移」）：读 `UserDefaults` 键 `bubu.vaccine.done` → 对每个 doseId 匹配 `VaccineDose.schedule`（`VaccineSchedule.swift:14` 起，id 形如 `"HepB-1"`）→ 建 `VaccineRecord(vaccineName: dose.vaccine, injectedAt: dose.dueDate(birthday:) ?? .now)`，note 标注「从旧打卡迁移，接种日期待确认」→ 置 `bubu.vaccine.migrated = true` 防重入。**不要删除旧键**（保留回滚能力）。
4. **`VaccineView` 改造**：`@Query(sort: \VaccineRecord.injectedAt) private var records`；`doneSet` 改 `Set(records.compactMap(\.doseId))`；打卡 toggle 创建/删除 `VaccineRecord`；同时修 R5（已完成剂次显示完成日期而非「建议尽快补种」）。
5. **同步接线**（每一处都有现成同类样板可抄）：
   - `DTOs.swift`：`VaccineRecordDTO`、`GrowthMeasurementDTO`（抄 `HealthRecordDTO` 结构）。
   - `APIClient.swift` 协议 + `MockAPIClient` + `PocketBaseClient`：`upsertVaccineRecord/fetchVaccineRecords/upsertGrowthMeasurement/fetchGrowthMeasurements`（抄 `upsertHealthRecord/fetchHealthRecords` 的实现与 escape/filter 模式）。
   - `SyncEngine.swift`：push 队列加两个集合（抄 `pushHealth` 同类函数）；`pullRemote()` 加两行 `await pull("vaccinerecords")...`、`await pull("growthmeasurements")...`；merge 函数抄 `mergeRemoteHealth`。
6. **`GrowthCurveView`**：优先读 `GrowthMeasurement`，无数据时回落现有 `HealthRecord` 文本解析（保留 `parseValue` 兼容旧数据）。

### 4.8 ChildProfile 头像同步（Phase 2 前置项，对应对照表 #12）

最小改动方案（V1 不做完整文件同步管线）：

1. `ChildProfileDTO` 增加 `avatarRemoteURL: String?`；`ChildProfile` 模型增加同名字段。
2. 头像在 `ChildProfileView` 保存时，通过现有 `uploadGenericFile`（collection `childprofiles`、fileField `avatar`）上传，成功后写 `avatarRemoteURL` 并 upsert。
3. `SyncEngine.downloadMissingFiles` 增加一段：`avatarMediaFileName == nil && avatarRemoteURL != nil` 时下载落地（抄 VoiceNote 下载段，10 行以内）。
4. PocketBase `childprofiles` collection 加 `avatar` file 字段。

若想再省事，V1 退而求其次：身份卡在无头像设备上显示 `BubuMascotBadge` 默认形象（现有兜底已可用），把本节整体推迟到 Phase 5——但需接受「家人设备身份卡无真实头像」。

---

## 5. 验收与回归清单

### 5.1 Phase 1（P0）硬门槛

1. 新拍照片本地打开正常；多图左右滑、双击缩放、捏合缩放正常（验根因 A）。
2. 删除本地媒体文件仅留 `remoteURL`：鉴权下载显示成功（验根因 B）。
3. 新上传一张图，**不等下一轮拉取**，立刻杀进程→重开→删本地文件→打开远端图成功（验根因 C：URL 当场就是对的）。
4. 断网打开远端图：出现失败态 + 重试按钮，不黑屏；恢复网络点重试成功。
5. 照片墙点图直开查看器；音频不再出现在照片墙；首页「张照片」数 = 纯照片数。
6. 连续上传 20 张照片后 Memory Graph 无 `URLSession`/`UploadProgressDelegate` 累积（验 R1）。
7. 视频、音频播放回归不破。

### 5.2 Phase 2-5

按原方案 §10.2（相册）、§10.3（身份卡）、§10.4（LLM 文字）、§10.5（语音）、§10.6（同步）原文执行，另加：

- 身份卡：家人设备（B 机）拉取后能看到 A 机设置的头像（若做了 §4.8）。
- LLM：服务端两个健壮性用例（空串、纯表情）返回 200 + 空 items，不返回 500。
- 疫苗迁移：迁移后旧键仍在、`bubu.vaccine.migrated == true`、二次启动不重复迁移。

### 5.3 每阶段统一出口

```bash
xcodegen generate
xcodebuild -scheme BubuTimeMachine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme BubuTimeMachine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

现有 4 个测试目标（CapsuleCrypto / CapsuleV3 / PocketBaseClientSyncQuery / Reaction）必须保持绿色；`PocketBaseClientSyncQueryTests` 若因 `multipartUpload` 签名变化受影响，更新测试而非削弱断言。

---

## 6. PocketBase 服务端变更清单

| Collection | 时机 | 字段 | 备注 |
|---|---|---|---|
| `vaccinerecords` | Phase 4 | localId(text,unique), vaccineName(text), doseId(text?), doseLabel(text?), injectedAt(date), hospital(text?), injectionSite(text?), reaction(text?), note(text?), sourceRaw(text), clientUpdatedAt(date) | viewRule/createRule/updateRule 照抄 `healthrecords` 现有规则 |
| `growthmeasurements` | Phase 4 | localId(text,unique), measuredAt(date), heightCm(number?), weightKg(number?), headCircumferenceCm(number?), note(text?), sourceRaw(text), clientUpdatedAt(date) | 同上 |
| `childprofiles` | Phase 2（若做 §4.8） | + avatar(file) | 已有 collection 加字段 |
| `photoalbums` / `photoalbumitems` | P2 暂缓 | — | 系统相册纯客户端计算，V1 不建表 |

⚠️ 注意：客户端先发版、PB 后建表会导致新集合拉取 404 → 触发软失败提示。**先建表再发客户端**，或确认 SyncEngine 对未知集合 404 走软失败静默（现有 `pull` 的 catch 即软失败，可接受，但建议顺序正确）。

AI 服务端部署：`server/ai` 新增路由后重启 FastAPI；确认 `.env` 的 `AI_API_KEY`、`DEEPSEEK_API_KEY` 在位；`/parse-natural-capture` 纳入现有限流（依赖 `require_api_key`，已自动生效）。

---

## 7. 给 Codex 的总提示词（v2，直接整段粘贴）

```text
你正在维护 SwiftUI + SwiftData + PocketBase + 自托管 FastAPI AI 的 iOS App「BubuTimeMachine」
（仓库 leoyb1010/BubuTimeMachine，HEAD ae0cbf1）。
工程约束：iOS 26 / Swift 6 / SWIFT_STRICT_CONCURRENCY=complete / SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor。
新增 DTO 一律照抄 Services/Networking/DTOs.swift 的写法；新增网络/同步代码复用 PocketBaseClient 现有
withAuthRetry、软失败与转义模式。必须可编译、可运行、可回归，不做无关重构，不删除现有功能。

按以下顺序执行（每阶段结束跑 xcodegen generate + xcodebuild build + 现有 tests，全绿再继续）：

Phase 1（P0 稳定性）：
1. 重写 DesignSystem/Components/MediaViewer.swift 的 ZoomableImageView：布局收敛到自定义
   UIScrollView 子类的 layoutSubviews（修首帧 bounds=0 黑屏）。
2. RemoteZoomableImage 改用 env.apiClient.downloadFile（带 PocketBase 鉴权），失败态加「重试」。
3. PocketBaseClient 两个 multipartUpload：从上传响应 JSON 读服务端真实文件名（媒体读 "file"，
   通用上传读对应 fileField）再拼 remoteURL；同时给每个临时 URLSession 补
   defer { session.finishTasksAndInvalidate() }（修 session 泄漏）。
4. PhotoWallView：只展示 photo/video，点击直接 fullScreenCover 打开 MediaGalleryViewer，
   不再 NavigationLink 进 EntryDetailView；CaptureHomeView.totalPhotos 只统计 .photo。

Phase 2（首屏与相册）：
5. 新增 DesignSystem/Components/BubuIdentityCard.swift（学生证风格身份卡：头像/姓名/年龄/生日/
   天数/出生地/短 ID/条码装饰），替换 CaptureHomeView.ageHeader，点卡进 ChildProfileView。
6. ChildProfileDTO + ChildProfile 增加 avatarRemoteURL，经 childprofiles collection 的 avatar
   file 字段上传，SyncEngine.downloadMissingFiles 补头像下载（家人设备身份卡显示真实头像）。
7. 新增 Features/Album/{SystemAlbum,AlbumHomeView,AlbumDetailView}.swift：纯计算系统相册
  （全部照片/最近/小视频/按月份/按月龄），首页照片入口改进 AlbumHomeView，相册内点图直开查看器。

Phase 3（LLM 文字输入 MVP）：
8. server/ai/main.py 新增 POST /parse-natural-capture（带 require_api_key）：把一句话拆成多条
   结构化 items（domain ∈ vaccine/growth/meal/snack/supplement/water/sleep/symptom/checkup/
   timeline/milestone/first_time/unknown）。LLM 输出必须逐条清洗后再构造响应（坏字段降级、
   缺字段丢弃该条），vaccine/symptom/supplement 服务端强制 needs_confirmation=true，
   绝不让 ValidationError 变 500；_extract_json 返回空 dict 时返回 warnings=["llm_output_unparseable"]。
9. Swift 端：新增 NaturalCaptureDTO.swift；AIService 协议加 parseNaturalCapture 和 classifyContent，
   删除无调用方的 classify(entryId:)；BubuAIService/MockAIService 补实现。
10. 新增 Features/NaturalCapture/{NaturalCaptureBar,NaturalCaptureReviewSheet,NaturalCaptureRouter}.swift：
    输入条放首页身份卡下方；解析结果走确认页（敏感/低置信必须确认）；Router 写入对应模型。
    注意：Entry 没有 aiSummary 属性，标题写 entry.title；睡眠优先写 HealthRecord.startAt/endAt；
    String.trimmed 在工程里是 private 扩展，新建共享的 bubuTrimmed。
    疫苗本阶段先存 HealthRecord(.checkup)+强确认。

Phase 4（疫苗/成长结构化）：
11. 新增 Models/{VaccineRecord,GrowthMeasurement}.swift，并把两个类型加进 BubuTimeMachineApp 的
    Schema 数组；首启把 @AppStorage("bubu.vaccine.done") 迁移为 VaccineRecord（标记 migrated，
    保留旧键）；VaccineView 改 @Query 读 VaccineRecord（已完成剂次不再显示「建议尽快补种」）；
    GrowthCurveView 优先读 GrowthMeasurement、旧 HealthRecord 文本解析作兼容；DTO/APIClient/
    PocketBaseClient/SyncEngine 照 healthrecords 样板接 vaccinerecords、growthmeasurements 两个
    collection；NaturalCaptureRouter 的 vaccine/growth 切到新模型。

Phase 5（语音与打磨）：
12. NaturalCaptureBar 接麦克风：AudioRecorder 录音 → transcribe → 转写文本可编辑 → 自动解析进
    确认页；失败可重试不丢音频。
13. 清理：删除无调用方的 UploadQueue；subscribeRealtime 的 since 改为请求发起前取值；
    MediaThumbnail 等待远端的呼吸动画补 onChange 启动；PocketBaseClient.ping 加 10s 超时。

红线：疫苗/症状/药物/过敏/体温异常必须确认后入库，不静默保存；不输出诊断或医疗建议；
错误提示保持温和文案，不在正式 UI 暴露异常原文；媒体链路必须兼容本地文件、远端鉴权文件、
断网、PocketBase 文件名改写。UI 走轻量克制的卡片设计，不做聊天机器人界面。
```

---

## 8. 风险与注意事项

1. **Swift 6 严格并发**是本工程最大的编译风险源：新代码尽量贴着现有同类文件抄结构（DTO 抄 DTOs.swift、网络抄 PocketBaseClient、View 默认 MainActor），不要引入新的并发原语。
2. **PocketBase 先建表后发版**（§6 表格），否则新集合首轮拉取报软失败提示。
3. **迁移幂等**：疫苗迁移必须有 `bubu.vaccine.migrated` 防重入；保留旧键以便回滚。
4. **LLM 输出永远不可信**：客户端 `requiresHardConfirmation`（原方案 §6.12）与服务端 `_sanitize_parse_result` 双层兜底，缺一不可。
5. **不要动现有 4 个测试的断言强度**；`multipartUpload` 改签名后同步更新 `PocketBaseClientSyncQueryTests`。
6. 原方案 §12.1（重复 syncNow）经核实不存在，**不要**据此改动 EntryDetailView。
7. 原方案 §12.5（NavigationLink(value: Entry) 改 EntryRoute）暂不执行：Phase 1 修复后照片墙不再依赖该跳转，现有注册点（RootTabView:13、TimelineView 各自 stack）工作正常；若后续仍现导航异常再启用。
