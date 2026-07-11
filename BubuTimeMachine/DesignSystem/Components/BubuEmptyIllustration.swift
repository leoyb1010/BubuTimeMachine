import SwiftUI
import UIKit

// MARK: - 布布空状态插画（H-4）
/// 已画好的插画资产（BubuEmptyTimeline 等）优先；资产缺失时回退吉祥物徽章，永不空白。
struct BubuEmptyIllustration: View {
    let assetName: String
    var fallbackExpression: BubuExpression = .bye
    var size: CGFloat = 150

    var body: some View {
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            BubuMascotBadge(size: size * 0.55, expression: fallbackExpression)
        }
    }
}
