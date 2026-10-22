import SwiftUI
import SwiftData

// MARK: - 「第一次」统一成一套
/// 以前成长页有三套互不相通的列表：本机 FirstTime（常年 0 条）、第二大脑「可能的第一次」、里程碑。
/// 家长确认了「第一次走路」，「第一次」卡片仍是 0 条。现在「第一次」= 本机记下的第一次
/// ∪ 家长确认过的第二大脑第一次（服务端结果 + 本机由它点亮的里程碑，离线也算），按标题去重；
/// 待确认的候选放在卡片底部的行动行。里程碑仍是发育清单，不混进来。

nonisolated struct GrowthFirstItem: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable { case family, secondBrain }
    let id: String
    let title: String
    let date: Date?
    let source: Source
}

nonisolated enum GrowthFirstsUnion {
    /// 去重用的标题键：去掉空白和标点，「第一次走路！」与「第一次走路」算同一个。
    static func key(_ title: String) -> String {
        title.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) }
            .map(String.init).joined().lowercased()
    }

    /// 本机记录优先（有家人写的原话）；同一个第一次只出现一次，按日期从近到远。
    static func merge(family: [(id: String, title: String, date: Date)],
                      litFromBrain: [(id: String, title: String, date: Date?)],
                      confirmedBrain: [GrowthFirstDTO]) -> [GrowthFirstItem] {
        var seen = Set<String>()
        var items: [GrowthFirstItem] = []
        func add(_ item: GrowthFirstItem) {
            let k = key(item.title)
            guard !k.isEmpty, seen.insert(k).inserted else { return }
            items.append(item)
        }
        for f in family { add(GrowthFirstItem(id: "family-" + f.id, title: f.title, date: f.date, source: .family)) }
        for c in confirmedBrain { add(GrowthFirstItem(id: "brain-" + c.id, title: c.displayTitle, date: c.day, source: .secondBrain)) }
        for m in litFromBrain { add(GrowthFirstItem(id: "lit-" + m.id, title: m.title, date: m.date, source: .secondBrain)) }
        return items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

/// 成长页的「第一次」卡片：已有的第一次 + 「N 个可能的第一次等你确认」。
struct GrowthFirstsCard: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \FirstTime.happenedAt, order: .reverse) private var firstTimes: [FirstTime]
    @Query(filter: #Predicate<Milestone> { $0.happenedAt != nil }) private var litMilestones: [Milestone]
    @State private var model = PossibleFirstsModel()

    private var items: [GrowthFirstItem] {
        GrowthFirstsUnion.merge(
            family: firstTimes.map { (id: $0.id.uuidString, title: $0.what, date: $0.happenedAt) },
            litFromBrain: litMilestones
                .filter { $0.detail?.hasPrefix(BrainFirstMilestoneWriter.notePrefix) == true }
                .map { (id: $0.id.uuidString, title: $0.title, date: $0.happenedAt) },
            confirmedBrain: model.confirmed)
    }

    var body: some View {
        let client = BubuLearningClient(env: env)
        let all = items
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("第一次", systemImage: "flag.checkered")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text("\(all.count) 个")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                    .contentTransition(.numericText())
            }
            if all.isEmpty {
                Text("家人记下的、和第二大脑在照片里认出来的“第一次”，都会汇到这里。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(all.prefix(3)) { row($0) }
                if all.count > 3 {
                    NavigationLink { GrowthFirstsListView(items: all) } label: {
                        HStack {
                            Text("看全部 \(all.count) 个第一次")
                            Spacer()
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let client, model.phase == .ready, !model.candidates.isEmpty {
                NavigationLink { PossibleFirstsView(model: model, client: client) } label: { candidatesRow }
                    .buttonStyle(BubuPressableStyle())
                    .accessibilityIdentifier("growth.firsts.candidates")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
        .animation(BubuMotion.gentle, value: model.phase)
        .task(id: client?.scope) { await model.load(client: client) }
        .accessibilityIdentifier("growth.firsts")
    }

    private func row(_ item: GrowthFirstItem) -> some View {
        HStack(spacing: 11) {
            Image(systemName: item.source == .family ? "flag.fill" : "sparkle.magnifyingglass")
                .foregroundStyle(BubuTheme.Color.deepRose)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(2)
                Text([item.date.map(BubuDateFormat.shortDate), item.source == .secondBrain ? "照片里认出来的" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var candidatesRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(BubuTheme.Font.scaled(20, weight: .semibold))
                .foregroundStyle(BubuTheme.Color.deepRose)
                .frame(width: 44, height: 44)
                .background(BubuTheme.Color.card, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.candidates.count) 个可能的第一次等你确认")
                    .font(BubuTheme.Font.body.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("第二大脑在照片里发现的，确认后收进这里")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(BubuTheme.Font.caption.weight(.bold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(
            LinearGradient(colors: [BubuTheme.Color.butterSurface, BubuTheme.Color.pinkSurface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
    }
}

/// 全部「第一次」。
struct GrowthFirstsListView: View {
    let items: [GrowthFirstItem]

    var body: some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(BubuTheme.Font.body.weight(.semibold)).foregroundStyle(BubuTheme.Color.warmBrown)
                Text([item.date.map(BubuDateFormat.shortDate), item.source == .secondBrain ? "照片里认出来的" : "家人记下的"]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(.vertical, 4)
            .listRowBackground(BubuTheme.Color.card)
            .accessibilityElement(children: .combine)
        }
        .scrollContentBackground(.hidden)
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle("第一次")
        .navigationBarTitleDisplayMode(.inline)
    }
}
