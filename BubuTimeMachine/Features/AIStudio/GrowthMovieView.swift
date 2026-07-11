import SwiftUI
import SwiftData
import AVKit

// MARK: - 年度成长电影
/// 端侧生成“电影草稿”：按年龄 / 地点 / 时间筛选真实照片，套用模板播放。
/// 配置了自托管服务器时，可再「合成高清版」——照片本就同步在家庭自己的服务器，
/// 服务端用 ffmpeg 合成真正的 mp4（Ken Burns + 交叉淡入）供播放/分享。
struct GrowthMovieView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]
    @Query(filter: #Predicate<Entry> { !$0.isArchived }) private var entries: [Entry]

    @State private var selectedTemplate: MovieTemplate = .documentary
    @State private var selectedYear: Int?
    @State private var selectedLocation: String?
    @State private var selectedRange: MovieTimeRange = .all
    @State private var stageIndex = -1
    @State private var draft: MovieDraft?
    @State private var aiNarration: String?
    @State private var showPlayer = false

    // 服务端合成态
    @State private var serverRendering = false
    @State private var serverProgress: Double = 0
    @State private var serverMovieURL: URL?
    @State private var serverHint = ""
    @State private var showServerPlayer = false

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }
    private let stages = ["筛选照片素材…", "整理时间和地点…", "套用电影模板…", "生成片头和字幕…"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                introCard
                templatePicker
                filterCard
                materialPreview
                if stageIndex >= 0 { progressArea }
                actionButtons
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("年度成长电影")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPlayer) {
            if let draft {
                GrowthMoviePlayer(draft: draft, mediaStore: env.mediaStore, tint: theme) {
                    showPlayer = false
                }
            }
        }
        .fullScreenCover(isPresented: $showServerPlayer) {
            if let serverMovieURL {
                ServerMoviePlayer(url: serverMovieURL, title: draftTitle) { showServerPlayer = false }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var introCard: some View {
        HStack(spacing: 14) {
            BubuMascotBadge(size: 62, expression: .tv)
            VStack(alignment: .leading, spacing: 5) {
                Text(draft == nil ? "做一支布布的小电影" : "电影草稿已准备好")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(draft == nil ? "先选模板，再按年龄、地点和时间挑照片。生成后可以预览播放，不会被旧记录背景干扰。" : "可以先播放看看，不满意就换模板或筛选条件重新生成。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择模板")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(MovieTemplate.allCases) { template in
                    Button {
                        selectedTemplate = template
                        draft = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(template.emoji).font(.system(size: 28))
                            Text(template.title)
                                .font(BubuTheme.Font.caption.weight(.semibold))
                                .foregroundStyle(BubuTheme.Color.warmBrown)
                            Text(template.subtitle)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(selectedTemplate == template ? theme.opacity(0.14) : BubuTheme.Color.card,
                                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous)
                                .stroke(selectedTemplate == template ? theme : BubuTheme.Color.hairline.opacity(0.45), lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("筛选素材", icon: "slider.horizontal.3")
            chipRow(title: "年龄") {
                FilterChip(title: "全部年龄", selected: selectedYear == nil, tint: theme) { selectedYear = nil; draft = nil }
                ForEach(availableYears, id: \.self) { year in
                    FilterChip(title: year == 0 ? "0岁" : "\(year)岁", selected: selectedYear == year, tint: theme) {
                        selectedYear = year; draft = nil
                    }
                }
            }
            chipRow(title: "地点") {
                FilterChip(title: "全部地点", selected: selectedLocation == nil, tint: theme) { selectedLocation = nil; draft = nil }
                ForEach(availableLocations, id: \.self) { location in
                    FilterChip(title: location, selected: selectedLocation == location, tint: theme) {
                        selectedLocation = location; draft = nil
                    }
                }
            }
            chipRow(title: "时间") {
                ForEach(MovieTimeRange.allCases) { range in
                    FilterChip(title: range.title, selected: selectedRange == range, tint: theme) {
                        selectedRange = range; draft = nil
                    }
                }
            }
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func chipRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
            }
        }
    }

    private var materialPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("将用于电影的素材", icon: "photo.stack")
                Spacer()
                Text("\(selectedPhotoFiles.count) 张")
                    .font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(theme)
            }
            if selectedPhotoFiles.isEmpty {
                HStack(spacing: 12) {
                    BubuMascotBadge(size: 52, expression: .bye)
                    Text("当前筛选下没有照片。可以换成全部年龄/全部地点，或先去时光轴补几张照片。")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(selectedPreviewMedia.prefix(6)) { media in
                        MediaThumbnail(media: media, mediaStore: env.mediaStore)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 86)
                            .clipped()
                    }
                }
            }
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var progressArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(stages.enumerated()), id: \.offset) { idx, stage in
                HStack(spacing: 10) {
                    if idx < stageIndex || draft != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme) }
                    else if idx == stageIndex { ProgressView().tint(theme) }
                    else { Image(systemName: "circle").foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.45)) }
                    Text(stage).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.warmBrown)
                    Spacer()
                }
            }
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await generateDraft() }
            } label: {
                Text(stageIndex >= 0 && draft == nil ? "生成中…" : (draft == nil ? "生成电影草稿" : "重新生成草稿"))
                    .font(BubuTheme.Font.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(selectedPhotoFiles.isEmpty ? BubuTheme.Color.secondaryText.opacity(0.35) : theme, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedPhotoFiles.isEmpty || (stageIndex >= 0 && draft == nil))

            if draft != nil {
                Button { showPlayer = true } label: {
                    Label("播放电影", systemImage: "play.circle.fill")
                        .font(BubuTheme.Font.headline.weight(.bold))
                        .foregroundStyle(theme)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(theme.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)

                // 配了服务器才出「合成高清版」：真正的 mp4，可存可分享
                if env.config.isAIConfigured {
                    Button { Task { await renderOnServer() } } label: {
                        Label(serverRendering
                              ? "服务端合成中… \(Int(serverProgress * 100))%"
                              : "合成高清版 · 服务端",
                              systemImage: serverRendering ? "gearshape.2.fill" : "film.fill")
                            .font(BubuTheme.Font.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(theme, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(serverRendering)

                    if let url = serverMovieURL ?? Self.existingMovie(
                        year: selectedYear ?? Calendar.current.component(.year, from: .now)) {
                        Button {
                            serverMovieURL = url
                            showServerPlayer = true
                        } label: {
                            Label("播放高清版", systemImage: "sparkles.tv.fill")
                                .font(BubuTheme.Font.headline.weight(.bold))
                                .foregroundStyle(theme)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(theme.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if !serverHint.isEmpty {
                        Text(serverHint)
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// 服务端合成成片：收集已同步照片的远端 URL → 提交渲染 → 轮询 → 下载播放。
    /// 轮询抗抖动：单次失败重试，连续 3 次才放弃；成片落 Documents，可随时重看（R4 P2-25/26）。
    private func renderOnServer() async {
        let photos = remoteMoviePhotos
        guard !photos.isEmpty else {
            serverHint = "这些照片还没同步到服务器，先联网同步后再合成高清版～"
            return
        }
        serverHint = ""; serverRendering = true; serverProgress = 0
        defer { serverRendering = false }
        let year = selectedYear ?? Calendar.current.component(.year, from: .now)
        do {
            var status = try await env.aiService.startMovieRender(
                childName: env.config.childName, year: year,
                template: selectedTemplate.rawValue, photos: photos, narration: aiNarration ?? "")
            var polls = 0
            var consecutiveFailures = 0
            while !status.ready && status.status != "failed" && polls < 300 {
                try await Task.sleep(for: .seconds(2))
                do {
                    status = try await env.aiService.movieRenderStatus(jobId: status.jobId)
                    consecutiveFailures = 0
                    serverProgress = status.progress
                } catch {
                    // 一次网络抖动不弃剧：连续 3 次失败才放弃
                    consecutiveFailures += 1
                    if consecutiveFailures >= 3 { throw error }
                }
                polls += 1
            }
            guard status.ready else {
                serverHint = status.status == "failed"
                    ? (status.error.isEmpty ? "服务端合成失败，稍后再试" : status.error)
                    : "还在合成中，稍后回到这里再试一次就能取到成片。"
                return
            }
            let tempURL = try await env.aiService.downloadRenderedMovie(jobId: status.jobId)
            serverMovieURL = Self.persistMovie(tempURL, year: year)
            showServerPlayer = true
        } catch {
            serverHint = "服务端合成暂不可用：\(error.localizedDescription)"
        }
    }

    /// 成片移入 Documents（看完不再即丢，重进页面也能直接播）。
    private static func persistMovie(_ tempURL: URL, year: Int) -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent("bubu_movie_\(year).mp4")
        try? fm.removeItem(at: dest)
        if (try? fm.moveItem(at: tempURL, to: dest)) != nil { return dest }
        return tempURL
    }

    /// 本年度已有成片就带出来（跨会话重看）。
    private static func existingMovie(year: Int) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("bubu_movie_\(year).mp4")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 已同步（有远端 URL）的照片 + 对齐的文案，供服务端合成。
    private var remoteMoviePhotos: [MovieRenderPhoto] {
        let caps = buildCaptions()
        return zip(selectedPreviewMedia, caps).compactMap { media, cap in
            guard let u = media.remoteURL, !u.isEmpty else { return nil }
            return MovieRenderPhoto(url: u, caption: cap)
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(BubuTheme.Font.headline)
            .foregroundStyle(BubuTheme.Color.warmBrown)
    }

    private var availableYears: [Int] {
        guard let profile else { return [] }
        return Array(Set(entries.map { AgeCalculator.ageYears(birthday: profile.birthday, at: $0.happenedAt) })).sorted()
    }

    private var availableLocations: [String] {
        Array(Set(entries.compactMap(\.locationName))).sorted().prefix(8).map { $0 }
    }

    private var filteredEntries: [Entry] {
        entries.filter { entry in
            let yearOK: Bool = {
                guard let selectedYear, let profile else { return true }
                return AgeCalculator.ageYears(birthday: profile.birthday, at: entry.happenedAt) == selectedYear
            }()
            let locationOK = selectedLocation == nil || entry.locationName == selectedLocation
            let rangeOK: Bool = {
                guard let start = selectedRange.startDate else { return true }
                return entry.happenedAt >= start
            }()
            return yearOK && locationOK && rangeOK
        }
        .sorted { $0.happenedAt < $1.happenedAt }
    }

    private var selectedPreviewMedia: [Media] {
        filteredEntries.flatMap { $0.media.filter { $0.type == .photo && $0.localFileName != nil } }
    }

    private var selectedPhotoFiles: [String] {
        selectedPreviewMedia.compactMap(\.localFileName)
    }

    private func generateDraft() async {
        guard !selectedPhotoFiles.isEmpty else { return }
        draft = nil
        for i in stages.indices {
            stageIndex = i
            try? await Task.sleep(for: .milliseconds(420))
        }
        let title = draftTitle
        var captions = buildCaptions()
        if env.config.isAIConfigured {
            let highlights = Array(Set(captions.filter { !$0.isEmpty })).prefix(8).map { String($0) }
            if let narration = try? await env.aiService.movieNarration(
                year: selectedYear ?? Calendar.current.component(.year, from: .now),
                childName: env.config.childName,
                highlights: highlights
            ), !narration.isEmpty {
                aiNarration = narration
                captions = distributeNarration(narration, count: selectedPhotoFiles.count)
            }
        }
        withAnimation(.smooth) {
            draft = MovieDraft(title: title, template: selectedTemplate, mediaFiles: selectedPhotoFiles, captions: captions, narration: aiNarration)
            stageIndex = -1
        }
    }

    private var draftTitle: String {
        let base = selectedYear.map { "第 \($0) 岁" } ?? selectedRange.title
        let place = selectedLocation.map { " · \($0)" } ?? ""
        return "《\(env.config.childName)的\(base)\(place)》"
    }

    private func buildCaptions() -> [String] {
        var caps: [String] = []
        for entry in filteredEntries {
            let count = entry.media.filter { $0.type == .photo && $0.localFileName != nil }.count
            guard count > 0 else { continue }
            let text = entry.note?.isEmpty == false ? entry.note! : BubuDateFormat.shortDate(entry.happenedAt)
            caps.append(contentsOf: Array(repeating: text, count: count))
        }
        return caps
    }

    private func distributeNarration(_ narration: String, count: Int) -> [String] {
        guard count > 0 else { return [] }
        let sentences = narration
            .split(whereSeparator: { "。！？!?\n".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !sentences.isEmpty else { return Array(repeating: narration, count: count) }
        return (0..<count).map { sentences[$0 % sentences.count] }
    }
}

struct MovieDraft: Identifiable {
    let id = UUID()
    let title: String
    let template: MovieTemplate
    let mediaFiles: [String]
    let captions: [String]
    var narration: String?
}

enum MovieTemplate: String, CaseIterable, Identifiable {
    case documentary, travel, birthday, daily
    var id: String { rawValue }
    var title: String { switch self { case .documentary: "温柔纪录片"; case .travel: "出门旅行"; case .birthday: "生日回顾"; case .daily: "日常碎片" } }
    var subtitle: String { switch self { case .documentary: "按时间慢慢讲"; case .travel: "适合公园和外出"; case .birthday: "更有仪式感"; case .daily: "短节奏、多照片" } }
    var emoji: String { switch self { case .documentary: "🎬"; case .travel: "🧳"; case .birthday: "🎂"; case .daily: "✨" } }
}

// MARK: - 服务端成片播放器（AVKit + 分享）
private struct ServerMoviePlayer: View {
    let url: URL
    let title: String
    let onClose: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
            }
            VStack {
                HStack {
                    Button { player?.pause(); onClose() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear { player = AVPlayer(url: url) }
        .onDisappear { player?.pause() }
    }
}

enum MovieTimeRange: String, CaseIterable, Identifiable {
    case all, recent3Months, recentYear
    var id: String { rawValue }
    var title: String { switch self { case .all: "全部时间"; case .recent3Months: "最近3个月"; case .recentYear: "最近1年" } }
    var startDate: Date? {
        switch self {
        case .all: nil
        case .recent3Months: Calendar.current.date(byAdding: .month, value: -3, to: .now)
        case .recentYear: Calendar.current.date(byAdding: .year, value: -1, to: .now)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : BubuTheme.Color.warmBrown)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? tint : BubuTheme.Color.softFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
