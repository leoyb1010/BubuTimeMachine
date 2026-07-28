import SwiftUI

// MARK: - 缓冲输入框（设置域通用）
/// 输入期间只写本地 `@State`，**失焦 / 回车 / 视图消失** 时才提交给调用方落库。
///
/// 为什么必须这样：直接把 `TextField` 绑到 `@Model` 属性并在 setter 里 `context.save()`，
/// 会让每一次按键都触发 SwiftData 变更广播 → 同屏 `@Query` 重取 → 视图树重建 →
/// TextField 拿到全新 Binding → **中文输入法未上屏的拼音（marked text）被清空**，
/// 表现为「这个框根本打不了字」。档案页「出生地」就是这么坏的。
///
/// 同理适用于任何 setter 有副作用的场景（写 UserDefaults、清同步游标、触发上传）：
/// 副作用只应在用户**完成输入**时发生一次，而不是每敲一个字符发生一次。
struct BubuBufferedField: View {
    let title: String
    let placeholder: String
    /// 当前已落库的值（外部真相源）。
    let value: String
    /// 用户完成输入时调用（失焦/回车/离开页面），入参为去除首尾空白后的文本。
    let onCommit: (String) -> Void

    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var disableAutocorrection = false
    /// 纵向布局（标题在上、输入框在下，占满宽）；false 为行内右对齐样式。
    var stacked = false

    @State private var draft = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                    field
                }
            } else {
                HStack {
                    Text(title)
                    Spacer(minLength: 12)
                    field.multilineTextAlignment(.trailing)
                }
            }
        }
        // 外部值变化（同步拉到新值、切换档案）时刷新草稿——但正在输入时不打断用户。
        .onChange(of: value) { _, newValue in
            guard !isEditing else { return }
            draft = newValue
        }
        .onAppear { draft = value }
        .onDisappear { commitIfNeeded() }
    }

    private var field: some View {
        TextField(placeholder, text: $draft)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(disableAutocorrection)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit { commitIfNeeded() }
            .onChange(of: focused) { _, nowFocused in
                isEditing = nowFocused
                if !nowFocused { commitIfNeeded() }
            }
    }

    private func commitIfNeeded() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value else { return }
        onCommit(trimmed)
    }
}
