import SwiftUI
import SwiftData

// MARK: - 时光轴
/// @Query 按 happenedAt 倒序读取本地 Entry，按「年-月」分段展示。
/// 离线优先：UI 只读本地 SwiftData，断网全功能可用。
struct TimelineView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(
        filter: #Predicate<Entry> { !$0.isArchived },
        sort: \Entry.happenedAt,
        order: .reverse
    )
    private var entries: [Entry]

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
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(BubuTheme.Color.primary.opacity(0.7))
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
}
