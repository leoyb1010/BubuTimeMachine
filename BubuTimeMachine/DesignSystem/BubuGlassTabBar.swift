import SwiftUI

// MARK: - 奶油马卡龙玻璃胶囊底栏
/// 替换系统 TabBar 的视觉外观，但路由逻辑完全由外部 selection 驱动，不改任何跳转。
/// 4 个页面 Tab + 1 个中央记录动作。页面路由仍由外部 selection 驱动；
/// 中央按钮只负责打开「记录此刻」，避免再把爱心误读成回首页。
struct BubuTabItem: Identifiable {
    let id: Int
    let title: String
    let systemImage: String
}

struct BubuGlassTabBar: View {
    @Binding var selection: Int
    var tint: Color
    /// 中央凸起键动作：打开「记录此刻」输入流。
    var onCenterTap: () -> Void

    // 四个页面入口 + 中央记录键。胶囊收进魔法屋，底栏不再拥挤。
    private let left: [BubuTabItem] = [
        .init(id: 0, title: "首页", systemImage: "house.fill"),
        .init(id: 1, title: "时光", systemImage: "clock.fill"),
    ]
    private let right: [BubuTabItem] = [
        .init(id: 2, title: "星座", systemImage: "star.fill"),
        .init(id: 3, title: "魔法屋", systemImage: "wand.and.stars.inverse"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(left) { item in tabButton(item) }
            centerButton
            ForEach(right) { item in tabButton(item) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.62), lineWidth: 1))
        .shadow(color: BubuTheme.Color.deepRose.opacity(0.28), radius: 18, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ item: BubuTabItem) -> some View {
        let active = selection == item.id
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = item.id }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(item.title).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? tint : BubuTheme.Color.secondaryText)
            .frame(width: 56, height: 50)
            .background(active ? BubuTheme.Color.cream2.opacity(0.78) : .clear,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    private var centerButton: some View {
        Button {
            onCenterTap()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "plus")
                    .font(.system(size: 23, weight: .black))
                Text("记录")
                    .font(.system(size: 9, weight: .black, design: .rounded))
            }
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(BubuTheme.Gradient.primaryButton, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                .shadow(color: BubuTheme.Color.deepRose.opacity(0.5), radius: 10, y: 4)
                .offset(y: -9)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .accessibilityLabel("记录此刻")
    }
}
