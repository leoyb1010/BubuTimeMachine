import SwiftUI
import SwiftData

// MARK: - 健康记录编辑
struct HealthRecordSheet: View {
    let kind: HealthRecordKind
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HealthRecord.recordedAt, order: .reverse) private var records: [HealthRecord]

    @State private var draft = HealthRecordDraft()

    private var theme: Color { env.theme.theme.primary }
    private var todayWaterTotal: Double {
        records
            .filter { $0.kind == .water && Calendar.current.isDateInToday($0.recordedAt) }
            .compactMap(\.amountValue)
            .reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HealthHeroCard(kind: kind, tint: theme)

                    switch kind {
                    case .meal:
                        MealComposer(draft: $draft, tint: theme)
                    case .snack:
                        SnackComposer(draft: $draft, tint: theme)
                    case .supplement:
                        SupplementComposer(draft: $draft, tint: theme)
                    case .water:
                        WaterComposer(draft: $draft, todayTotal: todayWaterTotal, tint: theme)
                    case .sleep:
                        SleepComposer(draft: $draft, tint: theme)
                    case .symptom:
                        SymptomComposer(draft: $draft, tint: theme)
                    case .checkup:
                        CheckupComposer(draft: $draft, tint: theme)
                    }

                    DetailNoteCard(draft: $draft, tint: theme)
                    HealthDisclaimerCard(kind: kind)
                }
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("记录\(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                        .disabled(!draft.canSave(kind: kind))
                }
            }
        }
        .tint(theme)
    }

    private func save() {
        let record = draft.makeRecord(kind: kind)
        record.syncState = .local
        context.insert(record)
        if kind == .checkup, draft.hasGrowthMeasurement {
            let measurement = draft.makeGrowthMeasurement()
            context.insert(measurement)
        }
        context.insert(FeedEvent(kind: .healthRecorded,
                                 actorRole: env.config.currentRole.rawValue,
                                 summary: "记录了\(kind.title)：\(record.title)"))
        try? context.save()
        env.refreshWidgetSnapshot(context: context)
        WidgetRefresher.reload()
        env.syncEngine.syncNow()
        dismiss()
    }
}

struct HealthRecordDraft: Equatable {
    var title = ""
    var detail = ""
    var recordedAt = Date.now
    var amountValue: Double?
    var amountUnit: String?
    var startAt: Date?
    var endAt: Date?
    var reaction = ""
    var severity = ""
    var temperatureCelsius: Double?
    var heightCm: Double?
    var weightKg: Double?
    var headCircumferenceCm: Double?
    var tags: [String] = []

    var hasGrowthMeasurement: Bool {
        heightCm != nil || weightKg != nil || headCircumferenceCm != nil
    }

    func canSave(kind: HealthRecordKind) -> Bool {
        switch kind {
        case .water:
            return amountValue != nil
        case .sleep:
            return startAt != nil || endAt != nil || !title.trimmed.isEmpty || !tags.isEmpty
        case .symptom:
            return !tags.isEmpty || temperatureCelsius != nil || !detail.trimmed.isEmpty
        case .checkup:
            return !title.trimmed.isEmpty || !tags.isEmpty || amountValue != nil || hasGrowthMeasurement
        default:
            return !title.trimmed.isEmpty || !tags.isEmpty || amountValue != nil
        }
    }

    func makeRecord(kind: HealthRecordKind) -> HealthRecord {
        let finalTitle: String
        if !title.trimmed.isEmpty {
            finalTitle = title.trimmed
        } else if let first = tags.first {
            finalTitle = first
        } else {
            finalTitle = kind.title
        }

        let record = HealthRecord(kind: kind, title: finalTitle, recordedAt: recordedAt)
        record.detail = detail.trimmed.isEmpty ? nil : detail.trimmed
        record.reaction = reaction.isEmpty ? nil : reaction
        record.amountValue = amountValue
        record.amountUnit = amountUnit
        record.startAt = startAt
        record.endAt = endAt
        record.severityRaw = severity.isEmpty ? nil : severity
        record.temperatureCelsius = temperatureCelsius
        record.tags = tags

        if kind == .sleep, let startAt, let endAt, endAt > startAt {
            let hours = endAt.timeIntervalSince(startAt) / 3600
            record.amountValue = hours
            record.amountUnit = "小时"
            record.amountText = Self.durationText(from: startAt, to: endAt)
        } else if let amountValue, let amountUnit {
            record.amountText = "\(Self.cleanAmount(amountValue))\(amountUnit)"
        }

        if kind == .symptom, let temperatureCelsius {
            let tempText = "体温 \(String(format: "%.1f", temperatureCelsius))℃"
            record.amountText = [record.amountText, tempText].compactMap { $0 }.joined(separator: " · ")
        }

        if kind == .checkup, hasGrowthMeasurement {
            let growthText = [
                heightCm.map { "身高 \(Self.cleanAmount($0))cm" },
                weightKg.map { "体重 \(Self.cleanAmount($0))kg" },
                headCircumferenceCm.map { "头围 \(Self.cleanAmount($0))cm" }
            ].compactMap { $0 }.joined(separator: " · ")
            record.amountText = [record.amountText, growthText.isEmpty ? nil : growthText]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        return record
    }

    func makeGrowthMeasurement() -> GrowthMeasurement {
        let measurement = GrowthMeasurement(measuredAt: recordedAt, source: "checkup")
        measurement.heightCm = heightCm
        measurement.weightKg = weightKg
        measurement.headCircumferenceCm = headCircumferenceCm
        let noteParts = [
            title.trimmed.isEmpty ? nil : title.trimmed,
            detail.trimmed.isEmpty ? nil : detail.trimmed
        ].compactMap { $0 }
        measurement.note = noteParts.isEmpty ? nil : noteParts.joined(separator: " · ")
        measurement.syncState = .local
        return measurement
    }

    static func durationText(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 { return "\(hours)小时\(rest)分钟" }
        if hours > 0 { return "\(hours)小时" }
        return "\(rest)分钟"
    }

    static func cleanAmount(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

private struct HealthHeroCard: View {
    let kind: HealthRecordKind
    let tint: Color

    var body: some View {
        let design = kind.design
        HStack(spacing: 14) {
            BubuMascotBadge(size: 62, expression: design.mascot)
            VStack(alignment: .leading, spacing: 5) {
                Label(design.heroTitle, systemImage: design.icon)
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(design.heroSubtitle)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }
}

private struct MealComposer: View {
    @Binding var draft: HealthRecordDraft
    let tint: Color

    var body: some View {
        ComposerCard(title: "食物卡片", icon: "fork.knife", tint: tint) {
            TextField("比如：小米粥、鸡蛋羹、青菜碎", text: $draft.title)
                .healthTextField()
            TagGrid(chips: HealthRecordKind.meal.design.chips, selected: $draft.tags, tint: tint)
            ReactionChips(options: ["喜欢", "一般", "不喜欢", "过敏/不适"], selection: $draft.reaction, tint: tint)
        }
    }
}

private struct SnackComposer: View {
    @Binding var draft: HealthRecordDraft
    let tint: Color

    var body: some View {
        ComposerCard(title: "小零食卡片", icon: "takeoutbag.and.cup.and.straw", tint: tint) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(HealthRecordKind.snack.design.chips, id: \.self) { chip in
                    Button {
                        draft.toggleTag(chip)
                        if draft.title.trimmed.isEmpty { draft.title = chip }
                    } label: {
                        VStack(spacing: 6) {
                            Text(chip)
                                .font(BubuTheme.Font.body.weight(.bold))
                            Text(draft.tags.contains(chip) ? "已选择" : "点一下")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(draft.tags.contains(chip) ? .white : BubuTheme.Color.warmBrown)
                        .frame(maxWidth: .infinity)
                        .frame(height: 66)
                        .background(draft.tags.contains(chip) ? tint : BubuTheme.Color.cream.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("补充具体零食", text: $draft.title)
                .healthTextField()
            ReactionChips(options: ["开心", "一般", "不喜欢", "疑似不适"], selection: $draft.reaction, tint: tint)
            TagGrid(chips: ["尝新", "常吃", "少量", "多吃了"], selected: $draft.tags, tint: tint)
        }
    }
}

private struct SupplementComposer: View {
    @Binding var draft: HealthRecordDraft
    let tint: Color
    private let units = ["滴", "粒", "ml", "袋"]

    var body: some View {
        ComposerCard(title: "补充类型和剂量", icon: "pills", tint: tint) {
            TagGrid(chips: HealthRecordKind.supplement.design.chips, selected: $draft.tags, tint: tint)
            TextField("比如：维D、益生菌", text: $draft.title)
                .healthTextField()
            AmountStepper(title: "本次剂量", value: $draft.amountValue, unit: draft.amountUnit ?? "滴", range: 0...20, step: 1, tint: tint)
            HStack {
                ForEach(units, id: \.self) { unit in
                    SelectableChip(text: unit, selected: draft.amountUnit == unit, tint: tint) {
                        draft.amountUnit = unit
                    }
                }
            }
            TagGrid(chips: ["早上", "中午", "晚上", "睡前"], selected: $draft.tags, tint: tint)
        }
        .onAppear {
            if draft.amountUnit == nil { draft.amountUnit = "滴" }
        }
    }
}

private struct WaterComposer: View {
    @Binding var draft: HealthRecordDraft
    let todayTotal: Double
    let tint: Color
    private let amounts: [Double] = HealthRecordKind.water.design.quickAmounts

    var body: some View {
        ComposerCard(title: "小水壶喝了多少", icon: "drop.fill", tint: tint) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 82, height: 82)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(draft.amountValue.map { "本次 \(Int($0)) ml" } ?? "点一下快速记录")
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("今日已记录 \(Int(todayTotal + (draft.amountValue ?? 0))) ml")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(amounts, id: \.self) { amount in
                    Button {
                        draft.amountValue = amount
                        draft.amountUnit = "ml"
                        draft.title = "喝水"
                    } label: {
                        Text("\(Int(amount)) ml")
                            .font(BubuTheme.Font.headline.weight(.bold))
                            .foregroundStyle(draft.amountValue == amount ? tint : BubuTheme.Color.warmBrown)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background((draft.amountValue == amount ? tint.opacity(0.18) : BubuTheme.Color.cream.opacity(0.7)),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            AmountStepper(title: "微调水量", value: $draft.amountValue, unit: "ml", range: 10...500, step: 10, tint: tint)
            TagGrid(chips: HealthRecordKind.water.design.chips, selected: $draft.tags, tint: tint)
        }
    }
}

private struct SleepComposer: View {
    @Binding var draft: HealthRecordDraft
    let tint: Color

    var body: some View {
        ComposerCard(title: "睡眠时间", icon: "moon.zzz.fill", tint: tint) {
            DatePicker("入睡", selection: Binding(
                get: { draft.startAt ?? draft.recordedAt },
                set: { draft.startAt = $0; draft.title = draft.tags.first ?? "睡眠" }
            ), displayedComponents: [.date, .hourAndMinute])
            DatePicker("醒来", selection: Binding(
                get: { draft.endAt ?? Date.now },
                set: { draft.endAt = $0; draft.title = draft.tags.first ?? "睡眠" }
            ), displayedComponents: [.date, .hourAndMinute])
            if let start = draft.startAt, let end = draft.endAt, end > start {
                Label("睡了 \(HealthRecordDraft.durationText(from: start, to: end))", systemImage: "clock")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            TagGrid(chips: HealthRecordKind.sleep.design.chips, selected: $draft.tags, tint: tint)
        }
    }
}

private struct SymptomComposer: View {
    @Binding var draft: HealthRecordDraft
    let tint: Color

    var body: some View {
        ComposerCard(title: "观察症状", icon: "cross.case.fill", tint: tint) {
            TagGrid(chips: HealthRecordKind.symptom.design.chips, selected: $draft.tags, tint: BubuTheme.Color.danger)
            TemperatureStepper(value: $draft.temperatureCelsius)
            VStack(alignment: .leading, spacing: 8) {
                Text("严重程度")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                HStack {
                    ForEach(["轻微", "观察中", "需要关注", "已就医"], id: \.self) { severity in
                        SelectableChip(text: severity, selected: draft.severity == severity, tint: BubuTheme.Color.danger) {
                            draft.severity = severity
                        }
                    }
                }
            }
            TextField("药物、护理或变化备注", text: $draft.detail, axis: .vertical)
                .lineLimit(3...6)
                .healthTextField()
        }
    }
}

private struct CheckupComposer: View {
    @Binding var draft: HealthRecordDraft
    let tint: Color

    var body: some View {
        ComposerCard(title: "体检数据", icon: "stethoscope", tint: tint) {
            TagGrid(chips: HealthRecordKind.checkup.design.chips, selected: $draft.tags, tint: tint)
            TextField("体检项目或疫苗名称", text: $draft.title)
                .healthTextField()
            VStack(spacing: 10) {
                AmountStepper(title: "身高", value: $draft.heightCm, unit: "cm", range: 30...140, step: 0.5, tint: tint)
                AmountStepper(title: "体重", value: $draft.weightKg, unit: "kg", range: 1...40, step: 0.1, tint: tint)
                AmountStepper(title: "头围", value: $draft.headCircumferenceCm, unit: "cm", range: 20...70, step: 0.5, tint: tint)
            }
            AmountStepper(title: "其它数值", value: $draft.amountValue, unit: draft.amountUnit ?? "cm", range: 0...130, step: 0.5, tint: tint)
            HStack {
                ForEach(["cm", "kg", "针", "颗"], id: \.self) { unit in
                    SelectableChip(text: unit, selected: draft.amountUnit == unit, tint: tint) {
                        draft.amountUnit = unit
                    }
                }
            }
            TextField("医生建议、头围、体重、牙齿等补充", text: $draft.detail, axis: .vertical)
                .lineLimit(3...6)
                .healthTextField()
        }
        .onAppear {
            if draft.amountUnit == nil { draft.amountUnit = "cm" }
        }
    }
}

private struct DetailNoteCard: View {
    @Binding var draft: HealthRecordDraft
    let tint: Color

    var body: some View {
        ComposerCard(title: "时间和备注", icon: "calendar", tint: tint) {
            DatePicker("记录时间", selection: $draft.recordedAt, displayedComponents: [.date, .hourAndMinute])
            if draft.detail.isEmpty {
                TextField("补充一点观察，比如吃完状态、睡醒精神……", text: $draft.detail, axis: .vertical)
                    .lineLimit(2...5)
                    .healthTextField()
            }
        }
    }
}

private struct HealthDisclaimerCard: View {
    let kind: HealthRecordKind

    var body: some View {
        Label(kind == .symptom ? "家庭观察不替代医生判断；高热、精神差或症状加重请及时就医。" : "健康记录只用于家庭观察，不替代医生建议。",
              systemImage: "heart.text.square")
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(BubuTheme.Color.card.opacity(0.72), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }
}

private struct ComposerCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            content()
        }
        .padding()
        .background(BubuTheme.Color.card.opacity(0.86), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        }
        .bubuCardShadow()
    }
}

private struct TagGrid: View {
    let chips: [String]
    @Binding var selected: [String]
    let tint: Color

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                SelectableChip(text: chip, selected: selected.contains(chip), tint: tint) {
                    if selected.contains(chip) {
                        selected.removeAll { $0 == chip }
                    } else {
                        selected.append(chip)
                    }
                }
            }
        }
    }
}

private struct ReactionChips: View {
    let options: [String]
    @Binding var selection: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("布布的反应")
                .font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    SelectableChip(text: option, selected: selection == option, tint: tint) {
                        selection = selection == option ? "" : option
                    }
                }
            }
        }
    }
}

private struct SelectableChip: View {
    let text: String
    let selected: Bool
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? tint : tint.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AmountStepper: View {
    let title: String
    @Binding var value: Double?
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                Text(value.map { "\(HealthRecordDraft.cleanAmount($0))\(unit)" } ?? "未填写")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
            }
            Spacer()
            HStack(spacing: 4) {
                TextField("输入", text: numericText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 62)
                if value != nil {
                    Text(unit)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Stepper("", value: Binding(
                get: { value ?? range.lowerBound },
                set: { value = min(max($0, range.lowerBound), range.upperBound) }
            ), in: range, step: step)
            .labelsHidden()
            .tint(tint)
        }
        .padding(12)
        .background(BubuTheme.Color.cream.opacity(0.65), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    private var numericText: Binding<String> {
        Binding {
            value.map { HealthRecordDraft.cleanAmount($0) } ?? ""
        } set: { raw in
            let text = raw
                .replacingOccurrences(of: "，", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                value = nil
                return
            }
            if let parsed = Double(text) {
                value = min(max(parsed, range.lowerBound), range.upperBound)
            }
        }
    }
}

private struct TemperatureStepper: View {
    @Binding var value: Double?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("体温")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                Text(value.map { String(format: "%.1f℃", $0) } ?? "未记录")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
            }
            Spacer()
            TextField("输入", text: temperatureText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Stepper("", value: Binding(
                get: { value ?? 36.5 },
                set: { value = min(max($0, 34.0), 42.0) }
            ), in: 34...42, step: 0.1)
            .labelsHidden()
            .tint(BubuTheme.Color.danger)
        }
        .padding(12)
        .background(BubuTheme.Color.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    private var temperatureText: Binding<String> {
        Binding {
            value.map { String(format: "%.1f", $0) } ?? ""
        } set: { raw in
            let text = raw
                .replacingOccurrences(of: "，", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                value = nil
                return
            }
            if let parsed = Double(text) {
                value = min(max(parsed, 34.0), 42.0)
            }
        }
    }
}

private extension HealthRecordDraft {
    mutating func toggleTag(_ tag: String) {
        if tags.contains(tag) {
            tags.removeAll { $0 == tag }
        } else {
            tags.append(tag)
        }
    }
}

private extension View {
    func healthTextField() -> some View {
        self
            .font(BubuTheme.Font.body)
            .padding(12)
            .background(BubuTheme.Color.cream.opacity(0.65), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
