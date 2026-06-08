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

    private func previewSwatch(_ theme: BubuThemeDefinition) -> some View {
        ZStack {
            switch theme.backgroundStyle {
            case .solid(let hex):
                Color(hex: hex)
            case .gradient(let a, let b):
                LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
            }
            HStack(spacing: 8) {
                Circle().fill(theme.primary).frame(width: 26, height: 26)
                Circle().fill(theme.secondary).frame(width: 20, height: 20)
            }
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }
}
