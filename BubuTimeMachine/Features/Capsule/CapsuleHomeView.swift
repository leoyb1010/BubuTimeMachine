import SwiftUI

// MARK: - 时间胶囊（占位，后续深入）
struct CapsuleHomeView: View {
    var body: some View {
        ComingSoonView(
            title: "时间胶囊",
            systemImage: "envelope.badge.shield.half.filled",
            message: "写一封信、录一段话给未来的布布，\n设定解锁时间（比如她 18 岁生日）。\n到期前加密锁定，谁也偷看不了。"
        )
        .navigationTitle("时间胶囊")
    }
}
