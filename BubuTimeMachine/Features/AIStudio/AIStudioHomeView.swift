import SwiftUI

// MARK: - AI 工坊（占位，后续深入）
struct AIStudioHomeView: View {
    var body: some View {
        ComingSoonView(
            title: "AI 工坊",
            systemImage: "wand.and.stars",
            message: "把父母视角改写成布布的第一人称日记，\n生成年度成长电影，合成家人合奏的完整故事。\n连上家里的服务器即可开启。"
        )
        .navigationTitle("AI 工坊")
    }
}
