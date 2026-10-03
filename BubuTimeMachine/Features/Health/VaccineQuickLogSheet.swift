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
    @State private var draftID = UUID()
    @State private var saveError: String?
    @State private var completed = false

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
                        .disabled(completed)
                }
            }
            .alert("取消这针的打卡？", isPresented: $showDeleteConfirm) {
                Button("取消打卡", role: .destructive) { deleteRecord() }
                Button("再想想", role: .cancel) {}
            } message: {
                Text("删除后家人设备也会同步移除这条记录。")
            }
            .alert("还没有保存成功", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() {
        guard !completed else { return }
        let draft = VaccineQuickLogPersistence.Draft(id: record?.id ?? draftID,
            editing: record.map(VaccineQuickLogPersistence.Target.init),
            vaccineName: dose?.vaccine ?? record?.vaccineName ?? "疫苗接种", doseID: dose?.id,
            doseLabel: dose?.doseLabel, injectedAt: injectedAt, hospital: hospital, reaction: reaction, note: note)
        do {
            try VaccineQuickLogPersistence.save(draft, in: context, didCommit: didCommit)
        } catch {
            saveError = "接种记录还没有保存：\(error.localizedDescription)。填写的内容仍保留，请稍后再试。"
        }
    }

    private func deleteRecord() {
        guard !completed, let record else { return }
        do {
            try VaccineQuickLogPersistence.delete(.init(record), in: context, didCommit: didCommit)
        } catch {
            saveError = "这条接种记录还没有删除：\(error.localizedDescription)。请稍后再试。"
        }
    }

    private func didCommit(_ committedContext: ModelContext) {
        completed = true
        Task { await ReminderScheduler.shared.refreshVaccineReminders(context: committedContext) }
        BubuHaptics.success()
        env.syncEngine.syncNow()
        dismiss()
    }
}

@MainActor
enum VaccineQuickLogPersistence {
    struct Target: Equatable {
        let id: UUID
        let remoteID: String?
        let source: String
        let updatedAt: Date
        init(_ record: VaccineRecord) {
            id = record.id; remoteID = record.remoteId; source = record.sourceRaw; updatedAt = record.updatedAt
        }
    }
    struct Draft {
        let id: UUID
        var editing: Target? = nil
        let vaccineName: String
        var doseID: String? = nil
        var doseLabel: String? = nil
        let injectedAt: Date
        var hospital = ""
        var reaction = ""
        var note = ""
    }
    enum SaveError: LocalizedError {
        case missingRecord, changedRecord, missingLegacySource
        var errorDescription: String? {
            switch self {
            case .missingRecord: "这条接种记录已被移除，请返回确认。"
            case .changedRecord: "这条接种记录已有其他修改，请重新打开后确认。"
            case .missingLegacySource: "旧版接种记录的同步来源暂时无法确认，请先完成同步再删除。"
            }
        }
    }

    static func save(_ draft: Draft, in uiContext: ModelContext,
                     persist: (ModelContext) throws -> Void = { try $0.save() },
                     didCommit: (ModelContext) -> Void = { _ in }) throws {
        let context = ModelContext(uiContext.container)
        context.autosaveEnabled = false
        do {
            let id = draft.id
            let record: VaccineRecord
            if let target = draft.editing {
                try rejectPendingTargetEdits(id, in: uiContext)
                guard target.id == id,
                      let existing = try context.fetch(FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == id })).first else {
                    throw SaveError.missingRecord
                }
                guard Target(existing) == target else { throw SaveError.changedRecord }
                record = existing
            } else if let existing = try context.fetch(FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == id })).first {
                // Same view retry after an already committed write must not add a second dose.
                guard existing.vaccineName == draft.vaccineName, existing.doseId == draft.doseID,
                      existing.doseLabel == draft.doseLabel, existing.injectedAt == draft.injectedAt,
                      existing.hospital == optionalText(draft.hospital), existing.reaction == optionalText(draft.reaction),
                      existing.note == optionalText(draft.note) else { throw SaveError.changedRecord }
                didCommit(context)
                return
            } else {
                record = VaccineRecord(vaccineName: draft.vaccineName, injectedAt: draft.injectedAt, source: "manual")
                record.id = draft.id
                record.doseId = draft.doseID
                record.doseLabel = draft.doseLabel
                context.insert(record)
            }
            record.injectedAt = draft.injectedAt
            record.hospital = optionalText(draft.hospital)
            record.reaction = optionalText(draft.reaction)
            record.note = optionalText(draft.note) // Clear a migration placeholder only after a successful commit.
            record.updatedAt = .now
            record.syncState = .local
            try persist(context)
            didCommit(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    static func delete(_ target: Target, in uiContext: ModelContext,
                       persist: (ModelContext) throws -> Void = { try $0.save() },
                       didCommit: (ModelContext) -> Void = { _ in }) throws {
        let id = target.id
        let isLegacy = target.source == "health-fallback"
        try rejectPendingTargetEdits(id, in: uiContext, includingHealth: isLegacy)
        // Retain only the rows to mirror after commit, not a whole UI-context rollback.
        let visibleRecord = try uiContext.fetch(FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == id })).first
        let visibleHealth = isLegacy
            ? try uiContext.fetch(FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == id })).first : nil
        let context = ModelContext(uiContext.container)
        context.autosaveEnabled = false
        do {
            guard let record = try context.fetch(FetchDescriptor<VaccineRecord>(predicate: #Predicate { $0.id == id })).first else {
                throw SaveError.missingRecord
            }
            guard Target(record) == target else { throw SaveError.changedRecord }
            var remoteID = record.remoteId.flatMap { $0.isEmpty ? nil : $0 }
            if isLegacy {
                // Older servers represented vaccines as HealthRecord. Their locally
                // backfilled VaccineRecord may have no remoteId at all.
                if let health = try context.fetch(FetchDescriptor<HealthRecord>(predicate: #Predicate { $0.id == id })).first {
                    guard health.tags.contains("疫苗") || health.title.contains("疫苗") else { throw SaveError.changedRecord }
                    let healthRemoteID = health.remoteId.flatMap { $0.isEmpty ? nil : $0 }
                    if let remoteID, let healthRemoteID, remoteID != healthRemoteID { throw SaveError.changedRecord }
                    remoteID = healthRemoteID ?? remoteID
                    context.delete(health)
                }
                guard remoteID != nil else { throw SaveError.missingLegacySource }
            }
            let collection = isLegacy ? "healthrecords" : "vaccinerecords"
            if let remoteID {
                let query = FetchDescriptor<PendingDeletion>(predicate: #Predicate {
                    $0.collection == collection && $0.remoteId == remoteID
                })
                if try context.fetchCount(query) == 0 {
                    context.insert(PendingDeletion(collection: collection, remoteId: remoteID))
                }
            }
            context.delete(record)
            try persist(context)
            if let visibleRecord { uiContext.delete(visibleRecord) }
            if let visibleHealth { uiContext.delete(visibleHealth) }
            didCommit(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func optionalText(_ value: String) -> String? {
        let trimmed = value.bubuTrimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rejectPendingTargetEdits(_ id: UUID, in context: ModelContext, includingHealth: Bool = false) throws {
        let changed = context.changedModelsArray + context.deletedModelsArray
        guard !changed.contains(where: {
            ($0 as? VaccineRecord)?.id == id || (includingHealth && ($0 as? HealthRecord)?.id == id)
        }) else { throw SaveError.changedRecord }
    }
}
