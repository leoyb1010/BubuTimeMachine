import SwiftUI
import UIKit

// MARK: - PDF 年册导出（Wave L §5.6）
/// 选一个年龄段，把布布这一年生成 A4 竖版 PDF：封面 + 月份章节 + 照片网格 + 摘录记录 + 里程碑 + 家人寄语。
/// 用 `ImageRenderer` 逐页渲染 SwiftUI 视图进 `UIGraphicsPDFRenderer`，零第三方依赖。
@MainActor
struct YearbookExporter {
    let mediaStore: MediaStore
    let theme: BubuThemeDefinition

    // A4 @ 72dpi
    static let pageSize = CGSize(width: 595, height: 842)

    struct Page: Sendable {
        let date: Date
        let note: String?
        let ageText: String
        let authorRole: String
        let imageFileNames: [String]
        let mood: String?
    }

    struct Input: Sendable {
        let childName: String
        let rangeTitle: String         // 「1 岁这一年」
        let coverImageFileName: String?
        let entries: [Page]
        let milestones: [String]       // 已点亮里程碑标题
        let messages: [String]         // 家人寄语（语音评论转写 / 文字评论）
    }

    /// 生成 PDF 到临时文件，返回 URL。
    /// 两阶段：先逐页渲成 UIImage（照片解码在后台线程、页间 yield 让出主线程），
    /// 最后一次性写 PDF（画现成位图，毫秒级）——整机卡死数秒的问题不再有（R4 P2-32）。
    func makePDF(_ input: Input, onProgress: ((Int, Int) -> Void)? = nil) async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("布布年册-\(input.rangeTitle).pdf")
        try? FileManager.default.removeItem(at: url)

        // 阶段一：渲染每一页（ImageRenderer 需主线程，但照片解码放后台 + 页间让出）
        var pages: [UIImage] = []
        let totalPages = 1 + input.entries.count
            + (input.milestones.isEmpty ? 0 : 1) + (input.messages.isEmpty ? 0 : 1)

        let cover = await loadImageAsync(input.coverImageFileName)
        if let img = renderPage({ CoverPage(input: input, theme: theme, cover: cover) }) { pages.append(img) }
        onProgress?(pages.count, totalPages)
        await Task.yield()

        for entry in input.entries {
            var images: [UIImage] = []
            for name in entry.imageFileNames.prefix(4) {
                if let img = await loadImageAsync(name) { images.append(img) }
            }
            if let img = renderPage({ EntryPage(entry: entry, theme: theme, images: images) }) { pages.append(img) }
            onProgress?(pages.count, totalPages)
            await Task.yield()
        }
        if !input.milestones.isEmpty,
           let img = renderPage({ ListPage(title: "这一年的里程碑", icon: "star.fill", items: input.milestones, theme: theme) }) {
            pages.append(img)
            await Task.yield()
        }
        if !input.messages.isEmpty,
           let img = renderPage({ ListPage(title: "家人想对你说", icon: "heart.fill", items: input.messages, theme: theme) }) {
            pages.append(img)
        }

        // 阶段二：写 PDF（画现成位图，快）
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
        do {
            try renderer.writePDF(to: url) { ctx in
                for page in pages {
                    ctx.beginPage()
                    page.draw(in: CGRect(origin: .zero, size: Self.pageSize))
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private func renderPage<V: View>(@ViewBuilder _ content: () -> V) -> UIImage? {
        let renderer = ImageRenderer(content: content().frame(width: Self.pageSize.width, height: Self.pageSize.height))
        renderer.scale = 2.0
        return renderer.uiImage
    }

    /// 照片解码在后台线程做（这是每页最贵的一步）。
    private func loadImageAsync(_ fileName: String?) async -> UIImage? {
        guard let fileName else { return nil }
        let url = mediaStore.mediaURL(for: fileName)
        return await Task.detached(priority: .userInitiated) {
            ThumbnailProvider.downsample(url: url, maxPixel: 1200)
        }.value
    }
}

// MARK: - PDF 页面视图

private struct CoverPage: View {
    let input: YearbookExporter.Input
    let theme: BubuThemeDefinition
    let cover: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.meshColors.isEmpty ? [theme.primary, theme.secondary] : theme.meshColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 24) {
                Spacer()
                if let cover {
                    Image(uiImage: cover)
                        .resizable().scaledToFill()
                        .frame(width: 260, height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white, lineWidth: 5))
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                }
                VStack(spacing: 10) {
                    Text(input.childName)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(input.rangeTitle)
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(.white.opacity(0.95))
                }
                Spacer()
                Text("布布时光机 · 年册")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 40)
            }
            .padding(40)
        }
    }
}

private struct EntryPage: View {
    let entry: YearbookExporter.Page
    let theme: BubuThemeDefinition
    let images: [UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(entry.ageText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primary)
                Spacer()
                Text(BubuDateFormat.longDate(entry.date))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if !images.isEmpty {
                let cols = images.count == 1 ? 1 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(height: images.count == 1 ? 360 : 220)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 19, design: .serif))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineSpacing(7)
            }
            HStack(spacing: 6) {
                if let mood = entry.mood { Text(mood) }
                Text("—— \(entry.authorRole)")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(46)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: "#FFFDF8"))
    }
}

private struct ListPage: View {
    let title: String
    let icon: String
    let items: [String]
    let theme: BubuThemeDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(theme.primary)
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
            }
            ForEach(Array(items.prefix(14).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(theme.primary).frame(width: 7, height: 7).padding(.top, 9)
                    Text(item)
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                }
            }
            Spacer()
        }
        .padding(46)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: "#FFFDF8"))
    }
}
