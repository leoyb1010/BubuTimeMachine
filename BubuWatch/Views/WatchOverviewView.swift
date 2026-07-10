import SwiftUI
import UIKit

// MARK: - 今日概览（抬腕即见）
struct WatchOverviewView: View {
    @Environment(WatchConnector.self) private var connector

    private var snap: WatchSnapshot? { connector.snapshot }
    private var name: String { snap?.childName ?? "布布" }
    private var birthday: Date? { snap?.birthday }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if let data = snap?.avatarData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 30, height: 30).clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                    } else {
                        Text("👶").font(.system(size: 22))
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                        if let birthday {
                            Text(AgeCalculator.ageDescription(birthday: birthday, at: .now))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(WatchTheme.rose)
                        }
                    }
                }

                if let birthday {
                    HStack(spacing: 8) {
                        stat(value: "\(AgeCalculator.daysSinceBirth(birthday: birthday, at: .now))",
                             label: "陪伴天", tint: WatchTheme.mint)
                        stat(value: "\(AgeCalculator.daysUntilNextBirthday(birthday: birthday, from: .now))",
                             label: "天后生日", tint: WatchTheme.butter)
                    }
                    if let s = snap {
                        stat(value: "\(s.achievedMilestones)/\(max(s.totalMilestones, 1))",
                             label: "里程碑", tint: WatchTheme.lav, wide: true)
                    }
                } else {
                    Text("打开手机上的布布时光机\n建立档案后，这里就有内容啦")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .containerBackground(WatchTheme.rose.opacity(0.18).gradient, for: .tabView)
    }

    private func stat(value: String, label: String, tint: Color, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: wide ? 22 : 26, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
