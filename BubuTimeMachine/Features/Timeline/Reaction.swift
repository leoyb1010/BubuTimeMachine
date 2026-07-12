import SwiftUI
import SwiftData

// MARK: - 亲一下 · 轻量反应（Wave K §4.1）
/// 适老化的互动形式：姥姥可能不打字，但一定会点亲亲。
///
/// **零迁移设计**：复用现有 `Comment` 模型与同步链路，反应是一条 `text` 以哨兵前缀开头的 Comment
/// （`\u{1}RXN:❤️`）。这样无需新增数据库列 / DTO 字段 / 服务端迁移，三台手机现成同步。
/// 同一人同一条只保留最新反应（插入前先删旧）。
enum Reaction: String, CaseIterable, Identifiable, Sendable {
    case heart = "❤️"
    case hug = "🤗"
    case laugh = "😂"
    case moved = "😭"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .heart: return "亲亲"
        case .hug: return "抱抱"
        case .laugh: return "笑死"
        case .moved: return "感动"
        }
    }

    private static let sentinel = "\u{1}RXN:"

    /// 把反应编码进 Comment.text。
    var encodedText: String { Self.sentinel + rawValue }

    /// 从 Comment.text 还原反应（非反应则返回 nil）。
    static func decode(_ text: String?) -> Reaction? {
        guard let text, text.hasPrefix(sentinel) else { return nil }
        let raw = String(text.dropFirst(sentinel.count))
        return Reaction(rawValue: raw)
    }

    /// 判断一条 Comment 是否是反应（用于在合奏区里过滤掉，不当普通评论显示）。
    static func isReaction(_ comment: Comment) -> Bool {
        decode(comment.text) != nil
    }
}

// MARK: - 反应聚合
struct ReactionSummary {
    /// 每种反应的计数（去重：同一作者同一反应只算一次，取其最新）。
    let counts: [Reaction: Int]
    /// 当前身份已选的反应。
    let mine: Reaction?

    var isEmpty: Bool { counts.values.allSatisfy { $0 == 0 } }

    /// 从一条 Entry 的 comments 聚合。
    static func from(_ comments: [Comment], myRole: String) -> ReactionSummary {
        // 每个作者只保留最新一条反应。
        var latestByAuthor: [String: (Date, Reaction)] = [:]
        for c in comments {
            guard let r = Reaction.decode(c.text) else { continue }
            if let existing = latestByAuthor[c.authorRole], existing.0 >= c.createdAt { continue }
            latestByAuthor[c.authorRole] = (c.createdAt, r)
        }
        var counts: [Reaction: Int] = [:]
        for (_, value) in latestByAuthor { counts[value.1, default: 0] += 1 }
        return ReactionSummary(counts: counts, mine: latestByAuthor[myRole]?.1)
    }
}

// MARK: - 反应聚合行（卡片/详情元信息行尾）
struct ReactionRow: View {
    let summary: ReactionSummary

    var body: some View {
        if !summary.isEmpty {
            HStack(spacing: 8) {
                ForEach(Reaction.allCases) { r in
                    if let n = summary.counts[r], n > 0 {
                        HStack(spacing: 2) {
                            Text(r.rawValue).font(BubuTheme.Font.scaled(13))
                            Text("\(n)").font(BubuTheme.Font.caption.weight(.medium))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(BubuTheme.Color.softFill, in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - 长按弹出的反应选择条
struct ReactionPicker: View {
    let current: Reaction?
    let onPick: (Reaction) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Reaction.allCases) { r in
                Button {
                    onPick(r)
                } label: {
                    Text(r.rawValue)
                        .font(BubuTheme.Font.scaled(30))
                        .scaleEffect(current == r ? 1.25 : 1.0)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(BubuTheme.Color.elevatedCard, in: Capsule())
        .bubuCardShadow()
    }
}
