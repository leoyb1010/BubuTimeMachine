import SwiftUI
import UIKit

// SwiftUI 26.5 的 Catalyst `LocationBasedFeedbackAdaptor` 会在首帧触发
// AttributeGraph EXC_BAD_ACCESS；Mac 没有 iPhone 式触觉硬件，直接不挂载该 modifier。
extension View {
    @ViewBuilder
    func bubuSensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T
    ) -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        self.sensoryFeedback(feedback, trigger: trigger)
        #endif
    }
}

// MARK: - 触觉反馈统一封装
/// 触觉与动效成对出现（映射表见 DESIGN_UPGRADE.md §4.2）。
/// 禁止散落直建 generator——语义化调用，方便全局调整强度。
@MainActor
enum BubuHaptics {
    /// 保存成功、里程碑点亮、胶囊解密成功
    static func success() {
        #if !targetEnvironment(macCatalyst)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// 删除确认、操作有风险
    static func warning() {
        #if !targetEnvironment(macCatalyst)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// 心情/表情/选项选中
    static func selection() {
        #if !targetEnvironment(macCatalyst)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// 轻触：录音开始等
    static func tapLight() {
        #if !targetEnvironment(macCatalyst)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// 中等：胶囊封存「盖章」
    static func stamp() {
        #if !targetEnvironment(macCatalyst)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// 重击：胶囊开启「破封」
    static func breakSeal() {
        #if !targetEnvironment(macCatalyst)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }
}
