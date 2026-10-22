import SwiftUI
import SwiftData
import Observation

// MARK: - 第二大脑「可能的第一次」（契约 §3）
// 第二大脑只读；确认/忽略存在服务端学习库。确认后由 App 在本机点亮一个 Milestone。

nonisolated struct GrowthFirstDTO: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let concept: String
    let title: String
    let date: String?
    let itemId: String?
    let previewUrl: String?
    let description: String?
    let status: String

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? concept : trimmed
    }

    var day: Date? {
        guard let date, !date.isEmpty else { return nil }
        return BubuLearningDates.day(String(date.prefix(10))) ?? BubuLearningDates.parseISO(date)
    }
}

nonisolated struct GrowthFirstListDTO: Decodable, Sendable {
    let items: [GrowthFirstDTO]
}

/// 服务没配、没部署（404）或暂时下线（503）时整块隐藏，不打扰家人。
nonisolated enum GrowthServiceAvailability {
    static func hides(_ error: Error) -> Bool {
        guard let error = error as? LearningServiceError else { return false }
        switch error {
        case .unavailableMedia, .invalidAddress: return true
        case .server(let code): return code == 404 || code == 501 || code == 502 || code == 503
        default: return false
        }
    }
}

@Observable @MainActor
final class PossibleFirstsModel {
    enum Phase: Equatable { case idle, loading, ready, hidden, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var candidates: [GrowthFirstDTO] = []
    private(set) var confirmed: [GrowthFirstDTO] = []
    private(set) var busyIDs: Set<String> = []
    var actionError: String?

    func load(client: BubuLearningClient?) async {
        guard let client else { phase = .hidden; return }
        if phase != .ready { phase = .loading }
        do {
            let list = try await client.get("api/firsts", query: [URLQueryItem(name: "status", value: "all")],
                                            as: GrowthFirstListDTO.self)
            candidates = list.items.filter { $0.status == "candidate" }.sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
            confirmed = list.items.filter { $0.status == "confirmed" }.sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
            phase = .ready
        } catch is CancellationError {
        } catch {
            if GrowthServiceAvailability.hides(error) {
                phase = .hidden
            } else if phase != .ready {
                phase = .failed(learningErrorText(error))
            }
        }
    }

    /// 确认：先过服务端，再在本机点亮；返回点亮后的标题（用于仪式）。
    func confirm(_ item: GrowthFirstDTO, client: BubuLearningClient) async -> GrowthFirstDTO? {
        guard !busyIDs.contains(item.id) else { return nil }
        busyIDs.insert(item.id)
        defer { busyIDs.remove(item.id) }
        do {
            let updated = try await client.send("POST", "api/firsts/\(item.id)/confirm", as: GrowthFirstDTO.self)
            candidates.removeAll { $0.id == item.id }
            confirmed.removeAll { $0.id == item.id }
            confirmed.insert(updated, at: 0)
            return updated
        } catch {
            actionError = confirmErrorText(error)
            return nil
        }
    }

    /// 忽略：先温柔地从列表里拿走，失败再放回。
    func dismiss(_ item: GrowthFirstDTO, client: BubuLearningClient) async {
        guard !busyIDs.contains(item.id), let index = candidates.firstIndex(of: item) else { return }
        busyIDs.insert(item.id)
        defer { busyIDs.remove(item.id) }
        _ = withAnimation(BubuMotion.gentle) { candidates.remove(at: index) }
        do {
            _ = try await client.send("POST", "api/firsts/\(item.id)/dismiss", as: GrowthFirstDTO.self)
        } catch {
            withAnimation(BubuMotion.gentle) { candidates.insert(item, at: min(index, candidates.count)) }
            actionError = confirmErrorText(error)
        }
    }

    private func confirmErrorText(_ error: Error) -> String {
        if (error as? LearningServiceError) == .unauthorized { return "只有审核家长可以确认或忽略「第一次」。" }
        if (error as? BubuLearningClientError) == .conflict { return "这一条刚被别的家人处理过，下拉刷新看看。" }
        return learningErrorText(error)
    }
}

// MARK: - 本机点亮

/// 复用里程碑编辑页的点亮路径：同标题已存在就点亮那一条（SyncEngine 也按标题去重），否则新建自定义里程碑。
/// 仪式由本页自己播，所以 `ceremonyPlayed = true`，里程碑页不会再补播一次。
@MainActor
enum BrainFirstMilestoneWriter {
    static let notePrefix = "来自第二大脑："

    @discardableResult
    static func light(_ first: GrowthFirstDTO, context: ModelContext, env: AppEnvironment) throws -> Milestone {
        let title = first.displayTitle
        let date = first.day ?? .now
        let note = notePrefix + ((first.description?.isEmpty == false) ? first.description! : first.concept)
        let existing = try context.fetch(FetchDescriptor<Milestone>(predicate: #Predicate { $0.title == title })).first
        let milestone: Milestone
        if let existing {
            milestone = existing
        } else {
            let template = MilestoneTemplate.presets.first { $0.title == title }
            milestone = Milestone(title: title, category: template?.category ?? "认知探索",
                                  emoji: template?.emoji ?? "🌟", isCustom: template == nil)
            context.insert(milestone)
        }
        if milestone.detail?.isEmpty ?? true { milestone.detail = note }
        if !milestone.isAchieved {
            milestone.happenedAt = date
            if let profile = try context.fetch(FetchDescriptor<ChildProfile>()).first {
                milestone.ageDescription = AgeCalculator.ageDescription(birthday: profile.birthday, at: date)
            }
            context.insert(FeedEvent(kind: .milestoneLit, actorRole: env.config.currentRole.rawValue,
                                     summary: "从第二大脑点亮了「\(title)」"))
        }
        milestone.ceremonyPlayed = true
        milestone.syncState = .local
        try context.save()
        env.refreshWidgetSnapshot(context: context)
        return milestone
    }
}

// MARK: - 成长页卡片

/// 成长首页的入口卡片：服务不可用时整块不出现。
struct PossibleFirstsCard: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = PossibleFirstsModel()

    var body: some View {
        let client = BubuLearningClient(env: env)
        Group {
            if let client, model.phase == .ready, !(model.candidates.isEmpty && model.confirmed.isEmpty) {
                NavigationLink { PossibleFirstsView(model: model, client: client) } label: { content }
                    .buttonStyle(BubuPressableStyle())
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(BubuMotion.gentle, value: model.phase)
        .task(id: client?.scope) { await model.load(client: client) }
    }

    private var content: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(BubuTheme.Font.scaled(24, weight: .semibold))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                    .frame(width: 52, height: 52)
                    .background(BubuTheme.Color.butterSurface, in: Circle())
                    .symbolEffect(.bounce, value: model.candidates.count)
                if !model.candidates.isEmpty {
                    Text("\(model.candidates.count)")
                        .font(BubuTheme.Font.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(BubuTheme.Color.primary, in: Capsule())
                        .offset(x: 6, y: -4)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("可能的第一次")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(model.candidates.isEmpty
                     ? "已确认 \(model.confirmed.count) 个，第二大脑还在留意新的"
                     : "第二大脑在照片里发现了 \(model.candidates.count) 个，等你来认一认")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(BubuTheme.Font.caption.weight(.bold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [BubuTheme.Color.butterSurface, BubuTheme.Color.pinkSurface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
        )
        .bubuCardShadow()
    }
}

// MARK: - 列表页

struct PossibleFirstsView: View {
    let model: PossibleFirstsModel
    let client: BubuLearningClient
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ChildProfile]
    @State private var ceremony: CeremonyItem?
    @State private var lightTick = 0

    struct CeremonyItem: Identifiable { let id: String; let title: String; let subtitle: String? }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                intro.entranceEffect(index: 0)
                candidateSection.entranceEffect(index: 1)
                if !model.confirmed.isEmpty {
                    historySection.entranceEffect(index: 2)
                }
            }
            .padding()
            .bubuContentColumn()
        }
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle("可能的第一次")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load(client: client) }
        .bubuSensoryFeedback(.success, trigger: lightTick)
        .alert("没能完成", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        .fullScreenCover(item: $ceremony) { item in
            CeremonyAnimation(title: "🎉 \(item.title)", subtitle: item.subtitle) { ceremony = nil }
                .presentationBackground(.clear)
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            BubuMascotBadge(size: 48, expression: .surprised)
            Text("第二大脑在布布的照片和视频里，找到了一些可能是“第一次”的瞬间。是的话点「确认」，会在里程碑里点亮；不是就「忽略」。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var candidateSection: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            Label("等你来认", systemImage: "sparkles")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            if model.candidates.isEmpty {
                VStack(spacing: BubuTheme.Spacing.s) {
                    BubuEmptyIllustration(assetName: "BubuEmptyFirsts", fallbackExpression: .happy, size: 120)
                    Text("暂时都认完啦，有新的发现会出现在这里。")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BubuTheme.Spacing.l)
                .transition(.opacity)
            } else {
                ForEach(model.candidates) { item in
                    candidateCard(item)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 0.86).combined(with: .opacity).combined(with: .offset(x: -40))
                        ))
                }
            }
        }
        .animation(BubuMotion.gentle, value: model.candidates)
    }

    private func candidateCard(_ item: GrowthFirstDTO) -> some View {
        let busy = model.busyIDs.contains(item.id)
        return VStack(alignment: .leading, spacing: 0) {
            if let preview = item.previewUrl, !preview.isEmpty {
                LearningRemoteImage(path: preview, client: client, label: item.displayTitle,
                                    contentMode: .fill, diskCache: true)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.concept)
                        .font(BubuTheme.Font.caption.weight(.bold))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(BubuTheme.Color.pinkSurface, in: Capsule())
                    if let day = item.day {
                        Text(dateText(day))
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
                Text(item.displayTitle)
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                if let text = item.description, !text.isEmpty {
                    Text(text)
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button { Task { await model.dismiss(item, client: client) } } label: {
                        Text("忽略")
                            .font(BubuTheme.Font.body.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(BubuTheme.Color.softFill, in: Capsule())
                    }
                    Button { Task { await confirm(item) } } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().tint(.white) } else { Image(systemName: "star.fill") }
                            Text("确认，点亮")
                        }
                        .font(BubuTheme.Font.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(BubuTheme.Color.primary, in: Capsule())
                    }
                }
                .buttonStyle(BubuPressableStyle())
                .disabled(busy)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(BubuTheme.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.m) {
            Label("已经确认的第一次", systemImage: "checkmark.seal.fill")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            ForEach(model.confirmed) { item in
                HStack(spacing: 12) {
                    Group {
                        if let preview = item.previewUrl, !preview.isEmpty {
                            LearningRemoteImage(path: preview, client: client, label: item.displayTitle,
                                                contentMode: .fill, diskCache: true)
                        } else {
                            Image(systemName: "star.fill").foregroundStyle(BubuTheme.Color.primary)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(BubuTheme.Color.butterSurface)
                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayTitle)
                            .font(BubuTheme.Font.body.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                            .lineLimit(2)
                        Text(item.day.map(dateText) ?? item.concept)
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BubuTheme.Color.success)
                }
                .padding(10)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
            }
        }
    }

    private func dateText(_ day: Date) -> String {
        guard let birthday = profiles.first?.birthday else { return BubuDateFormat.shortDate(day) }
        return "\(BubuDateFormat.shortDate(day)) · \(AgeCalculator.ageDescription(birthday: birthday, at: day))"
    }

    private func confirm(_ item: GrowthFirstDTO) async {
        guard let updated = await model.confirm(item, client: client) else { return }
        do {
            try BrainFirstMilestoneWriter.light(updated, context: context, env: env)
            BubuSound.play(.milestone)
            lightTick += 1
            let subtitle = updated.day.flatMap { day in
                profiles.first.map { "布布 \(AgeCalculator.ageDescription(birthday: $0.birthday, at: day)) 的第一次，已经点亮在里程碑里。" }
            } ?? "已经点亮在里程碑里。"
            ceremony = CeremonyItem(id: updated.id, title: updated.displayTitle, subtitle: subtitle)
        } catch {
            model.actionError = "服务端已经确认，但本机里程碑没存进去。可以到里程碑页手动点亮「\(updated.displayTitle)」。"
        }
    }
}
