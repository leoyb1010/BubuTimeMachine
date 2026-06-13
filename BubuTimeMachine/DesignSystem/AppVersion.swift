import Foundation

// MARK: - 应用版本号
/// 统一从 Bundle 读取版本信息，供「设置页版本行 / 更新记录 / 升级弹窗」复用。
enum AppVersion {
    /// 营销版本号，如 "1.2.0"。
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// 构建号，如 "2026061303"。
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// 展示用："v1.2.0"。
    static var displayShort: String { "v\(marketing)" }

    /// 展示用（带构建号）："v1.2.0 (2026061303)"。
    static var displayFull: String { "v\(marketing) (\(build))" }
}
