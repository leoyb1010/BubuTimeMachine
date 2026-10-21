import Foundation

nonisolated enum TimelineSortMode: String, CaseIterable, Sendable {
    case capture, oldest, recorded
    var title: String {
        switch self {
        case .capture: "最新拍摄"
        case .oldest: "最早拍摄"
        case .recorded: "最近收录"
        }
    }
    var ascending: Bool { self == .oldest }
}

nonisolated struct TimelineFilters: Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case all, photo, video, audio
        var title: String {
            switch self { case .all: "全部类型"; case .photo: "照片"; case .video: "视频"; case .audio: "语音" }
        }
    }
    enum Source: String, CaseIterable, Sendable {
        case all, automatic, family
        var title: String {
            switch self { case .all: "全部来源"; case .automatic: "第二大脑自动"; case .family: "家人记录" }
        }
    }
    static let automaticMarker = "【第二大脑自动整理】"
    var kind: Kind = .all
    var source: Source = .all
    var start: Date?
    var end: Date?
    var isActive: Bool { kind != .all || source != .all || start != nil || end != nil }

    func dateBounds(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let lower = start.map { calendar.startOfDay(for: $0) } ?? .distantPast
        let upper = end.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) } ?? .distantFuture
        return (lower, upper)
    }
    static func displayNote(_ note: String?) -> String? {
        guard let note else { return nil }
        if note == automaticMarker { return nil }
        let prefix = automaticMarker + "\n"
        return note.hasPrefix(prefix) ? String(note.dropFirst(prefix.count)) : note
    }
}
