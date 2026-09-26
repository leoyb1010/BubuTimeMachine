import SwiftUI

/// One journal, shared by the day page and entry detail. Illustrations never replace recorded facts.
struct SchoolReportCard: View {
    let entry: Entry
    let report: SchoolDailyReport
    var showsDetailLink = true
    var profileName: String?
    var profileBirthday: Date?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var originalOpen = false
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
                if original != nil {
                    Button { originalOpen = true } label: {
                        Label("原表", systemImage: "doc.viewfinder").font(.caption.weight(.semibold)).frame(minHeight: 44)
                    }.accessibilityLabel("看原表").accessibilityIdentifier("school.saved-original")
                }
            }.padding(.horizontal, 4)
            Label("已核对 · 留住她的一天", systemImage: "checkmark.seal")
                .font(.caption2).foregroundStyle(env.theme.theme.textAccent).padding(.horizontal, 4)
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
