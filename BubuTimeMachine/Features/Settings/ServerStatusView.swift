import SwiftUI

/// `GET status`：家里服务器的健康状况。取不到的字段为 null；不含路径、主机名、密钥。
nonisolated struct LearningServerStatusDTO: Decodable, Sendable, Equatable {
    let ok: Bool?
    let learningStore: Bool?
    let brainLibrary: Bool?
    let workerAlive: Bool?
    let workerHeartbeatAt: String?
    let snapshotAt: String?
    let captionsPending: Int?
    let voicesPending: Int?
    let backupAt: String?
    let items: Int?
    let checkedAt: String?
}

// MARK: - 设置 → 家里服务器状态
/// 给家长看的一页：素材库读不读得到、后台在不在跑、还有多少待整理、最近一次备份。
struct ServerStatusView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var status: LearningServerStatusDTO?
    @State private var failure: LearningErrorKind?
    @State private var failureText = ""
    @State private var loading = false

    var body: some View {
        let client = BubuLearningClient(env: env)
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                if client == nil {
                    BubuStateView(.empty, title: "还没连接家里的服务器", message: "在设置里连接家庭服务后，这里会显示它的状态。")
                } else if let status {
                    summary(status)
                    rows(status)
                } else if let failure {
                    BubuStateView(BubuStateKind(failure), message: failureText) { Task { await load(client) } }
                } else {
                    BubuStateView(.loading, message: "正在问问家里的服务器…")
                }
                Label("如果显示读不到素材库，通常是 Mac mini 上有系统弹窗等待允许。", systemImage: "lightbulb")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    .padding(.horizontal, 4)
            }
            .padding(BubuTheme.Spacing.item)
            .bubuContentColumn()
        }
        .background(BubuThemedBackground().ignoresSafeArea())
        .refreshable { await load(client) }
        .task(id: client?.scope) { await load(client) }
        .navigationTitle("家里服务器状态")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(_ status: LearningServerStatusDTO) -> some View {
        // The header is derived from the same rules as the rows below, so it can't say "一切正常" over a yellow chip.
        let headline = Self.headline(status)
        let healthy = headline.level != .warn
        return HStack(spacing: BubuTheme.Spacing.m) {
            ZStack {
                Circle().fill(healthy ? BubuTheme.Color.mintSurface : BubuTheme.Color.butterSurface)
                Image(systemName: healthy ? (headline.level == .progress ? "arrow.triangle.2.circlepath" : "checkmark.seal.fill")
                                          : "exclamationmark.triangle.fill")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(healthy ? BubuTheme.Color.success : BubuTheme.Color.warning)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline.title)
                    .font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                if let detail = headline.detail {
                    Text(detail).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.warmBrown)
                }
                Text(subtitle(status)).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(BubuTheme.Spacing.item)
        .background(BubuTheme.Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("server-status.summary")
    }

    private func subtitle(_ status: LearningServerStatusDTO) -> String {
        var parts: [String] = []
        if let items = status.items { parts.append("布布的时光 \(items) 份") }
        if let checked = Self.relative(status.checkedAt) { parts.append("\(checked)检查") }
        return parts.isEmpty ? "刚刚检查" : parts.joined(separator: " · ")
    }

    private func rows(_ status: LearningServerStatusDTO) -> some View {
        VStack(spacing: 0) {
            row("素材库可读", symbol: "photo.stack", state: Self.flag(status.brainLibrary, ok: "读得到", warn: "读不到"))
            Divider().padding(.leading, 44)
            row("学习数据可读", symbol: "book.closed", state: Self.flag(status.learningStore, ok: "读得到", warn: "读不到"))
            Divider().padding(.leading, 44)
            row("后台在运行", symbol: "gearshape.2", detail: Self.relative(status.workerHeartbeatAt).map { "上次心跳 \($0)" },
                state: Self.flag(status.workerAlive, ok: "在运行", warn: "停了"))
            Divider().padding(.leading, 44)
            row("照片说明待补", symbol: "person.text.rectangle", state: Self.pending(status.captionsPending, unit: "条"))
            Divider().padding(.leading, 44)
            row("声音待整理", symbol: "waveform", state: Self.pending(status.voicesPending, unit: "段"))
            Divider().padding(.leading, 44)
            row("最近备份", symbol: "externaldrive.badge.checkmark", state: Self.backup(status.backupAt))
        }
        .padding(.vertical, 4)
        .background(BubuTheme.Color.card.opacity(0.92), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private func row(_ title: String, symbol: String, detail: String? = nil, state: ServerStatusChip) -> some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            Image(systemName: symbol).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.deepRose)
                .frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                if let detail {
                    Text(detail).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            Spacer(minLength: 0)
            state
        }
        .padding(.horizontal, BubuTheme.Spacing.item).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("server-status.row")
    }

    private func load(_ client: BubuLearningClient?) async {
        guard let client, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            status = try await client.get("api/status", as: LearningServerStatusDTO.self)
            failure = nil
        } catch where isCancellation(error) {
        } catch LearningServiceError.unavailableMedia {
            // 404: the server predates 2.25.1.
            failure = .other
            failureText = "家里的服务器版本较旧，还看不到状态。更新服务端后再来看看。"
        } catch {
            failure = LearningErrorKind(error)
            failureText = learningErrorText(error, fallback: "暂时问不到家里服务器的状态，请稍后重试。")
        }
    }

    // MARK: Chip rules

    static func flag(_ value: Bool?, ok: String, warn: String) -> ServerStatusChip {
        switch value {
        case true?: ServerStatusChip(text: ok, level: .ok)
        case false?: ServerStatusChip(text: warn, level: .warn)
        case nil: ServerStatusChip(text: "取不到", level: .unknown)
        }
    }

    /// A backlog is work in progress, not a fault: neutral grey, never yellow.
    static func pending(_ count: Int?, unit: String) -> ServerStatusChip {
        guard let count else { return ServerStatusChip(text: "取不到", level: .unknown) }
        return count == 0 ? ServerStatusChip(text: "都处理好了", level: .ok) : ServerStatusChip(text: "整理中 \(count) \(unit)", level: .progress)
    }

    /// A backup older than two days is worth a look.
    static func backup(_ value: String?, now: Date = .now) -> ServerStatusChip {
        guard let date = value.flatMap(BubuLearningDates.parseISO) else { return ServerStatusChip(text: "还没开始", level: .warn) }
        let text = relativeText(date, now: now)
        return ServerStatusChip(text: text, level: now.timeIntervalSince(date) > 2 * 86_400 ? .warn : .ok)
    }

    struct Headline: Equatable {
        let level: ServerStatusChip.Level
        let title: String
        let detail: String?
    }

    /// Summarises the rows: any warning wins (named when there is one), then work in progress, then all clear.
    static func headline(_ status: LearningServerStatusDTO, now: Date = .now) -> Headline {
        var problems: [String] = []
        if status.brainLibrary == false { problems.append("素材库读不到") }
        if status.learningStore == false { problems.append("学习数据读不到") }
        if status.workerAlive == false { problems.append("后台停了") }
        if backup(status.backupAt, now: now).level == .warn {
            problems.append(status.backupAt.flatMap(BubuLearningDates.parseISO) == nil ? "备份还没开始" : "备份有一阵没更新了")
        }
        if problems.isEmpty, status.ok == false { problems.append("服务器报告了问题") }
        if problems.count == 1 { return Headline(level: .warn, title: problems[0], detail: nil) }
        if problems.count > 1 {
            return Headline(level: .warn, title: "有 \(problems.count) 处需要看一下", detail: problems.joined(separator: "、"))
        }
        let backlog = (status.captionsPending ?? 0) + (status.voicesPending ?? 0)
        if backlog > 0 { return Headline(level: .progress, title: "运行正常，还在慢慢整理", detail: nil) }
        return Headline(level: .ok, title: "一切正常", detail: nil)
    }

    static func relative(_ value: String?, now: Date = .now) -> String? {
        value.flatMap(BubuLearningDates.parseISO).map { relativeText($0, now: now) }
    }

    static func relativeText(_ date: Date, now: Date) -> String {
        if abs(now.timeIntervalSince(date)) < 60 { return "刚刚" }
        return Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .wide, locale: Locale(identifier: "zh_CN"))
            .format(date)
    }
}

struct ServerStatusChip: View {
    enum Level: Equatable { case ok, warn, progress, unknown }
    let text: String
    let level: Level

    var body: some View {
        Label(text, systemImage: symbol)
            .font(BubuTheme.Font.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(background, in: Capsule())
    }

    private var symbol: String {
        switch level {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.circle.fill"
        case .progress: "hourglass"
        case .unknown: "questionmark.circle"
        }
    }
    private var foreground: Color {
        switch level {
        case .ok: BubuTheme.Color.success
        case .warn: BubuTheme.Color.warning
        case .progress, .unknown: BubuTheme.Color.secondaryText
        }
    }
    private var background: Color {
        switch level {
        case .ok: BubuTheme.Color.mintSurface
        case .warn: BubuTheme.Color.butterSurface
        case .progress, .unknown: BubuTheme.Color.softFill
        }
    }
}
