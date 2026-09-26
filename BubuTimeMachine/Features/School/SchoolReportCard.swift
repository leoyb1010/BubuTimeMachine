import SwiftUI
import SwiftData

/// One journal, shared by the day page and entry detail. Illustrations never replace recorded facts.
struct SchoolReportCard: View {
    let entry: Entry
    let report: SchoolDailyReport
    var showsDetailLink = true
    var profileName: String?
    var profileBirthday: Date?
    var onCorrectedDate: ((Date) -> Void)?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context
    @State private var originalOpen = false
    @State private var correctionOpen = false
    @State private var recognizing = false
    @State private var recognitionMessage: String?
    @State private var attemptedAutomaticRepair = false
    private var original: Media? { entry.sortedMedia.first { $0.aiTags.contains("亲子桥原表") } }
    private var classroomMedia: [Media] { entry.sortedMedia.filter { !$0.aiTags.contains("亲子桥原表") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recognizing { Label("DeepSeek 正在补齐原表…", systemImage: "sparkle.magnifyingglass").font(.caption) }
            if BubuAdaptive.isWide(sizeClass) && !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 12) {
                    lifeColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                    observationsColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                lifeColumn
                observationsColumn
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("每日亲子桥").font(BubuTheme.Font.headline)
                    Text(identityLine).font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer(minLength: 0)
                Button { correctionOpen = true } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                    .accessibilityLabel("改一下亲子桥").accessibilityIdentifier("school.correct-report")
                if original != nil {
                    Button { originalOpen = true } label: {
                        Label("原表", systemImage: "doc.viewfinder").font(.caption.weight(.semibold)).frame(minHeight: 44)
                    }.accessibilityLabel("看原表").accessibilityIdentifier("school.saved-original")
                }
            }.padding(.horizontal, 4)
            Label(report.automaticallyImported == true && !report.confirmed ? "\(report.recognitionModel == "deepseek-flash" ? "DeepSeek" : "本机")自动记录 · 已填写 \(report.values.count) 项" : "已核对 · 留住她的一天",
                  systemImage: report.automaticallyImported == true && !report.confirmed ? "doc.text.viewfinder" : "checkmark.seal")
                .font(.caption2).foregroundStyle(env.theme.theme.textAccent).padding(.horizontal, 4)
                .accessibilityIdentifier("school.record-status")
            if let notes = report.reviewNotes, !notes.isEmpty {
                Text("可稍后修正：" + notes.joined(separator: "；"))
                    .font(.caption).foregroundStyle(BubuTheme.Color.secondaryText).padding(.horizontal, 4)
            }
            if original != nil {
                Button {
                    Task { await recognizeOriginal() }
                } label: {
                    HStack {
                        if recognizing { ProgressView() }
                        Label(recognizing ? "正在读取整张原表…" : "重新识别原表 · 补齐漏项", systemImage: "sparkle.magnifyingglass")
                    }.font(.subheadline).frame(minHeight: 44)
                }.disabled(recognizing).accessibilityIdentifier("school.recognize-original")
            }
            if let recognitionMessage {
                Text(recognitionMessage).font(.caption).foregroundStyle(SchoolPalette.secondary)
            }
            if showsDetailLink && !classroomMedia.isEmpty {
                SchoolPanel(title: "老师镜头里的她 · \(classroomMedia.count)", symbol: "photo.stack") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(classroomMedia.prefix(6))) { media in
                                NavigationLink { EntryDetailView(entry: entry) } label: {
                                    MediaThumbnail(media: media, mediaStore: env.mediaStore, size: .grid).frame(width: 90, height: 100)
                                }.buttonStyle(.plain).accessibilityLabel("查看老师照片和视频")
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            }
            if showsDetailLink {
                NavigationLink { EntryDetailView(entry: entry) } label: {
                    HStack {
                        Label("完整记录与原始资料", systemImage: "book.closed")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.font(BubuTheme.Font.caption.weight(.semibold)).frame(minHeight: 48).padding(.horizontal, 14)
                }.background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm))
            }
        }
        .foregroundStyle(BubuTheme.Color.warmBrown).tint(env.theme.theme.textAccent)
        .sheet(isPresented: $originalOpen) {
            if let original { SchoolOriginalSheet(fileID: original.id, fileName: original.localFileName, thumbnail: original.thumbnailFileName) }
        }
        .sheet(isPresented: $correctionOpen) {
            SchoolReportCorrection(entry: entry, report: report, onSaved: onCorrectedDate)
        }
        .task {
            if !attemptedAutomaticRepair, report.automaticallyImported == true,
               report.recognitionModel != "deepseek-flash", original != nil, env.schoolVisionService() != nil {
                attemptedAutomaticRepair = true
                await recognizeOriginal()
            }
        }
    }

    private func recognizeOriginal() async {
        guard !recognizing else { return }
        guard let service = env.schoolVisionService() else {
            recognitionMessage = "DeepSeek 尚未连接，原图和现有记录均保留。请开启亲子桥识别并检查连接配置。"
            return
        }
        guard let original, let name = original.localFileName else {
            recognitionMessage = "原表尚未下载到本机，请先打开原表下载。"; return
        }
        let entryID = entry.id
        let originalHash = original.contentHash ?? ""
        let happenedAt = entry.happenedAt
        recognizing = true; recognitionMessage = nil
        defer { recognizing = false }
        do {
            let image = try await SchoolVisionImage.data(from: env.mediaStore.mediaURL(for: name))
            let result = try await service.recognizeSchoolReport(image: image, referenceDate: happenedAt)
            try Task.checkCancellation()
            let incoming = try result.report(sourceHash: originalHash)
            // Writer re-fetches and merges in one synchronous transaction after the network wait.
            try MemoryJournalWriter.updateReport(id: entryID, date: happenedAt, report: incoming,
                                                 container: context.container, fillingMissingOnly: true)
            env.syncEngine.syncNow()
            env.refreshWidgetSnapshot(context: context)
            recognitionMessage = "已补齐识别结果，你修改过的内容和原表都保留。"
        } catch is CancellationError {
            recognitionMessage = "识别已取消，原记录没有改变。"
        } catch {
            recognitionMessage = "识别未完成，原记录没有改变。请检查网络后重试。"
        }
    }

    private var lifeColumn: some View {
        VStack(spacing: 8) {
            SchoolMealsPanel(report: report)
            SchoolMilkPanel(report: report)
            SchoolNapPanel(report: report)
            SchoolTemperaturePanel(report: report)
        }
    }
    private var observationsColumn: some View {
        VStack(spacing: 8) {
            SchoolBehaviorPanel(report: report)
            SchoolBodyPanel(report: report)
            SchoolBowelPanel(report: report)
            SchoolTeacherPanel(report: report)
        }
    }
    private var identityLine: String {
        let name = report[.reportedName].isEmpty ? "档案：" + (profileName ?? "未记录") : "表上姓名：" + report[.reportedName]
        let age: String
        if !report[.reportedAge].isEmpty { age = "表上年龄：" + report[.reportedAge] }
        else if let profileBirthday { age = "档案年龄：" + AgeCalculator.ageDescription(birthday: profileBirthday, at: entry.happenedAt) }
        else { age = "年龄未记录" }
        return name + " · " + age
    }
}
