import SwiftUI

// MARK: - 「东西搬走了」一次性提示
/// 信息架构调整最大的代价不是新布局不好，而是**老用户找不到东西了**。
/// 迁走入口的原位置留一条一次性提示：说清搬去哪儿，用户点「知道了」就永久收起。
///
/// 只用 AppStorage 记一个布尔键，不进 SwiftData、不参与同步——
/// 「这台设备上的这个人看过了」本来就是本机状态。
struct BubuMovedHint: View {
    let storageKey: String
    let message: String
    var systemImage: String = "arrow.turn.down.right"

    @AppStorage private var dismissed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(storageKey: String, message: String, systemImage: String = "arrow.turn.down.right") {
        self.storageKey = storageKey
        self.message = message
        self.systemImage = systemImage
        _dismissed = AppStorage(wrappedValue: false, storageKey)
    }

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(BubuTheme.Font.caption.weight(.bold))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                    .padding(.top, 2)
                Text(message)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button("知道了") {
                    if reduceMotion {
                        dismissed = true
                    } else {
                        withAnimation(BubuMotion.gentle) { dismissed = true }
                    }
                }
                .font(BubuTheme.Font.caption.weight(.bold))
                .foregroundStyle(BubuTheme.Color.deepRose)
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BubuTheme.Color.peachSurface.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }
}
