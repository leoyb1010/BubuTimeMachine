import SwiftUI
import AVKit

/// 一节课：解析进度 → 家长逐题核对（老师原声、答案、画面）→ 开放 → 一起学。
struct CourseDetailView: View {
    let client: BubuLearningClient
    let courseID: String
    let childID: String
    let canReview: Bool
    var onChange: () -> Void = {}
    @State private var course: LearningCourseDetailDTO?
    @State private var errorText: String?
    @State private var actionError: String?
    @State private var checked: Set<String> = []
    @State private var dateConfirmed = false
    @State private var working = false
    @State private var playing = false
    @State private var confirmDelete = false
    @State private var confirmRegenerate = false
    @State private var awaitingPack: String?
    @State private var player = NativeLearningAudioPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            if let course {
                ScrollView {
                    VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                        header(course)
                        stateSection(course)
                        if !course.sources.isEmpty { sourcesSection(course) }
                    }
                    .padding(BubuTheme.Spacing.item)
                    .bubuContentColumn(860)
                }
                .refreshable { await load() }
            } else if let errorText {
                ContentUnavailableView {
                    Label("课程暂时打不开", systemImage: "exclamationmark.triangle")
                } description: { Text(errorText) } actions: {
                    Button("重新加载") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("正在打开课程…")
            }
        }
        .navigationTitle(course?.title ?? "课程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canReview, course != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("重新生成互动", systemImage: "arrow.clockwise") {
                            if course?.state == "published" { confirmRegenerate = true } else { Task { await regenerate() } }
                        }
                        .disabled(course?.state == "processing" || course?.state == "uploading")
                        Button("删除这节课", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityIdentifier("learning.course.menu")
                }
            }
        }
        .confirmationDialog("重新生成这节课？", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("重新生成") { Task { await regenerate() } }
            Button("取消", role: .cancel) {}
        } message: { Text("新的题目需要家长重新核对，核对前布布暂时不能玩这节课。") }
        .confirmationDialog("删除这节课？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await delete() } }
            Button("取消", role: .cancel) {}
        } message: { Text("课程素材和互动都会从每日学习中移除，布布的时光不受影响。") }
        .task { await load() }
        .task(id: course?.state == "processing" || awaitingPack != nil) {
            while (course?.state == "processing" || awaitingPack != nil) && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
        .onDisappear { player.stop() }
        .fullScreenCover(isPresented: $playing) {
            if let pack = course?.pack {
                LearningPlayView(client: client, childID: childID,
                                 items: pack.payload.activities.map { LearningPlayItem(packID: pack.id, activity: $0) },
                                 title: pack.title)
            }
        }
        .accessibilityIdentifier("learning.course.detail")
    }

    // MARK: Sections

    private func header(_ course: LearningCourseDetailDTO) -> some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: 5) {
                Text(course.title).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                Text("\(Self.readableDay(course.schoolDate)) · \(course.kindLabel) · \(course.language == "zh-CN" ? "中文" : "英文")")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer(minLength: 0)
            CourseStateBadge(state: course.state)
        }
    }

    @ViewBuilder
    private func stateSection(_ course: LearningCourseDetailDTO) -> some View {
        switch course.state {
        case "processing":
            LearningPanel(title: "正在解析", symbol: "waveform.badge.magnifyingglass") {
                Text("家里的服务器正在完整听老师的原声、看课堂画面，然后整理互动题。几分钟后回来看看就好，不用一直等。")
                    .font(BubuTheme.Font.body)
                ProgressView().frame(maxWidth: .infinity)
            }
        case "uploading":
            LearningPanel(title: "上传没有完成", symbol: "icloud.slash", accent: BubuTheme.Color.danger) {
                Text("已收到 \(course.sourceCount)/\(course.expectedFiles ?? course.sourceCount) 个文件，上传中途断开了。请删除这节课后重新上传。")
                    .font(BubuTheme.Font.body)
            }
        case "failed":
            LearningPanel(title: "解析没有完成", symbol: "exclamationmark.triangle.fill", accent: BubuTheme.Color.danger) {
                Text("素材解析或出题没有完成（例如网络中断、视频损坏或声音轨道不完整）。可以先再试一次；仍不行就删除后重新上传原片。")
                    .font(BubuTheme.Font.body)
                if canReview {
                    Button("再试一次") { Task { await regenerate() } }.buttonStyle(.borderedProminent)
                        .tint(BubuTheme.Color.actionFill)
                }
            }
        case "no_lesson":
            LearningPanel(title: "没有生成互动题", symbol: "text.badge.xmark") {
                Text(course.pack?.payload.summary ?? "没有找到可核对的老师原声。")
                    .font(BubuTheme.Font.body)
                if canReview {
                    Button("再试一次生成") { Task { await regenerate() } }.buttonStyle(.bordered)
                }
            }
        case "draft":
            if let pack = course.pack, canReview {
                reviewSection(pack, course: course)
            } else {
                LearningPanel(title: "等家长核对", symbol: "hourglass") {
                    Text("题目已经整理好，家长核对后就能和布布一起玩啦。").font(BubuTheme.Font.body)
                }
            }
        case "published":
            if let pack = course.pack { publishedSection(pack) }
        default:
            LearningPanel(title: "还在准备", symbol: "hourglass") {
                Text("家长核对后，这节课就会出现在这里。").font(BubuTheme.Font.body)
            }
        }
        if let actionError {
            Text(actionError).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger)
        }
    }

    private func reviewSection(_ pack: LearningPackDTO, course: LearningCourseDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
            LearningPanel(title: "家长核对", symbol: "checkmark.seal.fill", subtitle: "确认后才会开放给布布") {
                Text("请逐题播放老师原声，确认题目、答案和画面都对得上。不对的题可以直接移除。")
                    .font(BubuTheme.Font.body)
                if !pack.payload.warnings.isEmpty {
                    ForEach(pack.payload.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle").font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
            }
            ForEach(Array(pack.payload.activities.enumerated()), id: \.element.id) { index, activity in
                ActivityReviewCard(index: index + 1, activity: activity, client: client, player: player,
                                   original: course.sources.first { $0.id == activity.prompt?.sourceId && !$0.mime.hasPrefix("image/") }?.originalUrl,
                                   checked: Binding(get: { checked.contains(activity.id) },
                                                    set: { if $0 { checked.insert(activity.id) } else { checked.remove(activity.id) } }),
                                   onRemove: { Task { await exclude(pack, activity) } })
            }
            Toggle(isOn: $dateConfirmed) {
                Text("上课日期是 \(Self.readableDay(course.schoolDate))").font(BubuTheme.Font.body.weight(.semibold))
            }
            .tint(BubuTheme.Color.primary)
            .padding(BubuTheme.Spacing.m)
            .background(BubuTheme.Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
            .accessibilityIdentifier("learning.review.date")
            Button { Task { await publish(pack) } } label: {
                HStack {
                    if working { ProgressView().tint(.white) }
                    Text(publishTitle(pack)).font(BubuTheme.Font.headline)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16).foregroundStyle(.white)
                .background(readyToPublish(pack) ? AnyShapeStyle(BubuTheme.Gradient.primaryButton) : AnyShapeStyle(BubuTheme.Color.softFill),
                            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!readyToPublish(pack) || working)
            .accessibilityIdentifier("learning.review.publish")
        }
    }

    private func publishedSection(_ pack: LearningPackDTO) -> some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
            BubuBigActionButton(title: "开始一起学", subtitle: "\(pack.payload.activities.count) 个老师原声小互动",
                                systemImage: "play.fill") { playing = true }
                .accessibilityIdentifier("learning.play")
            LearningPanel(title: "这节课的互动", symbol: "list.bullet.rectangle") {
                ForEach(pack.payload.activities) { activity in
                    HStack {
                        Text(activity.kindLabel).font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(BubuTheme.Color.pinkSurface, in: Capsule())
                        Text(activity.title).font(BubuTheme.Font.body)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func sourcesSection(_ course: LearningCourseDetailDTO) -> some View {
        LearningPanel(title: "课程素材", symbol: "film.stack", subtitle: "只用于每日学习", accent: BubuTheme.Color.deepRose) {
            ForEach(course.sources) { source in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: source.mime.hasPrefix("image/") ? "photo" : source.mime.hasPrefix("audio/") ? "waveform" : "video")
                        Text(source.name).font(BubuTheme.Font.body).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(Self.sourceState(source.state)).font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    if !source.analysis.description.isEmpty {
                        Text(source.analysis.description).font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText).lineLimit(3)
                    }
                    if !source.analysis.segments.isEmpty {
                        DisclosureGroup("老师原声转写（\(source.analysis.segments.count) 段）") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(source.analysis.segments) { segment in
                                    Text("\(OnlineTimelineDetailPage.timecode(segment.start))  \(segment.text)")
                                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .font(BubuTheme.Font.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Actions

    private func readyToPublish(_ pack: LearningPackDTO) -> Bool {
        dateConfirmed && !pack.payload.activities.isEmpty && pack.payload.activities.allSatisfy { checked.contains($0.id) }
    }

    private func publishTitle(_ pack: LearningPackDTO) -> String {
        let remaining = pack.payload.activities.filter { !checked.contains($0.id) }.count
        if remaining > 0 { return "还有 \(remaining) 题没核对" }
        return dateConfirmed ? "确认无误，开放给布布" : "请确认上课日期"
    }

    private func load() async {
        do {
            let value = try await client.get("api/courses/\(courseID)", as: LearningCourseDetailDTO.self)
            if value.pack?.id != course?.pack?.id { checked = []; dateConfirmed = false }
            if let waiting = awaitingPack, value.pack?.id != waiting || value.state == "failed" { awaitingPack = nil }
            course = value
            errorText = nil
        } catch is CancellationError {
        } catch {
            errorText = learningErrorText(error)
        }
    }

    private nonisolated struct PublishBody: Encodable, Sendable {
        let revision: Int
        let confirmations: [Confirmation]
        let dateConfirmed: Bool
        struct Confirmation: Encodable, Sendable { let activityId: String; let digest: String; let verified: Bool }
    }
    private nonisolated struct ExcludeBody: Encodable, Sendable { let revision: Int; let activityId: String }
    private nonisolated struct Queued: Decodable, Sendable { let queued: Bool }
    private nonisolated struct Deleted: Decodable, Sendable { let deleted: Bool }

    private func publish(_ pack: LearningPackDTO) async {
        working = true; actionError = nil
        defer { working = false }
        player.stop()
        let body = PublishBody(revision: pack.revision,
                               confirmations: pack.confirmations.map { .init(activityId: $0.activityId, digest: $0.digest, verified: true) },
                               dateConfirmed: true)
        do {
            _ = try await client.send("POST", "api/packs/\(pack.id)/publish", body: body, as: LearningPackDTO.self)
            await load(); onChange()
        } catch { actionError = learningErrorText(error, fallback: "开放没有成功，请刷新后重试。") }
    }

    private func exclude(_ pack: LearningPackDTO, _ activity: LearningActivityDTO) async {
        working = true; actionError = nil
        defer { working = false }
        player.stop()
        do {
            _ = try await client.send("POST", "api/packs/\(pack.id)/exclude",
                                      body: ExcludeBody(revision: pack.revision, activityId: activity.id), as: LearningPackDTO.self)
            let keep = checked
            await load()
            checked = keep.subtracting([activity.id])
            onChange()
        } catch { actionError = learningErrorText(error, fallback: "移除没有成功，请刷新后重试。") }
    }

    private func regenerate() async {
        actionError = nil
        player.stop()
        let previous = course?.pack?.id ?? ""
        do {
            let value = try await client.send("POST", "api/courses/\(courseID)/retry", as: LearningCourseDetailDTO.self)
            course = value
            awaitingPack = previous
            actionError = "已经开始重新整理，完成后这里会自动更新。"
        } catch { actionError = learningErrorText(error) }
    }

    private func delete() async {
        do {
            _ = try await client.send("DELETE", "api/courses/\(courseID)", as: Deleted.self)
            onChange(); dismiss()
        } catch { actionError = learningErrorText(error) }
    }

    static func readableDay(_ value: String) -> String {
        guard let date = BubuLearningDates.day(value) else { return value }
        return date.formatted(.dateTime.month().day().weekday().locale(Locale(identifier: "zh_CN")))
    }

    private static func sourceState(_ state: String) -> String {
        switch state {
        case "ready": "已解析"
        case "processing": "解析中"
        case "queued": "排队中"
        case "failed", "unavailable": "解析失败"
        default: state
        }
    }
}

private struct ActivityReviewCard: View {
    let index: Int
    let activity: LearningActivityDTO
    let client: BubuLearningClient
    let player: NativeLearningAudioPlayer
    let original: String?
    @Binding var checked: Bool
    let onRemove: () -> Void
    @State private var watching = false

    var body: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            HStack {
                Text("第 \(index) 题 · \(activity.kindLabel)").font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                Spacer()
                Button("移除这题", role: .destructive, action: onRemove).font(BubuTheme.Font.caption)
            }
            Text(activity.title).font(BubuTheme.Font.headline)
            if let instruction = activity.instruction, !instruction.isEmpty {
                Text(instruction).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            if let image = activity.prompt?.imageUrl {
                LearningRemoteImage(path: image, client: client, label: "老师提问时的画面", maxHeight: 220)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
            }
            clipRow(title: "题目原声", clip: activity.prompt, isAnswer: false)
            if let original, let start = activity.prompt?.start {
                Button { player.stop(); watching = true } label: {
                    Label("看这段原片（从提问前 2 秒开始）", systemImage: "film")
                }
                .buttonStyle(.bordered).tint(BubuTheme.Color.deepRose)
                .accessibilityIdentifier("learning.review.original")
                .sheet(isPresented: $watching) {
                    LearningOriginalClipSheet(client: client, path: original, start: start,
                                              end: activity.answer?.end ?? activity.prompt?.end ?? start + 8)
                }
            }
            if activity.answer != nil { clipRow(title: "答案原声", clip: activity.answer, isAnswer: true) }
            if !activity.choices.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(activity.choices) { choice in
                        ChoiceTile(choice: choice, client: client, highlighted: choice.id == activity.correctChoice, compact: true)
                    }
                }
            }
            Toggle("我听过原声，题目和答案都对", isOn: $checked)
                .tint(BubuTheme.Color.primary)
                .font(BubuTheme.Font.body.weight(.semibold))
                .accessibilityIdentifier("learning.review.check")
            if let error = player.errorText { Text(error).font(.caption).foregroundStyle(BubuTheme.Color.danger) }
        }
        .foregroundStyle(BubuTheme.Color.warmBrown)
        .padding(BubuTheme.Spacing.item)
        .background(BubuTheme.Color.card.opacity(0.95), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            .stroke(checked ? BubuTheme.Color.primary : .clear, lineWidth: 2))
    }

    private func clipRow(title: String, clip: LearningClipDTO?, isAnswer: Bool) -> some View {
        Button {
            player.play(clip: clip, activityKind: activity.kind, isAnswer: isAnswer, client: client)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(BubuTheme.Color.deepRose)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(BubuTheme.Font.caption.weight(.bold))
                    Text("“\(clip?.text ?? "")”").font(BubuTheme.Font.body).lineLimit(3)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(BubuTheme.Color.primary)
            }
            .padding(BubuTheme.Spacing.m)
            .background(BubuTheme.Color.softFill.opacity(0.5), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isAnswer ? "learning.review.answer" : "learning.review.prompt")
    }
}

/// 家长核对用：播放老师原片中这道题前后的一段，确认问题、指物和答案对得上。
private struct LearningOriginalClipSheet: View {
    let client: BubuLearningClient
    let path: String
    let start: Double
    let end: Double
    @State private var player: AVPlayer?
    @State private var errorText: String?
    @State private var boundary: Any?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                } else if let errorText {
                    Text(errorText).foregroundStyle(.white).padding()
                } else {
                    ProgressView("正在打开原片…").tint(.white).foregroundStyle(.white)
                }
            }
            .navigationTitle("原片 \(OnlineTimelineDetailPage.timecode(start))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .task { await prepare() }
        .onDisappear {
            if let boundary { player?.removeTimeObserver(boundary) }
            player?.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func prepare() async {
        do {
            let asset = try await client.authorizedAsset(path)
            guard try await asset.load(.isPlayable) else { throw LearningServiceError.unavailableMedia }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            await player.seek(to: CMTime(seconds: max(0, start - 2), preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: .zero)
            // Pause shortly after the teacher's answer; the parent can keep watching with the controls.
            boundary = player.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: end + 1.5, preferredTimescale: 600))],
                                                      queue: .main) { [weak player] in player?.pause() }
            self.player = player
            player.play()
        } catch {
            errorText = learningErrorText(error, fallback: "原片暂时打不开，请检查网络后重试。")
        }
    }
}
