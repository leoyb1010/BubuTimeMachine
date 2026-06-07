import SwiftUI
import SwiftData
import PhotosUI

// MARK: - 首页 · 成长仪表盘
/// 专属布布的主屏：年龄实时计数 + 那年今日 + 统计 + 精选 + 大记录按钮。
/// 背景可用主题渐变或布布的照片。
struct CaptureHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]

    @State private var model: CaptureModel?

    private var profile: ChildProfile? { profiles.first }
    private var theme: BubuThemeDefinition { env.theme.theme }

    var body: some View {
        ZStack {
            heroBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    ageHeader
                    statRow
                    onThisDaySection
                    recordButton
                    recentStrip
                    Spacer(minLength: 30)
                }
                .padding()
            }

            if let model {
                Color.clear
                    .sheet(isPresented: Binding(get: { model.showQuickCapture },
                                                set: { model.showQuickCapture = $0 })) {
                        QuickCaptureSheet(model: model)
                    }
                if model.savedFlash { savedToast }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
            }
        }
        .onAppear {
            if model == nil {
                model = CaptureModel(mediaStore: env.mediaStore, analyzer: env.photoAnalyzer,
                                     role: env.config.currentRole)
            }
        }
    }

    // MARK: 背景

    @ViewBuilder
    private var heroBackground: some View {
        if env.theme.heroMode == .photo,
           let name = profile?.heroBackgroundFileName,
           let data = env.mediaStore.data(forMedia: name),
           let ui = UIImage(data: data) {
            ZStack {
                Image(uiImage: ui).resizable().scaledToFill()
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [theme.primary.opacity(0.25), .clear, theme.primary.opacity(0.15)],
                               startPoint: .top, endPoint: .bottom)
            }
        } else {
            switch theme.backgroundStyle {
            case .solid(let hex):
                Color(hex: hex)
            case .gradient(let a, let b):
                LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    // MARK: 年龄头部

    @ViewBuilder
    private var ageHeader: some View {
        if let profile {
            VStack(spacing: 8) {
                Text(profile.name)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(AgeCalculator.ageDescription(birthday: profile.birthday, at: .now))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primary)
                Text("来到世界第 \(AgeCalculator.daysSinceBirth(birthday: profile.birthday)) 天")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(.top, 8)
        } else {
            Text("布布时光机").font(BubuTheme.Font.hugeTitle)
        }
    }

    // MARK: 统计行

    private var statRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(entries.count)", label: "个瞬间", icon: "sparkles")
            statCard(value: "\(totalPhotos)", label: "张照片", icon: "photo.stack")
            if let profile {
                statCard(value: "\(AgeCalculator.daysUntilNextBirthday(birthday: profile.birthday))",
                         label: "天后生日", icon: "gift")
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(theme.primary)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(label).font(.system(size: 12)).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var totalPhotos: Int {
        entries.reduce(0) { $0 + $1.media.count }
    }

    // MARK: 那年今日

    @ViewBuilder
    private var onThisDaySection: some View {
        let memories = onThisDayEntries
        if !memories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("那年今日", systemImage: "calendar.badge.clock")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(memories) { entry in
                            NavigationLink(value: entry) {
                                onThisDayCard(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
    }

    private func onThisDayCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let media = entry.media.first {
                MediaThumbnail(media: media, mediaStore: env.mediaStore)
                    .frame(width: 130, height: 130)
            } else {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.small)
                    .fill(theme.primary.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .overlay { Text(entry.mood?.emoji ?? "📝").font(.system(size: 40)) }
            }
            if let profile {
                Text(AgeCalculator.compactAge(birthday: profile.birthday, at: entry.happenedAt))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primary)
            }
            Text(yearsAgoText(entry.happenedAt))
                .font(.system(size: 11)).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(width: 130)
    }

    /// 历史上的今天（同月同日，往年）。
    private var onThisDayEntries: [Entry] {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: .now)
        return entries.filter { entry in
            let c = cal.dateComponents([.month, .day], from: entry.happenedAt)
            let isPast = !cal.isDate(entry.happenedAt, inSameDayAs: .now)
            return c.month == today.month && c.day == today.day && isPast
        }
    }

    private func yearsAgoText(_ date: Date) -> String {
        let years = Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 0
        return years <= 0 ? "今年" : "\(years)年前的今天"
    }

    // MARK: 大记录按钮

    private var recordButton: some View {
        BigButton(title: BubuTheme.Copy.recordNow, systemImage: "heart.circle.fill") {
            model?.startQuickCapture()
        }
        .accessibilityLabel("记录此刻，可以拍照、录视频或说话")
    }

    // MARK: 最近精选

    @ViewBuilder
    private var recentStrip: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("最近的瞬间", systemImage: "clock")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(entries.prefix(8)) { entry in
                            NavigationLink(value: entry) {
                                if let media = entry.media.first {
                                    MediaThumbnail(media: media, mediaStore: env.mediaStore)
                                        .frame(width: 96, height: 96)
                                } else {
                                    RoundedRectangle(cornerRadius: BubuTheme.Radius.small)
                                        .fill(theme.primary.opacity(0.1))
                                        .frame(width: 96, height: 96)
                                        .overlay { Text(entry.mood?.emoji ?? "📝").font(.system(size: 32)) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var savedToast: some View {
        VStack {
            Label("已经收好啦", systemImage: "checkmark.circle.fill")
                .font(BubuTheme.Font.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(BubuTheme.Color.success, in: Capsule())
                .bubuCardShadow()
            Spacer()
        }
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
