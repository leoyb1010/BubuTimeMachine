import SwiftUI
import SwiftData

// MARK: - 解析结果确认页 v2
/// 一组待保存小卡：可逐条「编辑标题/时间/数量」、删除；
/// 敏感（疫苗/症状/营养补充）与低置信项必须点「确认无误」才入库；
/// 置信度 < 0.6 的卡片默认折叠并提供手动分类下拉；
/// 保存时若仍有未确认项，会先明确提示而不是静默跳过。
struct NaturalCaptureReviewSheet: View {
    let result: NaturalCaptureResult
    let originalText: String
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var editableItems: [NaturalCaptureItem]
    @State private var confirmedIDs: Set<UUID> = []
    @State private var expandedIDs: Set<UUID>
    @State private var editingID: UUID?
    @State private var showUnconfirmedAlert = false

    init(result: NaturalCaptureResult, originalText: String, onSaved: @escaping () -> Void) {
        self.result = result
        self.originalText = originalText
        self.onSaved = onSaved
        _editableItems = State(initialValue: result.items)
        // 低置信默认折叠，其余展开
        _expandedIDs = State(initialValue: Set(result.items.filter { $0.confidence >= 0.6 }.map(\.id)))
    }

    private var theme: Color { env.theme.theme.primary }

    /// 可保存：不需要硬确认，或已被用户点「确认」。
    private var savableItems: [NaturalCaptureItem] {
        editableItems.filter { !$0.requiresHardConfirmation || confirmedIDs.contains($0.id) }
    }

    private var unconfirmedCount: Int {
        editableItems.count - savableItems.count
    }

    private var hasSymptom: Bool {
        editableItems.contains { $0.domain == .symptom }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if editableItems.isEmpty {
                        emptyState
                    } else {
                        Text("识别到 \(editableItems.count) 条记录")
                            .font(BubuTheme.Font.headline)
                            .foregroundStyle(BubuTheme.Color.warmBrown)

                        Text(originalText)
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        ForEach($editableItems) { $item in
                            itemCard($item)
                        }

                        if hasSymptom {
                            Text("以上仅记录事实，不构成医疗建议；如情况严重请及时联系医生。")
                                .font(.system(size: 11))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        if result.warnings.contains("date_inferred") || result.warnings.contains("item_date_dropped") {
                            Text("部分时间由系统推断或缺失，可点「编辑」修正。")
                                .font(.system(size: 11))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                    }
                }
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("确认保存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(unconfirmedCount == 0 ? "保存" : "保存 \(savableItems.count) 条") {
                        if unconfirmedCount > 0 {
                            showUnconfirmedAlert = true
                        } else {
                            saveAll()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(savableItems.isEmpty)
                }
            }
            .alert("还有 \(unconfirmedCount) 条需要确认", isPresented: $showUnconfirmedAlert) {
                Button("仍然保存其余 \(savableItems.count) 条") { saveAll() }
                Button("返回确认", role: .cancel) {}
            } message: {
                Text("疫苗、症状等敏感记录需要逐条点「确认无误」才会保存；未确认的这次不会入库。")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            BubuMascotBadge(size: 72, expression: .surprised)
            Text("这句话布布没听懂\n可以换个说法，或回首页用「记录此刻」")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: 单条卡片

    @ViewBuilder
    private func itemCard(_ item: Binding<NaturalCaptureItem>) -> some View {
        let value = item.wrappedValue
        let needsConfirm = value.requiresHardConfirmation
        let confirmed = confirmedIDs.contains(value.id)
        let lowConfidence = value.confidence < 0.6
        let expanded = expandedIDs.contains(value.id) || !lowConfidence
        let editing = editingID == value.id

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: value.domain.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme)
                    .frame(width: 26, height: 26)
                    .background(theme.opacity(0.10), in: Circle())

                if lowConfidence {
                    domainPicker(item)
                } else {
                    Text(value.domain.displayName)
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(theme)
                }

                if lowConfidence {
                    Text("置信度低")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(BubuTheme.Color.secondaryText.opacity(0.10), in: Capsule())
                }

                Spacer()

                if needsConfirm {
                    Text(confirmed ? "已确认" : "需要确认")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(confirmed ? .white : theme)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(confirmed ? AnyShapeStyle(BubuTheme.Color.success) : AnyShapeStyle(theme.opacity(0.12)),
                                    in: Capsule())
                }
                Button {
                    withAnimation(.smooth) {
                        editableItems.removeAll { $0.id == value.id }
                        confirmedIDs.remove(value.id)
                        if editingID == value.id { editingID = nil }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.5))
                }
                .accessibilityLabel("删除这条")
            }

            if editing {
                editFields(item)
            } else {
                Text(value.title)
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
            }

            if expanded {
                if !editing, let summary = fieldSummary(value) {
                    Text(summary)
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }

                HStack(spacing: 10) {
                    if !editing, let date = value.date {
                        Label(BubuDateFormat.shortDateTime(date), systemImage: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                    Spacer()

                    Button(editing ? "完成" : "编辑") {
                        withAnimation(.smooth) {
                            editingID = editing ? nil : value.id
                        }
                    }
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(theme)

                    if needsConfirm {
                        Button(confirmed ? "取消确认" : "确认无误") {
                            withAnimation(.smooth) {
                                if confirmed { confirmedIDs.remove(value.id) }
                                else { confirmedIDs.insert(value.id); BubuHaptics.selection() }
                            }
                        }
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(confirmed ? BubuTheme.Color.secondaryText : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(confirmed ? AnyShapeStyle(BubuTheme.Color.card) : AnyShapeStyle(theme), in: Capsule())
                    }
                }
            } else {
                Button {
                    withAnimation(.smooth) { _ = expandedIDs.insert(value.id) }
                } label: {
                    Label("展开核对", systemImage: "chevron.down")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(theme)
                }
            }
        }
        .padding(14)
        .background(BubuTheme.Color.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(needsConfirm && !confirmed ? theme.opacity(0.35) : .clear, lineWidth: 1)
        }
        .bubuCardShadow()
    }

    /// 低置信卡片的手动分类下拉。
    private func domainPicker(_ item: Binding<NaturalCaptureItem>) -> some View {
        Menu {
            ForEach(NaturalCaptureDomain.allCases.filter { $0 != .unknown }, id: \.self) { domain in
                Button {
                    item.wrappedValue.domain = domain
                } label: {
                    Label(domain.displayName, systemImage: domain.icon)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(item.wrappedValue.domain.displayName)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(BubuTheme.Font.caption.weight(.semibold))
            .foregroundStyle(theme)
        }
    }

    // MARK: 编辑字段（标题 / 时间 / 数量类）

    @ViewBuilder
    private func editFields(_ item: Binding<NaturalCaptureItem>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("标题", text: item.title)
                .font(BubuTheme.Font.body.weight(.semibold))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .padding(8)
                .background(BubuTheme.Color.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            DatePicker("时间", selection: dateBinding(item), in: ...Date.now,
                       displayedComponents: [.date, .hourAndMinute])
                .font(BubuTheme.Font.caption)

            switch item.wrappedValue.domain {
            case .water:
                amountField(item, key: "amount_ml", label: "喝水量", unit: "ml")
            case .growth, .checkup:
                amountField(item, key: "height_cm", label: "身高", unit: "cm")
                amountField(item, key: "weight_kg", label: "体重", unit: "kg")
                amountField(item, key: "head_circumference_cm", label: "头围", unit: "cm")
            case .symptom:
                amountField(item, key: "temperature_celsius", label: "体温", unit: "℃")
            default:
                EmptyView()
            }
        }
    }

    private func amountField(_ item: Binding<NaturalCaptureItem>, key: String, label: String, unit: String) -> some View {
        HStack {
            Text(label)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            TextField("未填写", text: numericFieldBinding(item, key: key))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(BubuTheme.Font.body)
            Text(unit)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(BubuTheme.Color.cream.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dateBinding(_ item: Binding<NaturalCaptureItem>) -> Binding<Date> {
        Binding(get: { item.wrappedValue.date ?? .now },
                set: { item.wrappedValue.date = $0 })
    }

    /// 数量字段的字符串绑定：空 → 移除字段；数字 → number；其它 → string。
    private func numericFieldBinding(_ item: Binding<NaturalCaptureItem>, key: String) -> Binding<String> {
        Binding(
            get: {
                if let value = item.wrappedValue.fields.double(key) { return trimNumber(value) }
                return item.wrappedValue.fields.string(key) ?? ""
            },
            set: { newValue in
                let trimmed = newValue.bubuTrimmed
                if trimmed.isEmpty {
                    item.wrappedValue.fields[key] = nil
                } else if let number = Double(trimmed) {
                    item.wrappedValue.fields[key] = .number(number)
                } else {
                    item.wrappedValue.fields[key] = .string(trimmed)
                }
            })
    }

    /// 关键字段摘要：让家长一眼核对 LLM 抽取的事实。
    private func fieldSummary(_ item: NaturalCaptureItem) -> String? {
        var parts: [String] = []
        switch item.domain {
        case .vaccine:
            if let v = item.fields.string("vaccine_name") { parts.append(v) }
            if let v = item.fields.string("dose_label") { parts.append(v) }
            if let v = item.fields.string("hospital") { parts.append(v) }
        case .growth:
            if let h = item.fields.double("height_cm") { parts.append("身高 \(trimNumber(h))cm") }
            if let w = item.fields.double("weight_kg") { parts.append("体重 \(trimNumber(w))kg") }
            if let hc = item.fields.double("head_circumference_cm") { parts.append("头围 \(trimNumber(hc))cm") }
        case .meal, .snack:
            let foods = item.fields.stringArray("food_items")
            if !foods.isEmpty { parts.append(foods.joined(separator: "、")) }
            if let a = item.fields.string("amount_text") { parts.append(a) }
        case .water:
            if let ml = item.fields.double("amount_ml") { parts.append("\(Int(ml))ml") }
        case .sleep:
            if let s = item.fields.isoDate("start_at") { parts.append("入睡 \(BubuDateFormat.shortTime(s))") }
            if let e = item.fields.isoDate("end_at") { parts.append("醒来 \(BubuDateFormat.shortTime(e))") }
            if parts.isEmpty, let m = item.fields.double("duration_minutes") {
                parts.append("约 \(trimNumber(m / 60)) 小时")
            }
        case .symptom:
            let symptoms = item.fields.stringArray("symptoms")
            if !symptoms.isEmpty { parts.append(symptoms.joined(separator: "、")) }
            if let t = item.fields.double("temperature_celsius") { parts.append(String(format: "体温 %.1f℃", t)) }
        case .supplement:
            if let n = item.fields.string("supplement_name") { parts.append(n) }
            if let a = item.fields.string("amount_text") { parts.append(a) }
        default:
            break
        }
        if parts.isEmpty, let note = item.note, note != item.title { return note }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func trimNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func saveAll() {
        let router = NaturalCaptureRouter(context: context,
                                          authorRole: env.config.currentRole.rawValue)
        for item in savableItems {
            router.save(item)
        }
        try? context.save()
        env.syncEngine.syncNow()
        BubuHaptics.success()
        BubuSound.play(.save)
        onSaved()
        dismiss()
    }
}
