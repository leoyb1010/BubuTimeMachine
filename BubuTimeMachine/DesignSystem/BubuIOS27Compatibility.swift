import SwiftUI

// MARK: - iOS 27 渐进增强
/// Xcode 26 仍是当前正式工具链。新 API 放在编译器门后：今天的发布路径不受影响，
/// Xcode 27 shadow build 会真正编译并验证这些分支，而不是靠运行时字符串猜能力。
extension View {
    @ViewBuilder
    nonisolated func bubuIOS27SwipeActionsContainer() -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            self.swipeActionsContainer()
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    nonisolated func bubuIOS27NavigationPolish() -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            self.toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func bubuIOS27TimelineActions(onShare: @escaping () -> Void,
                                  onDelete: @escaping () -> Void) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            self.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(action: onShare) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .tint(BubuTheme.Color.info)
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - 工具栏保留优先级（iOS 27 ToolbarItemVisibilityPriority）

/// 竖排栏 / 窄工具栏放不下时，谁先被收进溢出菜单。
enum BubuToolbarPriority: Sendable {
    case automatic
    /// 少用：分享、恢复码、收进绘本。
    case low
    /// 常用：记录此刻、搜索、筛选、完成 / 返回。
    case high
}

extension ToolbarContent {
    /// 设置工具栏项的保留优先级；iOS 26 原样返回。
    @ToolbarContentBuilder
    func bubuVisibilityPriority(_ priority: BubuToolbarPriority) -> some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            switch priority {
            case .automatic: self.visibilityPriority(.automatic)
            case .low: self.visibilityPriority(.low)
            case .high: self.visibilityPriority(.high)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
