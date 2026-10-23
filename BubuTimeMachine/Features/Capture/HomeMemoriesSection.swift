import SwiftUI

nonisolated struct MemoryCardDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String
    let coverId: String?
    let coverUrl: String?
    /// ~900px card cover (server 2.27+); falls back to the full-size cover.
    var cardUrl: String? = nil
    let itemIds: [String]
    let count: Int

    var symbol: String {
        switch kind {
        case "on_this_day": "calendar.badge.clock"
        case "family": "person.2.fill"
        case "trip": "airplane"
        default: "sparkles"
        }
    }
    var label: String {
        switch kind {
        case "on_this_day": "那年今天"
        case "family": "和家人"
        case "trip": "去过的地方"
        default: "主题回忆"
        }
    }

    /// 卡片上的小标签。「那年今天」的标题本来就是「1年前的今天」，标签再写一遍是重复，
    /// 改成那一年（从副标题「2025年10月20日–25日 · 5个瞬间」取年份）。
    var chipLabel: String {
        guard kind == "on_this_day" else { return label }
        let digits = subtitle.prefix { $0.isNumber }
        if digits.count == 4, subtitle.dropFirst(4).first == "年" { return "\(digits)年" }
        return label
    }

    /// 服务端副标题已经带了张数（「· 5个瞬间」），客户端不再拼计数。
    var displaySubtitle: String {
        subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct MemoryCardList: Decodable, Sendable { let items: [MemoryCardDTO] }

// MARK: - 首页：今天的回忆 + 生日倒计时
/// 回忆来自第二大脑（那年今天 / 和家人 / 旅行 / 主题，每条至少 5 张，按日期稳定轮换），
/// 本机的「那年今天」家人记录并进同一条轮播；生日倒计时只用本机档案里的生日。
/// 数据由首页的 `HomeTodayModel` 拉取，这里只负责展示：首次加载时放同尺寸骨架，不把下方内容顶开。
struct HomeMemoriesSection: View {
    let model: HomeTodayModel
    let client: BubuLearningClient?
    let birthday: Date?
    let childName: String
    let localOnThisDay: [Entry]
    let zoomNS: Namespace.ID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var opened: MemoryCardDTO?

    /// 父视图据此决定是否给本区留位置（没内容时不占 VStack 间距）。
    static func hasContent(model: HomeTodayModel, client: BubuLearningClient?, birthday: Date?, localOnThisDay: [Entry]) -> Bool {
        BirthdayCountdown(birthday: birthday) != nil || !localOnThisDay.isEmpty
            || (client != nil && (model.isLoading || !model.memories.isEmpty))
    }

    private var cardSize: CGSize {
        BubuAdaptive.isWide(sizeClass) ? CGSize(width: 280, height: 340) : CGSize(width: 240, height: 300)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            if let countdown = BirthdayCountdown(birthday: birthday) {
                // Two weeks out, the countdown becomes the way into the birthday film.
                if client != nil && countdown.days <= 14 {
                    NavigationLink { BirthdayFilmView() } label: { countdownCard(countdown) }
                        .buttonStyle(BubuPressableStyle())
                } else {
                    countdownCard(countdown)
                }
            }
            if showsCarousel {
                HomeSectionHeader(title: "今天的回忆") {
                    if !localOnThisDay.isEmpty {
                        NavigationLink { OnThisDayView() } label: { HomeSectionActionLabel(title: "那年今天") }
                            .buttonStyle(.plain)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: BubuTheme.Spacing.m) {
                        if model.memories.isEmpty && model.isLoading && client != nil {
                            ForEach(0..<2, id: \.self) { _ in
                                BubuSkeletonBlock(cornerRadius: BubuTheme.Radius.card, height: cardSize.height)
                                    .frame(width: cardSize.width)
                            }
                        }
                        if let client {
                            ForEach(model.memories) { memory in
                                Button { opened = memory } label: {
                                    MemoryCard(memory: memory, client: client, size: cardSize)
                                }
                                .buttonStyle(BubuPressableStyle())
                                .bubuCarouselTransition()
                                .accessibilityIdentifier("home.memory")
                            }
                        }
                        ForEach(localOnThisDay) { entry in
                            NavigationLink(value: entry.id) {
                                LocalMemoryCard(entry: entry, birthday: birthday, mediaStore: env.mediaStore, size: cardSize)
                            }
                            .buttonStyle(BubuPressableStyle())
                            .matchedTransitionSource(id: entry.id, in: zoomNS)
                            .bubuCarouselTransition()
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .transition(BubuMotion.entering(reduceMotion: reduceMotion))
            }
        }
        .animation(BubuMotion.allowed(BubuMotion.gentle, reduceMotion: reduceMotion), value: model.memories)
        .navigationDestination(item: $opened) { memory in
            if let client { MemoryDetailView(memory: memory, client: client) }
        }
    }

    private var showsCarousel: Bool {
        !localOnThisDay.isEmpty || (client != nil && (model.isLoading || !model.memories.isEmpty))
    }

    private func countdownCard(_ countdown: BirthdayCountdown) -> some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            Text("🎂").font(BubuTheme.Font.title)
                .bubuBreathingWiggle()
            VStack(alignment: .leading, spacing: 2) {
                Text(countdown.days == 0 ? "\(childName) \(countdown.age) 岁生日快乐！" : "距离\(childName) \(countdown.age) 岁生日还有 \(countdown.days) 天")
                    .font(BubuTheme.Font.body.weight(.bold)).foregroundStyle(BubuTheme.Color.warmBrown)
                Text(countdown.days == 0 ? "今天的每一张照片都值得收藏" : "可以开始悄悄准备惊喜啦")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer(minLength: 0)
            Text("\(countdown.days)").font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.deepRose)
                .contentTransition(.numericText())
                .opacity(countdown.days == 0 ? 0 : 1)
        }
        .padding(BubuTheme.Spacing.item)
        .background(LinearGradient(colors: [BubuTheme.Color.pinkSurface, BubuTheme.Color.butterSurface],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.birthday-countdown")
    }
}

/// Shown from 60 days before a birthday through the day itself.
struct BirthdayCountdown: Equatable {
    let age: Int
    let days: Int

    init?(birthday: Date?, now: Date = .now, calendar: Calendar = .current) {
        guard let birthday else { return nil }
        let today = calendar.startOfDay(for: now)
        let born = calendar.dateComponents([.year, .month, .day], from: birthday)
        let year = calendar.component(.year, from: today)
        guard var next = calendar.date(from: DateComponents(year: year, month: born.month, day: born.day)) else { return nil }
        if next < today { next = calendar.date(byAdding: .year, value: 1, to: next) ?? next }
        let days = calendar.dateComponents([.day], from: today, to: next).day ?? 999
        let age = calendar.component(.year, from: next) - (born.year ?? year)
        guard age >= 1, days <= 60 else { return nil }
        self.age = age
        self.days = days
    }
}

private struct MemoryCard: View {
    let memory: MemoryCardDTO
    let client: BubuLearningClient
    let size: CGSize

    var body: some View {
        HomeMemoryCardFrame(chip: memory.chipLabel, symbol: memory.symbol,
                            title: memory.title, subtitle: memory.displaySubtitle, size: size) {
            if let cover = memory.cardUrl ?? memory.coverUrl {
                LearningRemoteImage(path: cover, client: client, label: memory.title, contentMode: .fill, diskCache: true)
            } else {
                BubuTheme.Color.pinkSurface
            }
        }
    }
}

/// 本机的「那年今天」家人记录：和第二大脑回忆同一种卡面。
private struct LocalMemoryCard: View {
    let entry: Entry
    let birthday: Date?
    let mediaStore: MediaStore
    let size: CGSize

    var body: some View {
        let cal = Calendar.current
        let year = cal.component(.year, from: entry.happenedAt)
        let years = cal.component(.year, from: .now) - year
        HomeMemoryCardFrame(chip: "\(year)年", symbol: "calendar.badge.clock",
                            title: years <= 0 ? "今年的今天" : "\(years)年前的今天",
                            subtitle: subtitle, size: size) {
            if let media = entry.coverMedia {
                MediaThumbnail(media: media, mediaStore: mediaStore, cornerRadius: 0)
            } else {
                BubuTheme.Color.pinkSurface
                    .overlay { Text(entry.mood?.emoji ?? "📝").font(BubuTheme.Font.scaled(44)) }
            }
        }
    }

    private var subtitle: String {
        let note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !note.isEmpty { return note }
        guard let birthday else { return "家人记录" }
        return "那时 " + AgeCalculator.compactAge(birthday: birthday, at: entry.happenedAt)
    }
}

private struct HomeMemoryCardFrame<Cover: View>: View {
    let chip: String
    let symbol: String
    let title: String
    let subtitle: String
    let size: CGSize
    @ViewBuilder var cover: Cover

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay { cover }
                .clipped()
            // Fixed dark ink: warmBrown turns cream in dark mode and would wash out the white text.
            LinearGradient(colors: [.clear, BubuTheme.Color.paperInk.opacity(0.78)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HomePhotoChip(text: chip, symbol: symbol)
                Text(title).font(BubuTheme.Font.headline).foregroundStyle(.white).lineLimit(2)
                // 副标题完整显示：最多两行，再不够才轻微缩字，不出省略号。
                Text(subtitle).font(BubuTheme.Font.caption)
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BubuTheme.Spacing.m)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .shadow(color: BubuTheme.Color.deepRose.opacity(0.15), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// A memory's photos as a grid; tapping opens the same detail pager as 时光.
struct MemoryDetailView: View {
    let memory: MemoryCardDTO
    let client: BubuLearningClient

    var body: some View {
        OnlineItemsGridView(client: client, ids: memory.itemIds, title: memory.label) {
            VStack(alignment: .leading, spacing: 4) {
                Label(memory.chipLabel, systemImage: memory.symbol).font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.primaryInk)
                Text(memory.title).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                Text(memory.subtitle).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
    }
}
