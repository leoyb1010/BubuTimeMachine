import SwiftUI

// MARK: - 布布个人身份卡
/// 首页顶部的「学生证/工作证」风格卡片：头像、姓名、年龄、生日、来到世界第几天、
/// 出生地、短 ID 与条码装饰。克制配色 + 玻璃质感，点击进入资料编辑。
struct BubuIdentityCard: View {
    let profile: ChildProfile
    let theme: BubuThemeDefinition
    let mediaStore: MediaStore

    private var ageText: String {
        AgeCalculator.ageDescription(birthday: profile.birthday, at: .now)
    }

    private var daysText: String {
        "第 \(AgeCalculator.daysSinceBirth(birthday: profile.birthday)) 天"
    }

    private var shortID: String {
        String(profile.id.uuidString.prefix(8)).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            clipBar

            HStack(alignment: .top, spacing: 14) {
                avatarBlock

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BUBU IDENTITY")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.4)
                                .foregroundStyle(theme.primary.opacity(0.72))

                            Text(profile.name)
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(BubuTheme.Color.warmBrown)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }

                        Spacer()

                        Text("ACTIVE")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(theme.primary, in: Capsule())
                    }

                    infoGrid

                    HStack(spacing: 8) {
                        barcode
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ID NO. \(shortID)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                            Text("小小探险家 · 家庭认证")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.primary)
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .background(cardBackground)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(theme.primary.opacity(0.10))
                .frame(width: 96, height: 96)
                .offset(x: 28, y: 36)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .bubuCardShadow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("布布身份卡，\(profile.name)，\(ageText)，\(daysText)，点击编辑资料")
    }

    private var clipBar: some View {
        HStack {
            Capsule()
                .fill(.white.opacity(0.64))
                .frame(width: 54, height: 7)
                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
            Spacer()
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.primary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var avatarBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let name = profile.avatarMediaFileName,
                   let data = mediaStore.data(forMedia: name),
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    BubuMascotBadge(size: 88, expression: .happy)
                }
            }
            .frame(width: 92, height: 110)
            .background(BubuTheme.Color.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.65), lineWidth: 1)
            }

            Text("布布")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(theme.primary, in: Capsule())
                .offset(x: 6, y: 6)
        }
    }

    private var infoGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                idChip(title: "AGE", value: ageText)
                idChip(title: "DAY", value: daysText)
            }
            HStack(spacing: 8) {
                idChip(title: "BIRTH", value: BubuDateFormat.shortDate(profile.birthday))
                idChip(title: "FROM", value: profile.birthPlace?.isEmpty == false ? profile.birthPlace! : "地球小站")
            }
        }
    }

    private func idChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(theme.primary.opacity(0.70))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var barcode: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<12, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 1)
                    .fill(BubuTheme.Color.warmBrown.opacity(idx.isMultiple(of: 3) ? 0.55 : 0.28))
                    .frame(width: idx.isMultiple(of: 4) ? 3 : 2,
                           height: CGFloat([12, 18, 9, 15, 20, 11][idx % 6]))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                BubuTheme.Color.card.opacity(0.86),
                theme.primary.opacity(0.10),
                .white.opacity(0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
