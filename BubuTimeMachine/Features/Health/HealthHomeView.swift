import SwiftUI
import SwiftData

// MARK: - 布布健康
struct HealthHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(sort: \HealthRecord.recordedAt, order: .reverse) private var records: [HealthRecord]
    @State private var composingKind: HealthRecordKind?
    /// 进行中的哄睡开始时刻（App Group 持久化：杀掉重开也能收尾）
    @State private var sleepStartedAt: Date? = SharedDefaults.sleepStartedAt
    @State private var editingRecord: HealthRecord?
    @State private var deletingRecord: HealthRecord?

    private var theme: Color { env.theme.theme.primary }
    private var todayRecords: [HealthRecord] { records.filter { Calendar.current.isDateInToday($0.recordedAt) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                header
                sleepTimerCard
                insightLinks
                quickActions
                todaySection
                recentSection
                disclaimer
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("布布健康")
        .sheet(item: $composingKind) { kind in
            HealthRecordSheet(kind: kind)
        }
        .sheet(item: $editingRecord) { record in
            HealthRecordSheet(kind: record.kind, record: record)
        }
        .alert("删除这条健康记录？", isPresented: Binding(
            get: { deletingRecord != nil },
            set: { if !$0 { deletingRecord = nil } }
        )) {
            Button("删除", role: .destructive) { deletePendingRecord() }
            Button("取消", role: .cancel) { deletingRecord = nil }
        } message: {
            Text("删除后会同步到家里服务器，其他设备不会再拉回这条记录。")
        }
    }

    // MARK: 哄睡计时（R4 E-3：锁屏/灵动岛实时计时，醒来一键落一条睡眠记录）

    @ViewBuilder
    private var sleepTimerCard: some View {
        if let startedAt = sleepStartedAt {
            HStack(spacing: 12) {
                Text("😴").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 3) {
                    Text("布布睡着啦")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(startedAt, style: .timer)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme)
                }
                Spacer()
                Button {
                    endSleep(startedAt: startedAt)
                } label: {
                    Text("醒啦")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(theme, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(theme.opacity(0.10), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        } else {
            Button {
                startSleep()
            } label: {
                HStack(spacing: 12) {
                    Text("🌙").font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开始哄睡计时")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("锁屏和灵动岛都能看到睡了多久，醒来点一下自动记好")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(theme)
                }
                .padding(14)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                .bubuCardShadow()
            }
            .buttonStyle(.plain)
        }
    }

    private func startSleep() {
        let now = Date.now
        sleepStartedAt = now
        SharedDefaults.sleepStartedAt = now
        BubuActivityController.startSleepTimer(childName: env.config.childName, startedAt: now)
        BubuHaptics.success()
    }

    private func endSleep(startedAt: Date) {
        let end = Date.now
        sleepStartedAt = nil
        SharedDefaults.sleepStartedAt = nil

        let record = HealthRecord(kind: .sleep, title: "睡觉", recordedAt: end)
        record.startAt = startedAt
        record.endAt = end
        let hours = end.timeIntervalSince(startedAt) / 3600
        record.amountValue = hours
        record.amountUnit = "小时"
        record.amountText = HealthRecordDraft.durationText(from: startedAt, to: end)
        record.syncState = .local
        context.insert(record)
        context.insert(FeedEvent(kind: .healthRecorded,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "记录了睡眠：\(record.amountText ?? "")"))
        try? context.save()
        BubuActivityController.endSleepTimer(elapsedText: record.amountText ?? "")
        env.refreshWidgetSnapshot(context: context)
        env.syncEngine.syncNow()
        BubuHaptics.success()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("餐食、零食、营养补充都记在这里", systemImage: "heart.text.square.fill")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(theme)
            Text("这是家庭照护记录，不替代医生建议。它帮你看见布布每天吃了什么、睡得怎样、有没有不舒服。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    /// 成长曲线 / 疫苗接种入口（从流水账升级到可视化）。
    private var insightLinks: some View {
        HStack(spacing: 10) {
            NavigationLink { GrowthCurveView() } label: {
                insightTile(icon: "chart.xyaxis.line", title: "成长曲线", subtitle: "身高·体重·头围")
            }
            .buttonStyle(.plain)
            NavigationLink { VaccineView() } label: {
                insightTile(icon: "syringe.fill", title: "疫苗接种", subtitle: "按月龄排期打卡")
            }
            .buttonStyle(.plain)
        }
    }

    private func insightTile(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme)
            Text(title).font(BubuTheme.Font.body.weight(.semibold))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(subtitle).font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var quickActions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            ForEach(HealthRecordKind.allCases) { kind in
                Button { composingKind = kind } label: {
                    HStack(spacing: 10) {
                        Text(kind.emoji).font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(BubuTheme.Font.body.weight(.semibold))
                            Text(kind.placeholder).font(.system(size: 11)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("今天", systemImage: "sun.max.fill")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            if todayRecords.isEmpty {
                Text("今天还没有健康记录。可以先记一顿餐食或一次喝水。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            } else {
                ForEach(todayRecords.prefix(6)) { recordRow($0) }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("最近记录", systemImage: "clock.fill")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            ForEach(records.prefix(12)) { recordRow($0) }
        }
    }

    private func recordRow(_ record: HealthRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(record.kind.emoji).font(.system(size: 28))
                .frame(width: 42, height: 42)
                .background(theme.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title).font(BubuTheme.Font.body.weight(.semibold)).foregroundStyle(BubuTheme.Color.warmBrown)
                HStack(spacing: 8) {
                    Text(record.kind.title)
                    Text(BubuDateFormat.shortTime(record.recordedAt))
                    if let amount = amountSummary(record) { Text(amount) }
                }
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                if !record.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(record.tags.prefix(5), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(theme.opacity(0.10), in: Capsule())
                        }
                    }
                }
                if let detail = record.detail, !detail.isEmpty {
                    Text(detail).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                if let reaction = record.reaction, !reaction.isEmpty {
                    Text("反应：\(reaction)").font(BubuTheme.Font.caption).foregroundStyle(theme)
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Button {
                    editingRecord = record
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 38, height: 38)
                        .background(theme.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑健康记录")

                Button(role: .destructive) {
                    deletingRecord = record
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 38, height: 38)
                        .background(BubuTheme.Color.danger.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除健康记录")
            }
        }
        .padding(12)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    private func deletePendingRecord() {
        guard let record = deletingRecord else { return }
        PendingDeletion.enqueue(collection: "healthrecords", remoteId: record.remoteId, in: context)
        context.delete(record)
        try? context.save()
        env.refreshWidgetSnapshot(context: context)
        WidgetRefresher.reload()
        env.syncEngine.syncNow()
        deletingRecord = nil
    }

    private func amountSummary(_ record: HealthRecord) -> String? {
        if let amount = record.amountText, !amount.isEmpty { return amount }
        if record.kind == .sleep, let start = record.startAt, let end = record.endAt, end > start {
            return HealthRecordDraft.durationText(from: start, to: end)
        }
        if let value = record.amountValue, let unit = record.amountUnit {
            return "\(HealthRecordDraft.cleanAmount(value))\(unit)"
        }
        if let temp = record.temperatureCelsius {
            return String(format: "%.1f℃", temp)
        }
        return nil
    }

    private var disclaimer: some View {
        Text("如果出现持续发热、过敏、精神状态异常等情况，请及时咨询医生。这里的记录主要用于家庭观察和复盘。")
            .font(.system(size: 12))
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .padding(.top, 4)
    }
}
