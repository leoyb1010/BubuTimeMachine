import SwiftUI
import SwiftData

// MARK: - 照片墙
/// 首页「张照片」统计卡的落地页：全部媒体三列网格，点开进对应记录详情。
struct PhotoWallView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]

    private var items: [(media: Media, entry: Entry)] {
        entries.flatMap { entry in
            entry.media
                .sorted { $0.createdAt < $1.createdAt }
                .map { (media: $0, entry: entry) }
        }
    }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                VStack(spacing: 16) {
                    BubuMascotBadge(size: 84, expression: .surprised)
                    Text("还没有照片\n回首页点「记录此刻」拍下第一张吧")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 120)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(items, id: \.media.id) { item in
                        NavigationLink(value: item.entry) {
                            MediaThumbnail(media: item.media, mediaStore: env.mediaStore, cornerRadius: 6, size: .grid)
                                .aspectRatio(1, contentMode: .fit)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("布布的照片")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 生日倒计时
/// 首页「天后生日」统计卡的落地页：大数字倒计时 + 即将到来的岁数。
struct BirthdayCountdownView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            if let profile {
                let days = AgeCalculator.daysUntilNextBirthday(birthday: profile.birthday)
                let turning = AgeCalculator.ageYears(birthday: profile.birthday) + 1
                VStack(spacing: 22) {
                    BubuMascotBadge(size: 108, expression: .cheer)
                    VStack(spacing: 8) {
                        Text("\(days)")
                            .font(.system(size: 88, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme)
                            .contentTransition(.numericText())
                        Text("天后，\(profile.name)就 \(turning) 岁啦")
                            .font(BubuTheme.Font.headline)
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                    }
                    Text(nextBirthdayText(profile.birthday))
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)

                    VStack(spacing: 6) {
                        Text("可以提前准备一封时间胶囊，")
                        Text("在生日当天「叮」一声打开。")
                    }
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .padding(.top, 14)
                }
                .padding(32)
            }
        }
        .navigationTitle("下个生日")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func nextBirthdayText(_ birthday: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: birthday)
        guard let next = cal.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime) else { return "" }
        return BubuDateFormat.longDate(next)
    }
}
