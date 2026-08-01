import SwiftUI
import UIKit

// MARK: - 分享卡引擎
/// 把一条记录渲染成「好看到愿意转发」的图片，走系统分享面板出去。
///
/// **为什么不接微信/抖音/小红书的 SDK**：那些 SDK 都要开放平台审核绑定，
/// 还要往这个"数据不出家门"的 App 里塞第三方闭源代码，与产品人格冲突。
/// 而 iOS 系统分享面板里，这三家本来就注册了图片接收入口——
/// 所以真正该做的不是"接平台"，是把**可分享物**做到高级。一次渲染，三个平台全通。
///
/// **隐私红线**：卡面只出现照片、日期、年龄（可关）、一句话和布布的名字；
/// 绝不出现出生日期全称、证件号、地理位置。
enum ShareCard {

    /// 版式。尺寸按各平台的主流构图定：小红书竖版 3:4，微信朋友圈方图 1:1。
    enum Layout: String, CaseIterable, Identifiable {
        case portrait   // 3:4 竖版（小红书 / 朋友圈单图）
        case square     // 1:1 方版（朋友圈九宫格 / 头像位）
        case thenNow    // 那年今日对比（上下双图）

        var id: String { rawValue }

        var title: String {
            switch self {
            case .portrait: return "竖版"
            case .square: return "方版"
            case .thenNow: return "那年今日"
            }
        }

        var pixelSize: CGSize {
            switch self {
            case .portrait: return CGSize(width: 1080, height: 1440)
            case .square: return CGSize(width: 1080, height: 1080)
            case .thenNow: return CGSize(width: 1080, height: 1620)
            }
        }
    }

    /// 渲染所需的全部内容。视图层只认这个结构，与 SwiftData 解耦，方便预览与测试。
    struct Content: Sendable {
        var childName: String
        var dateText: String
        /// 「2岁2个月」。为空即不显示年龄。
        var ageText: String?
        var note: String?
        var photo: UIImage?
        /// 那年今日版式的另一张（更早的那张）与它的年龄。
        var thenPhoto: UIImage?
        var thenDateText: String?
        var thenAgeText: String?
        /// 对比版的年代标签（「今年」或「2024年」）。硬编码「今年」会在分享旧记录时说谎。
        var eraText: String = "今年"
        var thenEraText: String = "那年"
    }

    /// 渲染成 PNG。@MainActor：ImageRenderer 要在主线程跑。
    @MainActor
    static func render(_ content: Content, layout: Layout) -> UIImage? {
        let size = layout.pixelSize
        // 设计稿按 360pt 宽画，再用 scale 放到 1080px——
        // 这样卡面里的字号/间距可以用正常的 pt 数写，不用满屏乘 3。
        let designWidth: CGFloat = 360
        let scale = size.width / designWidth
        let view = ShareCardView(content: content, layout: layout)
            .frame(width: designWidth, height: size.height / scale)
            // 分享卡是固定纸面：奶油底配深棕墨，与设备深浅色无关（同 paperInk 的先例）。
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else { return nil }
        // 归一化成 1 倍图：ImageRenderer 出的 UIImage 其 `size` 是**点**（scale=3 时
        // 1080px 会报成 360），下游拿去判尺寸必然算错。这里按 cgImage 的真实像素重建，
        // 让 `size` 就等于像素数，契约无歧义。
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// 渲染并写成临时 PNG 文件——分享面板给文件比给 UIImage 更稳
    /// （部分 App 只认文件 URL，且文件带得走文件名）。
    @MainActor
    static func renderToFile(_ content: Content, layout: Layout) -> URL? {
        guard let image = render(content, layout: layout),
              let data = image.pngData() else { return nil }
        let stamp = content.dateText
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(content.childName)_\(stamp).png")
        try? data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - 卡面
private struct ShareCardView: View {
    let content: ShareCard.Content
    let layout: ShareCard.Layout

    var body: some View {
        ZStack {
            BubuTheme.Color.cream
            switch layout {
            case .portrait, .square: single
            case .thenNow: thenNow
            }
        }
    }

    // MARK: 单图版

    @ViewBuilder
    private var single: some View {
        if content.photo == nil {
            textHero
        } else {
            VStack(spacing: 0) {
                photoBlock(content.photo, height: layout == .square ? 240 : 350)
                captionBlock
            }
        }
    }

    /// 无照片的记录：与其发一张"渐变+🧸"的空卡，不如把那句话本身当主角。
    /// 大字居中排版——文字记录的分享卡应当像一张手写便签，而不是缺图的照片卡。
    private var textHero: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(content.dateText)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.primary)
                if let age = content.ageText, !age.isEmpty {
                    Text(age)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(BubuTheme.Color.softFill, in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Text(content.note?.isEmpty == false ? "「\(content.note!)」" : "这一天，也值得记住")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .lineLimit(7)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 26)
            Spacer(minLength: 0)
            signature
        }
        .padding(20)
        .background(
            LinearGradient(colors: [BubuTheme.Color.cream,
                                    BubuTheme.Color.peach.opacity(0.35),
                                    BubuTheme.Color.pink.opacity(0.25)],
                           startPoint: .top, endPoint: .bottomTrailing)
        )
    }

    private func photoBlock(_ image: UIImage?, height: CGFloat) -> some View {
        ZStack {
            if let image {
                // Color.clear + overlay：直接 scaledToFill 会把容器撑大，
                // 这是本项目踩过的老坑（竖长图溢出卡片边界）。
                Color.clear
                    .overlay {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                    .clipped()
            } else {
                LinearGradient(colors: [BubuTheme.Color.peach, BubuTheme.Color.pink],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text("🧸").font(.system(size: 64))
            }
        }
        .frame(height: height)
        .clipped()
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(content.dateText)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.primary)
                if let age = content.ageText, !age.isEmpty {
                    Text(age)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(BubuTheme.Color.softFill, in: Capsule())
                }
            }
            if let note = content.note, !note.isEmpty {
                // 行数按版式收口 + 允许缩字：fixedSize 会拒绝压缩，长文把落款挤出画布。
                Text(note)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(layout == .square ? 2 : 3)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            signature
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: 那年今日版（最容易被转发的一张）

    private var thenNow: some View {
        VStack(spacing: 0) {
            comparisonHalf(image: content.thenPhoto, era: content.thenEraText,
                           label: content.thenDateText ?? "那一年",
                           age: content.thenAgeText, tint: BubuTheme.Color.lav)
            Rectangle().fill(BubuTheme.Color.cream).frame(height: 6)
            comparisonHalf(image: content.photo, era: content.eraText,
                           label: content.dateText, age: content.ageText,
                           tint: BubuTheme.Color.primary)
            VStack(alignment: .leading, spacing: 8) {
                if let note = content.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                signature
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
    }

    /// 对比版的一半。
    /// - `era`（那年/今年）是这张卡成立的关键：只给日期的话，观者要自己算哪张更早，
    ///   而这张卡的全部意义就是"一眼看出长大了多少"。
    /// - 胶囊下垫一层自下而上的暗渐变：胶囊本身有色底，但遇到浅色照片时边界会糊，
    ///   垫一层就在任何照片上都读得出。
    private func comparisonHalf(image: UIImage?, era: String, label: String,
                                age: String?, tint: Color) -> some View {
        photoBlock(image, height: 230)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.35)],
                               startPoint: .center, endPoint: .bottom)
                    .frame(height: 90)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    Text(era)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                    Text(label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .opacity(0.9)
                    if let age, !age.isEmpty {
                        Text(age)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(tint, in: Capsule())
                .padding(12)
            }
    }

    // MARK: 落款

    /// 克制的落款：一行小字，不做二维码不做广告——这是给家人看的，不是投放物料。
    private var signature: some View {
        HStack(spacing: 5) {
            Text("🕰️").font(.system(size: 11))
            Text("\(content.childName)的时光机")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
    }
}
