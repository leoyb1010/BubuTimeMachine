import SwiftUI

// MARK: - 成长星座盘
/// 把里程碑可视化成星座：已达成 = 发光大星（带光晕 + 连线），未达成 = 灰点。
/// 只负责「展示方式」，里程碑数据与点亮逻辑由外部提供，不改任何功能。
///
/// 300+ 里程碑可用化策略（关键）：
/// - 星盘只渲染**外部传入的 milestones**（已被分类/搜索筛过）——一屏不会挤 300 颗。
/// - 顶部有「只看已点亮」开关：默认聚焦已点亮的星 + 连线，未点亮的灰点淡显，避免找不到。
/// - 点亮的星连成专属星座；点星进详情（复用现有里程碑详情）。
struct BubuConstellationView: View {
    let milestones: [Milestone]          // 已筛选
    let primary: Color
    var onTapStar: (Milestone) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 容器实际宽度（宽屏下星盘高度按它取比例）。由外层 onGeometryChange 写入。
    @State private var containerWidth: CGFloat = 360
    @ScaledMetric(relativeTo: .body) private var minimumStarWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .body) private var titleLineHeight: CGFloat = 15

    // 星盘显示一部分未点亮星，避免 0 点亮时空白；已点亮星保持发光并连线。
    private var achieved: [Milestone] { milestones.filter(\.isAchieved) }
    private var shown: [Milestone] {
        let maxStars = 12
        let lit = Array(achieved.prefix(maxStars))
        let locked = milestones.filter { !$0.isAchieved }
        return Array((lit + locked).prefix(maxStars))
    }
    private var totalCount: Int { milestones.count }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("✦ 已点亮 \(achieved.count) / \(totalCount) 颗星")
                    .font(BubuTheme.Font.scaled(15, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text("还有 \(max(0, totalCount - achieved.count)) 颗等你点亮 ♡")
                    .font(BubuTheme.Font.scaled(12, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }

            if milestones.isEmpty {
                VStack(spacing: 8) {
                    Text("✦").font(BubuTheme.Font.scaled(40)).foregroundStyle(primary.opacity(0.5))
                    Text("还没有点亮的星")
                        .font(BubuTheme.Font.scaled(14, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("去「奖章墙」点亮布布的第一次，这里就会升起一颗星")
                        .font(BubuTheme.Font.scaled(12, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
            // 星盘
            GeometryReader { geo in
                let layout = starLayout(width: geo.size.width)
                ZStack {
                    constellationLines(positions: layout.positions, milestones: shown)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, m in
                        starView(m, index: idx, size: layout.targetSize)
                            .position(layout.positions[idx])
                    }
                }
                .frame(width: geo.size.width, height: layout.height)
            }
            .frame(height: starLayout(width: containerWidth).height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .background(
                LinearGradient(colors: [BubuTheme.Color.lav.opacity(0.20),
                                        BubuTheme.Color.sky.opacity(0.18),
                                        BubuTheme.Color.cream2.opacity(0.30)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                BubuSparkle(size: 12, color: .white).padding(14)
            }

            Text("轻点亮起的星星，回到那一刻 ♡")
                .font(BubuTheme.Font.scaled(12, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
    }

    private func starLayout(width: CGFloat) -> ConstellationLayout {
        // 真实窄屏截图中，黄金螺旋的第11/12颗星压住了既有标签。
        // 为整个按钮预留空间；字体放大时减少列数、增长画布，不挤压或遮挡。
        ConstellationLayout.make(count: shown.count, width: width,
                                 minimumTargetWidth: minimumStarWidth,
                                 targetHeight: 48 + 6 + titleLineHeight * 3,
                                 maximumColumns: BubuAdaptive.isWide(sizeClass) ? 4 : 3)
    }

    @ViewBuilder
    private func constellationLines(positions: [CGPoint], milestones: [Milestone]) -> some View {
        // 已点亮的星顺序连线：底层浅粉粗描边 + 上层 rose→lav 渐变细线（对照设计稿双层 path）。
        let litPositions = zip(positions, milestones).compactMap { point, milestone in
            milestone.isAchieved ? point : nil
        }.suffix(7)
        if litPositions.count >= 2 {
            let path = Path { p in
                for (k, pt) in litPositions.enumerated() {
                    if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            ZStack {
                path.stroke(BubuTheme.Color.pink.opacity(0.55),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                path.stroke(
                    LinearGradient(colors: [BubuTheme.Color.primary, BubuTheme.Color.lav],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func starView(_ m: Milestone, index: Int, size: CGSize) -> some View {
        let starColor = BubuTheme.Color.hue(m.title.bubuStableHue, lightness: 0.82)
        return Button { onTapStar(m) } label: {
            VStack(spacing: 6) {
                ConstellationStar(emoji: m.emoji, color: starColor, index: index, lit: m.isAchieved,
                                  reduceMotion: reduceMotion)
                    .frame(height: 48)
                Text(m.title)
                    .font(BubuTheme.Font.scaled(12, weight: .bold, design: .rounded))
                    .foregroundStyle(m.isAchieved ? BubuTheme.Color.warmBrown : BubuTheme.Color.secondaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .shadow(color: BubuTheme.Color.cream.opacity(0.95), radius: 3)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.title)
        .accessibilityIdentifier("milestone.star." + m.id.uuidString)
    }
}

// 单颗已点亮的星：macStarPop 入场 + macHalo 呼吸光晕 + 径向高光。
private struct ConstellationStar: View {
    let emoji: String
    let color: Color
    let index: Int
    let lit: Bool
    let reduceMotion: Bool

    @State private var popped = false
    @State private var halo = false

    var body: some View {
        ZStack {
            // 呼吸光晕：用预渲染的径向渐变代替每颗星的高斯 blur，
            // 星盘最多 12 颗常驻呼吸时不再挂 12 个实时模糊层，只做 opacity/scale 合成（P2m）
            if lit {
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.6), color.opacity(0)],
                                         center: .center, startRadius: 2, endRadius: 24))
                    .frame(width: 48, height: 48)
                    .opacity(halo ? 0.9 : 0.5)
                    .scaleEffect(halo ? 1.12 : 0.92)
            }
            Circle()
                .fill(lit
                      ? AnyShapeStyle(RadialGradient(colors: [.white, color],
                                                     center: .init(x: 0.38, y: 0.32),
                                                     startRadius: 1,
                                                     endRadius: 28))
                      : AnyShapeStyle(BubuTheme.Color.softFill))
                .frame(width: lit ? 38 : 26, height: lit ? 38 : 26)
                .overlay(Circle().stroke(lit ? .white : BubuTheme.Color.hairline.opacity(0.8),
                                         lineWidth: lit ? 2 : 1))
                .overlay(Text(emoji).font(BubuTheme.Font.scaled(lit ? 17 : 11)).grayscale(lit ? 0 : 1).opacity(lit ? 1 : 0.45))
                .shadow(color: lit ? color.opacity(0.45) : .clear, radius: 5, y: 2)
        }
        .scaleEffect(reduceMotion ? 1 : (popped ? 1 : 0))
        .opacity(reduceMotion ? 1 : (popped ? 1 : 0))
        .onAppear {
            if reduceMotion { popped = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.12 + Double(index) * 0.06)) {
                popped = true
            }
            if lit {
                withAnimation(.easeInOut(duration: 2.4 + Double(index % 5) * 0.2)
                    .repeatForever(autoreverses: true).delay(Double(index) * 0.1)) {
                    halo = true
                }
            }
        }
    }
}
