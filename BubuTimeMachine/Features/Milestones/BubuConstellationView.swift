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
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text("还有 \(max(0, totalCount - achieved.count)) 颗等你点亮 ♡")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }

            if milestones.isEmpty {
                VStack(spacing: 8) {
                    Text("✦").font(.system(size: 40)).foregroundStyle(primary.opacity(0.5))
                    Text("还没有点亮的星")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("去「奖章墙」点亮布布的第一次，这里就会升起一颗星")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
            // 星盘
            GeometryReader { geo in
                let positions = layout(count: shown.count, in: geo.size)
                ZStack {
                    constellationLines(positions: positions, milestones: shown)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, m in
                        starView(m, index: idx, dense: shown.count > 12)
                            .position(positions.indices.contains(idx) ? positions[idx] : CGPoint(x: geo.size.width/2, y: geo.size.height/2))
                    }
                }
            }
            .frame(height: starboardHeight)
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
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
    }

    // 设计稿手工锚点（在 340×540 画布上的比例坐标，错落有致、绝不挤成网格）。
    // 一组 10 个，超过则在其后用「黄金角螺旋」错落延展，保持星空感而非排队。
    private static let anchorTemplate: [CGPoint] = [
        .init(x: 0.17, y: 0.09), .init(x: 0.44, y: 0.185), .init(x: 0.77, y: 0.12),
        .init(x: 0.29, y: 0.34), .init(x: 0.62, y: 0.41), .init(x: 0.22, y: 0.57),
        .init(x: 0.53, y: 0.63), .init(x: 0.79, y: 0.55), .init(x: 0.38, y: 0.815),
        .init(x: 0.68, y: 0.87)
    ]

    private var starboardHeight: CGFloat {
        // 首页式紧凑星盘：信息够看，但不把底栏附近空间全部吃掉。
        max(260, min(320, 230 + CGFloat(shown.count) * 4))
    }

    // 锚点布局：前 10 用模板比例；超出部分用黄金角螺旋错落填充。
    private func layout(count: Int, in size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let pad: CGFloat = 28
        let w = size.width - pad * 2, h = size.height - pad * 2
        return (0..<count).map { i in
            if i < Self.anchorTemplate.count {
                let a = Self.anchorTemplate[i]
                return CGPoint(x: pad + a.x * w, y: pad + a.y * h)
            }
            // 螺旋延展（黄金角 137.5°），落在下半区，避免与模板重叠
            let k = Double(i - Self.anchorTemplate.count)
            let ang = k * 2.399963
            let rad = (0.18 + 0.06 * k.truncatingRemainder(dividingBy: 5))
            let cx = 0.5 + cos(ang) * rad
            let cy = 0.5 + sin(ang) * rad * 0.7
            return CGPoint(x: pad + CGFloat(min(0.92, max(0.08, cx))) * w,
                           y: pad + CGFloat(min(0.95, max(0.05, cy))) * h)
        }
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

    private func starView(_ m: Milestone, index: Int, dense: Bool) -> some View {
        let starColor = BubuTheme.Color.hue(Double((abs(m.title.hashValue) % 360)), lightness: 0.82)
        return Button { onTapStar(m) } label: {
            VStack(spacing: 6) {
                ConstellationStar(emoji: m.emoji, color: starColor, index: index, lit: m.isAchieved,
                                  reduceMotion: reduceMotion)
                if m.isAchieved || !dense {
                    Text(m.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(m.isAchieved ? BubuTheme.Color.warmBrown : BubuTheme.Color.secondaryText)
                        .lineLimit(1).frame(width: 66)
                        .shadow(color: BubuTheme.Color.cream.opacity(0.95), radius: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.title)
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
            // 呼吸光晕
            if lit {
                Circle().fill(color)
                    .frame(width: 42, height: 42)
                    .blur(radius: 6)
                    .opacity(halo ? 0.48 : 0.26)
                    .scaleEffect(halo ? 1.14 : 0.9)
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
                .overlay(Text(emoji).font(.system(size: lit ? 17 : 11)).grayscale(lit ? 0 : 1).opacity(lit ? 1 : 0.45))
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
