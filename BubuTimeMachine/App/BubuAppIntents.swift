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
