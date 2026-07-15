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
    /// 记忆轮播款专用：本槽位要展示的「那一张」照片数据。
    /// 轮播时间线有 12 个 entry，若每个 entry 都带上完整 snapshot（含最多 3×2MB 图），
    /// 会逼近 WidgetKit ~30MB 内存红线导致空白。故轮播 entry 只携带该槽位需要的一张图，
    /// 其 snapshot 的 photoImageData 被清空（其余轻量字段照常）。其它款不设此字段，走 snapshot.photoImageData。
    var carouselPhoto: Data? = nil
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
    static let warmBrown = Color(red: 0.353, green: 0.239, blue: 0.204) // ink #5A3D34
    static let cream = Color(red: 1.000, green: 0.969, blue: 0.945)    // #FFF7F1
    static let secondary = Color(red: 0.663, green: 0.553, blue: 0.510) // ink2
}

// MARK: - 布布圆形头像（无头像时回退到吉祥物表情）
struct BubuAvatar: View {
    let imageData: Data?
    var size: CGFloat
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
        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
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

// MARK: - 暖色卡片渐变背景（统一各 family）
private struct BubuWidgetBackground: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            switch renderingMode {
            case .fullColor:
                // 桌面全彩：奶油马卡龙 peach → pink → lav 柔粉渐变（与 App 身份卡同源）
                LinearGradient(
                    colors: [WidgetPalette.peach.opacity(0.55),
                             WidgetPalette.pink.opacity(0.45),
                             WidgetPalette.lav.opacity(0.45),
                             WidgetPalette.cream],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            default:
                // 染色(tinted)/vibrant：系统会把内容单色化，渐变会糊成一坨——改用极淡的中性底，
                // 让系统的染色算法只作用在前景文字/图标上，保持清爽可读。
                Color.white.opacity(0.06)
            }
        }
    }
}

private extension View {
    func bubuWidgetBackground() -> some View {
        modifier(BubuWidgetBackground())
    }
}

private enum BubuWidgetStyle {
    case identity
    case moment
    case growth

    /// 点击小组件跳转到 App 对应页面的 deep link（App 端 BubuRoute 解析）。
    var deepLink: URL {
        switch self {
        case .identity: return URL(string: "bubu://identity")!
        case .moment: return URL(string: "bubu://moment")!
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
        .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    Capsule().fill(.white.opacity(0.66))
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
            .background(.white.opacity(0.62), in: Circle())
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
            BubuAvatar(imageData: snapshot.avatarImageData, size: compact ? 38 : 50)
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
                BubuAvatar(imageData: snapshot.avatarImageData, size: 70)
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
                        Text("BUBU IDENTITY")
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
                    Text("No.\(snapshot.idNumber)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    BubuPlusLink(size: 24)
                }
            }
        }
    }
}

private struct BubuIdentityLargeView: View {
    let snapshot: BubuSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BUBU IDENTITY")
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
                Text("ACTIVE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(WidgetPalette.primary, in: Capsule())
            }

            HStack(alignment: .top, spacing: 12) {
                BubuAvatar(imageData: snapshot.avatarImageData, size: 90)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        BubuInfoChip(title: "AGE", value: snapshot.ageText, tint: WidgetPalette.roseDeep)
                        BubuInfoChip(title: "DAY", value: snapshot.hasProfile ? "第 \(snapshot.daysSinceBirth) 天" : "待同步", tint: WidgetPalette.mint)
                    }
                    HStack(spacing: 8) {
                        BubuInfoChip(title: "BIRTH", value: birthDateText, tint: WidgetPalette.primary)
                        BubuInfoChip(title: "PHOTOS", value: "\(snapshot.totalPhotoCount) 张", tint: WidgetPalette.honey)
                    }
                    Text("No.\(snapshot.idNumber)")
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
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
            .background(.white.opacity(0.58), in: Capsule())
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
            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
        case .moment:
            BubuMomentSmallView(snapshot: snapshot)
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
        case .moment:
            BubuMomentMediumView(snapshot: snapshot)
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
        case .moment:
            BubuMomentLargeView(snapshot: snapshot)
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
            .overlay(alignment: .topTrailing) {
                if style == .moment, family == .systemMedium {
                    BubuPlusLink().padding(10)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        // 今日时光 S/M 走整图沉浸：照片自带 containerBackground、出血到边缘、不加内边距。
        if style == .moment, family == .systemSmall {
            BubuMomentSmallView(snapshot: entry.snapshot)
                .immersiveContainerBackground(imageData: entry.snapshot.recentPhotoImageData)
        } else if style == .moment, family == .systemMedium {
            BubuMomentMediumView(snapshot: entry.snapshot)
                .immersiveContainerBackground(imageData: entry.snapshot.recentPhotoImageData)
        } else {
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
                    LinearGradient(
                        colors: [WidgetPalette.cream.opacity(0.82), WidgetPalette.peach.opacity(0.7), WidgetPalette.pink.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
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

// MARK: - Widget 定义
struct BubuWidget: Widget {
    let kind = "BubuWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuWidgetEntryView(entry: entry, style: .identity)
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
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuWidgetEntryView(entry: entry, style: .moment)
        }
        .configurationDisplayName("布布今日时光")
        .description("最近照片、最近记录和本月照片。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct BubuGrowthWidget: Widget {
    let kind = "BubuGrowthWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuWidgetEntryView(entry: entry, style: .growth)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .widgetAccentable()
                Text(snapshot.hasProfile ? "\(snapshot.ageText) · 第 \(snapshot.daysSinceBirth) 天" : "打开 App 建立档案")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if snapshot.hasProfile {
                    Text("🎂 还有 \(snapshot.daysUntilBirthday) 天生日")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(BubuWidgetStyle.identity.deepLink)

        case .accessoryInline:
            // 锁屏顶部一行。
            Group {
                if snapshot.hasProfile {
                    Label("\(snapshot.name) \(snapshot.ageText) · 生日 \(snapshot.daysUntilBirthday) 天", systemImage: "sparkles")
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
    func placeholder(in context: Context) -> BubuEntry {
        BubuEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BubuEntry) -> Void) {
        completion(BubuEntry(date: .now, snapshot: BubuWidgetData.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BubuEntry>) -> Void) {
        var snapshot = BubuWidgetData.loadSnapshot()
        // 关键：把图片数组从 snapshot 里剥掉，避免 12 个 entry 各自完整拷贝 3 张图 → 撞 WidgetKit 内存红线。
        // 每个 entry 只在 carouselPhoto 里带「本槽位那一张」；同一张图在多个槽位间靠 Data 的写时复制共享底层缓冲。
        let photos = snapshot.photoImageData
        snapshot.photoImageData = []
        var entries: [BubuEntry] = []
        for slot in 0..<12 {   // 6 小时 × 每 30 分钟
            let date = Date.now.addingTimeInterval(TimeInterval(slot) * 30 * 60)
            let photo = photos.isEmpty ? nil : photos[slot % photos.count]
            entries.append(BubuEntry(date: date, snapshot: snapshot, photoIndex: 0, carouselPhoto: photo))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
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
                    if renderingMode == .fullColor { WidgetPalette.cream } else { Color.white.opacity(0.06) }
                }
            }
        }
    }
}

struct BubuMemoryWidget: Widget {
    let kind = "BubuMemoryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuMemoryProvider()) { entry in
            BubuMemoryWidgetView(entry: entry)
        }
        .configurationDisplayName("成长相框")
        .description("最近的照片每半小时自动换一张，桌面就是布布的相框。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        // 照片就是背景：StandBy/锁屏等场景系统若移除容器背景，只剩白字不可读。
        .containerBackgroundRemovable(false)
    }
}

// MARK: - 一键打卡小组件（交互按钮，不开 App 直接落库，R4 E-2）

// MARK: 打卡卡片底色（长按小组件 → 编辑 可选）
enum CheckInCardStyle: String, AppEnum {
    case cream
    case translucent

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "卡片底色")
    static let caseDisplayRepresentations: [CheckInCardStyle: DisplayRepresentation] = [
        .cream: "奶油底",
        .translucent: "清透底",
    ]
}

struct CheckInWidgetConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "打卡卡片样式"
    static let description = IntentDescription("选择卡片底色：经典奶油底，或更轻盈的清透底。")

    @Parameter(title: "卡片底色", default: .cream)
    var cardStyle: CheckInCardStyle
}

struct BubuCheckInEntry: TimelineEntry {
    let date: Date
    let snapshot: BubuSnapshot
    let style: CheckInCardStyle
}

struct BubuCheckInProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BubuCheckInEntry {
        BubuCheckInEntry(date: .now, snapshot: .sample, style: .cream)
    }

    func snapshot(for configuration: CheckInWidgetConfigIntent, in context: Context) async -> BubuCheckInEntry {
        BubuCheckInEntry(date: .now, snapshot: BubuWidgetData.loadSnapshot(), style: configuration.cardStyle)
    }

    func timeline(for configuration: CheckInWidgetConfigIntent, in context: Context) async -> Timeline<BubuCheckInEntry> {
        let entry = BubuCheckInEntry(date: .now, snapshot: BubuWidgetData.loadSnapshot(),
                                     style: configuration.cardStyle)
        // 与 BubuProvider 同节奏：日粒度内容，明天零点后刷新一次足矣。
        let nextMidnight = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(3600)
        return Timeline(entries: [entry], policy: .after(nextMidnight))
    }
}

private struct CheckInButton: View {
    let kind: HealthCheckInKind
    let tint: Color
    var compact = false

    var body: some View {
        Button(intent: HealthCheckInIntent(kind: kind)) {
            VStack(spacing: compact ? 2 : 4) {
                Text(kind.emoji).font(.system(size: compact ? 22 : 26))
                Text(kind.label)
                    .font(.system(size: compact ? 10 : 11.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetPalette.warmBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct BubuCheckInWidgetView: View {
    var entry: BubuCheckInEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private let kinds: [(HealthCheckInKind, Color)] = [
        (.milk, Color(red: 0.95, green: 0.47, blue: 0.62)),
        (.sleep, Color(red: 0.62, green: 0.55, blue: 0.90)),
        (.water, Color(red: 0.42, green: 0.68, blue: 0.93)),
        (.diaper, Color(red: 0.42, green: 0.78, blue: 0.65)),
    ]

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        CheckInButton(kind: kinds[0].0, tint: kinds[0].1, compact: true)
                        CheckInButton(kind: kinds[1].0, tint: kinds[1].1, compact: true)
                    }
                    HStack(spacing: 5) {
                        CheckInButton(kind: kinds[2].0, tint: kinds[2].1, compact: true)
                        CheckInButton(kind: kinds[3].0, tint: kinds[3].1, compact: true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("给\(entry.snapshot.name)打卡")
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(WidgetPalette.secondary)
                    HStack(spacing: 7) {
                        ForEach(kinds.indices, id: \.self) { i in
                            CheckInButton(kind: kinds[i].0, tint: kinds[i].1)
                        }
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            if renderingMode != .fullColor {
                // 染色/vibrant：与其它卡一致的中性淡底，让系统染色只作用于前景。
                Color.white.opacity(0.06)
            } else if entry.style == .translucent {
                // 清透底：系统自适应半透明材质（iOS 不允许主屏小组件真透出壁纸，这是官方允许的最轻底）。
                Rectangle().fill(.fill.tertiary)
            } else {
                WidgetPalette.cream
            }
        }
    }
}

struct BubuCheckInWidget: Widget {
    let kind = "BubuCheckInWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CheckInWidgetConfigIntent.self,
                               provider: BubuCheckInProvider()) { entry in
            BubuCheckInWidgetView(entry: entry)
        }
        .configurationDisplayName("一键打卡")
        .description("喂奶、睡觉、喝水、换尿布——点一下就记上，不用开 App。长按小组件可换卡片底色。")
        .supportedFamilies([.systemSmall, .systemMedium])
        // 打卡按钮文字是深棕实色，容器背景被系统移除（StandBy 等）后对比崩坏。
        .containerBackgroundRemovable(false)
    }
}

// MARK: - Bundle
@main
struct BubuWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BubuWidget()
        BubuMomentWidget()
        BubuGrowthWidget()
        BubuMemoryWidget()
        BubuCheckInWidget()
        BubuAccessoryWidget()
        BubuLiveActivity()
        BubuRecordControl()
    }
}
