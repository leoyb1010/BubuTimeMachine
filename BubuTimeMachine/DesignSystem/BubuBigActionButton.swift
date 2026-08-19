import SwiftUI

// MARK: - 超大主动作按钮（适老）
/// 姥姥模式的三个大按钮以前是 SimpleModeView 里自写的私有方法，和设计系统双轨；
/// 设计系统里那个 `BigButton` 又固定 176pt 高、零引用。这里合成一个共享组件。
///
/// 抗放大的三件事：
/// 1. 只给 minHeight、不给固定高度，配合上下 padding —— 字大了按钮长高，不裁字。
/// 2. `ViewThatFits`：横排（图标 ‖ 文字）放不下时自动改竖排（图标在上、文字在下），
///    而不是让「拍一张」在一条窄缝里断成三行。
/// 3. 无障碍最大档下 `scaled(cap:)` 放开一档 —— 这个版面撑得住。
struct BubuBigActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = BubuTheme.Color.primary
    /// 无障碍朗读用的完整描述，缺省是「标题，副标题」。
    var accessibilityDescription: String? = nil
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var elderCap: UIContentSizeCategory { BubuTheme.Font.elderContentSizeCategory }

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
                LinearGradient(colors: [tint, tint.opacity(0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            )
            .shadow(color: tint.opacity(0.3), radius: 12, y: 6)
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
            .background(.white.opacity(0.22), in: Circle())
    }

    private func texts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: BubuTheme.Spacing.xs) {
            Text(title)
                .font(BubuTheme.Font.scaled(32, weight: .black, cap: elderCap))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(BubuTheme.Font.scaled(17, weight: .bold, cap: elderCap))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }
}
