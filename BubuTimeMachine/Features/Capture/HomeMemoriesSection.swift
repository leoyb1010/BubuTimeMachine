import SwiftUI

nonisolated struct MemoryCardDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String
    let coverId: String?
    let coverUrl: String?
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
}

nonisolated struct MemoryCardList: Decodable, Sendable { let items: [MemoryCardDTO] }

// MARK: - 首页：回忆轮播 + 生日倒计时
/// 回忆来自第二大脑（那年今天 / 和家人 / 旅行 / 主题，每条至少 5 张，按日期稳定轮换）；
/// 生日倒计时只用本机档案里的生日。未连接家庭服务时只显示倒计时。
struct HomeMemoriesSection: View {
    let birthday: Date?
    let childName: String
    @Environment(AppEnvironment.self) private var env
    @State private var memories: [MemoryCardDTO] = []
    @State private var opened: MemoryCardDTO?

    var body: some View {
        let client = BubuLearningClient(env: env)
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            if let countdown = BirthdayCountdown(birthday: birthday) {
                countdownCard(countdown)
            }
            if let client, !memories.isEmpty {
                HStack {
                    Text("今天的回忆").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: BubuTheme.Spacing.m) {
                        ForEach(memories) { memory in
                            Button { opened = memory } label: { MemoryCard(memory: memory, client: client) }
                                .buttonStyle(BubuPressableStyle())
                                .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                                    view.scaleEffect(1 - abs(phase.value) * 0.06).opacity(1 - abs(phase.value) * 0.25)
                                }
                                .accessibilityIdentifier("home.memory")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .task(id: client?.scope) {
            guard let client else { memories = []; return }
            let today = BubuLearningDates.dayString(.now)
            let list = try? await client.get("api/memories", query: [URLQueryItem(name: "date", value: today)], as: MemoryCardList.self)
            withAnimation(BubuMotion.gentle) { memories = list?.items ?? [] }
        }
        .navigationDestination(item: $opened) { memory in
            if let client { MemoryDetailView(memory: memory, client: client) }
        }
    }

    private func countdownCard(_ countdown: BirthdayCountdown) -> some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            Text("🎂").font(BubuTheme.Font.title)
                .phaseAnimator([0.0, 1.0]) { view, phase in view.rotationEffect(.degrees(phase * 8 - 4)) }
                    animation: { _ in BubuMotion.breathe }
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay {
                    if let cover = memory.coverUrl {
                        LearningRemoteImage(path: cover, client: client, label: memory.title, contentMode: .fill, diskCache: true)
                    } else {
                        BubuTheme.Color.pinkSurface
                    }
                }
                .clipped()
            LinearGradient(colors: [.clear, BubuTheme.Color.warmBrown.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Label(memory.label, systemImage: memory.symbol)
                    .font(BubuTheme.Font.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.85), in: Capsule())
                    .foregroundStyle(BubuTheme.Color.deepRose)
                Text(memory.title).font(BubuTheme.Font.headline).foregroundStyle(.white).lineLimit(2)
                Text("\(memory.subtitle) · \(memory.count) 张").font(BubuTheme.Font.caption)
                    .foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            }
            .padding(BubuTheme.Spacing.m)
        }
        .frame(width: 236, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .shadow(color: BubuTheme.Color.deepRose.opacity(0.15), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// A memory's photos as a grid; tapping opens the same detail pager as 时光.
struct MemoryDetailView: View {
    let memory: MemoryCardDTO
    let client: BubuLearningClient
    @State private var items: [OnlineTimelineItem] = []
    @State private var selected: OnlineTimelineItem?
    @State private var failed = false
    @State private var loaded = false
    @Namespace private var zoom

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(memory.label, systemImage: memory.symbol).font(BubuTheme.Font.caption.weight(.bold))
                            .foregroundStyle(BubuTheme.Color.deepRose)
                        Text(memory.title).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(memory.subtitle).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    if failed {
                        Text("回忆暂时打不开，请稍后再试。").font(BubuTheme.Font.body)
                    } else if !loaded {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if items.isEmpty {
                        Text("这组回忆里的照片已经移出布布的时光了。").font(BubuTheme.Font.body)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button { selected = item } label: {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                                    .overlay { LearningRemoteImage(path: item.previewUrl, client: client, label: item.description, contentMode: .fill, diskCache: true) }
                                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                            }
                            .buttonStyle(BubuPressableStyle())
                            .matchedTransitionSource(id: item.id, in: zoom)
                            .entranceEffect(index: index)
                        }
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(900)
            }
        }
        .navigationTitle(memory.label)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { item in
            OnlineTimelineDetailPager(client: client, items: items, initial: item, loadMore: {}, hasMore: false)
                .navigationTransition(.zoom(sourceID: item.id, in: zoom))
        }
        .task {
            let ids = memory.itemIds.prefix(60).joined(separator: ",")
            do {
                items = try await client.get("api/online-timeline/items", query: [URLQueryItem(name: "ids", value: ids)],
                                             as: OnlineTimelineItems.self).items
            } catch { failed = true }
            loaded = true
        }
    }
}
