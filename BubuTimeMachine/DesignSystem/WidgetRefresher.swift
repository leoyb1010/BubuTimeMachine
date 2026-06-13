import Foundation
import WidgetKit

// MARK: - 小组件刷新
/// 主 App 改了会显示在小组件上的数据（布布档案/头像/记录）后，通知 WidgetKit 重载时间线，
/// 否则桌面小组件只会按系统的低频节奏更新，看起来「没反应」。
enum WidgetRefresher {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
