import SwiftUI

// MARK: - 奶油马卡龙玻璃胶囊底栏
/// 替换系统 TabBar 的视觉外观，但路由逻辑完全由外部 selection 驱动，不改任何跳转。
/// 5 个 Tab 的顺序/含义与原 RootTabView 完全一致：记录此刻/时光/里程碑/故事/胶囊。
struct BubuTabItem: Identifiable {
    let id: Int
    let title: String
    let systemImage: String
}

struct BubuGlassTabBar: View {
    @Binding var selection: Int
    var tint: Color
    /// 中央凸起键动作（记录此刻 = 选中第 0 个 Tab，与原「记录此刻」一致）。
    var onCenterTap: () -> Void

    // 左二 + 右二，中间留给凸起键。顺序对齐原 Tab：0记录 1时光 [＋] 2里程碑 3故事 4胶囊
    private let left: [BubuTabItem] = [
        .init(id: 1, title: "时光", systemImage: "clock.fill"),
        .init(id: 2, title: "里程碑", systemImage: "star.fill"),
    ]
    private let right: [BubuTabItem] = [
        .init(id: 3, title: "故事", systemImage: "wand.and.stars.inverse"),
        .init(id: 4, title: "胶囊", systemImage: "envelope.fill"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(left) { item in tabButton(item) }
            centerButton
            ForEach(right) { item in tabButton(item) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: BubuTheme.Color.deepRose.opacity(0.28), radius: 18, y: 10)
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
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
            .frame(width: 54, height: 50)
            .background(active ? BubuTheme.Color.cream2 : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var centerButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = 0 }
            onCenterTap()
        } label: {
            Image(systemName: "heart.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(BubuTheme.Gradient.primaryButton, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                .shadow(color: BubuTheme.Color.deepRose.opacity(0.5), radius: 10, y: 4)
                .offset(y: -8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
