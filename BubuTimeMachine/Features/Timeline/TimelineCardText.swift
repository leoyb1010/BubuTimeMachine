import Foundation

// MARK: - 时光轴卡片文案
/// 抽成纯函数，是因为这里踩过一个肉眼很容易漏掉的坑：
/// 卡片标题在没有标题时会把正文顶上来当标题，而下面那行摘要又原样再渲染一次正文——
/// 于是同一句话在同一张卡上下重复出现（v2.10.1 及更早）。
/// 规则钉在这里并配测试，改动 UI 时不会再复发。
nonisolated enum TimelineCardText {
    /// 卡片标题：有标题用标题；没标题就把正文顶上来；都没有才是「记录此刻」。
    static func headline(title: String?, note: String?) -> String {
        if let title, !title.isEmpty { return title }
        if let note, !note.isEmpty { return note }
        return "记录此刻"
    }

    /// 卡片副文案：只有当它和标题不是同一句话时才显示。
    /// - 无标题：正文已被顶上去当标题 → 不显示副文案
    /// - 标题与正文逐字相同 → 不显示副文案
    static func subtitle(title: String?, note: String?) -> String? {
        guard let note, !note.isEmpty else { return nil }
        guard let title, !title.isEmpty else { return nil }
        return note == title ? nil : note
    }
}
