import AppIntents
import SwiftData
import Foundation

// MARK: - App Intents 底座
/// 把布布的核心动作开放给整个系统：Siri、快捷指令、Spotlight、小组件交互按钮、
/// 控制中心 Controls、Action Button 全都复用这里的 Intent，一次定义、多处生效。
///
/// 数据：通过 SharedModelContainer 读写 App Group 共享 store（与主 App 同一份）。
/// 身份：从 SharedDefaults 取当前家庭署名身份。

// MARK: 记录此刻（一句话快速记录）

/// 直接落库一条文字瞬间。无参时由系统提示输入；带 note 时（小组件按钮/快捷指令传入）直接写。
struct RecordMomentIntent: AppIntent {
    static let title: LocalizedStringResource = "记录布布此刻"
    static let description = IntentDescription("快速记一句关于布布的瞬间，存进时光机。")

    /// 让 Siri/快捷指令可缺省询问；小组件/Controls 可预填。
    @Parameter(title: "想记点什么", requestValueDialog: "想记录布布的什么瞬间？")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("记录布布：\(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = SharedModelContainer.sharedIfAvailable?.mainContext else {
            return .result(dialog: "暂时还读不到共享数据，请先打开 App 一次。")
        }
        let role = SharedDefaults.currentRole
        do {
            try EntryWriter.quickTextEntry(note: note, role: role, in: context)
            // 写后钩子：重建 widget 快照 + 刷新小组件，桌面立刻读到这条新记录。
            SharedDefaults.refreshWidgetsAfterWrite(context: context)
            return .result(dialog: "已经帮你记下啦 🌟")
        } catch {
            throw error
        }
    }
}

// MARK: 打开 App 到记录（控制中心/Action Button 用）

/// 控制中心 / 锁屏 / Action Button 的「记录布布」入口：打开 App 并直达快速记录。
/// 控件按钮无法弹文字输入框，故置一个共享标志，App 启动/前台时消费它拉起记录面板。
struct OpenRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "打开布布时光机记录"
    static let description = IntentDescription("打开 App，直接记录布布此刻。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedDefaults.pendingRecord = true
        return .result()
    }
}

// MARK: 一键健康打卡（交互小组件 / Siri / 快捷指令，R4 E-2）

enum HealthCheckInKind: String, AppEnum {
    case milk, sleep, water, diaper

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "打卡类型"
    static let caseDisplayRepresentations: [HealthCheckInKind: DisplayRepresentation] = [
        .milk: "喂奶", .sleep: "睡觉", .water: "喝水", .diaper: "换尿布",
    ]

    var emoji: String {
        switch self {
        case .milk: "🍼"; case .sleep: "😴"; case .water: "💧"; case .diaper: "🧷"
        }
    }
    var label: String {
        switch self {
        case .milk: "喂奶"; case .sleep: "睡觉"; case .water: "喝水"; case .diaper: "换尿布"
        }
    }
}

/// 半夜喂奶单手在锁屏/桌面就能打卡——喂养期最高频的操作，一下都不用开 App。
struct HealthCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "布布健康打卡"
    static let description = IntentDescription("一键记录喂奶/睡觉/喝水/换尿布，不用打开 App。")

    @Parameter(title: "打卡类型")
    var kind: HealthCheckInKind

    init() {}
    init(kind: HealthCheckInKind) { self.kind = kind }

    static var parameterSummary: some ParameterSummary {
        Summary("给布布打卡：\(\.$kind)")
    }

    /// 换尿布无健康类型，与手表一致走文字记录，用固定文案以便去重。
    private static let diaperNote = "换好尿布啦 🧷"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = SharedModelContainer.sharedIfAvailable?.mainContext else {
            return .result(dialog: "先打开一次 App 再用打卡哦。")
        }
        let role = SharedDefaults.currentRole

        // 幂等：与手表路径不同，交互按钮没有 localId。WidgetKit 偶发会把同一次点击的 intent
        // 重复执行 → 重复打卡。这里对「同类型 + 极短时间窗内」去重（用 Media/Entry 自有字段做 COUNT，
        // 不穿透关系），既挡住系统重复执行，又不误伤真实的连续两次操作（窗口只有几秒）。
        if isRecentDuplicate(context: context) {
            return .result(dialog: "\(kind.emoji) \(kind.label)已记上")
        }

        switch kind {
        case .milk:
            try EntryWriter.quickHealthEntry(kind: .meal, title: "喂奶", role: role, in: context)
        case .sleep:
            try EntryWriter.quickHealthEntry(kind: .sleep, title: "睡觉", role: role, in: context)
        case .water:
            try EntryWriter.quickHealthEntry(kind: .water, title: "喝水", role: role, in: context)
        case .diaper:
            try EntryWriter.quickTextEntry(note: Self.diaperNote, role: role, in: context)
        }
        // 写后钩子：重建 widget 快照 + 刷新小组件，桌面/锁屏立刻反映这次打卡。
        SharedDefaults.refreshWidgetsAfterWrite(context: context)
        return .result(dialog: "\(kind.emoji) \(kind.label)已记上")
    }

    /// 极短时间窗内是否已有同类型打卡（挡 WidgetKit 重复执行）。
    @MainActor
    private func isRecentDuplicate(context: ModelContext) -> Bool {
        let cutoff = Date.now.addingTimeInterval(-4)   // 4 秒窗：足够挡系统重复执行，短到不会误伤真实连点
        switch kind {
        case .milk, .sleep, .water:
            let raw: String
            switch kind {
            case .milk: raw = HealthRecordKind.meal.rawValue
            case .sleep: raw = HealthRecordKind.sleep.rawValue
            case .water: raw = HealthRecordKind.water.rawValue
            case .diaper: raw = ""   // 不会到这
            }
            let d = FetchDescriptor<HealthRecord>(
                predicate: #Predicate { $0.kindRaw == raw && $0.recordedAt >= cutoff })
            return ((try? context.fetchCount(d)) ?? 0) > 0
        case .diaper:
            let note = Self.diaperNote
            let d = FetchDescriptor<Entry>(
                predicate: #Predicate { ($0.note ?? "") == note && $0.happenedAt >= cutoff })
            return ((try? context.fetchCount(d)) ?? 0) > 0
        }
    }
}

// MARK: 布布多大了

/// Siri 直接念出布布当前年龄；无档案时友好提示。
struct BubuAgeIntent: AppIntent {
    static let title: LocalizedStringResource = "布布多大了"
    static let description = IntentDescription("问问布布现在多大了。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = SharedModelContainer.sharedIfAvailable?.mainContext else {
            return .result(dialog: "暂时还读不到布布档案，请先打开 App 一次。")
        }
        guard let profile = EntryWriter.currentChildProfile(in: context) else {
            return .result(dialog: "还没有布布的档案哦，先在 App 里建一个吧。")
        }
        let age = AgeCalculator.ageDescription(birthday: profile.birthday, at: .now)
        let days = AgeCalculator.daysSinceBirth(birthday: profile.birthday)
        return .result(dialog: "\(profile.name)现在\(age)啦，已经来到世界第 \(days) 天 💛")
    }
}

// MARK: 打开 App 到指定页面（Siri：去年今天 / 今天学了什么 / 问问布布时光）

/// 意图只负责拼出 App 内已有的 `bubu://` 深链，再交给系统打开；页内定位由 BubuRouter 解析。
nonisolated enum BubuIntentLinks {
    static let scheme = "bubu"

    /// 与课程/时光一致：按上海时区取「哪一天」。
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 去年的今天（2 月 29 日落到 2 月 28 日）。
    static func sameDayLastYear(from now: Date = .now) -> Date {
        calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86_400)
    }

    /// 时光 → 指定日期：`bubu://moment?date=yyyy-MM-dd`。
    static func timeline(on date: Date) -> URL {
        url(host: "moment", query: [URLQueryItem(name: "date", value: dayString(date))])
    }

    /// 每日学习 → 指定日期：`bubu://learning?date=yyyy-MM-dd`。
    static func learning(on date: Date) -> URL {
        url(host: "learning", query: [URLQueryItem(name: "date", value: dayString(date))])
    }

    /// 布布问答：`bubu://ask?q=…`（问题最多 200 字，与服务端一致）。
    static func ask(_ question: String) -> URL {
        let trimmed = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return url(host: "ask", query: trimmed.isEmpty ? [] : [URLQueryItem(name: "q", value: trimmed)])
    }

    private static func url(host: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = query.isEmpty ? nil : query
        // "+" 在查询里会被当成空格，显式编码。
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? URL(string: "\(scheme)://\(host)")!
    }
}

/// 「看看布布去年今天」→ 打开时光，定位到去年的这一天。
struct OpenLastYearTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "看看布布去年今天"
    static let description = IntentDescription("打开布布时光机，看看去年的今天布布在做什么。")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(BubuIntentLinks.timeline(on: BubuIntentLinks.sameDayLastYear())))
    }
}

/// 「布布今天学了什么」→ 打开每日学习的今天。
struct OpenTodayLearningIntent: AppIntent {
    static let title: LocalizedStringResource = "布布今天学了什么"
    static let description = IntentDescription("打开每日学习，看看布布今天的课程。")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(BubuIntentLinks.learning(on: .now)))
    }
}

/// 「问问布布时光」→ 带着问题打开布布问答。
struct AskBubuTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "问问布布时光"
    static let description = IntentDescription("向布布的时光提一个问题，比如“她第一次去海边是什么时候”。")

    @Parameter(title: "想问什么", requestValueDialog: "想问问布布时光什么？")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("问问布布时光：\(\.$question)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(BubuIntentLinks.ask(question)))
    }
}

// MARK: 预置快捷短语

/// 免用户手动配快捷指令：装上即可在 Siri/快捷指令里用这些短语。
struct BubuAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordMomentIntent(),
            phrases: [
                "用\(.applicationName)记一笔",
                "在\(.applicationName)记录此刻",
                "\(.applicationName)记录布布"
            ],
            shortTitle: "记录此刻",
            systemImageName: "heart.circle.fill"
        )
        AppShortcut(
            intent: BubuAgeIntent(),
            phrases: [
                "\(.applicationName)布布多大了",
                "问问\(.applicationName)布布几岁了"
            ],
            shortTitle: "布布多大了",
            systemImageName: "birthday.cake.fill"
        )
        // 半夜喂奶最高频，却一直没进预置短语——Intent 早就实现了，只是没挂上来，
        // 于是锁屏/Siri 这条最省事的路径白白空着。
        AppShortcut(
            intent: HealthCheckInIntent(),
            phrases: [
                "用\(.applicationName)打卡\(\.$kind)",
                "\(.applicationName)给布布打卡\(\.$kind)",
                "在\(.applicationName)记一次\(\.$kind)"
            ],
            shortTitle: "健康打卡",
            systemImageName: "cross.case.fill"
        )
        AppShortcut(
            intent: OpenLastYearTodayIntent(),
            phrases: [
                "\(.applicationName)看看布布去年今天",
                "用\(.applicationName)看看去年今天"
            ],
            shortTitle: "去年今天",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: OpenTodayLearningIntent(),
            phrases: [
                "\(.applicationName)布布今天学了什么",
                "打开\(.applicationName)今天的学习"
            ],
            shortTitle: "今天学了什么",
            systemImageName: "graduationcap.fill"
        )
        AppShortcut(
            intent: AskBubuTimeIntent(),
            phrases: [
                "\(.applicationName)问问布布时光",
                "用\(.applicationName)问问布布时光"
            ],
            shortTitle: "问问布布时光",
            systemImageName: "bubble.left.and.text.bubble.right.fill"
        )
        AppShortcut(
            intent: OpenRecordIntent(),
            phrases: [
                "打开\(.applicationName)记录",
                "\(.applicationName)记录布布此刻"
            ],
            shortTitle: "打开记录",
            systemImageName: "plus.circle.fill"
        )
    }
}
