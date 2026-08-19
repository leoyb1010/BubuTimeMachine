import SwiftUI

// MARK: - 骨架屏
/// 「内容马上就来，位置先占住」的统一语言。
///
/// 什么时候用骨架、什么时候用转圈，界线是**能不能预知形状**：
/// - 能（相册再加载一屏、问答的下一条气泡）→ 骨架，页面不跳动、等待有形状。
/// - 不能（按钮里的提交中、后台任务的分阶段进度）→ 带文案的 ProgressView，
///   它已经说清了「在做什么」，换成骨架反而丢信息。
///
/// 动效是一道横扫的高光；reduceMotion 时降为静止的柔色块。
struct BubuSkeletonBlock: View {
    var cornerRadius: CGFloat = BubuTheme.Radius.sm
    var height: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(BubuTheme.Color.softFill)
            .frame(height: height)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.55)
                            .offset(x: phase * geo.size.width)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
            .accessibilityHidden(true)
    }
}

/// 一行文字的骨架（两条长短不一的横条，像真的有内容）。
struct BubuSkeletonLines: View {
    var lines: Int = 2
    var body: some View {
        VStack(alignment: .leading, spacing: BubuTheme.Spacing.s) {
            ForEach(0..<max(1, lines), id: \.self) { i in
                BubuSkeletonBlock(cornerRadius: BubuTheme.Radius.xs, height: 12)
                    .frame(maxWidth: i == lines - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
    }
}

/// 卡片骨架：缩略图方块 + 两行文字。列表/网格加载下一屏时占位用。
struct BubuSkeletonCard: View {
    var thumbnailSide: CGFloat = 56

    var body: some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            BubuSkeletonBlock(cornerRadius: BubuTheme.Radius.sm)
                .frame(width: thumbnailSide, height: thumbnailSide)
            BubuSkeletonLines(lines: 2)
            Spacer(minLength: 0)
        }
        .padding(BubuTheme.Spacing.item)
        .background(BubuTheme.Color.card,
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
    }
}
