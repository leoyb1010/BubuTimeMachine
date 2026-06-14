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

    // 星座只画已点亮的（错落有致、不乱）；未点亮的去奖章墙/列表看。
    private var shown: [Milestone] { milestones.filter(\.isAchieved) }
    private var totalCount: Int { milestones.count }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("✦ 已点亮 \(shown.count) / \(totalCount) 颗星")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
                Text("还有 \(max(0, totalCount - shown.count)) 颗等你点亮 ♡")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }

            if shown.isEmpty {
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
                    constellationLines(positions: positions)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, m in
                        starView(m, index: idx)
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

    private var starboardHeight: CGFloat {
        // 按数量给高度，最少一屏，最多滚动
        let rows = max(3, Int(ceil(Double(shown.count) / 4.0)))
        return min(520, CGFloat(rows) * 78 + 40)
    }

    // 散点星座布局：网格基底 + 每颗星按 id 哈希做小偏移，营造星空错落感（确定性，不随机抖动）。
    private func layout(count: Int, in size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let cols = 4
        let rows = max(1, Int(ceil(Double(count) / Double(cols))))
        let cellW = size.width / CGFloat(cols)
        let cellH = (size.height - 20) / CGFloat(rows)
        return (0..<count).map { i in
            let r = i / cols, c = i % cols
            // 确定性偏移：用索引生成的伪随机，星盘每次一致
            let jx = (sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let jy = (sin(Double(i) * 78.233) * 12543.139).truncatingRemainder(dividingBy: 1)
            let x = cellW * (CGFloat(c) + 0.5) + CGFloat(jx) * cellW * 0.32
            let y = 20 + cellH * (CGFloat(r) + 0.5) + CGFloat(jy) * cellH * 0.30
            return CGPoint(x: x, y: y)
        }
    }

    @ViewBuilder
    private func constellationLines(positions: [CGPoint]) -> some View {
        // 把已点亮的星（在 shown 里的索引）按顺序连线
        let litIndices = shown.enumerated().compactMap { $0.element.isAchieved ? $0.offset : nil }
        if litIndices.count >= 2 {
            Path { p in
                for (k, idx) in litIndices.enumerated() where positions.indices.contains(idx) {
                    if k == 0 { p.move(to: positions[idx]) }
                    else { p.addLine(to: positions[idx]) }
                }
            }
            .stroke(primary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 6]))
        }
    }

    private func starView(_ m: Milestone, index: Int) -> some View {
        let on = m.isAchieved
        let starColor = BubuTheme.Color.hue(Double((abs(m.title.hashValue) % 360)))
        return Button {
            if on { onTapStar(m) }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if on {
                        Circle().fill(starColor).frame(width: 50, height: 50)
                            .blur(radius: 7).opacity(0.5)
                    }
                    Circle()
                        .fill(on
                              ? RadialGradient(colors: [.white, starColor], center: .init(x: 0.38, y: 0.32), startRadius: 1, endRadius: 26)
                              : RadialGradient(colors: [BubuTheme.Color.softFill, BubuTheme.Color.softFill], center: .center, startRadius: 1, endRadius: 14))
                        .frame(width: on ? 46 : 26, height: on ? 46 : 26)
                        .overlay(Circle().stroke(on ? Color.white : BubuTheme.Color.hairline,
                                                 style: StrokeStyle(lineWidth: on ? 2 : 1, dash: on ? [] : [3])))
                        .overlay {
                            Text(on ? m.emoji : "·")
                                .font(.system(size: on ? 20 : 12))
                                .foregroundStyle(on ? .white : BubuTheme.Color.secondaryText)
                        }
                        .shadow(color: on ? starColor.opacity(0.6) : .clear, radius: 6, y: 3)
                }
                Text(m.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(on ? BubuTheme.Color.warmBrown : BubuTheme.Color.secondaryText)
                    .lineLimit(1).frame(width: 70)
                    .opacity(on ? 1 : 0.7)
            }
        }
        .buttonStyle(.plain)
    }
}
