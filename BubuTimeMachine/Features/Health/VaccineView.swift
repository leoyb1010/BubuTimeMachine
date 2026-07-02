import SwiftUI
import SwiftData

// MARK: - 疫苗接种表（国家免疫规划一类苗）
/// 数据源：结构化 VaccineRecord（SwiftData，可同步、可被 AI 归档、旧打卡自动迁移）。
/// 交互：点剂次 → 补录/修改详情 sheet；长按未完成剂次 → 一键快速完成；
/// 取消打卡走 PendingDeletion 删除队列，离线也不会在下轮拉取时复活。
struct VaccineView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ChildProfile]
    @Query(sort: \VaccineRecord.injectedAt) private var records: [VaccineRecord]

    @State private var logTarget: VaccineLogTarget?

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    /// 已完成的排期剂次（doseId → 记录），自由疫苗记录不参与排期打卡。
    private var recordByDose: [String: VaccineRecord] {
        Dictionary(records.compactMap { record in
            record.doseId.map { ($0, record) }
        }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryCard
                hintRow
                ForEach(groupedByYear, id: \.0) { yearLabel, doses in
                    sectionHeader(yearLabel)
                    ForEach(doses) { dose in doseRow(dose) }
                }
                if !extraRecords.isEmpty {
                    sectionHeader("其他疫苗记录")
                    ForEach(extraRecords) { record in extraRow(record) }
                }
                disclaimer
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("疫苗接种")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $logTarget) { target in
            VaccineQuickLogSheet(dose: target.dose,
                                 record: target.record,
                                 birthday: profile?.birthday)
        }
    }

    /// 不在国家排期内（AI 归档的自费苗等）的记录。
    private var extraRecords: [VaccineRecord] {
        records.filter { $0.doseId == nil }
    }

    private var summaryCard: some View {
        let total = VaccineDose.schedule.count
        let completed = recordByDose.count
        return HStack(spacing: 14) {
            BubuMascotBadge(size: 48, expression: .cheer)
            VStack(alignment: .leading, spacing: 4) {
                Text("已完成 \(completed) / \(total) 剂")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                if let next = nextDue {
                    Text("下一针：\(next.shortName) \(next.doseLabel) · \(dueText(next))")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(theme)
                } else {
                    Text("规划内的疫苗都打齐啦 🎉")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(theme)
                }
            }
            Spacer()
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var hintRow: some View {
        Text("点剂次补录日期/医院/反应 · 长按未完成的快速打卡")
            .font(.system(size: 11))
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .padding(.leading, 6)
    }

    private var nextDue: VaccineDose? {
        VaccineDose.schedule.filter { recordByDose[$0.id] == nil }.min { $0.monthDue < $1.monthDue }
    }

    /// 未完成：到期提示；已完成：显示接种日期。
    private func dueText(_ dose: VaccineDose) -> String {
        if let record = recordByDose[dose.id] {
            return BubuDateFormat.shortDate(record.injectedAt)
        }
        guard let profile else { return "\(dose.monthDue) 月龄" }
        let date = dose.dueDate(birthday: profile.birthday)
        if date < .now { return "建议尽快补种" }
        return BubuDateFormat.shortDate(date)
    }

    /// 按"周岁段"分组，方便家长一眼看。
    private var groupedByYear: [(String, [VaccineDose])] {
        let groups = Dictionary(grouping: VaccineDose.schedule.sorted { $0.monthDue < $1.monthDue }) {
            $0.monthDue / 12
        }
        return groups.keys.sorted().map { year in
            (year == 0 ? "1 岁内" : "\(year)–\(year + 1) 岁", groups[year] ?? [])
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(BubuTheme.Font.caption.weight(.semibold))
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .padding(.top, 8).padding(.leading, 6)
    }

    /// 旧版打卡迁移、接种日期尚未被家长确认。
    private func needsDateConfirm(_ record: VaccineRecord) -> Bool {
        record.sourceRaw == "migration" && (record.note?.contains("待确认") ?? false)
    }

    private func doseRow(_ dose: VaccineDose) -> some View {
        let record = recordByDose[dose.id]
        let isDone = record != nil
        return HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(isDone ? BubuTheme.Color.success : BubuTheme.Color.secondaryText.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(dose.shortName) · \(dose.doseLabel)")
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .strikethrough(isDone, color: BubuTheme.Color.secondaryText)
                    if let record, needsDateConfirm(record) {
                        Text("日期待确认")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(theme)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(theme.opacity(0.12), in: Capsule())
                    }
                }
                Text("\(dose.vaccine) · 预防\(dose.prevents)")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(dueText(dose))
                .font(.system(size: 11))
                .foregroundStyle(isDone ? BubuTheme.Color.secondaryText : theme)
        }
        .padding(12)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            logTarget = VaccineLogTarget(dose: dose, record: record)
        }
        .onLongPressGesture {
            guard record == nil else { return }
            instantComplete(dose)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dose.shortName) \(dose.doseLabel)，\(isDone ? "已完成，点按修改" : "未完成，点按补录，长按快速完成")")
    }

    private func extraRow(_ record: VaccineRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "syringe")
                .font(.system(size: 20))
                .foregroundStyle(theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.vaccineName)
                    .font(BubuTheme.Font.body.weight(.medium))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                if let detail = record.hospital ?? record.note {
                    Text(detail)
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(BubuDateFormat.shortDate(record.injectedAt))
                .font(.system(size: 11))
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding(12)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            logTarget = VaccineLogTarget(dose: nil, record: record)
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteRecord(record)
            } label: {
                Label("删除这条记录", systemImage: "trash")
            }
        }
    }

    /// 长按一键完成：接种日取「排期日与今天的较早者」，细节可此后点开补录。
    private func instantComplete(_ dose: VaccineDose) {
        let due = profile.map { dose.dueDate(birthday: $0.birthday) } ?? .now
        let record = VaccineRecord(vaccineName: dose.vaccine,
                                   injectedAt: min(due, .now),
                                   source: "manual")
        record.doseId = dose.id
        record.doseLabel = dose.doseLabel
        record.syncState = .local
        context.insert(record)
        try? context.save()
        BubuHaptics.success()
        env.syncEngine.syncNow()
    }

    private func deleteRecord(_ record: VaccineRecord) {
        let collection = record.sourceRaw == "health-fallback" ? "healthrecords" : "vaccinerecords"
        PendingDeletion.enqueue(collection: collection, remoteId: record.remoteId, in: context)
        context.delete(record)
        try? context.save()
        env.syncEngine.syncNow()
    }

    private var disclaimer: some View {
        Text("依据国家免疫规划（一类苗）排期，地区与个体差异以当地接种点通知为准。打卡仅作家庭提醒。")
            .font(.system(size: 12))
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .padding(.top, 4)
    }
}

/// 补录/编辑 sheet 的路由载体。
struct VaccineLogTarget: Identifiable {
    let dose: VaccineDose?
    let record: VaccineRecord?
    var id: String { dose?.id ?? record?.id.uuidString ?? UUID().uuidString }
}
