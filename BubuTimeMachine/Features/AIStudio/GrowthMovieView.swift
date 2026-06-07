import SwiftUI
import SwiftData

// MARK: - 年度成长电影
/// 选一岁 → 模拟"收集素材→编排→配乐→渲染"的生成流程 → 成片占位可播放。
/// 真实部署时由服务端 ffmpeg + LLM 旁白生成，前端流程不变。
struct GrowthMovieView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ChildProfile]
    @Query(filter: #Predicate<Entry> { !$0.isArchived }) private var entries: [Entry]

    @State private var selectedYear = 0
    @State private var stageIndex = -1
    @State private var done = false
    @State private var showPlayer = false

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }

    private let stages = ["收集这一岁的精选瞬间…", "按时间编排成故事线…", "配上温柔的背景音乐…", "渲染成片…"]

    private var availableYears: [Int] {
        guard let profile else { return [0] }
        let maxAge = AgeCalculator.ageYears(birthday: profile.birthday, at: .now)
        return Array(0...max(0, maxAge))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                poster
                yearPicker
                if stageIndex >= 0 { progressArea }
                generateButton
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("年度成长电影")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPlayer) {
            GrowthMoviePlayer(
                mediaFiles: yearPhotoFiles,
                captions: yearCaptions,
                title: "《\(env.config.childName)的第 \(selectedYear) 岁》",
                mediaStore: env.mediaStore,
                tint: theme,
                onClose: { showPlayer = false })
        }
    }

    /// 该岁所有照片（按发生时间排序）的沙盒文件名。
    private var yearPhotoFiles: [String] {
        yearEntries.flatMap { entry in
            entry.media
                .filter { $0.type == .photo }
                .compactMap { $0.localFileName }
        }
    }

    /// 配合照片的旁白字幕：用记录的备注 / 心情 / 年龄生成。
    private var yearCaptions: [String] {
        var caps: [String] = []
        for entry in yearEntries {
            let photos = entry.media.filter { $0.type == .photo }
            guard !photos.isEmpty else { continue }
            let base: String
            if let note = entry.note, !note.isEmpty {
                base = note
            } else if let profile {
                base = AgeCalculator.ageDescription(birthday: profile.birthday, at: entry.happenedAt)
            } else {
                base = entry.happenedAt.formatted(date: .abbreviated, time: .omitted)
            }
            // 每张照片共用该条记录的字幕
            caps.append(contentsOf: Array(repeating: base, count: photos.count))
        }
        return caps
    }

    /// 该岁的记录，按时间正序。
    private var yearEntries: [Entry] {
        guard let profile else { return entries.sorted { $0.happenedAt < $1.happenedAt } }
        return entries
            .filter { AgeCalculator.ageYears(birthday: profile.birthday, at: $0.happenedAt) == selectedYear }
            .sorted { $0.happenedAt < $1.happenedAt }
    }

    @ViewBuilder
    private var background: some View {
        switch env.theme.theme.backgroundStyle {
        case .solid(let hex): Color(hex: hex)
        case .gradient(let a, let b):
            LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var poster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                .fill(LinearGradient(colors: [theme.opacity(0.9), theme.opacity(0.5)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(spacing: 10) {
                if done {
                    Image(systemName: "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white)
                    Text("《\(env.config.childName)的第 \(selectedYear) 岁》")
                        .font(BubuTheme.Font.title).foregroundStyle(.white)
                    Text("约 \(clipCount) 个瞬间 · 轻触播放").font(BubuTheme.Font.caption).foregroundStyle(.white.opacity(0.85))
                } else {
                    Image(systemName: "film.stack").font(.system(size: 56)).foregroundStyle(.white.opacity(0.9))
                    Text("一部属于布布的小电影").font(BubuTheme.Font.headline).foregroundStyle(.white)
                }
            }
            .padding()
        }
        .frame(height: 200)
        .bubuCardShadow()
        .contentShape(Rectangle())
        .onTapGesture { if done { showPlayer = true } }
    }

    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择哪一岁").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableYears, id: \.self) { year in
                        Button {
                            selectedYear = year; stageIndex = -1; done = false
                        } label: {
                            Text(year == 0 ? "0岁" : "\(year)岁")
                                .font(BubuTheme.Font.body.weight(.medium))
                                .foregroundStyle(selectedYear == year ? .white : BubuTheme.Color.warmBrown)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(selectedYear == year ? theme : Color.white,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var progressArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(stages.enumerated()), id: \.offset) { idx, stage in
                HStack(spacing: 12) {
                    if idx < stageIndex || done {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme)
                    } else if idx == stageIndex {
                        ProgressView().tint(theme)
                    } else {
                        Image(systemName: "circle").foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.4))
                    }
                    Text(stage)
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(idx <= stageIndex || done ? BubuTheme.Color.warmBrown : BubuTheme.Color.secondaryText)
                    Spacer()
                }
            }
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            Text(done ? "重新生成" : (stageIndex >= 0 ? "生成中…" : "开始生成这一岁的电影"))
                .font(BubuTheme.Font.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(theme, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(stageIndex >= 0 && !done)
    }

    private var clipCount: Int {
        guard let profile else { return entries.count }
        return entries.filter { AgeCalculator.ageYears(birthday: profile.birthday, at: $0.happenedAt) == selectedYear }.count
    }

    private func generate() async {
        done = false
        for i in stages.indices {
            stageIndex = i
            try? await Task.sleep(for: .milliseconds(800))
        }
        // 旁白：真实 AI 优先（用该岁记录摘要），否则温柔占位
        var narration = "这一年，布布从 \(selectedYear) 岁慢慢长大……"
        if env.config.isAIConfigured, let ai = env.aiService as? BubuAIService {
            let highlights = yearEntries.prefix(8).compactMap { $0.note }
            if let text = try? await ai.movieNarration(
                year: selectedYear, childName: env.config.childName, highlights: Array(highlights)),
               !text.isEmpty {
                narration = text
            }
        } else {
            _ = try? await env.aiService.generateGrowthMovie(year: selectedYear)
        }
        // 持久化一条 GrowthMovie 记录
        let movie = GrowthMovie(year: selectedYear)
        movie.status = "ready"
        movie.narrationScript = narration
        context.insert(movie)
        try? context.save()
        withAnimation { done = true; stageIndex = stages.count }
        // 生成完成，若该岁有照片则自动放映
        if !yearPhotoFiles.isEmpty {
            try? await Task.sleep(for: .milliseconds(400))
            showPlayer = true
        }
    }
}
