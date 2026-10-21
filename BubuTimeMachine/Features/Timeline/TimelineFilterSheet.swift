import SwiftUI

struct TimelineFilterSheet: View {
    @Binding private var filters: TimelineFilters
    @State private var draft: TimelineFilters
    @Environment(\.dismiss) private var dismiss

    init(filters: Binding<TimelineFilters>) {
        _filters = filters
        _draft = State(initialValue: filters.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("想看什么") {
                    Picker("素材类型", selection: $draft.kind) {
                        ForEach(TimelineFilters.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("记录来源", selection: $draft.source) {
                        ForEach(TimelineFilters.Source.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle("限定拍摄日期", isOn: Binding(get: { draft.start != nil || draft.end != nil }, set: { enabled in
                        if enabled {
                            draft.start = Calendar.current.date(byAdding: .month, value: -1, to: .now)
                            draft.end = .now
                        } else { draft.start = nil; draft.end = nil }
                    }))
                    if draft.start != nil || draft.end != nil {
                        DatePicker("从哪一天", selection: Binding(get: { draft.start ?? .now }, set: { draft.start = $0 }),
                                   in: ...max(draft.end ?? .now, .now), displayedComponents: .date)
                            .accessibilityIdentifier("timeline.start-date")
                        DatePicker("到哪一天", selection: Binding(get: { draft.end ?? .now }, set: { draft.end = $0 }),
                                   in: ...Date.now, displayedComponents: .date)
                            .accessibilityIdentifier("timeline.end-date")
                        if invalidRange { Text("结束日期不能早于开始日期。").foregroundStyle(.red) }
                    }
                } header: { Text("拍摄日期") } footer: {
                    Text("按事情发生的日期筛选，结束当天也包含在内；不会改变原记录的日期。")
                }
                Section {
                    Button("清除全部筛选") { draft = .init() }
                } footer: {
                    Text("第二大脑自动整理与家人记录都保留。尚未确认归属的照片不会进入时光。")
                }
            }
            .navigationTitle("筛选时光")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") { filters = draft; dismiss() }.disabled(invalidRange)
                }
            }
        }
    }

    private var invalidRange: Bool {
        guard let start = draft.start, let end = draft.end else { return false }
        return Calendar.current.startOfDay(for: start) > Calendar.current.startOfDay(for: end)
    }
}
