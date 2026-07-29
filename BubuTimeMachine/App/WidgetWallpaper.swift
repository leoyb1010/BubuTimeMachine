import Foundation

// MARK: - 桌面壁纸底图（伪透明小组件）
/// 让桌面小组件看起来是"透明"的唯一可靠办法。
///
/// 为什么不能靠调不透明度：小组件的内容由扩展进程离屏渲染成一张图再交给桌面合成，
/// 组件拿不到壁纸像素——`.ultraThinMaterial` 之类的材质没有可采样的背景，只会退化成实心色；
/// 纯 alpha 又只在壁纸本身有花纹时才看得出来，壁纸那块若是接近纯色，
/// 压到 10% 和不透明看起来几乎一样（2026-07-29 真机验证过两轮）。
///
/// 所以改成"把壁纸本身喂给小组件"：用户导入一张桌面空白页截图，在 App 里拖框圈出
/// 小组件实际所在的位置，App 按那个位置裁好、每个尺寸存一张，小组件直接拿来当底。
/// 桌面上小组件的底就是它身后那块壁纸，视觉上完全消失。
///
/// **裁剪必须在主 App 做**：一张 1290×2796 的截图解成位图约 14MB，
/// 小组件进程只有 ~30MB，再叠上照片墙那 9 张缩略图必然被系统杀掉（白卡）。
/// 存进去的是已经裁好、缩到 2 倍点尺寸的小图，小组件只读几十 KB。
nonisolated enum WidgetWallpaper {

    /// 三种桌面小组件尺寸各存一张底图。锁屏/StandBy 不参与——那些位置没有壁纸可透。
    enum Slot: String, CaseIterable, Sendable {
        case small, medium, large

        /// 小组件宽度占屏宽的比例。取自 iPhone 17 Pro Max 实测：
        /// 屏宽 440pt，大/中卡 364pt、小卡 170pt。各机型比例相差在 1% 内，够用。
        var widthRatio: CGFloat {
            switch self {
            case .small: return 170.0 / 440.0
            case .medium, .large: return 364.0 / 440.0
            }
        }

        /// 高宽比（高 ÷ 宽）。大卡 364×382、中卡 364×170、小卡正方形。
        var heightOverWidth: CGFloat {
            switch self {
            case .small: return 1.0
            case .medium: return 170.0 / 364.0
            case .large: return 382.0 / 364.0
            }
        }

        var displayName: String {
            switch self {
            case .small: return "小卡"
            case .medium: return "中卡"
            case .large: return "大卡"
            }
        }

        /// 裁出来存盘的像素宽度：2 倍点尺寸足够清晰，又把文件压在几十 KB。
        var outputPixelWidth: CGFloat {
            switch self {
            case .small: return 340
            case .medium, .large: return 728
            }
        }
    }

    // MARK: 路径

    private static var directory: URL {
        let url = BubuStorage.containerURL.appendingPathComponent("WidgetWallpaper", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// 用户导入的原始截图。留着是为了之后能重新拖位置，不用再截一次图。
    static var sourceURL: URL { directory.appendingPathComponent("source.jpg") }

    static func croppedURL(for slot: Slot) -> URL {
        directory.appendingPathComponent("bg-\(slot.rawValue).jpg")
    }

    // MARK: 开关（App Group UserDefaults，小组件侧要读）

    private static var suite: UserDefaults? { UserDefaults(suiteName: BubuStorage.appGroupID) }
    private static let enabledKey = "widgetWallpaperEnabled"
    private static func rectKey(_ slot: Slot) -> String { "widgetWallpaperRect-\(slot.rawValue)" }

    static var isEnabled: Bool {
        get { suite?.bool(forKey: enabledKey) ?? false }
        set { suite?.set(newValue, forKey: enabledKey) }
    }

    /// 每个尺寸在原始截图里的归一化位置（0–1 的 x/y/w/h）。存着是为了下次打开能还原拖框。
    static func normalizedRect(for slot: Slot) -> CGRect? {
        guard let v = suite?.array(forKey: rectKey(slot)) as? [Double], v.count == 4 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    static func setNormalizedRect(_ rect: CGRect, for slot: Slot) {
        suite?.set([rect.origin.x, rect.origin.y, rect.width, rect.height], forKey: rectKey(slot))
    }

    // MARK: 读（小组件侧调用）

    /// 取该尺寸的底图。没导入、没裁过、或开关关着都返回 nil，调用方回退到原来的玻璃底。
    static func backgroundData(for slot: Slot) -> Data? {
        guard isEnabled else { return nil }
        let url = croppedURL(for: slot)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    static var hasSource: Bool {
        FileManager.default.fileExists(atPath: sourceURL.path)
    }

    // MARK: 写（主 App 侧调用）

    static func saveSource(_ data: Data) throws {
        try data.write(to: sourceURL, options: .atomic)
    }

    static func saveCropped(_ data: Data, for slot: Slot) throws {
        try data.write(to: croppedURL(for: slot), options: .atomic)
    }

    /// 清空：删图 + 关开关 + 清位置。用户点「移除壁纸」时调用。
    static func clear() {
        let fm = FileManager.default
        try? fm.removeItem(at: sourceURL)
        for slot in Slot.allCases {
            try? fm.removeItem(at: croppedURL(for: slot))
            suite?.removeObject(forKey: rectKey(slot))
        }
        isEnabled = false
    }
}
