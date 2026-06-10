import SwiftUI
import SwiftData

// MARK: - 时光轴
/// @Query 按 happenedAt 倒序读取本地 Entry，按「年-月」分段展示。
/// 离线优先：UI 只读本地 SwiftData，断网全功能可用。
struct TimelineView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Entry> { !$0.isArchived },
        sort: \Entry.happenedAt,
        order: .reverse
    )
    private var entries: [Entry]
    @Query private var profiles: [ChildProfile]
    @State private var showFamilyFeed = false
    @State private var entryPendingDelete: Entry?
    @Namespace private var zoomNS

    var body: some View {
        ZStack {
            BubuTheme.Color.background.ignoresSafeArea()

            if entries.isEmpty {
                emptyState
            } else {
                timeline
            }
        }
        .navigationTitle("时光轴")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFamilyFeed = true
                } label: {
                    Label("家庭动态", systemImage: "person.2.wave.2.fill")
                }
            }
        }
        .sheet(isPresented: $showFamilyFeed) {
            NavigationStack { FamilyFeedView() }
        }
        .alert("删除这条记录？", isPresented: Binding(
            get: { entryPendingDelete != nil },
            set: { if !$0 { entryPendingDelete = nil } }
        )) {
            Button("删除", role: .destructive) { deletePendingEntry() }
            Button("取消", role: .cancel) { entryPendingDelete = nil }
        } message: {
            Text("删除后会从时光轴隐藏，本地记录会标记为待同步删除。")
        }
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BubuTheme.Spacing.section, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(groupedSections.enumerated()), id: \.element.key) { sectionIndex, section in
                    Section {
                        ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                            NavigationLink(value: entry) {
                                TimelineEntryCard(entry: entry, mediaStore: env.mediaStore)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: entry.id, in: zoomNS)
                            .entranceEffect(index: sectionIndex == 0 ? index : 6)
                            .contextMenu {
                                Button(role: .destructive) {
                                    entryPendingDelete = entry
                                } label: {
                                    Label("删除记录", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    entryPendingDelete = entry
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: Entry.self) { entry in
            EntryDetailView(entry: entry)
                .navigationTransition(.zoom(sourceID: entry.id, in: zoomNS))
        }
    }

    /// 月份 + 年龄锚点：翻旧记录时「布布多大」比日期更有感。
    private func sectionHeader(_ section: TimelineSection) -> some View {
        HStack(spacing: 8) {
            Text(section.key)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            if let profile = profiles.first, let anchor = section.entries.first?.happenedAt {
                Text("布布 \(AgeCalculator.compactAge(birthday: profile.birthday, at: anchor))")
                    .font(BubuTheme.Font.caption.weight(.medium))
                    .foregroundStyle(env.theme.theme.primary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(env.theme.theme.primary.opacity(0.10), in: Capsule())
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.background.opacity(0.95))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            BubuMascotBadge(size: 78, expression: .bye)
            Text(BubuTheme.Copy.emptyTimeline)
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: 分段

    private struct TimelineSection {
        let key: String
        let entries: [Entry]
    }

    /// 按「YYYY年M月」分组，保持倒序。
    private var groupedSections: [TimelineSection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { entry -> DateComponents in
            calendar.dateComponents([.year, .month], from: entry.happenedAt)
        }
        return groups
            .map { (comps, items) in
                TimelineSection(key: monthTitle(comps), entries: items)
            }
            .sorted { lhs, rhs in
                (lhs.entries.first?.happenedAt ?? .distantPast) >
                (rhs.entries.first?.happenedAt ?? .distantPast)
            }
    }

    private func monthTitle(_ comps: DateComponents) -> String {
        guard let year = comps.year, let month = comps.month else { return "" }
        return "\(year)年\(month)月"
    }

    private func deletePendingEntry() {
        guard let entry = entryPendingDelete else { return }
        BubuHaptics.warning()
        entry.isArchived = true
        entry.editedAt = .now
        entry.syncState = .local
        context.insert(FeedEvent(kind: .entryArchived,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "删除了一条时光轴记录",
                                 targetLocalId: entry.id.uuidString))
        try? context.save()
        entryPendingDelete = nil
    }
}
