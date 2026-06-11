import SwiftUI
import SwiftData

// MARK: - 疫苗接种表（国家免疫规划一类苗）
/// 按布布月龄自动排期 + 完成打卡（本地 UserDefaults，零同步迁移风险）。
struct VaccineView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]

    /// 已完成的剂次 id 集合，存 UserDefaults（JSON 字符串数组）。
    @AppStorage("bubu.vaccine.done") private var doneRaw: String = "[]"

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    private var doneSet: Set<String> {
        guard let data = doneRaw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryCard
                ForEach(groupedByYear, id: \.0) { yearLabel, doses in
                    sectionHeader(yearLabel)
                    ForEach(doses) { dose in doseRow(dose) }
                }
                disclaimer
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("疫苗接种")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var done: Set<String> { doneSet }

    private var summaryCard: some View {
        let total = VaccineDose.schedule.count
        let completed = done.count
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
        VaccineDose.schedule.filter { !done.contains($0.id) }.min { $0.monthDue < $1.monthDue }
    }

    private func dueText(_ dose: VaccineDose) -> String {
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
        let isDone = done.contains(dose.id)
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

    private func toggle(_ dose: VaccineDose) {
        var set = done
        if set.contains(dose.id) { set.remove(dose.id) }
        else { set.insert(dose.id); BubuHaptics.success() }
        if let data = try? JSONEncoder().encode(Array(set).sorted()),
           let str = String(data: data, encoding: .utf8) {
            doneRaw = str
        }
    }

    private var disclaimer: some View {
        Text("依据国家免疫规划（一类苗）排期，地区与个体差异以当地接种点通知为准。打卡仅作家庭提醒。")
            .font(.system(size: 12))
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .padding(.top, 4)
    }
}
