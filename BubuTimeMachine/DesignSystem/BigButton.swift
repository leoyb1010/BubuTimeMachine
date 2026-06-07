import SwiftUI

// MARK: - 超大主按钮（适老）
/// 占屏幕约 1/2，无需精准点击。姥姥场景的关键交付物。
struct BigButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 72, weight: .medium))
                Text(title)
                    .font(BubuTheme.Font.title)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(
                LinearGradient(
                    colors: [BubuTheme.Color.primary,
                             BubuTheme.Color.primary.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.button, style: .continuous))
            .bubuCardShadow()
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.18)) { pressed = false } }
        )
    }
}

#Preview {
    BigButton(title: "记录此刻", systemImage: "heart.circle.fill") {}
        .padding()
        .background(BubuTheme.Color.background)
}
