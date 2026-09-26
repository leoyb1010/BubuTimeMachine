import SwiftUI
import SwiftData

/// Corrections edit the same memory; the original photo, teacher text and attachments stay intact.
struct SchoolReportCorrection: View {
    let entry: Entry
    var onSaved: ((Date) -> Void)?
    @State private var report: SchoolDailyReport
    @State private var date: Date
    @State private var message: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    init(entry: Entry, report: SchoolDailyReport, onSaved: ((Date) -> Void)? = nil) {
        self.entry = entry
        self.onSaved = onSaved
        _report = State(initialValue: report)
        _date = State(initialValue: entry.happenedAt)
    }
    private var original: JournalMediaFile? {
        guard let media = entry.sortedMedia.first(where: { $0.aiTags.contains("亲子桥原表") }),
              let file = media.localFileName else { return nil }
        return JournalMediaFile(id: media.id, fileName: file, thumbnail: media.thumbnailFileName,
                                hash: media.contentHash ?? "", isVideo: false, isSchoolReport: true)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("发生在", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    if let message { Text(message).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.danger) }
                    SchoolReportEditor(report: $report, sourceFile: original)
                }.padding().bubuContentColumn(700)
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .foregroundStyle(BubuTheme.Color.warmBrown).tint(env.theme.theme.textAccent)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("改一下亲子桥").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存修改") {
                        do {
                            try MemoryJournalWriter.updateReport(id: entry.id, date: date, report: report, container: context.container)
                            env.syncEngine.syncNow()
                            env.refreshWidgetSnapshot(context: context)
                            onSaved?(date)
                            dismiss()
                        } catch { message = "修改未保存，原记录还在：\(error.localizedDescription)" }
                    }.fontWeight(.semibold).accessibilityIdentifier("school.correction-save")
                }
            }
        }
    }
}
