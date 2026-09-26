import Testing
import UIKit
@testable import BubuTimeMachine

@MainActor
struct ThemeContrastTests {
    @Test("动态主题色可以在 SwiftUI 后台渲染线程解析")
    func dynamicProviderDoesNotInheritMainActor() async {
        let color = UIColor(BubuThemeDefinition.default.textAccent)
        let resolved = await Task.detached {
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        }.value
        #expect(BubuThemeDefinition.contrast(resolved, UIColor(white: 0.26, alpha: 1)) >= 4.5)
    }
    @Test("所有主题的正文色和白字按钮都达到 4.5 对比度")
    func everyPaletteHasReadableRoles() {
        let light = UIColor(red: 0.93, green: 0.82, blue: 0.85, alpha: 1)
        let dark = UIColor(white: 0.26, alpha: 1)
        for theme in BubuThemeDefinition.all {
            for (backdrop, brighten) in [(light, false), (dark, true), (.white, false)] {
                let accent = BubuThemeDefinition.readableAccent(hex: theme.primaryHex, against: backdrop, lighten: brighten)
                #expect(BubuThemeDefinition.contrast(accent, backdrop) >= 4.5, "主题 \(theme.name)")
            }
        }
    }
}
