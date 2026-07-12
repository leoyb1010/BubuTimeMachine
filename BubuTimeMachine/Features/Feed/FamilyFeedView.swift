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

    // 动态行缓存：从多张表现场派生，但只在数据指纹变化时重算一次。
    // 关键修复：原先 derivedEvents 每次 body 都 new 一批 id=UUID() 的 @Model，
    // 列表 diff/滚动位置全失效 + 每次重算全表 faulting（U-P1-4）。
    @State private var rows: [FeedRow] = []

    private var theme: Color { env.theme.theme.primary }

    /// 轻量指纹：各表条数 + 最新时间戳；变化即重建，不构建数组。
    private var fingerprint: String {
        "\(events.count)-\(entries.count)-\(comments.count)-\(milestones.count)"
        + "-\(Int(events.first?.happenedAt.timeIntervalSince1970 ?? 0))"
        + "-\(Int(entries.first?.happenedAt.timeIntervalSince1970 ?? 0))"
        + "-\(Int(comments.first?.createdAt.timeIntervalSince1970 ?? 0))"
    }

    private var filteredRows: [FeedRow] {
        guard let selectedKind else { return rows }
        return rows.filter { $0.kind == selectedKind }
    }

    /// FeedEvent 表不参与同步（各设备只有自己产生的）。要看到全家的动态，
    /// 从【已同步的数据】现场派生：Entry、Comment（含语音补充）、Milestone（R4 P2-22）。
    /// 派生结果用值类型 FeedRow，id 取稳定键 kind|target，跨 body 恒定。
    private func rebuildRows() {
        let persisted = Set(events.compactMap { e in e.targetLocalId.map { "\(e.kindRaw)|\($0)" } })
        func fresh(_ kind: FeedEventKind, _ target: String) -> Bool {
            !persisted.contains("\(kind.rawValue)|\(target)")
        }

        var all: [FeedRow] = []
        // 已持久化事件（本机产生）
        for e in events {
            let key = e.targetLocalId.map { "\(e.kindRaw)|\($0)" } ?? "\(e.kindRaw)|\(e.id.uuidString)"
            all.append(FeedRow(id: key, kind: e.kind, actorRole: e.actorRole,
                               summary: e.summary, happenedAt: e.happenedAt, targetLocalId: e.targetLocalId))
        }
        for entry in entries {
            let target = entry.id.uuidString
            guard fresh(.entryCreated, target) else { continue }
            all.append(FeedRow(id: "\(FeedEventKind.entryCreated.rawValue)|\(target)", kind: .entryCreated,
                               actorRole: entry.authorRole,
                               summary: entry.note?.isEmpty == false ? "记录了：\(entry.note!)" : "记录了布布的一个新瞬间",
                               happenedAt: entry.happenedAt, targetLocalId: target))
        }
        // 家人的评论/语音补充：每条评论用自己的 id 做目标，互相不会吞掉（R4 P2-23）
        for comment in comments {
            guard let entry = comment.entry, !entry.isArchived else { continue }
            let target = comment.id.uuidString
            let isVoice = comment.voiceFileName != nil || comment.remoteURL != nil
            let kind: FeedEventKind = isVoice ? .voiceAdded : .commentAdded
            guard fresh(kind, target) else { continue }
            let text = comment.text?.isEmpty == false ? "补充了：\(comment.text!)" : "补了一段语音"
            all.append(FeedRow(id: "\(kind.rawValue)|\(target)", kind: kind,
                               actorRole: comment.authorRole, summary: text,
                               happenedAt: comment.createdAt, targetLocalId: target))
        }
        for m in milestones {
            guard let happened = m.happenedAt else { continue }
            let target = m.id.uuidString
            guard fresh(.milestoneLit, target) else { continue }
            all.append(FeedRow(id: "\(FeedEventKind.milestoneLit.rawValue)|\(target)", kind: .milestoneLit,
                               actorRole: "家人", summary: "点亮了里程碑：\(m.title)",
                               happenedAt: happened, targetLocalId: target))
        }

        var seen = Set<String>()
        rows = all
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.happenedAt > $1.happenedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                filters
                ForEach(filteredRows) { row in
                    eventRow(row)
                }
                if filteredRows.isEmpty { emptyState }
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("家庭动态")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Entry.self) { EntryDetailView(entry: $0) }
        .onChange(of: fingerprint, initial: true) { _, _ in rebuildRows() }
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

    private func eventRow(_ event: FeedRow) -> some View {
        NavigationLink(value: entry(for: event)) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.kind.icon)
                    .font(BubuTheme.Font.scaled(22))
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

    private func entry(for event: FeedRow) -> Entry? {
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

// MARK: - 动态行（值类型，稳定 id）
/// 现场派生的动态行；id 取稳定键 kind|target，跨 body 恒定，供 ForEach diff 用。
private struct FeedRow: Identifiable {
    let id: String
    let kind: FeedEventKind
    let actorRole: String
    let summary: String
    let happenedAt: Date
    let targetLocalId: String?
}
