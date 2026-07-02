import Foundation
import SwiftData

// MARK: - 成长绘本章节（派生模型，不入库）
/// 对照设计稿「布布的故事 / 成长绘本」：把已达成、有「那一天的故事」(Milestone.detail) 的里程碑
/// 按时间编织成可翻页阅读的章节。纯派生——不新增 @Model、不写库，数据随里程碑实时变化。
struct StoryChapter: Identifiable, Hashable {
    let id: UUID
    let number: Int          // 第几章（1 起）
    let title: String        // 章名（取里程碑标题）
    let ageText: String      // 年龄（Milestone.ageDescription，兜底空串）
    let dateText: String     // 日期（happenedAt 格式化）
    let lines: [String]      // 正文逐行（把 detail 按句拆行，便于逐行浮现动画）
    let hue: Double          // 章节配色（由标题哈希生成，呼应星座/详情）
    let emoji: String
    let milestoneId: UUID

    var noText: String { "第 \(number) 章" }
}

enum StoryChapterBuilder {
    /// 把里程碑编织成章节：仅取「已达成」的，按发生时间升序；正文优先 detail。
    static func chapters(from milestones: [Milestone]) -> [StoryChapter] {
        let achieved = milestones
            .filter { $0.isAchieved && ($0.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }
            .sorted { ($0.happenedAt ?? .distantPast) < ($1.happenedAt ?? .distantPast) }

        return achieved.enumerated().map { idx, m in
            let detail = (m.detail?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            let lines = splitLines(detail ?? defaultLine(for: m))
            return StoryChapter(
                id: m.id,
                number: idx + 1,
                title: m.title,
                ageText: m.ageDescription ?? "",
                dateText: m.happenedAt.map(BubuDateFormat.yearMonthDay) ?? "",
                lines: lines,
                hue: Double(abs(m.title.hashValue) % 360),
                emoji: m.emoji,
                milestoneId: m.id
            )
        }
    }

    /// 没有故事文案时的温柔兜底（不会空着一页）。
    private static func defaultLine(for m: Milestone) -> String {
        "这一天，布布完成了「\(m.title)」。\n虽然还没写下故事，但这一刻已经被悄悄收藏。"
    }

    /// 按中文句末标点 / 换行拆成 2–6 行，便于逐行 fadeUp。
    private static func splitLines(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\n", with: "。")
        var parts: [String] = []
        var current = ""
        for ch in normalized {
            current.append(ch)
            if "。！？!?.".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return parts.isEmpty ? [text] : parts
    }
}
