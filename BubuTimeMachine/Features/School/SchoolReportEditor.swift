import SwiftUI

struct SchoolReportEditor: View {
    @Binding var report: SchoolDailyReport
    let sourceFile: JournalMediaFile?
    @Environment(AppEnvironment.self) private var env
    @State private var showingOriginal = false
    @FocusState private var editingField: SchoolReportField?
    @State private var expandedSection: String? = "一天四餐"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.image").font(.title2).foregroundStyle(env.theme.theme.textAccent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(report.automaticallyImported == true ? "亲子桥 · 数据调整" : "亲子桥 · 对照核对").font(BubuTheme.Font.headline)
                    Text(report.automaticallyImported == true ? "读到的数据已经填好；有误直接修改，原图一直保留。" : "手工填写后收好，空白栏目可以留空。")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            if let sourceFile {
                Button { showingOriginal = true } label: {
                    Label("放大原表，对照填写", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(BubuTheme.Font.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("school.original")
                .sheet(isPresented: $showingOriginal) {
                    SchoolOriginalSheet(fileID: sourceFile.id, fileName: sourceFile.fileName, thumbnail: sourceFile.thumbnail)
                }
            }
            if !report.dateEvidence.isEmpty {
                Label("原文日期候选：\(report.dateEvidence)\n手写日期可能识别错，请核对上方「发生在」。", systemImage: "calendar.badge.exclamationmark")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            ForEach(Array(SchoolReportField.sections.enumerated()), id: \.offset) { index, section in
                DisclosureGroup(isExpanded: Binding(get: { expandedSection == section.title },
                    set: { open in
                        withAnimation(reduceMotion ? nil : BubuMotion.quick) { expandedSection = open ? section.title : nil }
                    })) {
                    fields(section.fields)
                    if index == 3 || index == 4 {
                        Text("仅记录老师观察，不自动写入健康趋势。")
                            .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                } label: {
                    HStack {
                        Label(section.title, systemImage: section.symbol).font(BubuTheme.Font.headline)
                        Spacer(minLength: 8)
                        let filled = section.fields.filter { !report[$0].isEmpty }.count
                        if filled > 0 { Text("已填 \(filled) 项").font(.caption).foregroundStyle(BubuTheme.Color.secondaryText) }
                    }
                }
            }
            if !report.confirmed && report.automaticallyImported != true {
                Text("核对后，在页面底部确认即可收好。修改内容或日期会重新要求确认。")
                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .padding(16)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md))
        .toolbar {
            if editingField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成输入") { editingField = nil }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("school.keyboard.done")
                        .accessibilityHint("保留已填写的内容并收起键盘，继续核对表单")
                }
            }
        }
    }

    private func fields(_ fields: [SchoolReportField]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(fields, id: \.rawValue) { field in
                if SchoolReportField.meals.contains(field) {
                    mealFields(field)
                } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(field.rawValue).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        Spacer()
                        if !field.choices.isEmpty {
                            Menu("选老师勾的") {
                                ForEach(field.choices, id: \.self) { choice in
                                    Button(choice) { report.choose(choice, for: field) }
                                }
                                Button("留空") { report[field] = "" }
                            }.font(BubuTheme.Font.caption).accessibilityLabel("\(field.rawValue)，选择老师勾选的状态")
                        }
                    }
                    TextField(field.prompt, text: Binding(get: { report[field] }, set: { report[field] = $0 }), axis: .vertical)
                        .lineLimit(1...3).font(BubuTheme.Font.body)
                        .padding(10).background(BubuTheme.Color.background, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs))
                        .focused($editingField, equals: field)
                        .accessibilityIdentifier("school.field.\(field.rawValue)")
                    if let candidate = report.candidates[field.rawValue], report[field].isEmpty {
                        Button { report[field] = candidate } label: {
                            Label("识别候选 \(candidate) · 核对后采用", systemImage: "text.viewfinder")
                                .font(BubuTheme.Font.caption).frame(minHeight: 36, alignment: .leading)
                        }
                    }
                }
                }
            }
        }.padding(.top, 8)
    }

    private func mealFields(_ field: SchoolReportField) -> some View {
        let meal = SchoolMeal(report[field])
        return VStack(alignment: .leading, spacing: 10) {
            Text(field.rawValue).font(BubuTheme.Font.body.weight(.semibold))
            HStack(spacing: 12) {
                Text("食量").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                TextField("如 90%", text: Binding(get: { SchoolMeal(report[field]).amount },
                    set: { report.setMealAmount($0, for: field) }))
                    .font(BubuTheme.Font.body).padding(10)
                    .background(BubuTheme.Color.background, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs))
                    .focused($editingField, equals: field)
                    .submitLabel(.done)
                    .onSubmit { editingField = nil }
                    .accessibilityIdentifier("school.field.\(field.rawValue)")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("食量评价").font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                Picker("\(field.rawValue)食量评价", selection: Binding(get: { SchoolMeal(report[field]).rating },
                    set: { report.choose("食量" + $0, for: field) })) {
                    Text("未填").tag("")
                    ForEach(["佳", "普通", "不佳"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("school.appetite.\(field.rawValue)")
                Text("进食速度").font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                Picker("\(field.rawValue)进食速度", selection: Binding(get: { SchoolMeal(report[field]).speed },
                    set: { report.choose("速度" + $0, for: field) })) {
                    Text("未填").tag("")
                    ForEach(["快", "普通", "慢"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("school.speed.\(field.rawValue)")
            }
            if let candidate = report.candidates[field.rawValue], meal.amount.isEmpty {
                Button { report.setMealAmount(candidate, for: field) } label: {
                    Label("候选食量 \(candidate) · 核对后采用", systemImage: "text.viewfinder")
                        .font(BubuTheme.Font.caption).frame(minHeight: 36)
                }
            }
            if !meal.notes.isEmpty {
                Text(meal.notes.joined(separator: "；")).font(BubuTheme.Font.caption)
            }
        }.padding(.vertical, 6)
    }
}

/// Uses the existing bounded image loader. Zoom the report without re-decoding full originals.
struct SchoolOriginalSheet: View {
    let fileID: UUID
    let fileName: String?
    let thumbnail: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var loading = true
    @State private var scale: CGFloat = 1
    @State private var startingScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: geometry.size.width * scale)
                            .accessibilityLabel("老师发来的原始亲子桥表，可双指放大")
                            .gesture(MagnifyGesture().onChanged { scale = min(4, max(1, startingScale * $0.magnification)) }
                                .onEnded { _ in startingScale = scale })
                    } else if loading { ProgressView().frame(width: geometry.size.width, height: 200) }
                    else { ContentUnavailableView("原图暂未下载", systemImage: "icloud.and.arrow.down", description: Text("原始文件仍归属于这条时光，请在同步中心核对下载状态。")) }
                }
            }
            .navigationTitle("亲子桥原表").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("看好了") { dismiss() } } }
            .task {
                image = await env.thumbnails.image(mediaId: fileID, thumbnailFileName: nil,
                    localFileName: fileName, isPhoto: true, size: .detail)
                loading = false
            }
        }
    }
}
