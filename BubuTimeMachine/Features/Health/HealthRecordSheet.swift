import SwiftUI
import SwiftData

// MARK: - 健康记录编辑
struct HealthRecordSheet: View {
    let kind: HealthRecordKind
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var detail = ""
    @State private var amountText = ""
    @State private var reaction = ""
    @State private var recordedAt = Date.now

    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.title) {
                    TextField(kind.placeholder, text: $title)
                    TextField("数量/时长（可不填）", text: $amountText)
                    DatePicker("时间", selection: $recordedAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section("布布的反应") {
                    Picker("反应", selection: $reaction) {
                        Text("未记录").tag("")
                        Text("喜欢").tag("喜欢")
                        Text("一般").tag("一般")
                        Text("不喜欢").tag("不喜欢")
                        Text("疑似不适").tag("疑似不适")
                    }
                }
                Section("备注") {
                    TextField("比如吃完状态、睡醒精神、是否需要观察……", text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Text("健康记录只用于家庭观察，不替代医生建议。")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            .navigationTitle("记录\(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { title = defaultTitle }
        }
        .tint(theme)
    }

    private var defaultTitle: String {
        switch kind {
        case .meal: return ""
        case .snack: return ""
        case .supplement: return ""
        case .water: return "喝水"
        case .sleep: return "睡眠"
        case .symptom: return "不舒服观察"
        case .checkup: return "体检护理"
        }
    }

    private func save() {
        let record = HealthRecord(kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines), recordedAt: recordedAt)
        record.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail
        record.amountText = amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : amountText
        record.reaction = reaction.isEmpty ? nil : reaction
        record.syncState = .local
        context.insert(record)
        context.insert(FeedEvent(kind: .healthRecorded, actorRole: env.config.currentRole.rawValue,
                                 summary: "记录了\(kind.title)：\(record.title)"))
        try? context.save()
        dismiss()
    }
}
