import SwiftUI

// MARK: - 成长页 2.25 新区块
/// 「可能的第一次」（服务不可用时自动隐藏）、发育参考清单、成长脸延时。
struct GrowthUpgradeSections: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PossibleFirstsCard()
            DevelopmentChecklistCard()
            FaceTimelapseCard()
        }
    }
}
