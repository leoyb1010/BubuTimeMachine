import SwiftUI
import SwiftData

// 注：原「照片墙 PhotoWallView」已退役——首页照片入口改为相册（AlbumHomeView）后它再无任何入口，
// 「全部照片」系统相册完整覆盖其功能（AlbumDetailView 同为三列网格直开查看器）。

/// 全屏查看器路由（相册体系共用）。
struct MediaViewerRoute: Identifiable {
    let initialMediaID: UUID
    var id: UUID { initialMediaID }
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
                            .font(BubuTheme.Font.scaled(88, weight: .bold, design: .rounded))
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
