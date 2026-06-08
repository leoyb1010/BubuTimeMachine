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

                capabilityCard(
                    icon: "text.book.closed.fill",
                    title: "第一人称日记",
                    subtitle: "把父母视角，改写成布布自己的话",
                    destination: AnyView(FirstPersonDiaryView()))

                capabilityCard(
                    icon: "film.stack.fill",
                    title: "年度成长电影",
                    subtitle: "每一岁的精选，自动剪成一部小电影",
                    destination: AnyView(GrowthMovieView()))

                capabilityCard(
                    icon: "person.3.sequence.fill",
                    title: "家人合奏",
                    subtitle: "把三个人的补充，合成完整的故事",
                    destination: AnyView(FamilyEnsembleView()))

                capabilityCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "成长报告",
                    subtitle: "这段时间，布布有哪些悄悄的变化",
                    destination: AnyView(GrowthReportView()))

                Spacer(minLength: 30)
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("AI 工坊")
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
                    Text("布布的 AI 工坊").font(BubuTheme.Font.title)
                    Text("把零散的瞬间，变成有温度的作品。")
                        .font(BubuTheme.Font.body)
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
                    Text(subtitle).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(2)
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
