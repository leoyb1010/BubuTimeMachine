import SwiftUI
import SwiftData

// MARK: - 布布健康
struct HealthHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \HealthRecord.recordedAt, order: .reverse) private var records: [HealthRecord]
    @State private var composingKind: HealthRecordKind?

    private var theme: Color { env.theme.theme.primary }
    private var todayRecords: [HealthRecord] { records.filter { Calendar.current.isDateInToday($0.recordedAt) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                header
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
                    if let amount = record.amountText, !amount.isEmpty { Text(amount) }
                }
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                if let detail = record.detail, !detail.isEmpty {
                    Text(detail).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                if let reaction = record.reaction, !reaction.isEmpty {
                    Text("反应：\(reaction)").font(BubuTheme.Font.caption).foregroundStyle(theme)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    private var disclaimer: some View {
        Text("如果出现持续发热、过敏、精神状态异常等情况，请及时咨询医生。这里的记录主要用于家庭观察和复盘。")
            .font(.system(size: 12))
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .padding(.top, 4)
    }
}
