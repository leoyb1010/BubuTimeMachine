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
            return .result(dialog: "已经帮你记下啦 🌟")
        } catch {
            throw error
        }
    }
}

// MARK: 打开 App 到记录（控制中心/Action Button 用）

/// 控制中心 / 锁屏 / Action Button 的「记录布布」入口：打开 App。
/// 控件按钮无法弹文字输入框，故用打开 App 落到首页（「记录此刻」首屏即在），而非直接空写。
struct OpenRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "打开布布时光机记录"
    static let description = IntentDescription("打开 App，记录布布此刻。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
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
