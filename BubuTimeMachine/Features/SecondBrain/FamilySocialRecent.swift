import SwiftUI

// MARK: - 家人最近的小红心和留言（GET social/recent，契约 2.27）

nonisolated struct SocialRecentItemDTO: Decodable, Sendable, Hashable, Identifiable {
    let itemId: String
    let author: String?
    let text: String?
    let kind: String
    let createdAt: String?
    let previewUrl: String?

    var isHeart: Bool { kind == "heart" }
    var authorName: String {
        let name = (author ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "家人" : name
    }
    var date: Date? { createdAt.flatMap(BubuLearningDates.parseISO) }
    var id: String { [kind, itemId, authorName, createdAt ?? "", text ?? ""].joined(separator: "|") }
}
nonisolated struct SocialRecentList: Decodable, Sendable { let items: [SocialRecentItemDTO] }

nonisolated enum FamilySocialSummary {
    /// "姥姥给 3 张照片点了心 · 妈妈留了 2 句话": per person, in order of their latest activity, at most three parts.
    static func line(_ items: [SocialRecentItemDTO]) -> String? {
        var order: [String] = []
        var hearts: [String: Set<String>] = [:]
        var comments: [String: Int] = [:]
        for item in items {
            let name = item.authorName
            if !order.contains(name) { order.append(name) }
            if item.isHeart { hearts[name, default: []].insert(item.itemId) } else { comments[name, default: 0] += 1 }
        }
        var parts: [String] = []
        for name in order {
            var pieces: [String] = []
            if let count = hearts[name]?.count, count > 0 { pieces.append("给 \(count) 张照片点了心") }
            if let count = comments[name], count > 0 { pieces.append("留了 \(count) 句话") }
            guard !pieces.isEmpty else { continue }
            parts.append(name + pieces.joined(separator: "，"))
            if parts.count == 3 { break }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Top of 家人动态: the latest hearts and comments left on 布布's online timeline. Hidden when the
/// family service isn't connected, is too old for this endpoint, or nobody has said anything yet.
/// The host owns `route` and its `navigationDestination` (this section usually lives in a lazy stack).
struct FamilySocialRecentSection: View {
    @Binding var route: TimelinePagerRoute?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [SocialRecentItemDTO] = []
    @State private var opening: String?
    @State private var errorText: String?

    static let visibleRows = 6

    var body: some View {
        let client = BubuLearningClient(env: env)
        Group {
            if let client, !items.isEmpty {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
                    HStack(spacing: BubuTheme.Spacing.s) {
                        Image(systemName: "heart.text.square.fill").foregroundStyle(BubuTheme.Color.primary)
                        Text("照片下的悄悄话").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                    }
                    .accessibilityAddTraits(.isHeader)
                    if let line = FamilySocialSummary.line(items) {
                        Text(line).font(BubuTheme.Font.caption.weight(.semibold)).foregroundStyle(BubuTheme.Color.deepRose)
                    }
                    ForEach(Array(items.prefix(Self.visibleRows).enumerated()), id: \.element.id) { index, item in
                        row(item, client: client).entranceEffect(index: index)
                    }
                    if let errorText {
                        Text(errorText).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger)
                    }
                }
                .padding(BubuTheme.Spacing.item)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier("feed.social-recent")
            }
        }
        .task(id: client?.scope) {
            guard let client else { items = []; return }
            guard let list = try? await client.get("api/social/recent", query: [URLQueryItem(name: "limit", value: "20")],
                                                   as: SocialRecentList.self) else { return }
            withAnimation(reduceMotion ? nil : BubuMotion.gentle) { items = list.items }
        }
    }

    private func row(_ item: SocialRecentItemDTO, client: BubuLearningClient) -> some View {
        Button { Task { await open(item, client: client) } } label: {
            HStack(spacing: BubuTheme.Spacing.m) {
                Group {
                    if let preview = item.previewUrl, !preview.isEmpty {
                        LearningRemoteImage(path: preview, client: client, label: "布布的照片", contentMode: .fill, diskCache: true)
                    } else {
                        Image(systemName: "photo").foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: item.isHeart ? "heart.fill" : "text.bubble.fill")
                        .font(BubuTheme.Font.scaled(11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(item.isHeart ? BubuTheme.Color.actionFill : BubuTheme.Color.actionFillDeep, in: Circle())
                        .offset(x: 4, y: 4)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if item.isHeart {
                        Text("\(item.authorName) 送了一颗小红心").font(BubuTheme.Font.body.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                    } else {
                        Text(item.authorName).font(BubuTheme.Font.caption.weight(.bold)).foregroundStyle(BubuTheme.Color.deepRose)
                        Text(item.text ?? "").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown).lineLimit(2)
                    }
                    if let date = item.date {
                        Text(BubuDateFormat.shortDateTime(date)).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                if opening == item.itemId {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right").font(BubuTheme.Font.caption.weight(.bold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BubuPressableStyle())
        .disabled(opening != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开这张照片")
    }

    private func open(_ item: SocialRecentItemDTO, client: BubuLearningClient) async {
        guard opening == nil else { return }
        opening = item.itemId
        defer { opening = nil }
        do {
            if let found = try await client.timelineItems(ids: [item.itemId]).first {
                BubuHaptics.selection()
                errorText = nil
                route = TimelinePagerRoute(items: [found], initial: found)
            } else {
                errorText = "这张照片已经不在布布的时光里了。"
            }
        } catch {
            errorText = learningErrorText(error)
        }
    }
}
