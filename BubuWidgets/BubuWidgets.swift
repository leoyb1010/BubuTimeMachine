import WidgetKit
import SwiftUI
import AppIntents
import UIKit
import ImageIO

// MARK: - 时间线
struct BubuEntry: TimelineEntry {
    let date: Date
    let snapshot: BubuSnapshot
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
private extension View {
    func bubuWidgetBackground() -> some View {
        self.containerBackground(for: .widget) {
            // 奶油马卡龙：peach → pink → lav 柔粉渐变（与 App 身份卡同源）
            LinearGradient(
                colors: [WidgetPalette.peach.opacity(0.55),
                         WidgetPalette.pink.opacity(0.45),
                         WidgetPalette.lav.opacity(0.45),
                         WidgetPalette.cream],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
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

private struct BubuBirthdayBadge: View {
    let snapshot: BubuSnapshot
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            Text(snapshot.hasProfile ? "\(snapshot.daysUntilBirthday)" : "--")
                .font(.system(size: compact ? 20 : 28, weight: .black, design: .rounded))
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

private struct BubuRecentPhotoCard: View {
    let snapshot: BubuSnapshot

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let image = BubuAvatar.downsampledImage(from: snapshot.recentPhotoImageData, maxPixel: 180) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [WidgetPalette.mint.opacity(0.30), WidgetPalette.primary.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(WidgetPalette.mint)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.recentPhotoFileName == nil ? "最近照片" : "最近照片已同步")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(WidgetPalette.warmBrown)
                    .lineLimit(1)
                Text(snapshot.recentPhotoFileName == nil ? "记录一张照片后会出现在这里" : "桌面也能陪你回看成长瞬间")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Small：头像 + 名字 + 年龄
struct BubuSmallView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BubuAvatar(imageData: snapshot.avatarImageData, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.name)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.warmBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text("BUBU TIME")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.primary.opacity(0.72))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(snapshot.ageText)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(WidgetPalette.warmBrown)
                .minimumScaleFactor(0.58)
                .lineLimit(2)
            if snapshot.hasProfile {
                HStack(spacing: 5) {
                    Text("第 \(snapshot.daysSinceBirth) 天")
                    Text("生日 \(snapshot.daysUntilBirthday) 天")
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(WidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            } else {
                Text("打开 App 刷新")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium：头像 + 身份 + 生日倒计时
struct BubuMediumView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                BubuAvatar(imageData: snapshot.avatarImageData, size: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.name)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.warmBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(snapshot.ageText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetPalette.roseDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text(snapshot.hasProfile ? "来到世界第 \(snapshot.daysSinceBirth) 天" : "打开 App 后自动同步到桌面")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetPalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                Spacer(minLength: 0)
                BubuBirthdayBadge(snapshot: snapshot, compact: true)
            }

            HStack(spacing: 8) {
                BubuInfoChip(title: "成长天数", value: snapshot.hasProfile ? "\(snapshot.daysSinceBirth) 天" : "待记录", tint: WidgetPalette.mint)
                BubuInfoChip(title: "照片状态", value: snapshot.recentPhotoFileName == nil ? "未同步" : "已同步", tint: WidgetPalette.honey)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Large：大头像身份卡（最接近 App 内身份卡的高级感）
struct BubuLargeView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("BUBU IDENTITY")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(WidgetPalette.primary.opacity(0.7))
                Spacer()
                if snapshot.hasProfile {
                    Text("ACTIVE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(WidgetPalette.primary, in: Capsule())
                }
            }

            HStack(spacing: 14) {
                BubuAvatar(imageData: snapshot.avatarImageData, size: 82)
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.name)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.warmBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text(snapshot.ageText)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(WidgetPalette.roseDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text(birthDateText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetPalette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                BubuBirthdayBadge(snapshot: snapshot)
            }

            if snapshot.hasProfile {
                HStack(spacing: 8) {
                    BubuInfoChip(title: "成长天数", value: "\(snapshot.daysSinceBirth) 天", tint: WidgetPalette.mint)
                    BubuInfoChip(title: "生日倒计时", value: "\(snapshot.daysUntilBirthday) 天", tint: WidgetPalette.primary)
                    BubuInfoChip(title: "桌面内容", value: snapshot.recentPhotoFileName == nil ? "档案" : "档案+照片", tint: WidgetPalette.honey)
                }
            } else {
                Text("打开 App 后自动同步")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetPalette.secondary)
            }
            BubuRecentPhotoCard(snapshot: snapshot)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var birthDateText: String {
        guard let birthday = snapshot.birthday else { return "生日待补全" }
        return "生日 " + birthday.formatted(.dateTime.year().month().day())
    }
}

// MARK: - 锁屏 Circular：生日倒计时环
struct BubuCircularView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        Gauge(value: gaugeValue) {
            Image(systemName: "birthday.cake.fill")
        } currentValueLabel: {
            Text("\(snapshot.daysUntilBirthday)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }
    /// 距生日剩余比例（一年内）。
    private var gaugeValue: Double {
        guard snapshot.hasProfile else { return 0 }
        return Double(365 - min(snapshot.daysUntilBirthday, 365)) / 365.0
    }
}

// MARK: - 锁屏 Rectangular：年龄行
struct BubuRectangularView: View {
    let snapshot: BubuSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.name).font(.headline)
            Text(snapshot.ageText).font(.body)
            if snapshot.hasProfile {
                Text("距生日还有 \(snapshot.daysUntilBirthday) 天")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 容器：按 family 分发 + 背景
struct BubuWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BubuEntry

    var body: some View {
        switch family {
        case .systemSmall:
            BubuSmallView(snapshot: entry.snapshot).padding(14).bubuWidgetBackground()
        case .systemMedium:
            BubuMediumView(snapshot: entry.snapshot).padding(16).bubuWidgetBackground()
        case .systemLarge:
            BubuLargeView(snapshot: entry.snapshot).padding(18).bubuWidgetBackground()
        case .accessoryCircular:
            BubuCircularView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            BubuRectangularView(snapshot: entry.snapshot)
        default:
            BubuSmallView(snapshot: entry.snapshot).padding(14).bubuWidgetBackground()
        }
    }
}

// MARK: - Widget 定义
struct BubuWidget: Widget {
    let kind = "BubuWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BubuProvider()) { entry in
            BubuWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("布布时光机")
        .description("随时看到布布长大：年龄、来到世界第几天、生日倒计时。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

// MARK: - Bundle
@main
struct BubuWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BubuWidget()
        BubuLiveActivity()
        BubuRecordControl()
    }
}
