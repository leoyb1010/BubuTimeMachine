import SwiftUI
import SwiftData
import Observation
import Vision
import CryptoKit
import UIKit

// MARK: - 成长脸延时（全部端侧）
// 只从家庭服务 GET 照片；人脸检测、挑选、对齐、缓存都在这台手机上完成，从不上传任何东西。

nonisolated struct FaceTimelapsePhotoDTO: Decodable, Sendable, Hashable {
    let id: String
    let kind: String
    let capturedAt: String?
    let largeUrl: String
    let previewUrl: String?
    /// 契约 §1：同框家人名（不含布布）。旧服务没有这个字段时为 nil。
    let people: [String]?
}

nonisolated struct FaceTimelapsePageDTO: Decodable, Sendable {
    let items: [FaceTimelapsePhotoDTO]
}

/// 一个月挑出来的一张已对齐的脸。
nonisolated struct FaceTimelapseFrame: Identifiable, Sendable {
    let month: Int
    let image: UIImage
    var id: Int { month }

    var label: String {
        if month == 0 { return "出生那个月" }
        if month % 12 == 0 { return "\(month / 12) 岁" }
        if month > 12 { return "\(month / 12) 岁 \(month % 12) 个月" }
        return "\(month) 个月"
    }
}

// MARK: 端侧人脸挑选与对齐

nonisolated enum FaceTimelapseProcessor {
    struct Crop: Sendable {
        let score: Double
        let jpeg: Data
    }

    static let outputSide: CGFloat = 480
    /// 对齐后双眼在输出方图里的位置（比例）。
    static let leftEyeTarget = CGPoint(x: 0.37, y: 0.42)
    static let rightEyeTarget = CGPoint(x: 0.63, y: 0.42)

    @concurrent
    static func bestCrop(from data: Data) async -> Crop? { analyze(data) }

    /// 只接受“画面里恰好一张脸”的照片；分数 = 脸的大小 × 正脸程度²。
    static func analyze(_ data: Data) -> Crop? {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else { return nil }
        // 先把方向摆正并缩到最长边 1600，Vision 与绘制都在同一张直立位图上进行。
        let longest = max(source.size.width, source.size.height)
        let scale = min(1, 1600 / longest)
        let size = CGSize(width: floor(source.size.width * scale), height: floor(source.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = upright.cgImage else { return nil }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }
        // 极小的背景脸（< 0.2% 画面）不算数，其余必须恰好一张。
        let faces = (request.results ?? []).filter { $0.boundingBox.width * $0.boundingBox.height >= 0.002 }
        guard faces.count == 1, let face = faces.first, let landmarks = face.landmarks else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        func centroid(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region, region.pointCount > 0 else { return nil }
            let points = region.pointsInImage(imageSize: imageSize)
            let x = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
            let y = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
            return CGPoint(x: x, y: imageSize.height - y)   // Vision 左下原点 → UIKit 左上原点
        }
        guard let eyeA = centroid(landmarks.leftPupil) ?? centroid(landmarks.leftEye),
              let eyeB = centroid(landmarks.rightPupil) ?? centroid(landmarks.rightEye) else { return nil }
        let (left, right) = eyeA.x <= eyeB.x ? (eyeA, eyeB) : (eyeB, eyeA)
        let eyeDistance = hypot(right.x - left.x, right.y - left.y)
        let area = Double(face.boundingBox.width * face.boundingBox.height)
        guard eyeDistance >= 36, area >= 0.01 else { return nil }

        let roll = atan2(right.y - left.y, right.x - left.x)
        guard abs(roll) < .pi / 4 else { return nil }

        // 正脸程度：有 yaw 用 yaw；再用鼻子相对两眼中点的偏移做对称性校验，取较小者。
        let mid = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        var frontal = 1.0
        if let nose = centroid(landmarks.nose) {
            let offset = Double(abs((nose.x - mid.x) * cos(roll) + (nose.y - mid.y) * sin(roll)) / eyeDistance)
            frontal = max(0, 1 - offset * 2.2)
        }
        if let yaw = face.yaw?.doubleValue {
            frontal = min(frontal, max(0, cos(yaw * 1.6)))
        }
        guard frontal > 0.35 else { return nil }
        let score = area.squareRoot() * frontal * frontal

        // 按眼睛对齐：旋转摆平 → 缩放到统一眼距 → 平移到统一位置。
        let side = outputSide
        let targetDistance = (rightEyeTarget.x - leftEyeTarget.x) * side
        let s = targetDistance / eyeDistance
        let targetMid = CGPoint(x: (leftEyeTarget.x + rightEyeTarget.x) / 2 * side, y: leftEyeTarget.y * side)
        let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor(red: 0.99, green: 0.95, blue: 0.92, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let cg = context.cgContext
            cg.translateBy(x: targetMid.x, y: targetMid.y)
            cg.rotate(by: -roll)
            cg.scaleBy(x: s, y: s)
            cg.translateBy(x: -mid.x, y: -mid.y)
            upright.draw(at: .zero)
        }
        guard let jpeg = out.jpegData(compressionQuality: 0.86) else { return nil }
        return Crop(score: score, jpeg: jpeg)
    }
}

// MARK: 缓存（Caches，按账号隔离）

nonisolated enum FaceTimelapseCache {
    struct Entry: Codable, Sendable {
        var itemId: String?
        var checkedAt: Date
    }
    struct Manifest: Codable, Sendable {
        var entries: [Int: Entry] = [:]
    }

    static func folder(scope: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let hash = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        let url = caches.appendingPathComponent("BubuFaceTimelapse", isDirectory: true)
            .appendingPathComponent(String(hash), isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func frameURL(_ folder: URL, month: Int) -> URL { folder.appendingPathComponent("m\(month).jpg") }

    static func loadManifest(_ folder: URL) -> Manifest {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return Manifest() }
        return manifest
    }

    static func save(_ manifest: Manifest, _ folder: URL) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }

    static func writeFrame(_ jpeg: Data, folder: URL, month: Int) {
        try? jpeg.write(to: frameURL(folder, month: month),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    @concurrent
    static func loadFrame(folder: URL, month: Int) async -> UIImage? {
        guard let data = try? Data(contentsOf: frameURL(folder, month: month)), let image = UIImage(data: data) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }

    static func clear(_ folder: URL) { try? FileManager.default.removeItem(at: folder) }

    /// 需要重新挑的月份：本月半天一次；过去没挑到的月份一周后再试；挑到了就一直用。
    static func needsCheck(_ entry: Entry?, monthEnd: Date, now: Date = .now) -> Bool {
        guard let entry else { return true }
        if monthEnd >= Calendar.current.startOfDay(for: now) { return now.timeIntervalSince(entry.checkedAt) > 12 * 3600 }
        if entry.itemId == nil { return now.timeIntervalSince(entry.checkedAt) > 7 * 86_400 }
        return false
    }
}

// MARK: 逐月挑选

@Observable @MainActor
final class FaceTimelapseModel {
    enum Phase: Equatable { case idle, working, done, unavailable, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var frames: [FaceTimelapseFrame] = []
    private(set) var checkedMonths = 0
    private(set) var totalMonths = 0
    private(set) var missingMonths = 0

    /// 每个月最多下载几张大图来比较（候选按“无同框家人”优先）。
    static let candidatesPerMonth = 8

    func build(client: BubuLearningClient, birthday: Date) async {
        guard phase != .working, let folder = FaceTimelapseCache.folder(scope: client.scope) else { return }
        phase = .working
        let cal = Calendar.current
        let birth = cal.startOfDay(for: birthday)
        let lastMonth = min(72, max(0, cal.dateComponents([.month], from: birth, to: cal.startOfDay(for: .now)).month ?? 0))
        totalMonths = lastMonth + 1
        checkedMonths = 0
        var manifest = FaceTimelapseCache.loadManifest(folder)
        var collected: [Int: FaceTimelapseFrame] = [:]
        var networkFailures = 0

        for month in 0...lastMonth {
            if Task.isCancelled { break }
            guard let start = cal.date(byAdding: .month, value: month, to: birth),
                  let next = cal.date(byAdding: .month, value: month + 1, to: birth),
                  let end = cal.date(byAdding: .day, value: -1, to: next) else { continue }
            let entry = manifest.entries[month]
            if !FaceTimelapseCache.needsCheck(entry, monthEnd: end) {
                if entry?.itemId != nil, let image = await FaceTimelapseCache.loadFrame(folder: folder, month: month) {
                    collected[month] = FaceTimelapseFrame(month: month, image: image)
                    publish(collected)
                }
                checkedMonths += 1
                continue
            }
            do {
                let page = try await client.get("api/online-timeline", query: [
                    URLQueryItem(name: "kind", value: "photo"),
                    URLQueryItem(name: "start", value: BubuLearningDates.dayString(start)),
                    URLQueryItem(name: "end", value: BubuLearningDates.dayString(end)),
                    URLQueryItem(name: "order", value: "asc"),
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "limit", value: "30"),
                ], as: FaceTimelapsePageDTO.self)
                networkFailures = 0
                let ranked = page.items
                    .filter { $0.kind != "video" && !$0.largeUrl.isEmpty }
                    .enumerated()
                    .sorted { lhs, rhs in
                        let a = Self.peopleRank(lhs.element), b = Self.peopleRank(rhs.element)
                        return a != b ? a < b : lhs.offset < rhs.offset
                    }
                    .map(\.element)
                var best: (id: String, crop: FaceTimelapseProcessor.Crop)?
                for photo in ranked.prefix(Self.candidatesPerMonth) {
                    if Task.isCancelled { break }
                    guard let data = try? await client.mediaData(photo.largeUrl),
                          let crop = await FaceTimelapseProcessor.bestCrop(from: data) else { continue }
                    if crop.score > (best?.crop.score ?? 0) { best = (photo.id, crop) }
                }
                if Task.isCancelled { break }
                var keptID = best?.id
                if let best {
                    FaceTimelapseCache.writeFrame(best.crop.jpeg, folder: folder, month: month)
                    if let image = UIImage(data: best.crop.jpeg) {
                        collected[month] = FaceTimelapseFrame(month: month, image: image)
                        publish(collected)
                    }
                } else if let previous = entry?.itemId,
                          let image = await FaceTimelapseCache.loadFrame(folder: folder, month: month) {
                    // 本月重新挑没挑到新的，保留之前那张。
                    keptID = previous
                    collected[month] = FaceTimelapseFrame(month: month, image: image)
                    publish(collected)
                }
                manifest.entries[month] = FaceTimelapseCache.Entry(itemId: keptID, checkedAt: .now)
                FaceTimelapseCache.save(manifest, folder)
            } catch is CancellationError {
                break
            } catch {
                if GrowthServiceAvailability.hides(error) { phase = .unavailable; return }
                networkFailures += 1
                if networkFailures >= 3 {
                    phase = frames.isEmpty ? .failed(learningErrorText(error)) : .done
                    return
                }
            }
            checkedMonths += 1
        }
        missingMonths = max(0, totalMonths - collected.count)
        phase = Task.isCancelled ? .idle : .done
    }

    func reset(client: BubuLearningClient) {
        if let folder = FaceTimelapseCache.folder(scope: client.scope) { FaceTimelapseCache.clear(folder) }
        frames = []
        phase = .idle
    }

    private func publish(_ collected: [Int: FaceTimelapseFrame]) {
        withAnimation(BubuMotion.gentle) { frames = collected.keys.sorted().compactMap { collected[$0] } }
    }

    private static func peopleRank(_ photo: FaceTimelapsePhotoDTO) -> Int {
        guard let people = photo.people else { return 1 }
        return people.isEmpty ? 0 : 2
    }
}

// MARK: - 成长页卡片

struct FaceTimelapseCard: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let client = BubuLearningClient(env: env) {
            NavigationLink { FaceTimelapseView(client: client) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "face.smiling.inverse")
                        .font(BubuTheme.Font.scaled(24, weight: .semibold))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                        .frame(width: 52, height: 52)
                        .background(BubuTheme.Color.lavSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("成长脸 · 延时")
                            .font(BubuTheme.Font.headline)
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("每个月挑一张正脸，看布布一点点长大 · 只在手机上处理")
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(BubuTheme.Font.caption.weight(.bold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .padding(16)
                .background(
                    LinearGradient(colors: [BubuTheme.Color.lavSurface, BubuTheme.Color.skySurface],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                )
                .bubuCardShadow()
            }
            .buttonStyle(BubuPressableStyle())
        }
    }
}

// MARK: - 延时页

struct FaceTimelapseView: View {
    let client: BubuLearningClient
    @Query private var profiles: [ChildProfile]
    @State private var model = FaceTimelapseModel()
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.l) {
                content
                privacyNote
            }
            .padding()
            .bubuContentColumn()
        }
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle("成长脸")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { confirmReset = true } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.phase == .working)
                    .accessibilityLabel("重新挑选")
            }
        }
        .alert("重新挑一遍？", isPresented: $confirmReset) {
            Button("重新挑选") {
                model.reset(client: client)
                Task { await start() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清掉手机里缓存的这些脸，重新下载照片在本机挑选，需要一点时间。")
        }
        .task { await start() }
    }

    private func start() async {
        guard let birthday = profiles.first?.birthday else { return }
        await model.build(client: client, birthday: birthday)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .unavailable:
            stateCard(expression: .thinking, text: "家庭服务暂时不可用，等它回来再来看看布布的成长脸吧。")
        case .failed(let message):
            stateCard(expression: .thinking, text: message)
        default:
            if profiles.first == nil {
                stateCard(expression: .thinking, text: "先在档案里填上布布的生日，才能按月龄排好每一张脸。")
            } else if model.frames.count >= 2 {
                FaceTimelapsePlayer(frames: model.frames)
                    .entranceEffect(index: 0)
                progress
            } else if model.phase == .done {
                stateCard(expression: .surprised,
                          text: model.frames.count == 1
                            ? "目前只挑到 1 个月的正脸，再多拍几张布布的正面照，下个月就能播放啦。"
                            : "还没挑到合适的正脸。只拍到布布一个人、脸正对镜头的照片最合适。")
            } else {
                VStack(spacing: BubuTheme.Spacing.m) {
                    BubuEmptyIllustration(assetName: "BubuEmptyFaceTimelapse", fallbackExpression: .thinking, size: 130)
                        .bubuFloating()
                    Text("正在一个月一个月地翻照片，找布布的正脸…")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    progress
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BubuTheme.Spacing.l)
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        if model.totalMonths > 0 {
            VStack(alignment: .leading, spacing: 6) {
                if model.phase == .working {
                    ProgressView(value: Double(model.checkedMonths), total: Double(model.totalMonths))
                        .tint(BubuTheme.Color.primary)
                        .animation(BubuMotion.gentle, value: model.checkedMonths)
                    Text("已翻到第 \(model.checkedMonths) / \(model.totalMonths) 个月 · 挑到 \(model.frames.count) 张")
                        .contentTransition(.numericText())
                } else {
                    Text("共 \(model.totalMonths) 个月，挑到 \(model.frames.count) 张"
                         + (model.missingMonths > 0 ? "；有 \(model.missingMonths) 个月没有合适的正脸，播放时会跳过。" : "。"))
                }
            }
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stateCard(expression: BubuExpression, text: String) -> some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            BubuMascotBadge(size: 70, expression: expression)
            Text(text)
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(BubuTheme.Spacing.l)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private var privacyNote: some View {
        Label("照片只下载到这台手机，在本机识别和对齐，结果存在缓存里，不会上传到任何地方。", systemImage: "lock.shield.fill")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 播放器（交叉淡入 + 月龄标签 + 播放/暂停 + 拖动条）

struct FaceTimelapsePlayer: View {
    let frames: [FaceTimelapseFrame]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = true
    @State private var anchorDate = Date.now
    @State private var anchorPosition = 0.0

    private let secondsPerFrame = 1.1

    private func position(at date: Date) -> Double {
        let count = Double(frames.count)
        guard playing, count > 1 else { return min(anchorPosition, max(count - 1, 0)) }
        let raw = anchorPosition + date.timeIntervalSince(anchorDate) / secondsPerFrame
        return raw.truncatingRemainder(dividingBy: count)
    }

    var body: some View {
        TimelineView(AnimationTimelineSchedule(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let pos = position(at: context.date)
            let index = min(Int(pos), frames.count - 1)
            let nextIndex = (index + 1) % frames.count
            let fraction = pos - Double(index)
            // 每帧前 55% 静止，后 45% 平滑淡入下一帧；减弱动态效果时直接切换，不做淡入。
            let t = reduceMotion ? (fraction >= 0.999 ? 1 : 0) : smoothstep((fraction - 0.55) / 0.45)
            let shown = t > 0.5 ? frames[nextIndex] : frames[index]
            VStack(spacing: BubuTheme.Spacing.m) {
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: frames[index].image)
                        .resizable().scaledToFill()
                        .scaleEffect(reduceMotion ? 1 : 1 + 0.03 * fraction)
                    Image(uiImage: frames[nextIndex].image)
                        .resizable().scaledToFill()
                        .opacity(t)
                    Text(shown.label)
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.paperInk)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(.white.opacity(0.85), in: Capsule())
                        .padding(14)
                        .contentTransition(.opacity)
                        .animation(BubuMotion.quick, value: shown.month)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                .bubuCardShadow()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("布布 \(shown.label) 的样子")

                HStack(spacing: BubuTheme.Spacing.m) {
                    Button {
                        if playing {
                            anchorPosition = position(at: .now)
                            playing = false
                        } else {
                            anchorDate = .now
                            playing = true
                        }
                        BubuHaptics.tapLight()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(BubuTheme.Font.headline)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(BubuTheme.Color.primary, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(BubuPressableStyle())
                    .accessibilityLabel(playing ? "暂停" : "播放")

                    Slider(value: Binding(
                        get: { min(pos, Double(frames.count - 1)) },
                        set: { value in
                            playing = false
                            // 减弱动态效果时拖动吸附到整月，画面一张张硬切。
                            anchorPosition = reduceMotion ? value.rounded() : value
                        }
                    ), in: 0...Double(max(frames.count - 1, 1)))
                    .tint(BubuTheme.Color.primary)
                    .accessibilityLabel("月龄")
                    .accessibilityValue(shown.label)
                }
                if reduceMotion && !playing {
                    Text("已开启“减弱动态效果”，拖动滑块一个月一个月地看")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        // 减弱动态效果：不自动播放，改为手动拖动；中途打开该设置也立即停下。
        .onAppear { if reduceMotion { pause() } }
        .onChange(of: reduceMotion) { _, reduce in if reduce { pause() } }
    }

    private func pause() {
        guard playing else { return }
        anchorPosition = position(at: .now).rounded(.down)
        playing = false
    }

    private func smoothstep(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
