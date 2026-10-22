import SwiftUI
import SwiftData
import PDFKit

// MARK: - PDF 年册导出页
/// 选一个年龄段（如「1 岁这一年」），生成 A4 竖版 PDF 年册并分享。
struct YearbookView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt) private var entries: [Entry]
    @Query(sort: \Milestone.happenedAt, order: .reverse) private var milestones: [Milestone]
    @Query private var profiles: [ChildProfile]

    @State private var selectedYear = 0
    @State private var generating = false
    @State private var pdfURL: URL?
    @State private var showShare = false
    @State private var errorText: String?
    @State private var progressText: String?
    /// 第二大脑每月成长小报（连了家庭服务器才有；离线时为空，年册只用本机数据）。
    @State private var monthlyReports: [YearbookMonthlyReport] = []

    private var profile: ChildProfile? { ChildProfile.canonical(from: profiles) }
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                hero
                yearPicker
                summary
                generateButton
                if let errorText {
                    Text(errorText).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger)
                    NavigationLink("前往同步与备份") { SyncCenterView() }
                }
            }
            .padding()
            .bubuContentColumn()   // 宽屏收进居中内容列，窄屏原样
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("PDF 年册")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let pdfURL { ShareSheet(items: [pdfURL]) }
        }
        .task(id: BubuLearningClient(env: env)?.scope) { await loadMonthlyReports() }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed.fill").font(BubuTheme.Font.scaled(52)).foregroundStyle(theme)
            Text("把布布的一年，做成一本书")
                .font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
            Text("封面 + 每条记录的照片与文字 + 里程碑 + 家人寄语，A4 竖版 PDF。打印出来，就是 30 年后还能摸到的实体礼物。")
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    /// 可选年龄段：从 0 岁到当前年龄。
    private var availableYears: [Int] {
        guard let profile else { return [0] }
        let age = AgeCalculator.ageYears(birthday: profile.birthday)
        return Array(0...max(age, 0))
    }

    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择年龄段").font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableYears, id: \.self) { year in
                        Button { selectedYear = year } label: {
                            Text(yearLabel(year))
                                .font(BubuTheme.Font.body.weight(.medium))
                                .foregroundStyle(selectedYear == year ? .white : BubuTheme.Color.warmBrown)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(selectedYear == year ? theme : BubuTheme.Color.softFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func yearLabel(_ year: Int) -> String {
        year == 0 ? "0–1 岁" : "\(year) 岁这一年"
    }

    private var entriesInRange: [Entry] {
        guard let profile else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .year, value: selectedYear, to: profile.birthday),
              let end = cal.date(byAdding: .year, value: selectedYear + 1, to: profile.birthday) else { return [] }
        return entries.filter { $0.happenedAt >= start && $0.happenedAt < end }
    }

    private var summary: some View {
        let list = entriesInRange
        return HStack(spacing: 12) {
            BubuMascotBadge(size: 44, expression: .reading)
            VStack(alignment: .leading, spacing: 2) {
                Text("这一年有 \(list.count) 条记录、\(list.reduce(0) { $0 + $1.sortedMedia.count }) 张照片")
                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                if !reportsInRange.isEmpty {
                    Text("还会加入第二大脑的 \(reportsInRange.count) 篇每月成长小报和当月精选照片")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            Spacer()
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack {
                if generating { ProgressView().tint(.white) }
                else { Image(systemName: "doc.badge.arrow.up") }
                Text(generating ? (progressText ?? "正在排版…") : "生成年册 PDF")
            }
            .font(BubuTheme.Font.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(theme, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(generating || profile == nil || (entriesInRange.isEmpty && reportsInRange.isEmpty))
    }

    /// 该年龄段内的月报，按月份先后。
    private var reportsInRange: [YearbookMonthlyReport] {
        guard let profile else { return [] }
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .year, value: selectedYear, to: profile.birthday),
              let end = cal.date(byAdding: .year, value: selectedYear + 1, to: profile.birthday) else { return [] }
        let firstMonth = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
        return monthlyReports.filter { report in
            guard let month = report.monthDate else { return false }
            return month >= firstMonth && month < end
        }
        .sorted { $0.month < $1.month }
    }

    private func loadMonthlyReports() async {
        guard let client = BubuLearningClient(env: env) else { monthlyReports = []; return }
        // 离线、未部署或拿不到都安静降级为只用本机数据。
        monthlyReports = (try? await client.get("api/monthly", as: YearbookMonthlyReportList.self).items) ?? []
    }

    private func generate() async {
        guard let profile else { return }
        generating = true
        pdfURL = nil
        showShare = false
        errorText = nil
        progressText = nil
        defer { generating = false; progressText = nil }

        let cal = Calendar.current
        // 主线程收集快照。
        let pages: [YearbookExporter.Page] = entriesInRange.map { e in
            YearbookExporter.Page(
                date: e.happenedAt,
                note: e.firstPersonNote ?? e.note,
                ageText: AgeCalculator.compactAge(birthday: profile.birthday, at: e.happenedAt),
                authorRole: e.authorRole,
                imageFileNames: e.sortedMedia.filter { $0.type == .photo }.map { $0.localFileName },
                mood: e.mood?.emoji)
        }
        let rangeStart = cal.date(byAdding: .year, value: selectedYear, to: profile.birthday) ?? profile.birthday
        let rangeEnd = cal.date(byAdding: .year, value: selectedYear + 1, to: profile.birthday) ?? .now
        let yearMilestones = milestones
            .filter { $0.isAchieved && ($0.happenedAt.map { $0 >= rangeStart && $0 < rangeEnd } ?? false) }
            .map(\.title)
        // 家人寄语：取该年记录的文字评论（排除反应）。
        let messages = entriesInRange.flatMap { e in
            e.comments.filter { !Reaction.isReaction($0) }.compactMap { c -> String? in
                guard let t = c.text, !t.isEmpty else { return nil }
                return "\(c.authorRole)：\(t)"
            }
        }
        let coverFile = profile.heroBackgroundFileName ?? entriesInRange.first?.sortedMedia.first(where: { $0.type == .photo })?.localFileName

        let input = YearbookExporter.Input(
            childName: profile.name,
            rangeTitle: yearLabel(selectedYear),
            coverImageFileName: coverFile,
            entries: pages,
            milestones: yearMilestones,
            messages: Array(messages.prefix(14)))

        let exporter = YearbookExporter(mediaStore: env.mediaStore, theme: env.theme.theme)
        let reports = reportsInRange
        do {
            progressText = "正在检查照片原片…"
            var url = try await exporter.makePDF(input, onProgress: { done, total in
                progressText = "正在排版… \(done)/\(total)"
            })
            // 连着家庭服务器时，在封面后插入每月成长小报；任何一步失败都保留本机年册。
            if !reports.isEmpty, let client = BubuLearningClient(env: env) {
                progressText = "正在加入每月成长小报…"
                if let merged = await YearbookMonthlyPages.append(reports, to: url, client: client,
                                                                   theme: env.theme.theme, onProgress: { done, total in
                    progressText = "正在加入每月成长小报… \(done)/\(total)"
                }) {
                    try? FileManager.default.removeItem(at: url)
                    url = merged
                }
            }
            pdfURL = url
            showShare = true
            BubuHaptics.success()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 第二大脑每月成长小报（年册附页）

/// `GET api/monthly` 的单条月报（只取年册用到的字段）。
nonisolated struct YearbookMonthlyReport: Decodable, Sendable, Hashable {
    let month: String
    let title: String
    let summary: String
    let highlightIds: [String]?
    let photos: Int?
    let videos: Int?
    let places: [String]?
    let firsts: [String]?

    var monthDate: Date? {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    }

    var monthTitle: String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        return parts.count == 2 ? "\(parts[0]) 年 \(parts[1]) 月" : month
    }

    /// 当月精选的第一张作为这一页的照片。
    var highlightPreviewPath: String? {
        guard let id = highlightIds?.first, id.range(of: "^[a-f0-9]{24}$", options: .regularExpression) != nil else { return nil }
        return "/learning/api/online-timeline/\(id)/preview?size=large"
    }
}

nonisolated struct YearbookMonthlyReportList: Decodable, Sendable { let items: [YearbookMonthlyReport] }

/// 把月报渲染成 A4 页面，插到本机年册封面之后。复用年册同样的位图写页方式。
@MainActor
enum YearbookMonthlyPages {
    static func append(_ reports: [YearbookMonthlyReport], to base: URL, client: BubuLearningClient,
                       theme: BubuThemeDefinition, onProgress: (Int, Int) -> Void) async -> URL? {
        let size = YearbookExporter.pageSize
        let extraURL = FileManager.default.temporaryDirectory.appendingPathComponent("布布月报-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: extraURL) }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let ctx = CGContext(extraURL as CFURL, mediaBox: &mediaBox, nil) else { return nil }
        for (index, report) in reports.enumerated() {
            var photo: UIImage?
            if let path = report.highlightPreviewPath, let data = try? await client.mediaData(path) {
                photo = await decode(data)
            }
            let renderer = ImageRenderer(content: YearbookMonthlyPage(report: report, photo: photo, theme: theme)
                .frame(width: size.width, height: size.height))
            renderer.scale = 2
            guard let cg = renderer.uiImage?.cgImage else { continue }
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
            ctx.endPDFPage()
            onProgress(index + 1, reports.count)
            await Task.yield()
        }
        ctx.closePDF()
        guard let document = PDFDocument(url: base), let extra = PDFDocument(url: extraURL), extra.pageCount > 0 else { return nil }
        let insertAt = min(1, document.pageCount)
        for page in 0..<extra.pageCount {
            if let copy = extra.page(at: page) { document.insert(copy, at: insertAt + page) }
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(base.deletingPathExtension().lastPathComponent + "-含月报.pdf")
        return document.write(to: output) ? output : nil
    }

    @concurrent
    private static func decode(_ data: Data) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return image.preparingThumbnail(of: CGSize(width: 1400, height: 1400)) ?? image
    }
}

/// 打印友好的一页月报：月份、标题、小结、精选照片和当月数字。
private struct YearbookMonthlyPage: View {
    let report: YearbookMonthlyReport
    let photo: UIImage?
    let theme: BubuThemeDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(theme.textAccent)
                Text(report.monthTitle).font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.paperInkSecondary)
                Spacer()
                Text("每月成长小报").font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.paperInkSecondary)
            }
            Text(report.title).font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.paperInk)
            if let photo {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)
                    .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text(report.summary).font(.system(size: 17, design: .serif))
                .foregroundStyle(BubuTheme.Color.paperInk)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                if let photos = report.photos, photos > 0 { stat("\(photos)", "张照片") }
                if let videos = report.videos, videos > 0 { stat("\(videos)", "段视频") }
                if let places = report.places, !places.isEmpty { stat(places.prefix(3).joined(separator: "、"), "去过的地方") }
            }
            if let firsts = report.firsts, !firsts.isEmpty {
                Text("这个月的第一次：" + firsts.prefix(5).joined(separator: "、"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textAccent)
            }
            Spacer(minLength: 0)
        }
        .padding(46)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: "#FFFDF8"))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(BubuTheme.Color.paperInk)
                .lineLimit(1)
            Text(label).font(.system(size: 12, design: .rounded)).foregroundStyle(BubuTheme.Color.paperInkSecondary)
        }
    }
}
