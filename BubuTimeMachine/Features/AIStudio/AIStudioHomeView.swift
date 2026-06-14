import SwiftUI

// MARK: - AI 工坊
/// 自托管 AI 的创作中心。当前为完整可玩的 Mock 工作流；
/// 正式部署接入真实 LLM 后，UI 与交互不变。
struct AIStudioHomeView: View {
    @Environment(AppEnvironment.self) private var env
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                banner

                storybookCard      // 成长绘本（把里程碑编织成翻页故事）

                Text("智能创作")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .padding(.leading, 6)
                    .padding(.top, 2)

                capabilityCard(
                    icon: "text.book.closed.fill",
                    title: "第一人称日记",
                    subtitle: "改写成布布的话",
                    destination: AnyView(FirstPersonDiaryView()))

                capabilityCard(
                    icon: "film.stack.fill",
                    title: "年度成长电影",
                    subtitle: "精选照片成短片",
                    destination: AnyView(GrowthMovieView()))

                capabilityCard(
                    icon: "person.3.sequence.fill",
                    title: "家人合奏",
                    subtitle: "合成完整故事",
                    destination: AnyView(FamilyEnsembleView()))

                capabilityCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "成长报告",
                    subtitle: "整理成长变化",
                    destination: AnyView(GrowthReportView()))

                Spacer(minLength: 30)
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("布布的故事")
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                BubuMascotBadge(size: 58, expression: .drawing)
                VStack(alignment: .leading, spacing: 4) {
                    Text("布布的故事").font(BubuTheme.Font.title)
                    Text("把瞬间变成故事")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [theme, theme.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    // 成长绘本主卡（butter→peach→pink，对照设计稿；点进翻页绘本）
    private var storybookCard: some View {
        NavigationLink {
            BubuStoryView()
        } label: {
            HStack(spacing: 14) {
                BubuDreamPhoto(hue: 18, height: 72, cornerRadius: 16, motif: "✦")
                    .frame(width: 60)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white, lineWidth: 3))
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("成长绘本")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    Text("由你记录的点滴，自动编织成可翻页的故事")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [BubuTheme.Color.butter, BubuTheme.Color.peach, BubuTheme.Color.pink],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                BubuSparkle(size: 13, color: .white.opacity(0.95)).padding(14)
            }
            .bubuCardShadow()
        }
        .buttonStyle(.plain)
    }

    private func capabilityCard(icon: String, title: String, subtitle: String, destination: AnyView) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(theme)
                    .frame(width: 54, height: 54)
                    .background(theme.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                    Text(subtitle).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding()
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
        }
        .buttonStyle(.plain)
    }
}
