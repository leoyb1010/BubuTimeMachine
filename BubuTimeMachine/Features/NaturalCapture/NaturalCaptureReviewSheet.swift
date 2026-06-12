import SwiftUI
import SwiftData

// MARK: - 解析结果确认页
/// 展示 LLM 拆出的待保存卡片：普通记录可直接保存；疫苗/症状/营养补充与低置信项
/// 必须逐条点「确认」后才会入库，杜绝静默写入敏感内容。
struct NaturalCaptureReviewSheet: View {
    let result: NaturalCaptureResult
    let originalText: String
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var editableItems: [NaturalCaptureItem]
    @State private var confirmedIDs: Set<UUID> = []

    init(result: NaturalCaptureResult, originalText: String, onSaved: @escaping () -> Void) {
        self.result = result
        self.originalText = originalText
        self.onSaved = onSaved
        _editableItems = State(initialValue: result.items)
    }

    private var theme: Color { env.theme.theme.primary }

    /// 可保存：不需要硬确认，或已被用户点「确认」。
    private var savableItems: [NaturalCaptureItem] {
        editableItems.filter { !$0.requiresHardConfirmation || confirmedIDs.contains($0.id) }
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

                        ForEach(editableItems) { item in
                            itemCard(item)
                        }

                        if hasSymptom {
                            Text("以上仅记录事实，不构成医疗建议；如情况严重请及时联系医生。")
                                .font(.system(size: 11))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        if result.warnings.contains("date_inferred") {
                            Text("部分日期由系统推断，保存前请确认。")
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
                    Button(savableItems.count == editableItems.count
                           ? "保存"
                           : "保存 \(savableItems.count) 条") {
                        saveAll()
                    }
                    .fontWeight(.bold)
                    .disabled(savableItems.isEmpty)
                }
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

    private func itemCard(_ item: NaturalCaptureItem) -> some View {
        let needsConfirm = item.requiresHardConfirmation
        let confirmed = confirmedIDs.contains(item.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.domain.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme)
                    .frame(width: 26, height: 26)
                    .background(theme.opacity(0.10), in: Circle())
                Text(item.domain.displayName)
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(theme)
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
                        editableItems.removeAll { $0.id == item.id }
                        confirmedIDs.remove(item.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.5))
                }
                .accessibilityLabel("删除这条")
            }

            Text(item.title)
                .font(BubuTheme.Font.body.weight(.semibold))
                .foregroundStyle(BubuTheme.Color.warmBrown)

            if let summary = fieldSummary(item) {
                Text(summary)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }

            HStack(spacing: 10) {
                if let date = item.date {
                    Label(BubuDateFormat.shortDateTime(date), systemImage: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
                if needsConfirm {
                    Button(confirmed ? "取消确认" : "确认无误") {
                        withAnimation(.smooth) {
                            if confirmed { confirmedIDs.remove(item.id) }
                            else { confirmedIDs.insert(item.id); BubuHaptics.selection() }
                        }
                    }
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(confirmed ? BubuTheme.Color.secondaryText : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(confirmed ? AnyShapeStyle(BubuTheme.Color.card) : AnyShapeStyle(theme), in: Capsule())
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
        let router = NaturalCaptureRouter(context: context, env: env)
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
