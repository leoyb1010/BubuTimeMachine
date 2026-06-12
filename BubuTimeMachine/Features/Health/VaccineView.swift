import SwiftUI
import SwiftData

// MARK: - 疫苗接种表（国家免疫规划一类苗）
/// 按布布月龄自动排期 + 完成打卡。
/// 数据源已从 @AppStorage 升级为结构化 VaccineRecord（SwiftData）：
/// 可记录日期、可家庭同步、可被 AI 一句话自动归档；旧打卡由启动迁移自动转换。
struct VaccineView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ChildProfile]
    @Query(sort: \VaccineRecord.injectedAt) private var records: [VaccineRecord]

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

    private var nextDue: VaccineDose? {
        VaccineDose.schedule.filter { recordByDose[$0.id] == nil }.min { $0.monthDue < $1.monthDue }
    }

    /// 未完成：到期提示；已完成：显示接种日期（不再出现「建议尽快补种」）。
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

    private func doseRow(_ dose: VaccineDose) -> some View {
        let isDone = recordByDose[dose.id] != nil
        return Button {
            toggle(dose)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isDone ? BubuTheme.Color.success : BubuTheme.Color.secondaryText.opacity(0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(dose.shortName) · \(dose.doseLabel)")
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .strikethrough(isDone, color: BubuTheme.Color.secondaryText)
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
        }
        .buttonStyle(.plain)
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
                if let note = record.note {
                    Text(note)
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
    }

    private func toggle(_ dose: VaccineDose) {
        if let record = recordByDose[dose.id] {
            // 取消打卡：本地删除；已上云的远端也删，避免下轮拉取复活
            let remoteId = record.remoteId
            context.delete(record)
            try? context.save()
            if let remoteId {
                let client = env.apiClient
                Task { try? await client.deleteVaccineRecord(remoteId: remoteId) }
            }
        } else {
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
    }

    private var disclaimer: some View {
        Text("依据国家免疫规划（一类苗）排期，地区与个体差异以当地接种点通知为准。打卡仅作家庭提醒。")
            .font(.system(size: 12))
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .padding(.top, 4)
    }
}
