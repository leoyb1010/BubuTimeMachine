import SwiftUI

// MARK: - 星尘背景（全 App 统一的动效母题）
/// 深空底上 18 颗缓慢漂移、明暗呼吸的星点。手表是 OLED + 深色环境，
/// 星点用马卡龙色低透明度，像星星而不是贴纸。
///
/// 省电纪律：
/// - 手腕放下（`isLuminanceReduced`）时切到 `.everyMinute` 调度并停掉漂移——
///   AOD 下继续跑 20fps 动画是电池杀手，也过不了系统的降亮渲染预算。
/// - 星点用 `Canvas` 一次画完，不是 18 个 View——离屏合成一层，代价接近一张静态图。
struct WatchStarfield: View {
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 星星的固定属性一次生成（种子确定，重进页面星空不跳变）。
    private struct Star {
        let x: Double        // 0–1 归一化位置
        let y: Double
        let radius: Double   // pt
        let tint: Int        // WatchTheme 色序号
        let phase: Double    // 呼吸相位偏移
        let driftSpeed: Double
    }

    private static let stars: [Star] = {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed % 10_000) / 10_000
        }
        return (0..<18).map { _ in
            Star(x: next(), y: next(),
                 radius: 0.6 + next() * 1.1,
                 tint: Int(next() * 4),
                 phase: next() * .pi * 2,
                 driftSpeed: 0.3 + next() * 0.7)
        }
    }()

    private static let tints: [Color] = [
        WatchTheme.rose, WatchTheme.butter, WatchTheme.lav, WatchTheme.sky,
    ]

    var body: some View {
        // AOD 用 paused 停调度（同一种 schedule 类型，三目两分支才能同型）；
        // 暂停时 Canvas 停止重绘，星星冻结在最后一帧——正是降亮该有的样子。
        TimelineView(.animation(minimumInterval: 1 / 12, paused: dimmed)) { timeline in
            Canvas { context, size in
                let t = dimmed ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for star in Self.stars {
                    // 慢速纵向漂移 + 呼吸；AOD 下 t=0 即静止。
                    let drift = (t * star.driftSpeed * 0.008).truncatingRemainder(dividingBy: 1)
                    let y = (star.y + drift).truncatingRemainder(dividingBy: 1)
                    let breath = dimmed ? 0.5 : 0.55 + 0.45 * sin(t * 0.8 + star.phase)
                    let rect = CGRect(x: star.x * size.width - star.radius,
                                      y: y * size.height - star.radius,
                                      width: star.radius * 2, height: star.radius * 2)
                    context.fill(Path(ellipseIn: rect),
                                 with: .color(Self.tints[star.tint].opacity(0.28 * breath)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 深空页底
/// 各页统一底色：近黑深空 + 顶部一点该页的主题色晕染 + 星尘。
struct WatchSpaceBackground: View {
    var accent: Color

    var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.043, blue: 0.078)   // #0D0B14 深空
            LinearGradient(colors: [accent.opacity(0.20), .clear],
                           startPoint: .top, endPoint: .center)
            WatchStarfield()
        }
        .ignoresSafeArea()
    }
}
