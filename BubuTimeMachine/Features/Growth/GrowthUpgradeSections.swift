import SwiftUI

// MARK: - 成长页 2.25 新区块
/// 统一的「第一次」（本机 + 第二大脑已确认，底部带待确认候选）、发育参考清单、成长脸延时。
struct GrowthUpgradeSections: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GrowthFirstsCard()
            DevelopmentChecklistCard()
            FaceTimelapseCard()
        }
    }
}
