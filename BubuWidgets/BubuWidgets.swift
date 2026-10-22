import WidgetKit
import SwiftUI
import AppIntents
import UIKit
import ImageIO

// MARK: - 时间线
struct BubuEntry: TimelineEntry {
    let date: Date
    let snapshot: BubuSnapshot
    /// 记忆轮播款用：本 entry 展示第几张照片（多 entry 时间线自动翻页，免刷新预算）。
    var photoIndex: Int = 0
    /// 时光机轮播款：本槽位展示的那一段回忆（元信息）。
    var moment: SharedMoment? = nil
    /// 照片墙款：本槽位这一屏要铺的若干张（元信息 + 图片数据成对）。
    var wallMoments: [SharedMoment] = []
    var wallPhotos: [Data] = []
    /// 记忆轮播款专用：本槽位要展示的「那一张」照片数据。
    /// 轮播时间线有 12 个 entry，若每个 entry 都带上完整 snapshot（含最多 3×2MB 图），
    /// 会逼近 WidgetKit ~30MB 内存红线导致空白。故轮播 entry 只携带该槽位需要的一张图，
    /// 其 snapshot 的 photoImageData 被清空（其余轻量字段照常）。其它款不设此字段，走 snapshot.photoImageData。
    var carouselPhoto: Data? = nil
    /// 今日精选（服务端）：有它时照片墙/相框展示精选，点击深链到在线时光详情。
    var isDailyPicks = false
    var wallLinks: [String: URL] = [:]
    var pickURL: URL? = nil
    var pickReason: String? = nil
    var pickDateText: String? = nil
    /// 照片墙右上角轮换点的实际页数（≤1 时不画点）。
    var pageCount = 0
}

/// 轮播时间线的统一收尾：条目截到 `cutoff`（零点），零点后 2 分钟重建——
/// 精选跨零点要改标「昨日精选」或回落本机照片，「那年今日」徽章也只属于当天。
private func cappedTimeline(_ entries: [BubuEntry], cutoff: Date) -> Timeline<BubuEntry> {
    let kept = entries.filter { $0.date < cutoff }
    guard !kept.isEmpty, kept.count < entries.count else { return Timeline(entries: entries, policy: .atEnd) }
    return Timeline(entries: kept, policy: .after(cutoff.addingTimeInterval(120)))
}

/// 本机照片的零点（与「那年今日」同一本机日历）。
private func nextLocalMidnight(after date: Date = .now) -> Date {
    Calendar.current.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0),
                              matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
}

/// 确定性洗牌（同一 seed 结果恒定）：同一天内稳定、跨天自然翻新。
private func dailyShuffled<T>(_ items: [T], seed: Int) -> [T] {
    var result = items
    var state = UInt64(truncatingIfNeeded: seed) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    var i = result.count - 1
    while i > 0 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let j = Int(state >> 33) % (i + 1)
        result.swapAt(i, j)
        i -= 1
    }
    return result
}

struct BubuProvider: TimelineProvider {
    func placeholder(in context: Context) -> BubuEntry {
        BubuEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BubuEntry) -> Void) {
        completion(BubuEntry(date: .now, snapshot: BubuWidgetData.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuEntry>) -> Void) {
        let snapshot = BubuWidgetData.loadSnapshot()
        let entry = BubuEntry(date: .now, snapshot: snapshot)
        // 按天刷新：年龄/天数/倒计时是日粒度，明天零点后刷新一次足矣（不耗电）。
        let nextMidnight = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

// MARK: - 时光机照片墙 provider
/// 桌面上的「照片墙」：一屏铺多张照片（大卡 9 张、中卡 4 张、小卡 4 张），
/// 每 30 分钟整墙换一批。
///
/// 两代问题都出在这里，记录一下免得再犯：
/// ① 最早用 BubuProvider——单 entry、明天零点才刷新，桌面一整天纹丝不动；
/// ② 上一版改成轮播但仍是「一屏一张」，照片少时看起来还是没怎么变。
/// 现在是整墙轮换：一次换 9 张，视觉上一定看得出翻新了。
struct BubuMomentProvider: TimelineProvider {
    /// 一屏铺多少张（按最大尺寸备料，小尺寸自己截取前几张）。
    private static let wallSize = 9
    /// 时间线槽位数：8 × 30 分钟 = 4 小时一轮。
    private static let slots = 8

    func placeholder(in context: Context) -> BubuEntry {
        BubuEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BubuEntry) -> Void) {
        var snap = BubuWidgetData.loadSnapshot()
        let picks = DailyPicksReader.load()
        if !picks.isEmpty {
            snap.photoImageData = []
            completion(Self.pickEntry(picks, snapshot: snap, date: .now, slot: 0))
            return
        }
        let moments = Array(snap.moments.prefix(Self.wallSize))
        snap.photoImageData = []
        completion(BubuEntry(date: .now, snapshot: snap,
                             wallMoments: moments,
                             wallPhotos: moments.compactMap { BubuWidgetData.momentImageData(fileName: $0.photoFileName) }))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuEntry>) -> Void) {
        var snapshot = BubuWidgetData.loadSnapshot()
        let moments = snapshot.moments
        // 图片数据从 snapshot 剥离：每个 entry 只带本屏那几张，
        // 否则 8 个 entry 各拷一份会撞 WidgetKit 内存红线、小组件直接空白。
        snapshot.photoImageData = []

        // 今日精选优先：≤6 张不重复铺墙，每 30 分钟换一个领头（底部那句话跟着换）。
        let picks = DailyPicksReader.load()
        if !picks.isEmpty {
            let entries = (0..<Self.slots).map { slot in
                Self.pickEntry(picks, snapshot: snapshot,
                               date: Date.now.addingTimeInterval(TimeInterval(slot) * 30 * 60), slot: slot)
            }
            completion(cappedTimeline(entries, cutoff: DailyPicksReader.nextMidnight()))
            return
        }

        guard !moments.isEmpty else {
            let next = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 5),
                                                 matchingPolicy: .nextTime) ?? Date.now.addingTimeInterval(3600)
            completion(Timeline(entries: [BubuEntry(date: .now, snapshot: snapshot)], policy: .after(next)))
            return
        }

        // 每天换一种顺序：用「今天是第几天」当种子，同一天内稳定、跨天自然翻新。
        // 不能用 random——每次重建时间线顺序都变的话，画面会毫无规律地跳。
        let daySeed = Int(Date.now.timeIntervalSince1970 / 86_400)
        let ordered = dailyShuffled(moments, seed: daySeed)
        // 同一屏绝不重复同一张：池子够一屏时每屏取连续的 wallSize 张（循环取用）；
        // 不够一屏时这一屏就只铺池里这几张，版式按实际张数排（见 BubuMomentWallView）。
        let perWall = min(Self.wallSize, ordered.count)
        let pages = ordered.count > Self.wallSize
            ? min(Self.slots, (ordered.count + Self.wallSize - 1) / Self.wallSize)
            : min(Self.slots, ordered.count)

        var entries: [BubuEntry] = []
        for slot in 0..<Self.slots {
            let date = Date.now.addingTimeInterval(TimeInterval(slot) * 30 * 60)
            let start = ordered.count > Self.wallSize ? (slot % pages) * Self.wallSize : slot % pages
            let wall = (0..<perWall).map { ordered[(start + $0) % ordered.count] }
            entries.append(BubuEntry(date: date, snapshot: snapshot,
                                     photoIndex: slot,
                                     moment: wall.first,
                                     wallMoments: wall,
                                     wallPhotos: wall.compactMap { BubuWidgetData.momentImageData(fileName: $0.photoFileName) },
                                     pageCount: pages))
        }
        completion(cappedTimeline(entries, cutoff: nextLocalMidnight()))
    }

    private static func pickEntry(_ picks: [(pick: WidgetDailyPick, data: Data)], snapshot: BubuSnapshot,
                                  date: Date, slot: Int) -> BubuEntry {
        let rotated = Array(picks[(slot % picks.count)...] + picks[..<(slot % picks.count)])
        let moments = rotated.map { item in
            SharedMoment(photoFileName: item.pick.file, title: item.pick.caption, note: nil,
                         date: item.pick.capturedDate ?? date, moodEmoji: nil,
                         isOnThisDay: item.pick.isOnThisDay)
        }
        var links: [String: URL] = [:]
        for item in picks { links[item.pick.file] = item.pick.url }
        return BubuEntry(date: date, snapshot: snapshot, photoIndex: slot, moment: moments.first,
                         wallMoments: moments, wallPhotos: rotated.map(\.data),
                         isDailyPicks: true, wallLinks: links, pickURL: rotated.first?.pick.url,
                         pageCount: min(picks.count, Self.slots))
    }
}

// MARK: - 配色（与主 App 同源暖色，不引入 App 的 BubuTheme 以保持 widget 轻量）
private enum WidgetPalette {
    // 奶油马卡龙（与主 App BubuTheme 对齐）
    static let primary = Color(red: 0.949, green: 0.471, blue: 0.624)  // rose #F2789F
    static let roseDeep = Color(red: 0.882, green: 0.361, blue: 0.525) // deeprose #E15C86
    static let peach = Color(red: 1.000, green: 0.827, blue: 0.745)    // #FFD3BE
    static let pink = Color(red: 1.000, green: 0.761, blue: 0.839)     // #FFC2D6
    static let lav = Color(red: 0.863, green: 0.788, blue: 1.000)      // #DCC9FF
    static let honey = Color(red: 1.000, green: 0.886, blue: 0.627)    // butter
    static let mint = Color(red: 0.749, green: 0.922, blue: 0.827)
    static let cream = Color(red: 1.000, green: 0.969, blue: 0.945)    // #FFF7F1
    /// 主文字：浅色下深棕 ink #5A3D34；深色（深色模式或深色导入壁纸）下奶油 #FFF7F1。
    /// 深色壁纸上固定深棕对比度只有约 1.5:1，几乎读不出来。
    static let warmBrown = dynamic(light: (0.353, 0.239, 0.204), dark: (1.000, 0.969, 0.945))
    /// 次级文字。浅色比 App 内的 ink2 深一档（#947869，透明底上不发飘）；深色用浅粉 #F2D6CB。
    static let secondary = dynamic(light: (0.580, 0.470, 0.420), dark: (0.949, 0.839, 0.796))
    /// 小卡片/胶囊底：浅色是白，深色是黑（再由调用方压不透明度）。
    static let chip = dynamic(light: (1, 1, 1), dark: (0, 0, 0))
    /// 实底纸色：浅色奶油，深色暖炭 #2A211F。
    static let paper = dynamic(light: (1.000, 0.969, 0.945), dark: (0.165, 0.129, 0.122))

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// 导入壁纸的平均亮度（0…1）。读不到时为 nil。小组件按它选字色，而不是按系统深浅色。
private func wallpaperLuminance(for family: WidgetFamily) -> Double? {
    let slot: WidgetWallpaper.Slot
    switch family {
    case .systemSmall: slot = .small
    case .systemMedium: slot = .medium
    case .systemLarge: slot = .large
    default: return nil
    }
    guard let data = WidgetWallpaper.backgroundData(for: slot),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 16,
          ] as CFDictionary) else { return nil }
    var pixel = [UInt8](repeating: 0, count: 4)
    let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.interpolationQuality = .medium
        context.draw(thumb, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return true
    }
    guard drawn else { return nil }
    return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
}

// MARK: - 布布圆形头像（无头像时回退到吉祥物表情）
struct BubuAvatar: View {
    let imageData: Data?
    var size: CGFloat
    /// 可爱模式（信息卡用）：糖果渐变描边 + 右下角蝴蝶结贴纸。
    var cute = false
    var body: some View {
        ZStack {
            if let image = Self.downsampledImage(from: imageData, maxPixel: size * 3) {
                Image(uiImage: image)
                    .resizable()
                    // iOS 18+ 主屏染色/淡色模式：照片保持全彩，不被系统单色化成实心色块。
                    // 必须紧跟在 Image 上调用（scaledToFill 之后类型退化为 some View）。
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [WidgetPalette.primary.opacity(0.34), WidgetPalette.honey.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text("布")
                    .font(.system(size: size * 0.44, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if cute {
                Circle().stroke(
                    AngularGradient(colors: [WidgetPalette.pink, WidgetPalette.honey, WidgetPalette.mint,
                                             WidgetPalette.lav, WidgetPalette.pink], center: .center),
                    lineWidth: 2.5)
            } else {
                Circle().stroke(.white.opacity(0.85), lineWidth: 2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if cute {
                Text("🎀")
                    .font(.system(size: max(12, size * 0.28)))
                    .rotationEffect(.degrees(12))
                    .offset(x: size * 0.06, y: size * 0.05)
            }
        }
        .shadow(color: WidgetPalette.primary.opacity(0.25), radius: 4, y: 2)
    }

    static func downsampledImage(from data: Data?, maxPixel: CGFloat) -> UIImage? {
        guard let data else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(96, Int(maxPixel))
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 毛玻璃卡片底（统一各 family）
/// 【真机验证过的结论，别再改回去】小组件的内容是**离屏渲染成一张图**再交给桌面合成的，
/// 组件进程拿不到壁纸像素。所以 `.ultraThinMaterial` / `.regularMaterial` 这类材质
/// 在小组件里**不会**虚化壁纸——系统只会把它画成一块近乎实心的白板（2026-07-29 实测）。
///
/// 小组件里唯一能真正透出壁纸的只有 **alpha**：整张卡的通透感必须靠低不透明度叠色做，
/// 总不透明度控制在 0.3 上下——
/// 再低，固定深棕色的文字（`warmBrown`，本来是配奶油底设计的）在花壁纸上会读不出来；
/// 再高，就退回成一块浮在桌面上的实心粉卡。
///
/// 想要系统级的真·液态玻璃，是桌面侧的开关：长按桌面 → 编辑 → 自定 → 「清除」，
/// 那是 iOS 26 给全部图标和小组件统一上玻璃，组件这边只要别画实心底就能吃到。
private struct BubuGlassContainer: View {
    var tintStrength: Double = 1.0
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 用户导入过桌面壁纸：直接把它身后那块壁纸铺成底，桌面上小组件就"消失"了。
        // 这条路不受「壁纸有没有花纹」影响——它本来就是壁纸本身，
        // 比调不透明度可靠得多（调 alpha 在纯色壁纸区域等于没调）。
        if let slot = Self.slot(for: family),
           let data = WidgetWallpaper.backgroundData(for: slot),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            glass
        }
    }

    private static func slot(for family: WidgetFamily) -> WidgetWallpaper.Slot? {
        switch family {
        case .systemSmall: return .small
        case .systemMedium: return .medium
        case .systemLarge: return .large
        default: return nil   // 锁屏 / StandBy 位置没有壁纸可透
        }
    }

    private var glass: some View {
        ZStack {
            // 近乎全透。为什么压到这么低：真机上壁纸在小组件那一带是接近纯净的浅灰，
            // 底下没有花纹可透——底色留到 27% 时，视觉上和一张不透明的浅粉卡几乎没区别
            // （2026-07-29 真机反馈）。透明度只有压到 10% 以下，卡片才真的"退到壁纸里"，
            // 剩下头像、数字块、照片浮在上面。
            // 深色模式：约 20% 黑压住深色壁纸，奶油字才立得住。
            colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.06)
            LinearGradient(
                colors: [WidgetPalette.peach.opacity(0.06 * tintStrength),
                         WidgetPalette.pink.opacity(0.05 * tintStrength),
                         WidgetPalette.lav.opacity(0.045 * tintStrength),
                         WidgetPalette.cream.opacity(0.04 * tintStrength)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // 玻璃描边。底色透了之后卡片没有边界，会直接糊进壁纸里；
            // 这道亮边把「这是一块玻璃」的形状立回来——真玻璃的观感八成来自边缘高光，不是底色。
            // 用 ContainerRelativeShape 而不是写死圆角：它自动跟随系统给这个尺寸的小组件圆角，
            // 手写半径在不同机型/不同 family 上必然对不齐。
            ContainerRelativeShape()
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.25 : 0.55), lineWidth: 1)
        }
    }
}

private extension View {
    /// 全彩走毛玻璃；染色(tinted)/vibrant 下系统会把内容单色化，
    /// 玻璃与渐变都会糊成一坨，降级成极淡中性底，让染色只作用在前景。
    @ViewBuilder
    func bubuGlassBackground(_ mode: WidgetRenderingMode, tintStrength: Double = 1.0) -> some View {
        if mode == .fullColor {
            modifier(WallpaperAwareScheme())
                .containerBackground(for: .widget) { BubuGlassContainer(tintStrength: tintStrength) }
        } else {
            containerBackground(for: .widget) { Color.white.opacity(0.06) }
        }
    }
}

/// 铺了导入壁纸时，字色跟着壁纸本身的亮度走（深壁纸用奶油字，浅壁纸用深棕字），
/// 不跟系统深浅色——壁纸就是小组件的底。
private struct WallpaperAwareScheme: ViewModifier {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let scheme = wallpaperLuminance(for: family).map { $0 < 0.55 ? ColorScheme.dark : .light } ?? colorScheme
        content.environment(\.colorScheme, scheme)
    }
}

private struct BubuWidgetBackground: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.bubuGlassBackground(renderingMode)
    }
}

private extension View {
    func bubuWidgetBackground() -> some View {
        modifier(BubuWidgetBackground())
    }
}

/// 旧的「按 style 分叉」体系。moment 已独立成 BubuMomentCarouselView（整图轮播），
/// 不再走这套，故此枚举只剩身份卡与成长一览两款。
private enum BubuWidgetStyle {
    case identity
    case growth

    /// 点击小组件跳转到 App 对应页面的 deep link（App 端 BubuRoute 解析）。
    var deepLink: URL {
        switch self {
        case .identity: return URL(string: "bubu://identity")!
        case .growth: return URL(string: "bubu://growth")!
        }
    }

    /// 「＋记一笔」快捷 Link：打开 App 并直接拉起快速记录。
    static let recordLink = URL(string: "bubu://record")!
}

/// 「＋记一笔」小圆钮：Link 优先于 widgetURL，点它直达快速记录（仅中/大尺寸可用 Link）。
private struct BubuPlusLink: View {
    var size: CGFloat = 26

    var body: some View {
        Link(destination: BubuWidgetStyle.recordLink) {
            Image(systemName: "plus")
                .font(.system(size: size * 0.46, weight: .black))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(WidgetPalette.primary, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: WidgetPalette.primary.opacity(0.3), radius: 3, y: 1)
        }
    }
}

private struct BubuInfoChip: View {
    let title: String
    let value: String
    var tint: Color = WidgetPalette.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(WidgetPalette.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(WidgetPalette.chip.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct BubuMetricPill: View {
    let title: String
    let value: String
    var icon: String
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.warmBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(WidgetPalette.chip.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BubuPhotoTile: View {
    let imageData: Data?
    var cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = BubuAvatar.downsampledImage(from: imageData, maxPixel: max(proxy.size.width, proxy.size.height) * 3) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: max(1, proxy.size.width), height: max(1, proxy.size.height))
                } else {
                    LinearGradient(
                        colors: [WidgetPalette.honey.opacity(0.66), WidgetPalette.pink.opacity(0.62), WidgetPalette.lav.opacity(0.52)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.white.opacity(0.86))
                }
            }
            .frame(width: max(1, proxy.size.width), height: max(1, proxy.size.height))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .clipped()
        }
        .clipped()
    }
}

private struct BubuBirthdayBadge: View {
    let snapshot: BubuSnapshot
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            Text(snapshot.hasProfile ? "\(snapshot.daysUntilBirthday)" : "--")
                .font(.system(size: compact ? 18 : 28, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(snapshot.hasProfile ? "天后生日" : "待补档案")
                .font(.system(size: compact ? 8 : 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
        }
        .frame(width: compact ? 58 : 70, height: compact ? 46 : 58)
        .background(
            LinearGradient(colors: [WidgetPalette.primary, WidgetPalette.honey],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .shadow(color: WidgetPalette.primary.opacity(0.22), radius: 8, y: 4)
    }
}

private struct BubuProgressStars: View {
    let snapshot: BubuSnapshot
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: starFilled(index) ? "star.fill" : "star")
                        .font(.system(size: compact ? 10 : 12, weight: .black))
                        .foregroundColor(starFilled(index) ? WidgetPalette.honey : WidgetPalette.secondary.opacity(0.32))
                }
                Spacer(minLength: 0)
                Text(snapshot.milestoneProgressText)
                    .font(.system(size: compact ? 10 : 11, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.roseDeep)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.chip.opacity(0.48))
                    Capsule()
                        .fill(LinearGradient(colors: [WidgetPalette.honey, WidgetPalette.primary],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * snapshot.milestoneProgress))
                }
            }
            .frame(height: compact ? 5 : 7)
        }
    }

    private func starFilled(_ index: Int) -> Bool {
        snapshot.milestoneProgress >= Double(index + 1) / 5.0
    }
}

private struct BubuMotifRow: View {
    var body: some View {
        HStack(spacing: 7) {
            motif("heart.fill", WidgetPalette.primary)
            motif("sparkles", WidgetPalette.honey)
            motif("moon.stars.fill", WidgetPalette.lav)
            motif("balloon.2.fill", WidgetPalette.mint)
            motif("seal.fill", WidgetPalette.pink)
        }
    }

    private func motif(_ icon: String, _ tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(WidgetPalette.chip.opacity(0.42), in: Circle())
    }
}

private struct BubuPhotoStrip: View {
    let snapshot: BubuSnapshot

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                BubuPhotoTile(imageData: imageData(at: index), cornerRadius: 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
    }

    private func imageData(at index: Int) -> Data? {
        guard snapshot.photoImageData.indices.contains(index) else { return nil }
        return snapshot.photoImageData[index]
    }
}

private struct BubuDayHeader: View {
    let snapshot: BubuSnapshot
    var compact = false

    var body: some View {
        HStack(spacing: 9) {
            BubuAvatar(imageData: snapshot.avatarImageData, size: compact ? 38 : 50, cute: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.system(size: compact ? 18 : 22, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.warmBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(snapshot.ageText)
                    .font(.system(size: compact ? 11 : 13, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.roseDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            Spacer(minLength: 0)
            Text("No.\(snapshot.idNumber)")
                .font(.system(size: compact ? 7 : 8, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.secondary.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

// MARK: - 身份陪伴
// MARK: - 信息卡可爱化装饰（手账贴纸 + 波点底纹）

/// 手账贴纸：低透明 emoji 带轻微旋转散布在卡片边角，像贴在成长手账上的小贴纸。
/// 位置避开信息区（右上/右中/左下），不遮字。emoji 在染色模式下保持原色，无需降级分支。
private struct BubuStickerDecor: View {
    var compact = false
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Group {
                Text("☁️").font(.system(size: compact ? 15 : 19)).opacity(0.55)
                    .rotationEffect(.degrees(-10)).position(x: w * 0.86, y: h * 0.09)
                Text("🎈").font(.system(size: compact ? 12 : 15)).opacity(0.6)
                    .rotationEffect(.degrees(12)).position(x: w * 0.95, y: h * 0.42)
                if !compact {
                    Text("🧸").font(.system(size: 14)).opacity(0.5)
                        .rotationEffect(.degrees(-14)).position(x: w * 0.05, y: h * 0.62)
                }
                Text("⭐️").font(.system(size: compact ? 10 : 12)).opacity(0.55)
                    .rotationEffect(.degrees(8)).position(x: w * 0.07, y: h * 0.93)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 淡淡的波点底纹：给奶油底加一层手帐纸的质感，透明度压得很低不抢内容。
private struct BubuDotsPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 26
            var y: CGFloat = 6
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 6 : 6 + spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3.4, height: 3.4)),
                             with: .color(WidgetPalette.primary.opacity(0.07)))
                    x += spacing
                }
                y += spacing * 0.86
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

private struct BubuIdentitySmallView: View {
    let snapshot: BubuSnapshot
    /// 生日前 7 天（含当天）进入生日强调态。
    private var birthdayWeek: Bool { snapshot.hasProfile && snapshot.daysUntilBirthday <= 7 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BubuDayHeader(snapshot: snapshot, compact: true)
            Spacer(minLength: 0)
            if birthdayWeek {
                birthdayEmphasis
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("陪伴第")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.secondary)
                    Text(snapshot.hasProfile ? "\(snapshot.daysSinceBirth)" : "--")
                        .font(.system(size: 37, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.warmBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("天")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.primary)
                }
            }
            BubuProgressStars(snapshot: snapshot, compact: true)
        }
        .background { BubuDotsPattern() }
        .overlay { BubuStickerDecor(compact: true) }
    }

    /// 生日周强调：突出「还有 N 天生日」。
    private var birthdayEmphasis: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "birthday.cake.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(WidgetPalette.primary)
                Text(snapshot.daysUntilBirthday == 0 ? "生日快乐" : "生日倒计时")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.roseDeep)
            }
            Text(snapshot.daysUntilBirthday == 0 ? "🎂" : "\(snapshot.daysUntilBirthday)")
                .font(.system(size: 37, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
            Text(snapshot.daysUntilBirthday == 0 ? "今天是布布的生日" : "天后就是生日啦")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.roseDeep)
        }
    }
}

private struct BubuIdentityMediumView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 7) {
                BubuAvatar(imageData: snapshot.avatarImageData, size: 70, cute: true)
                Text(snapshot.name)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(WidgetPalette.primary, in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("❀ 布布小档案")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(WidgetPalette.primary.opacity(0.72))
                            .lineLimit(1)
                        Text(snapshot.name)
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundColor(WidgetPalette.warmBrown)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    Spacer(minLength: 0)
                    BubuBirthdayBadge(snapshot: snapshot, compact: true)
                }
                HStack(spacing: 8) {
                    BubuInfoChip(title: "AGE", value: snapshot.ageText, tint: WidgetPalette.roseDeep)
                    BubuInfoChip(title: "DAY", value: snapshot.hasProfile ? "第 \(snapshot.daysSinceBirth) 天" : "待同步", tint: WidgetPalette.mint)
                }
                HStack {
                    Text("🎀 No.\(snapshot.idNumber)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    BubuPlusLink(size: 24)
                }
            }
        }
        .background { BubuDotsPattern() }
        .overlay { BubuStickerDecor() }
    }
}

private struct BubuIdentityLargeView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("❀ 布布小档案")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(WidgetPalette.primary.opacity(0.72))
                    Text(snapshot.name)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.warmBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                Spacer()
                BubuPlusLink(size: 26)
                Text("元气满满 ✨")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WidgetPalette.primary, in: Capsule())
            }

            HStack(alignment: .top, spacing: 12) {
                BubuAvatar(imageData: snapshot.avatarImageData, size: 90, cute: true)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        BubuInfoChip(title: "AGE", value: snapshot.ageText, tint: WidgetPalette.roseDeep)
                        BubuInfoChip(title: "DAY", value: snapshot.hasProfile ? "第 \(snapshot.daysSinceBirth) 天" : "待同步", tint: WidgetPalette.mint)
                    }
                    HStack(spacing: 8) {
                        BubuInfoChip(title: "BIRTH", value: birthDateText, tint: WidgetPalette.primary)
                        BubuInfoChip(title: "PHOTOS", value: "\(snapshot.totalPhotoCount) 张", tint: WidgetPalette.honey)
                    }
                    Text("🎀 No.\(snapshot.idNumber)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                BubuMetricPill(title: "生日", value: "\(snapshot.daysUntilBirthday) 天", icon: "birthday.cake.fill", tint: WidgetPalette.primary)
                BubuMetricPill(title: "本月照片", value: "\(snapshot.monthlyPhotoCount) 张", icon: "photo.stack.fill", tint: WidgetPalette.honey)
            }
            BubuProgressStars(snapshot: snapshot)
            Spacer(minLength: 0)
        }
        .background { BubuDotsPattern() }
        .overlay { BubuStickerDecor() }
    }

    private var birthDateText: String {
        guard let birthday = snapshot.birthday else { return "待补全" }
        return birthday.formatted(.dateTime.month().day())
    }
}

// MARK: - 今日时光（整图沉浸版式：照片作 containerBackground 铺满，此处只放前景白字）
private struct BubuMomentSmallView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(snapshot.recentMoodEmoji ?? "✨").font(.system(size: 13))
                Text(dateText)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
            }
            Text(snapshot.recentEntryTitle.isEmpty ? "今日时光" : snapshot.recentEntryTitle)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(13)
    }

    private var dateText: String {
        (snapshot.recentEntryDate ?? .now).formatted(.dateTime.month().day())
    }
}

private struct BubuMomentMediumView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Text(snapshot.recentMoodEmoji ?? "✨").font(.system(size: 14))
                Text(dateText)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 0)
                Text(snapshot.name)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(.white.opacity(0.22), in: Capsule())
            }
            Text(snapshot.recentEntryTitle.isEmpty ? "今日时光" : snapshot.recentEntryTitle)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            if !snapshot.recentEntryNote.isEmpty {
                Text(snapshot.recentEntryNote)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(15)
    }

    private var dateText: String {
        (snapshot.recentEntryDate ?? .now).formatted(.dateTime.month().day())
    }
}

private struct BubuMomentLargeView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BubuMomentHeader(snapshot: snapshot)
                BubuPlusLink(size: 24)
            }
            Text(snapshot.recentEntryTitle)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.warmBrown)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            BubuPhotoStrip(snapshot: snapshot)
                .frame(height: 92)
                .clipped()

            Text(snapshot.recentEntryNote)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundColor(WidgetPalette.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(WidgetPalette.chip.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            BubuMomentStatsRow(snapshot: snapshot)
            Spacer(minLength: 0)
        }
    }
}

private struct BubuMomentStatsRow: View {
    let snapshot: BubuSnapshot

    var body: some View {
        HStack(spacing: 8) {
            BubuMetricPill(title: "陪伴", value: "\(snapshot.daysSinceBirth) 天", icon: "heart.fill", tint: WidgetPalette.primary)
            BubuMetricPill(title: "本月照片", value: "\(snapshot.monthlyPhotoCount) 张", icon: "photo.stack.fill", tint: WidgetPalette.honey)
            BubuMetricPill(title: "记录", value: "\(snapshot.totalEntryCount) 条", icon: "book.pages.fill", tint: WidgetPalette.mint)
        }
    }
}

private struct BubuMomentHeader: View {
    let snapshot: BubuSnapshot
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Label("今日时光", systemImage: "photo.on.rectangle.angled")
                .font(.system(size: compact ? 9 : 11, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(snapshot.recentMoodEmoji ?? "✨")
                Text((snapshot.recentEntryDate ?? .now).formatted(.dateTime.month().day()))
            }
            .font(.system(size: compact ? 9 : 10, weight: .black, design: .rounded))
            .foregroundColor(WidgetPalette.secondary)
            .lineLimit(1)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 4 : 5)
            .background(WidgetPalette.chip.opacity(0.58), in: Capsule())
        }
    }
}

// MARK: - 成长一览
private struct BubuGrowthSmallView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(WidgetPalette.honey)
                Spacer()
                Text(snapshot.milestoneProgressText)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.roseDeep)
            }
            Text("里程碑")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.warmBrown)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            BubuProgressStars(snapshot: snapshot)
            Spacer(minLength: 0)
            BubuMotifRow()
        }
    }
}

private struct BubuGrowthMediumView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                BubuAvatar(imageData: snapshot.avatarImageData, size: 58)
                Text("成长一览")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.warmBrown)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("第 \(snapshot.daysSinceBirth) 天")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.primary)
                        .lineLimit(1)
                    BubuPlusLink(size: 22)
                }
            }
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    BubuMetricPill(title: "身高", value: snapshot.latestHeightText, icon: "ruler.fill", tint: WidgetPalette.mint)
                    BubuMetricPill(title: "体重", value: snapshot.latestWeightText, icon: "scalemass.fill", tint: WidgetPalette.honey)
                }
                HStack(spacing: 8) {
                    BubuMetricPill(title: "里程碑", value: snapshot.milestoneProgressText, icon: "star.fill", tint: WidgetPalette.primary)
                    BubuMetricPill(title: "下一个", value: snapshot.nextMilestoneTitle, icon: "flag.checkered", tint: WidgetPalette.lav)
                }
            }
        }
    }
}

private struct BubuGrowthLargeView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BubuDayHeader(snapshot: snapshot)
                Spacer()
                BubuPlusLink(size: 26)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("里程碑")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.warmBrown)
                    Spacer()
                    Text(snapshot.milestoneProgressText)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.roseDeep)
                }
                BubuProgressStars(snapshot: snapshot)
                BubuMotifRow()
            }
            .padding(11)
            .background(WidgetPalette.chip.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 8) {
                BubuMetricPill(title: "身高", value: snapshot.latestHeightText, icon: "ruler.fill", tint: WidgetPalette.mint)
                BubuMetricPill(title: "体重", value: snapshot.latestWeightText, icon: "scalemass.fill", tint: WidgetPalette.honey)
            }
            HStack(spacing: 8) {
                BubuMetricPill(title: "下一个", value: "\(snapshot.nextMilestoneEmoji) \(snapshot.nextMilestoneTitle)", icon: "flag.fill", tint: WidgetPalette.lav)
                BubuMetricPill(title: "最新", value: latestMilestoneText, icon: "checkmark.seal.fill", tint: WidgetPalette.primary)
            }
            Spacer(minLength: 0)
        }
    }

    private var latestMilestoneText: String {
        if let title = snapshot.latestMilestoneTitle {
            return "\(snapshot.latestMilestoneEmoji ?? "🌟") \(title)"
        }
        return "待点亮"
    }
}

private struct BubuSmallView: View {
    let snapshot: BubuSnapshot
    let style: BubuWidgetStyle

    var body: some View {
        switch style {
        case .identity:
            BubuIdentitySmallView(snapshot: snapshot)
        case .growth:
            BubuGrowthSmallView(snapshot: snapshot)
        }
    }
}

private struct BubuMediumView: View {
    let snapshot: BubuSnapshot
    let style: BubuWidgetStyle

    var body: some View {
        switch style {
        case .identity:
            BubuIdentityMediumView(snapshot: snapshot)
        case .growth:
            BubuGrowthMediumView(snapshot: snapshot)
        }
    }
}

private struct BubuLargeView: View {
    let snapshot: BubuSnapshot
    let style: BubuWidgetStyle

    var body: some View {
        switch style {
        case .identity:
            BubuIdentityLargeView(snapshot: snapshot)
        case .growth:
            BubuGrowthLargeView(snapshot: snapshot)
        }
    }
}

// MARK: - 容器：按 family 分发 + 背景
private struct BubuWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BubuEntry
    var style: BubuWidgetStyle

    var body: some View {
        content
            .widgetURL(style.deepLink)
            // 沉浸式时光中尺寸：右上角是照片空区，「＋记一笔」用 overlay 悬浮。
            // 其余版式的「＋」内嵌在各自布局的空位里（见各 View），避免盖住生日徽章/ACTIVE/数据 pill。
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch family {
            case .systemSmall:
                BubuSmallView(snapshot: entry.snapshot, style: style)
                    .padding(14).bubuWidgetBackground()
            case .systemMedium:
                BubuMediumView(snapshot: entry.snapshot, style: style)
                    .padding(15).bubuWidgetBackground()
            case .systemLarge where style == .identity:
                // 身份卡大尺寸：头像柔焦铺底 + 暖色蒙版，比纯渐变更有「相框」质感，信息仍清晰。
                BubuLargeView(snapshot: entry.snapshot, style: style)
                    .padding(17)
                    .softPhotoBackground(imageData: entry.snapshot.avatarImageData)
            case .systemLarge:
                BubuLargeView(snapshot: entry.snapshot, style: style)
                    .padding(17).bubuWidgetBackground()
            default:
                BubuSmallView(snapshot: entry.snapshot, style: style)
                    .padding(14).bubuWidgetBackground()
            }
        }
    }
}

// MARK: - 整图沉浸容器背景（照片出血铺满 + 底部渐变蒙版）
private struct ImmersiveContainerBackground: ViewModifier {
    let imageData: Data?
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            ZStack {
                if let image = BubuAvatar.downsampledImage(from: imageData, maxPixel: 900),
                   renderingMode == .fullColor {
                    Image(uiImage: image).resizable().scaledToFill()
                    LinearGradient(colors: [.clear, .clear, .black.opacity(0.3), .black.opacity(0.72)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    LinearGradient(colors: [WidgetPalette.peach.opacity(0.7), WidgetPalette.pink.opacity(0.6), WidgetPalette.lav.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    LinearGradient(colors: [.clear, .black.opacity(0.24)], startPoint: .top, endPoint: .bottom)
                }
            }
        }
    }
}

private extension View {
    func immersiveContainerBackground(imageData: Data?) -> some View {
        modifier(ImmersiveContainerBackground(imageData: imageData))
    }
    func softPhotoBackground(imageData: Data?) -> some View {
        modifier(SoftPhotoBackground(imageData: imageData))
    }
}

// MARK: - 柔焦照片铺底（身份卡大尺寸：头像放大模糊 + 暖色蒙版，信息层仍清晰）
private struct SoftPhotoBackground: ViewModifier {
    let imageData: Data?
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            ZStack {
                if let image = BubuAvatar.downsampledImage(from: imageData, maxPixel: 400),
                   renderingMode == .fullColor {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 28)
                        .opacity(0.55)
                    // 暖色蒙版：压住模糊照片，保证上层白卡片信息对比度。
                    if colorScheme == .dark {
                        LinearGradient(colors: [WidgetPalette.paper.opacity(0.86), WidgetPalette.roseDeep.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        LinearGradient(
                            colors: [WidgetPalette.cream.opacity(0.82), WidgetPalette.peach.opacity(0.7), WidgetPalette.pink.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                } else if colorScheme == .dark {
                    LinearGradient(colors: [WidgetPalette.paper, WidgetPalette.roseDeep.opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    LinearGradient(
                        colors: [WidgetPalette.peach.opacity(0.55), WidgetPalette.pink.opacity(0.45), WidgetPalette.lav.opacity(0.45), WidgetPalette.cream],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
        }
    }
}


// MARK: - 时光机照片墙
/// 桌面上的一面照片墙：像翻朋友圈/微博的图墙那样，一屏铺满布布的若干个瞬间。
///
/// 为什么不是单张大图：单张即使会轮播，照片少的时候看着仍像没变；
/// 一屏 9 张则「一眼就是一段生活」，每 30 分钟整墙换一批，变化明显、也更耐看。
struct BubuMomentWallView: View {
    var entry: BubuEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// 本屏最多张数：大卡 9、中卡 4、小卡 4。少于上限时按实际张数换版式，同一屏不重复、不缺块。
    private var tileCount: Int {
        switch family {
        case .systemLarge: return 9
        default: return 4
        }
    }

    private var tiles: [(moment: SharedMoment, image: UIImage)] {
        let maxPixel: CGFloat = family == .systemLarge ? 420 : 320
        var seen = Set<String>()
        return zip(entry.wallMoments, entry.wallPhotos)
            .filter { seen.insert($0.0.photoFileName).inserted }
            .prefix(tileCount)
            .compactMap { pair in
                guard let img = BubuAvatar.downsampledImage(from: pair.1, maxPixel: maxPixel) else { return nil }
                return (pair.0, img)
            }
    }

    var body: some View {
        let items = tiles
        Group {
            if items.isEmpty {
                emptyState.padding(14).bubuWallBackground(renderingMode)
            } else if family == .systemLarge {
                largeWall(items).padding(12).bubuWallBackground(renderingMode)
            } else if family == .systemMedium {
                mediumWall(items).padding(12).bubuWallBackground(renderingMode)
            } else {
                smallWall(items).padding(10).bubuWallBackground(renderingMode)
            }
        }
        .widgetURL(entry.pickURL ?? URL(string: "bubu://moment"))
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
    }

    private typealias Item = (moment: SharedMoment, image: UIImage)

    // MARK: 大卡：标题行 + 图墙（按张数排版）+ 底部一句话

    private func largeWall(_ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            Group {
                switch items.count {
                case 9...: grid(Array(items.prefix(9)), columns: 3, corner: 12, badge: true)
                case 6...8: grid(Array(items.prefix(6)), columns: 3, corner: 12, badge: true)
                case 4...5: grid(Array(items.prefix(4)), columns: 2, corner: 14, badge: true)
                case 2...3: leadAndRow(items, corner: 14, vertical: true)
                default: linked(items[0]) { tile(items[0], corner: 16, showBadge: true) }
                }
            }
            .frame(maxHeight: .infinity)
            if let lead = items.first?.moment {
                caption(lead)
            }
        }
    }

    // MARK: 中卡：标题行 + 1–4 张横排

    private func mediumWall(_ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            grid(Array(items.prefix(4)), columns: min(4, items.count), corner: 10, badge: true)
        }
    }

    // MARK: 小卡：2×2 / 一大两小 / 两张并排 / 满幅

    private func smallWall(_ items: [Item]) -> some View {
        Group {
            switch items.count {
            case 4...: grid(Array(items.prefix(4)), columns: 2, corner: 9, badge: false, spacing: 4)
            case 3: leadAndRow(items, corner: 9, vertical: false, spacing: 4)
            case 2: grid(items, columns: 2, corner: 9, badge: false, spacing: 4)
            default: tile(items[0], corner: 12, showBadge: false)
            }
        }
    }

    /// 等分网格：张数正好铺满 rows × columns，瓦片随可用空间伸缩（不留空行）。
    private func grid(_ items: [Item], columns: Int, corner: CGFloat, badge: Bool,
                      spacing: CGFloat = 5) -> some View {
        let rows = stride(from: 0, to: items.count, by: max(1, columns)).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
        return VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        linked(item) { tile(item, corner: corner, showBadge: badge) }
                    }
                }
            }
        }
    }

    /// 一大配一两小：大卡上大下小，小卡左大右小。
    @ViewBuilder
    private func leadAndRow(_ items: [Item], corner: CGFloat, vertical: Bool, spacing: CGFloat = 5) -> some View {
        let rest = Array(items.dropFirst().prefix(2))
        if vertical {
            VStack(spacing: spacing) {
                linked(items[0]) { tile(items[0], corner: corner, showBadge: true) }
                    .frame(maxHeight: .infinity).layoutPriority(1)
                grid(rest, columns: rest.count, corner: corner, badge: true, spacing: spacing)
                    .frame(maxHeight: .infinity)
            }
        } else {
            HStack(spacing: spacing) {
                tile(items[0], corner: corner, showBadge: false)
                VStack(spacing: spacing) {
                    ForEach(Array(rest.enumerated()), id: \.offset) { _, item in
                        tile(item, corner: corner, showBadge: false)
                    }
                }
            }
        }
    }

    // MARK: 构件

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.isDailyPicks ? "sparkles" : "photo.stack.fill")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(WidgetPalette.primary)
            Text(entry.isDailyPicks ? "布布今日精选" : "布布的时光墙")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.warmBrown)
            Spacer(minLength: 0)
            // 轮换位置点：点数 = 实际页数，让人知道这面墙会一直翻，不是坏了。
            if entry.pageCount > 1 {
                HStack(spacing: 3) {
                    ForEach(0..<min(entry.pageCount, 8), id: \.self) { i in
                        Circle()
                            .fill(i == entry.photoIndex % entry.pageCount
                                  ? WidgetPalette.primary : WidgetPalette.primary.opacity(0.25))
                            .frame(width: 4.5, height: 4.5)
                    }
                }
            }
            BubuPlusLink(size: 22)
        }
    }

    /// 精选瓦片各自深链到在线时光详情（中/大尺寸才支持 Link；小卡走 widgetURL）。
    @ViewBuilder
    private func linked<Content: View>(_ item: Item,
                                       @ViewBuilder content: () -> Content) -> some View {
        if let url = entry.wallLinks[item.moment.photoFileName] {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }

    /// 一块照片瓦片：正方形填充裁切；「那年今日」左上角打徽章。
    private func tile(_ item: Item, corner: CGFloat, showBadge: Bool) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Image(uiImage: item.image)
                    .resizable()
                    // 染色/淡色模式下照片保持真彩，不被系统涂成色块
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(alignment: .topLeading) {
                if showBadge && item.moment.isOnThisDay {
                    Text("那年今日")
                        .font(.system(size: 7.5, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2.5)
                        .background(WidgetPalette.roseDeep.opacity(0.92), in: Capsule())
                        .padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.8)
            }
    }

    /// 底部一句话：带头的那张照片的标题 + 日期 + 当时多大。
    private func caption(_ moment: SharedMoment) -> some View {
        HStack(spacing: 6) {
            if let mood = moment.moodEmoji { Text(mood).font(.system(size: 12)) }
            Text(moment.title ?? moment.note ?? "布布的一天")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(WidgetPalette.warmBrown)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(ageAt(moment.date) ?? moment.date.formatted(.dateTime.month().day()))
                .font(.system(size: 10.5, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.primary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(WidgetPalette.chip.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func ageAt(_ date: Date) -> String? {
        guard let birthday = entry.snapshot.birthday, date >= birthday else { return nil }
        return "布布 " + AgeCalculator.compactAge(birthday: birthday, at: date)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🖼️").font(.system(size: family == .systemSmall ? 28 : 38))
            Text("记几条带照片的时光")
                .font(.system(size: family == .systemSmall ? 11 : 13, weight: .heavy, design: .rounded))
                .foregroundColor(WidgetPalette.warmBrown)
            if family != .systemSmall {
                Text("桌面就会铺成一面布布的照片墙")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 照片墙底：玻璃底衬托照片。粉调再压淡一档——墙上照片本身就够花，
/// 底色抢戏会让整墙显脏。
private extension View {
    func bubuWallBackground(_ mode: WidgetRenderingMode) -> some View {
        bubuGlassBackground(mode, tintStrength: 0.7)
    }
}

// MARK: - 布布全景卡（一屏看全）
/// 把过去要在好几个小组件之间来回看的信息收进一张大卡：
/// 身份（头像/名字/年龄/陪伴天数/编号）+ 身高体重 + 里程碑进度 +
/// 本月照片与记录总数 + 生日倒计时 + 最近记录一句话。
///
/// 定位与其它款的区别：时光墙是「看照片」，这张是「看数据」——
/// 想一眼知道布布现在什么状况时看它，不用点进 App。
struct BubuPanoramaView: View {
    var entry: BubuEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var s: BubuSnapshot { entry.snapshot }

    var body: some View {
        VStack(spacing: 10) {
            identityRow
            Divider().overlay(WidgetPalette.primary.opacity(0.18))
            statsGrid
            milestoneBar
            recentRow
            Spacer(minLength: 0)
        }
        .padding(15)
        .bubuGlassBackground(renderingMode)
        .widgetURL(URL(string: "bubu://identity"))
    }

    // MARK: 身份行

    private var identityRow: some View {
        HStack(spacing: 12) {
            BubuAvatar(imageData: s.avatarImageData, size: 62, cute: true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.name)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.warmBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if s.daysUntilBirthday == 0 {
                        Text("🎂 生日快乐")
                            .font(.system(size: 9.5, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(WidgetPalette.roseDeep, in: Capsule())
                    }
                }
                Text(s.ageText)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetPalette.primary)
                    .lineLimit(1)
                Text("🎀 No.\(s.idNumber)")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            BubuPlusLink(size: 26)
        }
    }

    // MARK: 数据格（2×3）

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            statTile("陪伴", s.hasProfile ? "\(s.daysSinceBirth)" : "--", unit: "天",
                     icon: "heart.fill", tint: WidgetPalette.primary)
            statTile("身高", heightValue, unit: "cm", icon: "ruler.fill", tint: WidgetPalette.mint)
            statTile("体重", weightValue, unit: "kg", icon: "scalemass.fill", tint: WidgetPalette.lav)
            statTile("生日", s.hasProfile ? "\(s.daysUntilBirthday)" : "--", unit: "天后",
                     icon: "birthday.cake.fill", tint: WidgetPalette.roseDeep)
            statTile("本月照片", "\(s.monthlyPhotoCount)", unit: "张",
                     icon: "photo.stack.fill", tint: WidgetPalette.honey)
            statTile("记录", "\(s.totalEntryCount)", unit: "条",
                     icon: "book.pages.fill", tint: WidgetPalette.peach)
        }
    }

    /// 身高/体重快照里存的是「82 cm」这种带单位串，这里拆出数值单独排版。
    private var heightValue: String { Self.numberPart(s.latestHeightText) }
    private var weightValue: String { Self.numberPart(s.latestWeightText) }

    private static func numberPart(_ text: String) -> String {
        text.split(separator: " ").first.map(String.init) ?? "--"
    }

    private func statTile(_ title: String, _ value: String, unit: String,
                          icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 8.5, weight: .black))
                Text(title).font(.system(size: 8.5, weight: .black, design: .rounded))
            }
            .foregroundColor(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.warmBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(WidgetPalette.chip.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 里程碑进度条

    private var milestoneBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(WidgetPalette.honey)
                Text("点亮的第一次")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.warmBrown)
                Spacer(minLength: 0)
                Text(s.milestoneProgressText)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.chip.opacity(0.48))
                    Capsule()
                        .fill(LinearGradient(colors: [WidgetPalette.honey, WidgetPalette.primary],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * s.milestoneProgress))
                }
            }
            .frame(height: 7)
            if let latest = s.latestMilestoneTitle {
                Text("最近点亮：\(latest)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(WidgetPalette.chip.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 最近一条

    private var recentRow: some View {
        HStack(spacing: 8) {
            if let mood = s.recentMoodEmoji {
                Text(mood).font(.system(size: 15))
            } else {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(WidgetPalette.primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(s.recentEntryTitle)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetPalette.warmBrown)
                    .lineLimit(1)
                Text(s.recentEntryNote)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let date = s.recentEntryDate {
                Text(date.formatted(.dateTime.month().day()))
                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(WidgetPalette.chip.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Widget 定义
struct BubuWidget: Widget {
    let kind = "BubuWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuWidgetEntryView(entry: entry, style: .identity)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        }
        .configurationDisplayName("布布身份卡")
        .description("头像、年龄、陪伴天数和生日倒计时。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct BubuMomentWidget: Widget {
    let kind = "BubuMomentWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuMomentProvider()) { entry in
            BubuMomentWallView(entry: entry)
        }
        .configurationDisplayName("布布时光墙")
        .description("一屏铺满布布的瞬间，每半小时整墙换一批——最近的、那年今日的、还有你可能已经忘了的。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct BubuPanoramaWidget: Widget {
    let kind = "BubuPanoramaWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuPanoramaView(entry: entry)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        }
        .configurationDisplayName("布布全景卡")
        .description("一屏看全：身份、年龄、身高体重、里程碑进度、本月照片和最近记录。")
        .supportedFamilies([.systemLarge])
        .containerBackgroundRemovable(false)
    }
}

struct BubuGrowthWidget: Widget {
    let kind = "BubuGrowthWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuWidgetEntryView(entry: entry, style: .growth)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        }
        .configurationDisplayName("布布成长一览")
        .description("身高体重、里程碑和下一个成长目标。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

// MARK: - 锁屏 / StandBy accessory 系列（家长最高频看一眼的位置）
private struct BubuAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: BubuSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            // 生日倒计时环：外圈进度 + 中间天数。
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: birthdayProgress) {
                    Image(systemName: "birthday.cake.fill")
                } currentValueLabel: {
                    Text(snapshot.hasProfile ? "\(snapshot.daysUntilBirthday)" : "--")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
            }
            .widgetURL(BubuWidgetStyle.identity.deepLink)

        case .accessoryRectangular:
            // 锁屏上任何人拿起手机都能看到：真名 + 精确年龄 + 生日倒计时 = 出生日期。
            // 标为隐私敏感，锁定时系统自动打码，解锁后照常显示。
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .widgetAccentable()
                    .privacySensitive()
                Text(snapshot.hasProfile ? "\(snapshot.ageText) · 第 \(snapshot.daysSinceBirth) 天" : "打开 App 建立档案")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .privacySensitive()
                if snapshot.hasProfile {
                    Text("🎂 还有 \(snapshot.daysUntilBirthday) 天生日")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(BubuWidgetStyle.identity.deepLink)

        case .accessoryInline:
            // 锁屏顶部一行。
            Group {
                if snapshot.hasProfile {
                    Label("\(snapshot.name) \(snapshot.ageText) · 生日 \(snapshot.daysUntilBirthday) 天", systemImage: "sparkles")
                        .privacySensitive()
                } else {
                    Label("打开布布时光机建立档案", systemImage: "sparkles")
                }
            }
            .widgetURL(BubuWidgetStyle.identity.deepLink)

        default:
            Text(snapshot.name)
        }
    }

    /// 生日倒计时进度（越接近生日环越满）。
    private var birthdayProgress: Double {
        guard snapshot.hasProfile else { return 0 }
        let days = Double(snapshot.daysUntilBirthday)
        return max(0, min(1, (365 - days) / 365))
    }
}

struct BubuAccessoryWidget: Widget {
    let kind = "BubuAccessoryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuAccessoryView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        }
        .configurationDisplayName("布布锁屏")
        .description("锁屏上的年龄、陪伴天数和生日倒计时。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - 记忆轮播小组件（R4 F-1：桌面变成会自动翻页的成长相框）

/// 多 entry 时间线：未来 6 小时每 30 分钟一个 entry 轮换一张照片。
/// 翻页由时间线驱动，不消耗 WidgetKit 刷新预算（一次生成、系统按时切换）。
struct BubuMemoryProvider: TimelineProvider {
    /// 6 小时 × 每 30 分钟。
    private static let slots = 12

    func placeholder(in context: Context) -> BubuEntry {
        BubuEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BubuEntry) -> Void) {
        completion(BubuEntry(date: .now, snapshot: BubuWidgetData.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuEntry>) -> Void) {
        var snapshot = BubuWidgetData.loadSnapshot()
        // 关键：把图片数组从 snapshot 里剥掉，避免 12 个 entry 各自完整拷贝 3 张图 → 撞 WidgetKit 内存红线。
        // 每个 entry 只在 carouselPhoto 里带「本槽位那一张」。
        let fallbackPhotos = snapshot.photoImageData
        snapshot.photoImageData = []
        var entries: [BubuEntry] = []
        let now = Date.now
        // 今日精选优先：每 30 分钟换一张精选，点开就是那一张的在线详情。
        let picks = DailyPicksReader.load()
        if !picks.isEmpty {
            for slot in 0..<Self.slots {
                let item = picks[slot % picks.count]
                entries.append(BubuEntry(date: now.addingTimeInterval(TimeInterval(slot) * 30 * 60),
                                         snapshot: snapshot, carouselPhoto: item.data, isDailyPicks: true,
                                         pickURL: item.pick.url, pickReason: item.pick.reason,
                                         pickDateText: item.pick.dateText))
            }
            completion(cappedTimeline(entries, cutoff: DailyPicksReader.nextMidnight()))
            return
        }
        // 本机照片：按时光墙同一个池子（snapshot.moments）逐槽读图，6 小时内尽量不重复；
        // 点开跳到这张照片那一天的时光。池子为空的老快照才回落到最近 3 张。
        let ordered = dailyShuffled(snapshot.moments, seed: Int(now.timeIntervalSince1970 / 86_400))
        if !ordered.isEmpty {
            for slot in 0..<Self.slots {
                let moment = ordered[slot % ordered.count]
                guard let photo = BubuWidgetData.momentImageData(fileName: moment.photoFileName) else { continue }
                entries.append(BubuEntry(date: now.addingTimeInterval(TimeInterval(slot) * 30 * 60),
                                         snapshot: snapshot, moment: moment, carouselPhoto: photo,
                                         pickURL: BubuIntentLinks.timeline(on: moment.date)))
            }
        }
        if entries.isEmpty {
            for slot in 0..<Self.slots {
                let photo = fallbackPhotos.isEmpty ? nil : fallbackPhotos[slot % fallbackPhotos.count]
                entries.append(BubuEntry(date: now.addingTimeInterval(TimeInterval(slot) * 30 * 60),
                                         snapshot: snapshot, carouselPhoto: photo))
            }
        }
        // 槽位按「第几个」排时间：读图失败跳过的槽位不留空档。
        entries = entries.enumerated().map { index, entry in
            BubuEntry(date: now.addingTimeInterval(TimeInterval(index) * 30 * 60), snapshot: entry.snapshot,
                      moment: entry.moment, carouselPhoto: entry.carouselPhoto, pickURL: entry.pickURL)
        }
        completion(cappedTimeline(entries, cutoff: nextLocalMidnight()))
    }
}

struct BubuMemoryWidgetView: View {
    var entry: BubuEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var photoData: Data? {
        // 轮播款：本槽位那一张（entry.carouselPhoto）。兜底仍读 snapshot.photoImageData（其它入口/预览）。
        if let carousel = entry.carouselPhoto { return carousel }
        let photos = entry.snapshot.photoImageData
        guard !photos.isEmpty else { return nil }
        return photos[entry.photoIndex % photos.count]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = photoData, let image = BubuAvatar.downsampledImage(from: data, maxPixel: 800) {
                Color.clear
                VStack(alignment: .leading, spacing: 2) {
                    if entry.isDailyPicks {
                        HStack(spacing: 4) {
                            if let reason = entry.pickReason, !reason.isEmpty {
                                Text(reason)
                                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(WidgetPalette.roseDeep.opacity(0.92), in: Capsule())
                            }
                            if let day = entry.pickDateText {
                                Text(day).font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.9)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    Text(entry.snapshot.name)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                    Text(entry.snapshot.ageText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .containerBackground(for: .widget) {
                    Image(uiImage: image)
                        .resizable()
                        // 相框的意义就是真照片：染色模式下保持全彩（须紧跟 Image 调用）。
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                        .overlay {
                            LinearGradient(colors: [.clear, .black.opacity(0.45)],
                                           startPoint: .center, endPoint: .bottom)
                        }
                }
            } else {
                VStack(spacing: 6) {
                    Text("🖼️").font(.system(size: 30))
                    Text("多记几张照片\n这里就是\(entry.snapshot.name)的相框")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(for: .widget) {
                    // 染色/vibrant 模式下奶油实底会糊成一坨，与其它卡一致降级成中性淡底。
                    if renderingMode == .fullColor { WidgetPalette.paper } else { Color.white.opacity(0.06) }
                }
            }
        }
    }
}

struct BubuMemoryWidget: Widget {
    let kind = "BubuMemoryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuMemoryProvider()) { entry in
            BubuMemoryWidgetView(entry: entry).widgetURL(entry.pickURL ?? URL(string: "bubu://moment"))
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        }
        .configurationDisplayName("成长相框")
        .description("时光里的照片每半小时自动换一张，点一下回到那一天。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        // 照片就是背景：StandBy/锁屏等场景系统若移除容器背景，只剩白字不可读。
        .containerBackgroundRemovable(false)
    }
}

// MARK: - Bundle
@main
struct BubuWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BubuWidget()
        BubuMomentWidget()
        BubuPanoramaWidget()
        BubuGrowthWidget()
        BubuMemoryWidget()
        BubuAccessoryWidget()
        BubuLiveActivity()
        BubuRecordControl()
    }
}
