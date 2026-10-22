import SwiftUI

// MARK: - 更新记录 / 升级弹窗
/// - WhatsNewListView：设置页进入，按版本倒序展示全部更新记录。
/// - WhatsNewSheet：升级后首次启动自动弹出，只展示最新一版。
/// - WhatsNewGate：判断是否需要弹窗（比对上次见过的版本）。

// MARK: 升级弹窗判定
enum WhatsNewGate {
    /// 判定基准 = 最新一条更新记录的 version（与 App 营销版本解耦）。
    /// 这样即便 App 版本号没动，只要 Changelog 顶部加了新版本，就会再弹一次；
    /// 想强制重弹也只需在 Changelog 顶部加条目，不用改这里。
    private static var currentTag: String { Changelog.latest?.version ?? AppVersion.marketing }

    /// 用新 key（v2）——历史上早期版本曾把脏值写进旧 key，换 key 让那段历史失效，
    /// 保证本次升级能正常弹一次。
    private static let key = "bubu.whatsnew.lastSeenTag.v2"

    /// 是否该弹更新弹窗。
    /// - 已看过当前更新条目：不弹。
    /// - 没看过（升级/首次见到新条目）：弹。
    /// - 真·全新安装且还没完成引导：不弹，别打扰第一次。
    static func shouldPresent(isReturningUser: Bool) -> Bool {
        let seen = UserDefaults.standard.string(forKey: key)
        if seen == currentTag { return false }   // 已看过这条
        if seen == nil && !isReturningUser {
            markSeen()                           // 全新安装：记下、不弹
            return false
        }
        return true                              // 升级 / 新条目 → 弹
    }

    static func markSeen() {
        UserDefaults.standard.set(currentTag, forKey: key)
    }
}

// MARK: 更新要点 → 对应页面
/// 只写「新增了什么」不够：家长读完关掉弹窗，还是找不到它在哪。
/// 每条要点里提到的功能都给一个「去看看」，点了直接进那一页。
enum WhatsNewDestination: String, CaseIterable, Identifiable {
    case ask = "布布问答"
    case birthdayFilm = "生日影片"
    case words = "语言成长线"
    case places = "去过的地方"
    case recognition = "认一认"
    case monthlyReport = "成长小报"
    case voices = "布布的声音"
    case soundRing = "声音年轮"
    case weeklyReport = "布布周报"
    case movie = "成长电影"
    case capsule = "时间胶囊"
    case serverStatus = "家里服务器状态"

    var id: String { rawValue }

    /// 按在文字里出现的先后排列，一条要点可能带两三个入口。
    static func matches(in text: String) -> [WhatsNewDestination] {
        allCases
            .compactMap { destination in text.range(of: destination.rawValue).map { (destination, $0.lowerBound) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}

private struct WhatsNewDestinationView: View {
    @Environment(AppEnvironment.self) private var env
    let destination: WhatsNewDestination

    var body: some View {
        switch destination {
        case .ask:
            if BubuLearningClient(env: env) != nil { AskBubuView() } else { BubuQAView() }
        case .birthdayFilm: BirthdayFilmView()
        case .words: WordsGrowthView()
        case .places: PlacesMapView()
        case .recognition: RecognitionView()
        case .monthlyReport: MonthlyReportView()
        case .voices: BubuVoicesView()
        case .soundRing: SoundRingView()
        case .weeklyReport: WeeklyReportView()
        case .movie: GrowthMovieView()
        case .capsule: CapsuleHomeView()
        case .serverStatus: ServerStatusView()
        }
    }
}

/// 要点下方的一排「去看看」小胶囊。
private struct WhatsNewLinks: View {
    let text: String

    var body: some View {
        let destinations = WhatsNewDestination.matches(in: text)
        if !destinations.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(destinations) { destination in
                    NavigationLink {
                        WhatsNewDestinationView(destination: destination)
                    } label: {
                        HStack(spacing: 4) {
                            Text("去看看 \(destination.rawValue)")
                            Image(systemName: "chevron.right").font(BubuTheme.Font.scaled(10, weight: .bold))
                        }
                        .font(BubuTheme.Font.scaled(13, weight: .semibold))
                        .foregroundStyle(BubuTheme.Color.primaryInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(BubuTheme.Color.pinkSurface.opacity(0.7), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("去看看\(destination.rawValue)")
                }
            }
        }
    }
}

// MARK: 升级弹窗（只展示最新一版）
struct WhatsNewSheet: View {
    let note: ReleaseNote
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("✨").font(BubuTheme.Font.scaled(44))
                Text("更新好啦")
                    .font(BubuTheme.Font.hugeTitle)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("v\(note.version) · \(note.title)")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(note.highlights, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BubuTheme.Color.primaryInk)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item)
                                    .font(BubuTheme.Font.body)
                                    .foregroundStyle(BubuTheme.Color.warmBrown)
                                    .fixedSize(horizontal: false, vertical: true)
                                WhatsNewLinks(text: item)
                            }
                        }
                    }
                }
                .padding(20)
            }

            Button {
                WhatsNewGate.markSeen()
                onClose()
            } label: {
                Text("知道了")
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BubuTheme.Color.actionFill, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(BubuTheme.Color.cream)
    }
}

// MARK: 更新记录全列表（设置页进入）
struct WhatsNewListView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Changelog.all) { note in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("v\(note.version)")
                                .font(BubuTheme.Font.scaled(20, weight: .black))
                                .foregroundStyle(BubuTheme.Color.warmBrown)
                            Spacer()
                            Text(note.date)
                                .font(BubuTheme.Font.scaled(12))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        Text(note.title)
                            .font(BubuTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.primaryInk)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(note.highlights, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("·").foregroundStyle(BubuTheme.Color.primaryInk)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item)
                                            .font(BubuTheme.Font.scaled(14))
                                            .foregroundStyle(BubuTheme.Color.warmBrown)
                                            .fixedSize(horizontal: false, vertical: true)
                                        // 只给最新一版加入口：旧版本的功能名可能已经改过。
                                        if note.version == Changelog.latest?.version {
                                            WhatsNewLinks(text: item)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                }
            }
            .padding()
            .bubuContentColumn()   // 宽屏收进居中内容列，窄屏原样
        }
        .background(BubuTheme.Color.cream.ignoresSafeArea())
        .navigationTitle("更新记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}
