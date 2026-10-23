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
    @Environment(\.scenePhase) private var scenePhase
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
            VStack(alignment: .leading, spacing: 12) {
                // 日期与吉祥物一行；周历单独占满整行，日期格不小于 44pt。
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Button { calendarOpen = true } label: {
                            HStack(spacing: 4) {
                                Text("\(Calendar.current.component(.month, from: day))月\(Calendar.current.component(.day, from: day))日")
                                    .font(BubuTheme.Font.headline)
                                Image(systemName: "chevron.down").font(.caption.weight(.bold)).accessibilityHidden(true)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("school.choose-date")
                            .accessibilityHint("打开日历选择哪一天")
                        Text(day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                            .font(BubuTheme.Font.caption).foregroundStyle(SchoolPalette.secondary)
                        Text("今天也很棒呀！").font(.system(.footnote, design: .rounded)).foregroundStyle(SchoolPalette.ink)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !typeSize.isAccessibilitySize {
                        Image("SchoolGirl").resizable().scaledToFit().frame(width: 118, height: 82)
                            .overlay(alignment: .topLeading) {
                                Image(systemName: "heart.fill").font(.caption).rotationEffect(.degrees(-18))
                                    .foregroundStyle(SchoolPalette.coral.opacity(0.6)).offset(x: -10, y: 2)
                            }
                            .accessibilityHidden(true)
                    }
                }
                weekStrip
                NavigationLink { DailyLearningHomeView(initialDay: day) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "graduationcap.fill").foregroundStyle(env.theme.theme.textAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Calendar.current.isDateInToday(day) ? "今天的每日学习" : "这一天的每日学习")
                                .font(BubuTheme.Font.body.weight(.semibold))
                            Text("家长上传课程视频，核对后和布布一起玩")
                                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(.vertical, 14).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("school.learning-entry")
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
                    }.padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, BubuTheme.Spacing.item).padding(.top, 4).padding(.bottom, BubuTheme.Spacing.item).bubuContentColumn(760)
            .id("school.day-top")
        }
        .onChange(of: scrollRevision) { _, _ in
            proxy.scrollTo("school.day-top", anchor: .top)
        }
        }
        .foregroundStyle(BubuTheme.Color.warmBrown)
        .background {
            // 纸张铺满整屏（含状态栏）：GeometryReader 先忽略安全区拿到全屏尺寸，再在全屏范围内裁切，
            // 底下垫一层与纸张同色的底色，状态栏下不会再露出白条。
            if colorScheme == .dark { BubuTheme.Color.background.ignoresSafeArea() }
            else {
                GeometryReader { proxy in
                    Image("SchoolPaper").resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }
                .background(SchoolPalette.paper)
                .ignoresSafeArea()
            }
        }
        .tint(env.theme.theme.textAccent)
        // 系统导航栏：「历史」「记录」是带图标和标题的工具栏按钮，Duo 外屏 / 内屏横拿时随栏竖排到侧边。
        .navigationTitle("幼儿园")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SchoolJournalHistory() } label: {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("school.history")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { composing = true } label: { Label("记录", systemImage: "plus") }
                    .accessibilityIdentifier("journal.primary")
            }
            .bubuVisibilityPriority(.high)
        }
        .sheet(isPresented: $composing) {
            MemoryJournalComposer(kind: .school, initialDate: day, onSaved: { value in selectDay(value) })
        }
        .sheet(isPresented: $calendarOpen) {
            SchoolDatePickerSheet(selection: Binding(get: { day }, set: { value in selectDay(value) })) {
                calendarOpen = false
            }
        }
        .accessibilityIdentifier("school.home")
        .bubuSensoryFeedback(.selection, trigger: day)
        // 每日学习的入口在这一页：回到前台时顺手把锁屏上留下的课程上传活动推进或收尾。
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await BubuActivityController.reconcileCourseUploads(client: BubuLearningClient(env: env)) }
        }
        .overlay(alignment: .bottom) {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-uitest-motion-check") {
                Text(reduceMotion ? "减少动态效果已启用" : "标准动效").font(.caption2)
                    .padding(6).background(BubuTheme.Color.card)
            }
            #endif
        }
        .task {
            await BubuActivityController.reconcileCourseUploads(client: BubuLearningClient(env: env))
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

    @ViewBuilder
    private var weekStrip: some View {
        HStack(spacing: 2) {
            Button { shiftWeek(-7) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("上一周")
            // 大字号下五个日期格放不下：改成可横向滑动的一行，格子保持 ≥ 64pt。
            if typeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) { dayCells(minWidth: 72) }
                }
            } else {
                dayCells(minWidth: 44)
            }
            Button { shiftWeek(7) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("下一周").disabled(Calendar.current.isDateInToday(day))
        }
        .padding(4)
        .background(BubuTheme.Color.card.opacity(0.85), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
    }

    /// Five consecutive days keep Saturday/Sunday selectable, unlike a fixed school-week strip.
    private func dayCells(minWidth: CGFloat) -> some View {
        ForEach((-2...2), id: \.self) { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: day) ?? day
            let selected = offset == 0
            Button { selectDay(date) } label: {
                VStack(spacing: 2) {
                    Text(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: date) - 1])
                        .font(.system(.caption2, design: .rounded))
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(.body, design: .rounded).weight(selected ? .bold : .medium)).monospacedDigit()
                }
                .frame(maxWidth: .infinity, minHeight: 52).frame(minWidth: minWidth)
                .foregroundStyle(selected ? .white : SchoolPalette.ink)
                .background(selected ? SchoolPalette.coralInk : .clear,
                            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(date > Date.now)
                .accessibilityLabel(BubuDateFormat.shortDate(date))
                .accessibilityAddTraits(selected ? .isSelected : [])
        }
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
                    SchoolReportCard(entry: entry, report: report, profileName: ChildProfile.canonical(from: profiles)?.name, profileBirthday: ChildProfile.canonical(from: profiles)?.birthday,
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

/// 翻到某一天：弹窗高度跟着日历本身走（矮屏放不下时在弹窗里滚动），不再固定半屏。
private struct SchoolDatePickerSheet: View {
    let selection: Binding<Date>
    let onDone: () -> Void
    @State private var contentHeight: CGFloat = 380
    @State private var barHeight: CGFloat = 56

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker("回看哪一天", selection: selection, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { barHeight = $0 }
            .navigationTitle("翻到这一天").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("看这天", systemImage: "calendar", role: .confirm) { onDone() }
                }
            }
        }
        .bubuLayoutRoot()
        .presentationDetents([.height(contentHeight + barHeight)])
        .presentationSizing(.fitted)
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
