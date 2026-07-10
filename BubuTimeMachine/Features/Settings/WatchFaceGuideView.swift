import SwiftUI

// MARK: - 把布布放上表盘（引导）
/// watchOS 不允许第三方 App 编程安装表盘，但可以引导用户把「布布」复杂功能加到任意照片表盘上，
/// 四个角摆满布布数据 + 布布照片当底 = 最接近「布布专属表盘」的合法形态。
struct WatchFaceGuideView: View {
    private let steps: [(icon: String, title: String, detail: String)] = [
        ("hand.tap.fill", "长按表盘进入编辑",
         "在 Apple Watch 上长按当前表盘，点「编辑」。想要照片当底就先左滑选一个「照片」表盘。"),
        ("photo.on.rectangle.angled", "选一张布布的照片",
         "照片表盘里选布布的照片当背景。抬腕就能看到她的脸。"),
        ("puzzlepiece.extension.fill", "四个角加上「布布」复杂功能",
         "在表盘四角的复杂功能位里，找到「布布」——可以放生日倒计时环、陪伴天数、年龄、一行近况。点一下就能回到手表 App。")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    stepCard(index: idx + 1, step: step)
                }
                tip
            }
            .padding()
        }
        .navigationTitle("布布上表盘")
        .navigationBarTitleDisplayMode(.inline)
        .background(BubuTheme.Color.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("⌚️").font(.system(size: 48))
            Text("把布布放上你的表盘")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("抬腕就能看到布布的年龄、生日倒计时，点一下直达手表 App")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private func stepCard(index: Int, step: (icon: String, title: String, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(BubuTheme.Color.primary.opacity(0.16)).frame(width: 44, height: 44)
                Image(systemName: step.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.primary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("第 \(index) 步 · \(step.title)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(step.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .bubuCardShadow()
    }

    private var tip: some View {
        Text("提示：先在手表上装好「布布时光机」App，复杂功能列表里才会出现「布布」。手机记录后，表盘数据会自动更新。")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(BubuTheme.Color.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
