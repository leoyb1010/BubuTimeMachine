import SwiftUI

// MARK: - 超大主动作按钮（适老）
/// 姥姥模式的三个大按钮以前是 SimpleModeView 里自写的私有方法，和设计系统双轨；
/// 设计系统里那个 `BigButton` 又固定 176pt 高、零引用。这里合成一个共享组件。
///
/// 抗放大的三件事：
/// 1. 只给 minHeight、不给固定高度，配合上下 padding —— 字大了按钮长高，不裁字。
/// 2. `ViewThatFits`：横排（图标 ‖ 文字）放不下时自动改竖排（图标在上、文字在下），
///    而不是让「拍一张」在一条窄缝里断成三行。
/// 3. 无障碍最大档下 `scaled(cap:)` 一路放到 AX5（姥姥模式允许的最大档）—— 这个版面撑得住。
///
/// 对比度：白字压在深底上（每档两个色都 ≥ 4.8:1，含副标题），不再用马卡龙浅色 + 白字（原来只有 1.9–2.8:1）。
/// 深底固定不随深浅色模式变化：深色模式里白字照样清楚。
struct BubuBigActionButton: View {
    /// 深色填充（两色渐变，两端对白字都 ≥ 4.5:1）。
    struct Fill: Sendable {
        let top: Color
        let bottom: Color
        /// 玫瑰：#C2456F → #9E2F57（白字 4.8 / 7.0:1）
        static let rose = Fill(top: Color(red: 0.761, green: 0.271, blue: 0.435), bottom: Color(red: 0.620, green: 0.184, blue: 0.341))
        /// 天蓝：#2F64A8 → #27589A（白字 6.0 / 7.1:1）
        static let sky = Fill(top: Color(red: 0.184, green: 0.392, blue: 0.659), bottom: Color(red: 0.153, green: 0.345, blue: 0.604))
        /// 青草：#2E7D52 → #237047（白字 5.0 / 6.0:1）
        static let leaf = Fill(top: Color(red: 0.180, green: 0.490, blue: 0.322), bottom: Color(red: 0.137, green: 0.439, blue: 0.278))
    }

    /// 最大放到 AX5：与 App 在姥姥模式放开的 dynamicTypeSize 上限一致。
    static let largestCategory: UIContentSizeCategory = .accessibilityExtraExtraExtraLarge

    let title: String
    let subtitle: String
    let systemImage: String
    var fill: Fill = .rose
    /// 无障碍朗读用的完整描述，缺省是「标题，副标题」。
    var accessibilityDescription: String? = nil
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var elderCap: UIContentSizeCategory { Self.largestCategory }

    var body: some View {
        Button {
            BubuHaptics.tapLight()
            action()
        } label: {
            ViewThatFits(in: .horizontal) {
                horizontalLayout
                verticalLayout
            }
            .padding(.horizontal, 22)
            .padding(.vertical, BubuTheme.Spacing.item)
            .frame(maxWidth: .infinity,
                   minHeight: BubuAdaptive.value(sizeClass, compact: 118, regular: 156))
            .background(
                LinearGradient(colors: [fill.top, fill.bottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            )
            .shadow(color: fill.bottom.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription ?? "\(title)，\(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 18) {
            icon
            texts(alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private var verticalLayout: some View {
        VStack(spacing: BubuTheme.Spacing.m) {
            icon
            texts(alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(BubuTheme.Font.scaled(42, weight: .black, design: .default, cap: elderCap))
            .foregroundStyle(.white)
            // 圆底跟着字号一起长，不固定 74pt——否则最大档下图标会撑破圆。
            .frame(minWidth: 74, minHeight: 74)
            .padding(BubuTheme.Spacing.s)
            .background(.white.opacity(0.18), in: Circle())
    }

    private func texts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: BubuTheme.Spacing.xs) {
            Text(title)
                .font(BubuTheme.Font.scaled(32, weight: .black, cap: elderCap))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(BubuTheme.Font.scaled(17, weight: .bold, cap: elderCap))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }
}
