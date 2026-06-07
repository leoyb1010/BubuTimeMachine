import SwiftUI

// MARK: - 里程碑 & 人生第一次（占位，后续深入）
struct MilestonesHomeView: View {
    var body: some View {
        ComingSoonView(
            title: "里程碑 & 第一次",
            systemImage: "star.circle.fill",
            message: "会走路、第一次叫妈妈、第一次吃西瓜……\n这里会成为布布的成就墙，每一个第一次都有温暖的仪式。"
        )
        .navigationTitle("里程碑")
    }
}
