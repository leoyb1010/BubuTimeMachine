import SwiftUI
import SwiftData
import UIKit

/// A day in her kindergarten life, not a second generic timeline or a feature billboard.
struct SchoolJournalHome: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var dateSelection
    @State private var day = Calendar.current.startOfDay(for: Date.now)
    @State private var composing = false
    @State private var calendarOpen = false
    @State private var scrollRevision = 0

    private var week: [Date] {
        let weekday = Calendar.current.component(.weekday, from: day)
        let start = Calendar.current.date(byAdding: .day, value: weekday == 1 ? -6 : 2 - weekday, to: day) ?? day
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text("幼儿园").font(.system(size: 27, weight: .heavy, design: .rounded))
                    Spacer()
                    NavigationLink { SchoolJournalHistory() } label: {
                        headerAction("历史", symbol: "clock.arrow.circlepath", filled: false)
                    }.accessibilityIdentifier("school.history")
                    Button { composing = true } label: {
                        headerAction("记录", symbol: "plus", filled: true)
                    }.accessibilityIdentifier("journal.primary")
                }.buttonStyle(.plain)
                ZStack(alignment: .bottom) {
                    Image(systemName: "heart.fill").font(.system(size: 12)).rotationEffect(.degrees(-18))
                        .foregroundStyle(SchoolPalette.coral.opacity(0.6)).offset(x: -70, y: -22).accessibilityHidden(true)
                    Image("SchoolGirl").resizable().scaledToFit().frame(width: 118, height: 82)
                        .offset(x: -8, y: -10).accessibilityHidden(true)
                        .opacity(typeSize.isAccessibilitySize ? 0 : 1)
                    HStack(alignment: .bottom, spacing: 0) {
                        VStack(alignment: .leading, spacing: 7) {
                            Button { calendarOpen = true } label: {
                                Text("\(Calendar.current.component(.month, from: day))月\(Calendar.current.component(.day, from: day))日")
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                            }.buttonStyle(.plain).accessibilityIdentifier("school.choose-date")
                            Text(day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                                .font(.caption).foregroundStyle(SchoolPalette.secondary)
                            Text("今天也很棒呀！").font(.system(size: 11)).foregroundStyle(SchoolPalette.ink)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        weekStrip.frame(width: 158)
                    }.padding(.bottom, 18)
                }.frame(height: typeSize.isAccessibilitySize ? 140 : 52)
                SchoolDayEntries(day: day, onCorrectedDate: { value in selectDay(value) })
                NavigationLink { MemoryJournalView(kind: .saying) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "quote.bubble.fill").foregroundStyle(env.theme.theme.textAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("放学路上的布布说").font(BubuTheme.Font.body.weight(.semibold))
                            Text("留住她今天想告诉你的话").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(.vertical, 12)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 10).bubuContentColumn(760)
            .id("school.day-top")
        }
        .onChange(of: scrollRevision) { _, _ in
            proxy.scrollTo("school.day-top", anchor: .top)
        }
        }
        .foregroundStyle(BubuTheme.Color.warmBrown)
        .background {
            if colorScheme == .dark { BubuTheme.Color.background.ignoresSafeArea() }
            else { Image("SchoolPaper").resizable().scaledToFill().ignoresSafeArea().clipped() }
        }
        .tint(env.theme.theme.textAccent)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $composing) {
            MemoryJournalComposer(kind: .school, initialDate: day, onSaved: { value in selectDay(value) })
        }
        .sheet(isPresented: $calendarOpen) {
            NavigationStack {
                DatePicker("回看哪一天", selection: Binding(get: { day }, set: { value in selectDay(value) }), in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding()
                    .navigationTitle("翻到这一天").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("看这天") { calendarOpen = false } } }
            }.presentationDetents([.medium, .large])
        }
        .accessibilityIdentifier("school.home")
        .bubuSensoryFeedback(.selection, trigger: day)
        .overlay(alignment: .bottom) {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-uitest-motion-check") {
                Text(reduceMotion ? "减少动态效果已启用" : "标准动效").font(.caption2)
                    .padding(6).background(BubuTheme.Color.card)
            }
            #endif
        }
        .task {
            #if DEBUG && targetEnvironment(simulator)
            SchoolJournalFixture.insertIfRequested(into: modelContext)
            if ProcessInfo.processInfo.arguments.contains("-uitest-in-memory"),
               ProcessInfo.processInfo.arguments.contains("-uitest-legacy-school-draft"),
               let data = UIImage(named: "BubuPlaying")?.jpegData(compressionQuality: 0.9),
               let fileName = try? env.mediaStore.savePhoto(data) {
                let hash = MediaStore.sha256Hex(data)
                var report = SchoolDailyReport()
                report.candidates[SchoolReportField.morningSnack.rawValue] = "90%"
                report.sourceHash = hash
                var draft = MemoryJournalDraft(id: UUID(), kind: .school, date: .now, source: "旧版识别原文")
                draft.schoolReport = report
                let file = JournalMediaFile(id: UUID(), fileName: fileName, thumbnail: nil, hash: hash, isVideo: false, isSchoolReport: true)
                try? JournalDraftStore.save(.init(draft: draft, files: [file], voice: nil), to: JournalDraftStore.file(for: .school))
                composing = true
            }
            if ProcessInfo.processInfo.arguments.contains("-uitest-in-memory"),
               ProcessInfo.processInfo.arguments.contains("-uitest-school-import") { composing = true }
            #endif
        }
    }

    private func headerAction(_ title: String, symbol: String, filled: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 23, weight: .semibold))
                .foregroundStyle(filled ? .white : SchoolPalette.ink)
                .frame(width: 36, height: 36)
                .background(filled ? SchoolPalette.coral : BubuTheme.Color.card, in: Circle())
            Text(title).font(.system(size: 10))
        }.frame(minWidth: 44, minHeight: 48)
    }

    private var weekStrip: some View {
        HStack(spacing: 1) {
            Button { shiftWeek(-7) } label: {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).frame(width: 15, height: 44)
            }.accessibilityLabel("上一周")
            // Five consecutive days keep Saturday/Sunday selectable, unlike a fixed school-week strip.
            ForEach((-2...2), id: \.self) { offset in
                let date = Calendar.current.date(byAdding: .day, value: offset, to: day) ?? day
                let selected = offset == 0
                Button { selectDay(date) } label: {
                    VStack(spacing: 5) {
                        Text(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: date) - 1])
                            .font(.system(size: 8))
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded)).monospacedDigit()
                    }.frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selected ? .white : SchoolPalette.ink)
                        .background(selected ? SchoolPalette.coral : .clear, in: Capsule())
                }.buttonStyle(.plain).disabled(date > Date.now)
                    .accessibilityLabel(BubuDateFormat.shortDate(date))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button { shiftWeek(7) } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).frame(width: 15, height: 44)
            }.accessibilityLabel("下一周").disabled(Calendar.current.isDateInToday(day))
        }.padding(5).background(BubuTheme.Color.card.opacity(0.85), in: Capsule())
    }
    private func shiftWeek(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: offset, to: day) {
            selectDay(min(next, Calendar.current.startOfDay(for: .now)))
        }
    }
    // Explicit closure adapters above avoid an Xcode 26.6 IRGen crash when an
    // actor-isolated Date method reference is converted into a SwiftUI callback.
    private func selectDay(_ value: Date) {
        withAnimation(reduceMotion ? nil : BubuMotion.quick) {
            day = Calendar.current.startOfDay(for: value)
            scrollRevision += 1
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Synthetic, in-memory-only visual fixture. Never available in signed Release builds.
private enum SchoolJournalFixture {
    static func insertIfRequested(into context: ModelContext) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uitest-in-memory"), arguments.contains("-uitest-school-report") else { return }
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000009217")!
        guard (try? context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id }))) == 0 else { return }
        var report = SchoolDailyReport()
        for field in SchoolReportField.meals { report[field] = "90%；食量佳；速度普通" }
        report[.fruit] = "100%；食量佳；速度快"
        report[.milkFirst] = "10:20；牛奶 120ml；喝完"
        report[.milkSecond] = "15:00；牛奶 100ml；剩余 20ml"
        report[.nap] = "12:17–14:30"; report[.napQuality] = "很安静"
        report[.temperatureAM] = "36.6°C"; report[.temperatureNoon] = "36.7°C"; report[.temperaturePM] = "36.3°C"
        report[.mood] = "佳"; report[.participation] = "主动"; report[.peers] = "佳"
        report[.specialBehavior] = "主动把积木递给小伙伴（验收样例）"
        report[.health] = "健康"; report[.appearance] = "整洁良好"
        report[.bowel] = "有排便"; report[.bowelFirst] = "10:30；便量正常；状况正常；颜色正常"
        report[.supplies] = "湿巾、袜子、上衣"; report[.notice] = "明天带上替换衣物（验收样例）"
        report[.reportedName] = "布布（验收样例）"; report[.reportedAge] = "2岁4个月"
        report.confirmed = true
        var draft = MemoryJournalDraft(id: id, kind: .school, date: .now)
        draft.schoolReport = report
        let entry = Entry(happenedAt: draft.date, authorRole: "妈妈", note: draft.note)
        entry.id = id
        context.insert(entry)
        try? context.save()
    }
}
#endif

private struct SchoolDayEntries: View {
    let onCorrectedDate: (Date) -> Void
    @Query private var entries: [Entry]
    @Query private var profiles: [ChildProfile]
    @Environment(AppEnvironment.self) private var env
    init(day: Date, onCorrectedDate: @escaping (Date) -> Void) {
        self.onCorrectedDate = onCorrectedDate
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let bareMarker = MemoryJournalKind.school.marker
        let marker = bareMarker + "\n"
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate {
            !$0.isArchived && $0.happenedAt >= start && $0.happenedAt < end
                && ($0.note == bareMarker || ($0.note?.starts(with: marker) ?? false))
        }, sortBy: [SortDescriptor(\Entry.createdAt, order: .reverse)])
        descriptor.fetchLimit = 80
        _entries = Query(descriptor)
    }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    Label("这一天，等你来收好", systemImage: "doc.text.image")
                        .font(BubuTheme.Font.headline).foregroundStyle(env.theme.theme.textAccent)
                    Text("一张亲子桥，留下她吃饭、午睡和交朋友的小日常。")
                        .font(BubuTheme.Font.body)
                    HStack(spacing: 18) {
                        Label("餐食", systemImage: "fork.knife")
                        Label("午睡", systemImage: "moon.zzz")
                        Label("表现", systemImage: "face.smiling")
                    }.font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                    Divider()
                    Label("老师的照片和视频，也收在同一天", systemImage: "photo.on.rectangle.angled")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md))
            }
            ForEach(entries) { entry in
                if let report = SchoolDailyReport.from(note: entry.note) {
                    SchoolReportCard(entry: entry, report: report, profileName: profiles.first?.name, profileBirthday: profiles.first?.birthday,
                                     onCorrectedDate: onCorrectedDate)
                } else {
                    NavigationLink { EntryDetailView(entry: entry) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(entry.sortedMedia.isEmpty ? "今天的小故事" : "老师镜头里的她", systemImage: entry.sortedMedia.isEmpty ? "pencil.line" : "photo.stack")
                                .font(BubuTheme.Font.headline)
                            if let cover = entry.coverMedia {
                                MediaThumbnail(media: cover, mediaStore: env.mediaStore).frame(height: 200)
                            }
                            Text(MemoryJournalKind.school.body(entry.note)).font(BubuTheme.Font.body).lineLimit(5)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md))
                    }.buttonStyle(.plain)
                }
            }
            if entries.count == 80 {
                NavigationLink("这一天还有更多，去历史记录查看") { SchoolJournalHistory() }
            }
        }
    }
}

private struct SchoolJournalHistory: View {
    @State private var search = ""
    @State private var limit = 40
    var body: some View {
        ScrollView { JournalEntries(kind: .school, search: search, limit: limit) { limit += 40 }.padding().bubuContentColumn(760) }
            .background(BubuThemedBackground().ignoresSafeArea()).navigationTitle("幼儿园回忆")
            .searchable(text: $search, prompt: "找老师的话、餐食或小故事")
            .onChange(of: search) { _, _ in limit = 40 }
    }
}
