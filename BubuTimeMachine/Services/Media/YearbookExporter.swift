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
    /// 逐页流式写入：每页「后台解码照片 → 主线程渲成位图 → 立即画进 PDF → 释放」，
    /// 全程只有当前一页位图在内存里，不再攒 `[UIImage]`（整年 300 条 ≈ 2.4GB 必闪退的老问题不再有）。
    /// ImageRenderer 必须在主线程，故本方法保持 @MainActor；照片解码走后台，页间 `Task.yield()` 让出主线程，
    /// 配合 onProgress 让 UI 有进度、不假死。
    func makePDF(_ input: Input, onProgress: ((Int, Int) -> Void)? = nil) async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("布布年册-\(input.rangeTitle).pdf")
        try? FileManager.default.removeItem(at: url)

        let totalPages = 1 + input.entries.count
            + (input.milestones.isEmpty ? 0 : 1) + (input.messages.isEmpty ? 0 : 1)

        // 增量 PDF：一页画完立即落盘，位图随即释放。
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        // 把一张现成位图作为一页写入 PDF（PDF 坐标系原点在左下，需翻转）。
        func addPage(_ image: UIImage) {
            guard let cg = image.cgImage else { return }
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: Self.pageSize.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(origin: .zero, size: Self.pageSize))
            ctx.restoreGState()
            ctx.endPDFPage()
        }

        var done = 0

        // 封面
        let cover = await loadImageAsync(input.coverImageFileName)
        if let img = renderPage({ CoverPage(input: input, theme: theme, cover: cover) }) { addPage(img) }
        done += 1
        onProgress?(done, totalPages)
        await Task.yield()

        // 每条记录一页
        for entry in input.entries {
            var images: [UIImage] = []
            for name in entry.imageFileNames.prefix(4) {
                if let img = await loadImageAsync(name) { images.append(img) }
            }
            if let img = renderPage({ EntryPage(entry: entry, theme: theme, images: images) }) { addPage(img) }
            images = []   // 本页源图与渲染位图到此都不再持有
            done += 1
            onProgress?(done, totalPages)
            await Task.yield()
        }

        // 里程碑
        if !input.milestones.isEmpty {
            if let img = renderPage({ ListPage(title: "这一年的里程碑", icon: "star.fill", items: input.milestones, theme: theme) }) {
                addPage(img)
            }
            done += 1
            onProgress?(done, totalPages)
            await Task.yield()
        }

        // 家人寄语
        if !input.messages.isEmpty {
            if let img = renderPage({ ListPage(title: "家人想对你说", icon: "heart.fill", items: input.messages, theme: theme) }) {
                addPage(img)
            }
            done += 1
            onProgress?(done, totalPages)
        }

        ctx.closePDF()
        return url
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
