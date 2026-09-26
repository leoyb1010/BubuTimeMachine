import SwiftUI

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
    @State private var originalOpen = false
    @State private var correctionOpen = false
    private var original: Media? { entry.sortedMedia.first { $0.aiTags.contains("亲子桥原表") } }
    private var classroomMedia: [Media] { entry.sortedMedia.filter { !$0.aiTags.contains("亲子桥原表") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            if BubuAdaptive.isWide(sizeClass) && !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 12) {
                    lifeColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                    observationsColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                lifeColumn
                observationsColumn
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
    }

    private var lifeColumn: some View {
        VStack(spacing: 12) {
            SchoolMealsPanel(report: report)
            SchoolMilkPanel(report: report)
            SchoolNapPanel(report: report)
            SchoolTemperaturePanel(report: report)
        }
    }
    private var observationsColumn: some View {
        VStack(spacing: 12) {
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
