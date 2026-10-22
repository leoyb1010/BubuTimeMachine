import SwiftUI
import UIKit

// MARK: - 仪式动画
/// 里程碑 / 人生第一次完成时的温暖仪式感。轻量、温柔，不喧宾夺主。
/// 卡片用暖色渐变（不用灰色毛玻璃，后者压在粉色页面上发闷），有照片时放一张照片。
/// 分三拍：卡片弹出 → 星星迸发 → 光环散开；减弱动态效果时直接到位、不放迸发。
struct CeremonyAnimation: View {
    let title: String
    let subtitle: String?
    /// 这一刻的照片（可选）。
    var photo: UIImage? = nil
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false
    @State private var sparkle = false
    @State private var burst = false

    var body: some View {
        ZStack {
            celebrationBackground
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 18) {
                ZStack {
                    if !reduceMotion {
                        sparkleRing
                    }

                    if let photo {
                        Image(uiImage: photo)
                            .resizable().scaledToFill()
                            .frame(width: 132, height: 132)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                            .overlay(alignment: .bottomTrailing) { BubuMascotBadge(size: 44, expression: .yeah) }
                            .scaleEffect(appear ? 1 : 0.64)
                            .accessibilityHidden(true)
                    } else {
                        BubuMascotBadge(size: 104, expression: .yeah)
                            .scaleEffect(appear ? 1 : 0.64)
                    }
                    if burst && !reduceMotion {
                        BubuBurst(count: 18, radius: 120)
                    }
                }

                Text(title.replacingOccurrences(of: "🎉 ", with: ""))
                    .font(BubuTheme.Font.title)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("收好这一刻")
                        .font(BubuTheme.Font.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(BubuTheme.Color.actionFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 30)
            .frame(maxWidth: 340)
            .background(
                LinearGradient(colors: [BubuTheme.Color.warmSurfaceTop, BubuTheme.Color.pinkSurface],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                    .stroke(.white.opacity(0.6), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
            .scaleEffect(appear ? 1 : 0.86)
            .opacity(appear ? 1 : 0)
            .padding(24)
        }
        .onAppear {
            BubuHaptics.success()
            guard !reduceMotion else {
                appear = true
                return
            }
            withAnimation(BubuMotion.ceremony) { appear = true }
            // 第二拍：卡片落定后再迸发星星；第三拍：光环慢慢散开。
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                burst = true
            }
            withAnimation(.easeOut(duration: 1.1).delay(0.35)) { sparkle = true }
        }
    }

    private var celebrationBackground: some View {
        ZStack {
            LinearGradient(colors: [
                BubuTheme.Color.background,
                BubuTheme.Color.primary.opacity(0.16),
                BubuTheme.Color.card
            ], startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(spacing: 22) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 0)
                        .fill(index.isMultiple(of: 2) ? .white.opacity(0.12) : BubuTheme.Color.primary.opacity(0.06))
                        .frame(height: 18)
                        .rotationEffect(.degrees(-8))
                }
            }
            .offset(y: -20)

            Rectangle()
                .fill(.white.opacity(0.20))
        }
    }

    private var sparkleRing: some View {
        ForEach(0..<10, id: \.self) { index in
            Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                .font(BubuTheme.Font.scaled(index.isMultiple(of: 2) ? 15 : 10, weight: .semibold))
                .foregroundStyle(BubuTheme.Color.primary.opacity(0.82))
                .offset(y: sparkle ? -78 : -38)
                .rotationEffect(.degrees(Double(index) / 10 * 360))
                .opacity(sparkle ? 0 : 1)
        }
    }
}
