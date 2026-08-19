import Foundation

// MARK: - 同步轮询退避
/// 断网/服务器下线时还每 30 秒打一次请求，既耗电又毫无意义
/// （人在外面一整天就是 2880 次注定失败的空请求）。
/// 这里把「连续失败 N 次后该隔多久再试」抽成纯函数，方便钉测试。
///
/// 曲线：30s → 60 → 120 → 240 → 480（8 分钟）封顶。
/// 为什么封在 8 分钟而不是更长：家里服务器修好后，用户希望「很快」自己就同步上，
/// 再长会让人以为 App 坏了而去手动折腾。手动点「重试」会把失败计数清零、立刻回到 30 秒。
nonisolated enum SyncBackoff {
    static let baseInterval: TimeInterval = 30
    static let maxInterval: TimeInterval = 480
    /// 指数增长的最大档位（2^4 = 16 倍，正好触到上限）。
    static let maxExponent = 4

    static func interval(failures: Int) -> TimeInterval {
        guard failures > 0 else { return baseInterval }
        let factor = pow(2.0, Double(min(failures, maxExponent)))
        return min(baseInterval * factor, maxInterval)
    }
}
