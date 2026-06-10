import UIKit

// MARK: - 触觉反馈统一封装
/// 触觉与动效成对出现（映射表见 DESIGN_UPGRADE.md §4.2）。
/// 禁止散落直建 generator——语义化调用，方便全局调整强度。
@MainActor
enum BubuHaptics {
    /// 保存成功、里程碑点亮、胶囊解密成功
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 删除确认、操作有风险
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// 心情/表情/选项选中
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 轻触：录音开始等
    static func tapLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 中等：胶囊封存「盖章」
    static func stamp() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// 重击：胶囊开启「破封」
    static func breakSeal() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}
