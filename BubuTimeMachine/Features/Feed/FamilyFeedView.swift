import SwiftUI
import SwiftData

// MARK: - 家庭动态墙
struct FamilyFeedView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \FeedEvent.happenedAt, order: .reverse) private var events: [FeedEvent]
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse) private var entries: [Entry]
    @Query(sort: \Comment.createdAt, order: .reverse) private var comments: [Comment]
    @Query private var milestones: [Milestone]
    @State private var selectedKind: FeedEventKind?

    private var theme: Color { env.theme.theme.primary }
    private var filteredEvents: [FeedEvent] {
        guard let selectedKind else { return derivedEvents }
        return derivedEvents.filter { $0.kind == selectedKind }
    }
    /// FeedEvent 表不参与同步（各设备只有自己产生的）。要看到全家的动态，
    /// 从【已同步的数据】现场派生：Entry、Comment（含语音补充）、Milestone（R4 P2-22）。
    private var derivedEvents: [FeedEvent] {
        let persisted = Set(events.compactMap { e in e.targetLocalId.map { "\(e.kindRaw)|\($0)" } })
        func fresh(_ kind: FeedEventKind, _ target: String) -> Bool {
            !persisted.contains("\(kind.rawValue)|\(target)")
        }

        let entryEvents = entries.compactMap { entry -> FeedEvent? in
            let target = entry.id.uuidString
            guard fresh(.entryCreated, target) else { return nil }
            return FeedEvent(kind: .entryCreated, actorRole: entry.authorRole,
                             summary: entry.note?.isEmpty == false ? "记录了：\(entry.note!)" : "记录了布布的一个新瞬间",
                             targetLocalId: target, happenedAt: entry.happenedAt)
        }
        // 家人的评论/语音补充：每条评论用自己的 id 做目标，互相不会吞掉（R4 P2-23）
        let commentEvents = comments.compactMap { comment -> FeedEvent? in
            guard let entry = comment.entry, !entry.isArchived else { return nil }
            let target = comment.id.uuidString
            let isVoice = comment.voiceFileName != nil || comment.remoteURL != nil
            guard fresh(isVoice ? .voiceAdded : .commentAdded, target) else { return nil }
            let text = comment.text?.isEmpty == false ? "补充了：\(comment.text!)" : "补了一段语音"
            return FeedEvent(kind: isVoice ? .voiceAdded : .commentAdded,
                             actorRole: comment.authorRole, summary: text,
                             targetLocalId: target, happenedAt: comment.createdAt)
        }
        let milestoneEvents = milestones.compactMap { m -> FeedEvent? in
            guard let happened = m.happenedAt else { return nil }
            let target = m.id.uuidString
            guard fresh(.milestoneLit, target) else { return nil }
            return FeedEvent(kind: .milestoneLit, actorRole: "家人",
                             summary: "点亮了里程碑：\(m.title)",
                             targetLocalId: target, happenedAt: happened)
        }

        var seen = Set<String>()
        return (events + entryEvents + commentEvents + milestoneEvents)
            .filter { event in
                let key = event.targetLocalId.map { "\(event.kindRaw)|\($0)" }
                    ?? "\(event.kindRaw)|\(event.id.uuidString)"
                return seen.insert(key).inserted
            }
            .sorted { $0.happenedAt > $1.happenedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                filters
                ForEach(filteredEvents) { event in
                    eventRow(event)
                }
                if filteredEvents.isEmpty { emptyState }
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("家庭动态")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Entry.self) { EntryDetailView(entry: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("布布的家庭动态墙")
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("谁记录了新瞬间、谁补充了评论、谁点亮了里程碑，都会汇到这里。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("全部", selected: selectedKind == nil) { selectedKind = nil }
                ForEach(FeedEventKind.allCases) { kind in
                    filterChip(kind.title, selected: selectedKind == kind) { selectedKind = kind }
                }
            }
        }
    }

    private func filterChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : theme)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? theme : theme.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func eventRow(_ event: FeedEvent) -> some View {
        NavigationLink(value: entry(for: event)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.kind.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(theme, in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(event.actorRole.isEmpty ? "家人" : event.actorRole)
                            .font(BubuTheme.Font.body.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text(event.kind.title)
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(theme)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(theme.opacity(0.1), in: Capsule())
                    }
                    Text(event.summary)
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(3)
                    Text(BubuDateFormat.shortDateTime(event.happenedAt))
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
            }
            .padding()
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(entry(for: event) == nil)
    }

    private func entry(for event: FeedEvent) -> Entry? {
        guard event.kind == .entryCreated,
              let target = event.targetLocalId,
              let id = UUID(uuidString: target) else { return nil }
        return entries.first { $0.id == id }
    }

    private var emptyState: some View {
        Text("还没有家庭动态。发一条记录后，这里就会热闹起来。")
            .font(BubuTheme.Font.body)
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
    }
}
