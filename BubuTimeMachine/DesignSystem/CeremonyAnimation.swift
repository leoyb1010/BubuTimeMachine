import SwiftUI
import UIKit

// MARK: - 仪式动画
/// 里程碑 / 人生第一次完成时的温暖仪式感。轻量、温柔，不喧宾夺主。
/// 入场伴随成功触觉反馈；尊重「减弱动态效果」（直接定格，不放粒子）。
struct CeremonyAnimation: View {
    let title: String
    let subtitle: String?
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false
    @State private var sparkle = false
    @State private var secondWave = false

    var body: some View {
        ZStack {
            BubuTheme.Color.warmBrown.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                ZStack {
                    if !reduceMotion {
                        sparkleRing(count: 8, size: 18, near: -40, far: -70, fired: sparkle)
                        sparkleRing(count: 6, size: 12, near: -30, far: -92, fired: secondWave)
                            .rotationEffect(.degrees(22))
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            guard !reduceMotion else {
                appear = true
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true }
            withAnimation(.easeOut(duration: 1.1).delay(0.2)) { sparkle = true }
            withAnimation(.easeOut(duration: 1.3).delay(0.45)) { secondWave = true }
        }
    }

    private func sparkleRing(count: Int, size: CGFloat, near: CGFloat, far: CGFloat, fired: Bool) -> some View {
        ForEach(0..<count, id: \.self) { i in
            Image(systemName: "sparkle")
                .font(.system(size: size))
                .foregroundStyle(BubuTheme.Color.primary)
                .offset(y: fired ? far : near)
                .rotationEffect(.degrees(Double(i) / Double(count) * 360))
                .opacity(fired ? 0 : 1)
        }
    }
}
