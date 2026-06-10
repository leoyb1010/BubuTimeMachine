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
    @State private var showFamilyFeed = false
    @State private var entryPendingDelete: Entry?

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
                ForEach(groupedSections, id: \.key) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            NavigationLink(value: entry) {
                                TimelineEntryCard(entry: entry, mediaStore: env.mediaStore)
                            }
                            .buttonStyle(.plain)
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
                        sectionHeader(section.key)
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: Entry.self) { entry in
            EntryDetailView(entry: entry)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(BubuTheme.Font.headline)
            .foregroundStyle(BubuTheme.Color.warmBrown)
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
