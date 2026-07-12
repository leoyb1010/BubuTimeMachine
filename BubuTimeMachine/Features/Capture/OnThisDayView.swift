import SwiftUI
import SwiftData

// MARK: - 那年今日 · 落地页（Wave L §5.3）
/// 按年份纵向排「2025 的今天 / 2024 的今天」，每年一张大卡（照片 + 当时年龄 + 当时记录原文）。
/// 空年份显示「这一年的今天没有记录——今天补一条？」，把怀旧转化为新记录。
struct OnThisDayView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var profiles: [ChildProfile]

    @State private var startQuickCapture = false

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(yearRows, id: \.year) { row in
                    yearCard(row)
                }
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("那年今日")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        let today = Date.now
        return VStack(alignment: .leading, spacing: 6) {
            Text(BubuDateFormat.monthDay(today) + " 的回忆")
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("每一年的今天，布布都在长大")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
    }

    // MARK: 年份行

    private struct YearRow {
        let year: Int
        let entries: [Entry]   // 该年同月同日的记录（可能为空）
    }

    /// 从布布出生那年的"今天"到今年，每年一行（含空年）。
    private var yearRows: [YearRow] {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: .now)
        let thisYear = cal.component(.year, from: .now)
        let startYear: Int = {
            if let birthday = profile?.birthday { return cal.component(.year, from: birthday) }
            if let earliest = entries.map(\.happenedAt).min() { return cal.component(.year, from: earliest) }
            return thisYear
        }()

        // 同月同日且往年的记录，按年分组。
        let matched = entries.filter { e in
            let c = cal.dateComponents([.month, .day], from: e.happenedAt)
            return c.month == today.month && c.day == today.day && !cal.isDateInToday(e.happenedAt)
        }
        let byYear = Dictionary(grouping: matched) { cal.component(.year, from: $0.happenedAt) }

        return stride(from: thisYear - 1, through: startYear, by: -1).map { year in
            YearRow(year: year, entries: byYear[year] ?? [])
        }
    }

    @ViewBuilder
    private func yearCard(_ row: YearRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(String(row.year)) 年的今天")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                if let profile, let date = sampleDate(row) {
                    Text(AgeCalculator.compactAge(birthday: profile.birthday, at: date))
                        .font(BubuTheme.Font.caption.weight(.medium))
                        .foregroundStyle(theme)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(theme.opacity(0.1), in: Capsule())
                }
            }

            if row.entries.isEmpty {
                emptyYear(row.year)
            } else {
                ForEach(row.entries) { entry in
                    NavigationLink(value: entry.id) { memoryRow(entry) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func sampleDate(_ row: YearRow) -> Date? {
        row.entries.first?.happenedAt
    }

    private func memoryRow(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let media = entry.coverMedia {
                MediaThumbnail(media: media, mediaStore: env.mediaStore, cornerRadius: BubuTheme.Radius.small, size: .card)
                    .frame(width: 96, height: 96)
            } else {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.small)
                    .fill(theme.opacity(0.12))
                    .frame(width: 96, height: 96)
                    .overlay { Text(entry.mood?.emoji ?? "📝").font(BubuTheme.Font.scaled(36)) }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("那天的布布").font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Text(BubuDateFormat.shortDate(entry.happenedAt))
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer()
        }
    }

    private func emptyYear(_ year: Int) -> some View {
        HStack(spacing: 12) {
            BubuMascotBadge(size: 44, expression: .bye)
            Text("这一年的今天没有记录")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
