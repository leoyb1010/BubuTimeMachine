import SwiftUI
import SwiftData

// MARK: - 疫苗快速补录 / 编辑
/// 点剂次弹出：接种日期、医院、反应、备注；编辑模式可取消打卡（删除走 PendingDeletion 队列）。
/// 迁移来的记录在此确认真实接种日期后，自动摘掉「日期待确认」标记。
struct VaccineQuickLogSheet: View {
    let dose: VaccineDose?            // 排期剂次；自由疫苗记录（AI 归档）为 nil
    let record: VaccineRecord?        // 编辑已有记录；nil = 新打卡

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [ChildProfile]

    @State private var injectedAt: Date
    @State private var hospital: String
    @State private var reaction: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { record != nil }

    /// 旧版打卡迁移且日期尚未被家长确认。
    private var isMigrationPending: Bool {
        guard let record else { return false }
        return record.sourceRaw == "migration" && (record.note?.contains("待确认") ?? false)
    }

    init(dose: VaccineDose?, record: VaccineRecord?, birthday: Date?) {
        self.dose = dose
        self.record = record
        let fallback: Date
        if let record {
            fallback = record.injectedAt
        } else if let dose, let birthday {
            fallback = min(dose.dueDate(birthday: birthday), .now)
        } else {
            fallback = .now
        }
        _injectedAt = State(initialValue: fallback)
        _hospital = State(initialValue: record?.hospital ?? "")
        _reaction = State(initialValue: record?.reaction ?? "")
        let initialNote = record?.note ?? ""
        // 迁移占位说明不进编辑框，由下方提示语承担
        _note = State(initialValue: initialNote.contains("待确认") ? "" : initialNote)
    }

    private var title: String {
        if let dose { return "\(dose.shortName) · \(dose.doseLabel)" }
        return record?.vaccineName ?? "疫苗记录"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("接种日期", selection: $injectedAt, in: ...Date.now,
                               displayedComponents: [.date])
                    TextField("接种医院/门诊（可选）", text: $hospital)
                    TextField("接种后反应（可选）", text: $reaction)
                    TextField("备注（可选）", text: $note)
                } header: {
                    Text(title)
                } footer: {
                    if isMigrationPending {
                        Text("此记录由旧版打卡迁移，请确认真实接种日期后保存。")
                    } else if let dose {
                        Text("\(dose.vaccine) · 预防\(dose.prevents)")
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("取消打卡 / 删除记录", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "修改接种记录" : "补录接种")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                }
            }
            .alert("取消这针的打卡？", isPresented: $showDeleteConfirm) {
                Button("取消打卡", role: .destructive) { deleteRecord() }
                Button("再想想", role: .cancel) {}
            } message: {
                Text("删除后家人设备也会同步移除这条记录。")
            }
        }
    }

    private func save() {
        if let record {
            record.injectedAt = injectedAt
            record.hospital = hospital.bubuTrimmed.isEmpty ? nil : hospital.bubuTrimmed
            record.reaction = reaction.bubuTrimmed.isEmpty ? nil : reaction.bubuTrimmed
            record.note = note.bubuTrimmed.isEmpty ? nil : note.bubuTrimmed   // 迁移「待确认」标记随之摘除
            record.updatedAt = .now
            record.syncState = .local
        } else {
            let vaccineName = dose?.vaccine ?? "疫苗接种"
            let newRecord = VaccineRecord(vaccineName: vaccineName, injectedAt: injectedAt, source: "manual")
            newRecord.doseId = dose?.id
            newRecord.doseLabel = dose?.doseLabel
            newRecord.hospital = hospital.bubuTrimmed.isEmpty ? nil : hospital.bubuTrimmed
            newRecord.reaction = reaction.bubuTrimmed.isEmpty ? nil : reaction.bubuTrimmed
            newRecord.note = note.bubuTrimmed.isEmpty ? nil : note.bubuTrimmed
            newRecord.syncState = .local
            context.insert(newRecord)
        }
        try? context.save()
        Task { await ReminderScheduler.shared.refreshVaccineReminders(context: context) }   // 打卡后自动排下一针
        BubuHaptics.success()
        env.syncEngine.syncNow()
        dismiss()
    }

    private func deleteRecord() {
        guard let record else { return }
        let collection = record.sourceRaw == "health-fallback" ? "healthrecords" : "vaccinerecords"
        PendingDeletion.enqueue(collection: collection, remoteId: record.remoteId, in: context)
        context.delete(record)
        try? context.save()
        Task { await ReminderScheduler.shared.refreshVaccineReminders(context: context) }   // 打卡后自动排下一针
        env.syncEngine.syncNow()
        dismiss()
    }
}
