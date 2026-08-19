import SwiftUI

// MARK: - 统一轻提示
/// 「做完了 / 可以反悔」这类反馈以前每个页面各写各的（MediaViewer 一套、EntryDetail 一套），
/// 位置、时长、动效都对不上。这里收成一个组件：底部胶囊、自动消失、可带一个动作按钮。
///
/// 用法：
/// ```swift
/// @State private var toast: BubuToastState?
/// ...
/// .bubuToast($toast)
/// ...
/// toast = .init(message: "已删除", actionTitle: "撤销") { restore() }
/// ```
struct BubuToastState: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var systemImage: String?
    var actionTitle: String?
    /// 自动消失时长。带动作按钮时默认给足反悔时间。
    var duration: TimeInterval
    var action: (() -> Void)?

    init(message: String,
         systemImage: String? = nil,
         actionTitle: String? = nil,
         duration: TimeInterval? = nil,
         action: (() -> Void)? = nil) {
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.duration = duration ?? (actionTitle == nil ? 1.8 : 3.5)
        self.action = action
    }

    static func == (lhs: BubuToastState, rhs: BubuToastState) -> Bool { lhs.id == rhs.id }
}

private struct BubuToastModifier: ViewModifier {
    @Binding var state: BubuToastState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let state {
                    toastBody(state)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                        .transition(reduceMotion
                                    ? .opacity
                                    : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                  removal: .opacity))
                        .id(state.id)
                }
            }
            .animation(reduceMotion ? nil : BubuMotion.gentle, value: state)
            // id 变化即重新计时：连续两次删除不会被上一条的定时器提前关掉。
            .task(id: state?.id) {
                guard let current = state else { return }
                try? await Task.sleep(for: .seconds(current.duration))
                guard !Task.isCancelled, state?.id == current.id else { return }
                state = nil
            }
    }

    private func toastBody(_ state: BubuToastState) -> some View {
        HStack(spacing: 10) {
            if let icon = state.systemImage {
                Image(systemName: icon)
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
            }
            Text(state.message)
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let title = state.actionTitle, let action = state.action {
                Button {
                    action()
                    self.state = nil
                } label: {
                    Text(title)
                        .font(BubuTheme.Font.body.weight(.bold))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                }
                .buttonStyle(.plain)
                .accessibilityHint("撤销刚才的操作")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card, in: Capsule(style: .continuous))
        .bubuCardShadow()
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// 底部轻提示。传入的状态置空即消失，也可由组件自身按 duration 自动收起。
    func bubuToast(_ state: Binding<BubuToastState?>) -> some View {
        modifier(BubuToastModifier(state: state))
    }
}
