import SwiftUI

// MARK: - 主题与外观
/// 切换全局主题配色，选择首页背景模式（主题背景 / 布布照片）。
struct ThemeSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var manager: ThemeManager { env.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                Text("主题配色")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                    ForEach(BubuThemeDefinition.all) { theme in
                        themeCard(theme)
                    }
                }

                Text("首页背景")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .padding(.top, 8)

                Picker("背景模式", selection: Binding(
                    get: { manager.heroMode },
                    set: { manager.heroMode = $0 })) {
                    ForEach(HeroBackgroundMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text("「布布照片」需在「布布的档案」里设置一张背景图。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("主题与外观")
    }

    private func themeCard(_ theme: BubuThemeDefinition) -> some View {
        let selected = theme.id == manager.currentThemeId
        return Button {
            manager.select(theme)
            BubuHaptics.success()
        } label: {
            VStack(spacing: 10) {
                previewSwatch(theme)
                HStack(spacing: 6) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.primary)
                    }
                    Text(theme.name)
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                }
            }
            .padding(12)
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                    .stroke(selected ? theme.primary : .clear, lineWidth: 2.5)
            }
            .bubuCardShadow()
        }
        .buttonStyle(.plain)
    }

    /// 迷你首页实景卡：mesh 渐变底 + 头像圈 + 强调按钮 + 一条时光轴卡片缩影，
    /// 用真实主题色渲染（非截图），让选择像「试衣间」预览。
    private func previewSwatch(_ theme: BubuThemeDefinition) -> some View {
        ZStack {
            // mesh 调色板做静态斜向渐变，近似 hero 观感（列表里不跑动画，省电）。
            LinearGradient(colors: theme.meshColors.isEmpty ? [theme.primary] : theme.meshColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                Capsule().fill(theme.primary).frame(width: 34, height: 7)
                // 时光轴卡片缩影
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BubuTheme.Color.card.mix(with: theme.surfaceTint, by: 0.06))
                    .frame(width: 78, height: 22)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(theme.secondary).frame(width: 16, height: 14)
                            VStack(alignment: .leading, spacing: 3) {
                                Capsule().fill(theme.surfaceTint.opacity(0.5)).frame(width: 30, height: 4)
                                Capsule().fill(theme.surfaceTint.opacity(0.3)).frame(width: 22, height: 4)
                            }
                        }
                        .padding(.leading, 5)
                    }
            }
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }
}
