import Foundation

// MARK: - 中文日期格式
/// 统一中文界面的日期显示，避免跟随设备/模拟器地区变成英文。
nonisolated enum BubuDateFormat {
    private static let zhCN = Locale(identifier: "zh_CN")

    static func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(zhCN))
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(zhCN))
    }

    static func shortDateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(zhCN))
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(zhCN))
    }

    static func yearMonthDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle.dateTime.year().month().day().locale(zhCN))
    }
}
