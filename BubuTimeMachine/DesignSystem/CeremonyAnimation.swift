import SwiftUI

// MARK: - 仪式动画
/// 里程碑 / 人生第一次完成时的温暖仪式感。轻量、温柔，不喧宾夺主。
struct CeremonyAnimation: View {
    let title: String
    let subtitle: String?
    var onDismiss: () -> Void

    @State private var appear = false
    @State private var sparkle = false

    var body: some View {
        ZStack {
            BubuTheme.Color.warmBrown.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                ZStack {
                    ForEach(0..<8, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 18))
                            .foregroundStyle(BubuTheme.Color.primary)
                            .offset(y: sparkle ? -70 : -40)
                            .rotationEffect(.degrees(Double(i) / 8 * 360))
                            .opacity(sparkle ? 0 : 1)
                    }
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 88))
                        .foregroundStyle(BubuTheme.Color.primary)
                        .scaleEffect(appear ? 1 : 0.4)
                }

                Text(title)
                    .font(BubuTheme.Font.title)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(40)
            .scaleEffect(appear ? 1 : 0.8)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true }
            withAnimation(.easeOut(duration: 1.1).delay(0.2)) { sparkle = true }
        }
    }
}
