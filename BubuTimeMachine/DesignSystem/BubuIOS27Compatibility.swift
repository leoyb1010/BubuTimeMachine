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
            self.toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)
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
