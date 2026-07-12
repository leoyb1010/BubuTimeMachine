import Foundation
import SwiftData

// MARK: - 成长绘本章节（派生模型，不入库）
/// 成长绘本 = 把「你主动收进绘本的记录(Entry)」按时间编织成可翻页阅读的故事书。
/// 来源是你的日常记录，而不是里程碑——里程碑是「成就墙」，绘本是「你亲手策展的时光故事」。
/// 纯派生：不新增 @Model、不写库，随记录实时变化。收录与否由 Entry.inStorybook 决定（你在时光轴/详情勾选）。
struct StoryChapter: Identifiable, Hashable {
    let id: UUID
    let number: Int          // 第几章（1 起）
    let title: String        // 章名（记录标题 / 首句 / 心情兜底）
    let ageText: String      // 年龄（按 happenedAt 相对生日计算，兜底空串）
    let dateText: String     // 日期（happenedAt 格式化）
    let lines: [String]      // 正文逐行（优先 AI 第一人称，其次原文；按句拆行便于逐行浮现）
    let hue: Double          // 章节配色（由标题哈希生成，呼应星座/详情）
    let emoji: String        // 章节图标（心情 emoji，兜底 ✨）
    let photoFileName: String?      // 配图：记录里第一张照片的缩略图文件名（无则 nil，走渐变兜底）
    let entryId: UUID

    var noText: String { "第 \(number) 章" }
    /// 是否有真实照片配图。
    var hasPhoto: Bool { photoFileName != nil }
}

enum StoryChapterBuilder {
    /// 把记录编织成绘本章节：只取用户收进绘本（inStorybook）且未归档的记录，按发生时间升序。
    /// 正文优先用 AI 第一人称改写（最有故事感），退到父母视角原文。
    static func chapters(from entries: [Entry], birthday: Date?) -> [StoryChapter] {
        let picked = entries
            .filter { $0.inStorybook && !$0.isArchived }
            .sorted { $0.happenedAt < $1.happenedAt }

        return picked.enumerated().map { idx, e in
            let body = storyText(for: e)
            return StoryChapter(
                id: e.id,
                number: idx + 1,
                title: chapterTitle(for: e),
                ageText: birthday.map { AgeCalculator.ageDescription(birthday: $0, at: e.happenedAt) } ?? "",
                dateText: BubuDateFormat.yearMonthDay(e.happenedAt),
                lines: splitLines(body),
                hue: chapterTitle(for: e).bubuStableHue,
                emoji: e.mood?.emoji ?? "✨",
                photoFileName: coverPhotoFileName(for: e),
                entryId: e.id
            )
        }
    }

    /// 章名：优先记录标题；无标题时取正文首句；再兜底成日期化的温柔标题。
    private static func chapterTitle(for e: Entry) -> String {
        if let t = e.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        let body = storyText(for: e)
        if let first = splitLines(body).first, first.count <= 18 { return first }
        return "布布的这一天"
    }

    /// 正文文本：AI 第一人称改写优先（讲故事感最强），退到父母视角原文，再兜底一句温柔占位。
    private static func storyText(for e: Entry) -> String {
        if let fp = e.firstPersonNote?.trimmingCharacters(in: .whitespacesAndNewlines), !fp.isEmpty { return fp }
        if let note = e.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { return note }
        return "这一天，布布留下了一段没有文字的时光，\n但它已经被悄悄收进这本书里。"
    }

    /// 配图：取记录里第一张照片的缩略图文件名（优先缩略图，退到原图文件名，都没有则 nil）。
    private static func coverPhotoFileName(for e: Entry) -> String? {
        guard let first = e.sortedMedia.first(where: { $0.type == .photo }) else { return nil }
        return first.thumbnailFileName ?? first.localFileName
    }

    /// 按中文句末标点 / 换行拆成若干行，便于逐行 fadeUp。
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
