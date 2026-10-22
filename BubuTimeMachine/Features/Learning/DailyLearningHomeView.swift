import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - 每日学习
/// 独立入口：家长按日期上传幼儿园课程视频，服务端解析出原声互动课，家长核对后开放给布布。
/// 与「时光」完全分开：不会从照片库里挑课程，课程原片也不会出现在时光里。
struct DailyLearningHomeView: View {
    var initialDay: Date = .now
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if let client = BubuLearningClient(env: env) {
                DailyLearningHome(client: client, initialDay: initialDay).id(client.scope)
            } else {
                ZStack {
                    BubuThemedBackground().ignoresSafeArea()
                    ContentUnavailableView {
                        Label("连接家庭服务后开始每日学习", systemImage: "graduationcap")
                    } description: {
                        Text("上传幼儿园课程视频后，家里的服务器会整理出老师原声的互动小课。请先在设置里连接家庭服务器和账号。")
                    }
                }
            }
        }
        .navigationTitle("每日学习")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("learning.home")
    }
}

struct DailyLearningHome: View {
    let client: BubuLearningClient
    @Environment(BubuRouter.self) private var router
    @State private var day: Date
    @State private var context: LearningContextDTO?
    @State private var courses: [LearningCourseDTO] = []
    @State private var weekDays: Set<String> = []
    @State private var recent: [LearningCourseDTO] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var uploading = false
    @State private var opened: LearningCourseDTO?
    @State private var review: String?
    @State private var weeklyReport = false
    @State private var refreshTick = 0

    init(client: BubuLearningClient, initialDay: Date) {
        self.client = client
        _day = State(initialValue: initialDay)
    }

    private var dayString: String { BubuLearningDates.dayString(day) }
    private var canReview: Bool { context?.user.canReview ?? false }
    private var hasProcessing: Bool { courses.contains { $0.state == "processing" } }

    var body: some View {
        ZStack {
            BubuThemedBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.item) {
                    weekHeader
                    if canReview { uploadButton }
                    coursesSection
                    reviewSection
                    weeklyReportCard
                    if !recentOtherDays.isEmpty { recentSection }
                }
                .padding(BubuTheme.Spacing.item)
                .bubuContentColumn(820)
            }
            .refreshable { await load() }
        }
        .toolbar {
            if canReview {
                ToolbarItem(placement: .primaryAction) {
                    Button { uploading = true } label: { Label("上传课程", systemImage: "plus") }
                        .accessibilityIdentifier("learning.upload.toolbar")
                }
            }
        }
        .task(id: "\(dayString)|\(refreshTick)") { await load() }
        .task(id: router.pendingLearningDay) {
            guard let raw = router.pendingLearningDay else { return }
            router.pendingLearningDay = nil
            if let target = BubuLearningDates.day(raw) { day = target }
        }
        .task(id: hasProcessing) {
            // Analysis runs in the background on the family server; keep the status fresh.
            while hasProcessing && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await load(quiet: true)
            }
        }
        .sheet(isPresented: $uploading) {
            CourseUploadSheet(client: client, day: day, childID: context?.defaultChild) { course in
                day = BubuLearningDates.day(course.schoolDate) ?? day
                refreshTick += 1
            }
        }
        .navigationDestination(item: $opened) { course in
            CourseDetailView(client: client, courseID: course.id, childID: context?.defaultChild ?? course.childId,
                             canReview: canReview, onChange: { refreshTick += 1 })
        }
        .navigationDestination(item: $review) { period in
            LearningReviewView(client: client, childID: context?.defaultChild, period: period, day: dayString)
        }
        .navigationDestination(isPresented: $weeklyReport) {
            LearningWeeklyReportView(client: client, childID: context?.defaultChild, day: day)
        }
    }

    // MARK: Sections

    private var weekHeader: some View {
        LearningPanel(title: day.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))),
                    symbol: "calendar", subtitle: "按上课日期整理") {
            HStack(spacing: 6) {
                ForEach(weekDates, id: \.self) { date in
                    let key = BubuLearningDates.dayString(date)
                    let selected = key == dayString
                    Button { day = date } label: {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "zh_CN"))))
                                .font(.caption2)
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.system(.body, design: .rounded).weight(.bold))
                            Circle().fill(weekDays.contains(key) ? (selected ? Color.white : BubuTheme.Color.primary) : .clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.white : BubuTheme.Color.warmBrown)
                        .background(selected ? BubuTheme.Color.primary : BubuTheme.Color.softFill.opacity(0.45),
                                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) + (weekDays.contains(key) ? "，有课程" : ""))
                }
            }
            HStack {
                Button { shift(-7) } label: { Label("上一周", systemImage: "chevron.left") }
                Spacer()
                DatePicker("日期", selection: $day, in: ...Date.now.addingTimeInterval(86_400 * 30), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                Spacer()
                Button { shift(7) } label: { Label("下一周", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
            }
            .font(BubuTheme.Font.caption)
            .tint(BubuTheme.Color.deepRose)
        }
    }

    private var uploadButton: some View {
        Button { uploading = true } label: {
            HStack(spacing: BubuTheme.Spacing.m) {
                Image(systemName: "square.and.arrow.up.fill").font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("上传这一天的课程视频").font(BubuTheme.Font.headline)
                    Text("家长选择课程素材，自动解析老师原声，核对后开放")
                        .font(BubuTheme.Font.caption).opacity(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(BubuTheme.Spacing.l)
            .background(BubuTheme.Gradient.primaryButton,
                        in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .shadow(color: BubuTheme.Color.primary.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("learning.upload")
    }

    @ViewBuilder
    private var coursesSection: some View {
        LearningPanel(title: "这一天的课", symbol: "books.vertical.fill", subtitle: courses.isEmpty ? "" : "\(courses.count) 节") {
            if loading && courses.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if let errorText, courses.isEmpty {
                VStack(spacing: 8) {
                    Text(errorText).font(BubuTheme.Font.caption).multilineTextAlignment(.center)
                    Button("重新加载") { Task { await load() } }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity).padding()
            } else if courses.isEmpty {
                Text(canReview ? "这一天还没有课程。点上面的按钮上传老师的课堂视频。" : "这一天还没有开放的课程。")
                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                VStack(spacing: BubuTheme.Spacing.s) {
                    ForEach(courses) { course in
                        Button { opened = course } label: { CourseCard(course: course) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("learning.course")
                    }
                }
            }
        }
    }

    private var reviewSection: some View {
        LearningPanel(title: "复习", symbol: "arrow.triangle.2.circlepath", subtitle: "只用已开放的课程", accent: BubuTheme.Color.deepRose) {
            HStack(spacing: BubuTheme.Spacing.s) {
                reviewButton("本周复习", detail: "近 7 天", period: "week", tint: BubuTheme.Color.butterSurface)
                reviewButton("本月复习", detail: "近 30 天", period: "month", tint: BubuTheme.Color.mintSurface)
            }
        }
    }

    private var weeklyReportCard: some View {
        Button { weeklyReport = true } label: {
            HStack(spacing: BubuTheme.Spacing.m) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.title2)
                    .foregroundStyle(BubuTheme.Color.deepRose)
                    .frame(width: 48, height: 48)
                    .background(BubuTheme.Color.card, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("本周学习报告").font(BubuTheme.Font.headline)
                    Text("学了什么、答对多少、跟读进步和下周复习建议")
                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(BubuTheme.Color.secondaryText).accessibilityHidden(true)
            }
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .padding(BubuTheme.Spacing.l)
            .background(
                LinearGradient(colors: [BubuTheme.Color.butterSurface, BubuTheme.Color.pinkSurface],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(BubuPressableStyle())
        .accessibilityIdentifier("learning.weekly.open")
    }

    private var recentOtherDays: [LearningCourseDTO] { recent.filter { $0.schoolDate != dayString } }

    private var recentSection: some View {
        LearningPanel(title: "最近的课", symbol: "clock.arrow.circlepath", subtitle: "近 30 天，按日期积累", accent: BubuTheme.Color.deepRose) {
            VStack(spacing: BubuTheme.Spacing.s) {
                ForEach(recentOtherDays.prefix(12)) { course in
                    Button { opened = course } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(CourseDetailView.readableDay(course.schoolDate)).font(.caption.weight(.semibold))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                            CourseCard(course: course)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("learning.recent")
                }
            }
        }
    }

    private func reviewButton(_ title: String, detail: String, period: String, tint: Color) -> some View {
        Button { review = period } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(BubuTheme.Font.body.weight(.bold))
                Text(detail).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .foregroundStyle(BubuTheme.Color.warmBrown)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BubuTheme.Spacing.m)
            .background(tint, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
        }
        .buttonStyle(BubuPressableStyle())
        .accessibilityIdentifier("learning.review.\(period)")
    }

    // MARK: Data

    private var weekDates: [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = (calendar.component(.weekday, from: day) + 5) % 7  // Monday = 0
        let monday = calendar.date(byAdding: .day, value: -weekday, to: calendar.startOfDay(for: day)) ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
    }

    private func load(quiet: Bool = false) async {
        let requestedDay = dayString
        if !quiet { loading = true }
        defer { loading = false }
        do {
            if context == nil {
                context = try await client.get("api/context", as: LearningContextDTO.self)
            }
            let child = context?.defaultChild
            var base = [URLQueryItem]()
            if let child { base.append(URLQueryItem(name: "child_id", value: child)) }
            let dayQuery = base + [URLQueryItem(name: "start", value: dayString), URLQueryItem(name: "end", value: dayString)]
            let first = weekDates.first ?? day, last = weekDates.last ?? day
            let weekQuery = base + [URLQueryItem(name: "start", value: BubuLearningDates.dayString(first)),
                                    URLQueryItem(name: "end", value: BubuLearningDates.dayString(last))]
            let today = Date.now
            let monthAgo = Calendar(identifier: .gregorian).date(byAdding: .day, value: -30, to: today) ?? today
            let recentQuery = base + [URLQueryItem(name: "start", value: BubuLearningDates.dayString(monthAgo)),
                                      URLQueryItem(name: "end", value: BubuLearningDates.dayString(today))]
            // Three independent reads in parallel; polling only refreshes while a course is processing.
            async let dayList = client.get("api/courses", query: dayQuery, as: LearningCourseList.self)
            async let weekList = client.get("api/courses", query: weekQuery, as: LearningCourseList.self)
            async let recentList = client.get("api/courses", query: recentQuery, as: LearningCourseList.self)
            let (list, week, latest) = try await (dayList, weekList, recentList)
            // A slow poll for the previous day must not overwrite the newly chosen day.
            guard requestedDay == dayString else { return }
            withAnimation(BubuMotion.gentle) {
                courses = list.items
                weekDays = Set(week.items.map(\.schoolDate))
                recent = latest.items
            }
            // 刚上传的课程到了草稿/失败，就收起锁屏上的上传进度。
            BubuActivityController.syncCourseUpload(with: (list.items + latest.items).map { (id: $0.id, state: $0.state) })
            errorText = nil
            await LearningAttemptOutbox.shared.flush(client: client)
        } catch is CancellationError {
        } catch {
            if !quiet { errorText = learningErrorText(error) }
        }
    }
}

struct CourseCard: View {
    let course: LearningCourseDTO

    var body: some View {
        HStack(spacing: BubuTheme.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous).fill(BubuTheme.Color.pinkSurface)
                Image(systemName: LearningCourseKind(rawValue: course.kind)?.symbol ?? "book.fill")
                    .foregroundStyle(BubuTheme.Color.deepRose)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title).font(BubuTheme.Font.body.weight(.bold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(course.kindLabel)
                    Text("·")
                    Text("\(course.sourceCount) 个文件")
                    if course.activityCount > 0 { Text("· \(course.activityCount) 个互动") }
                }
                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
            }
            Spacer(minLength: 0)
            CourseStateBadge(state: course.state)
        }
        .foregroundStyle(BubuTheme.Color.warmBrown)
        .padding(BubuTheme.Spacing.m)
        .background(BubuTheme.Color.elevatedCard, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct CourseStateBadge: View {
    let state: String

    var body: some View {
        HStack(spacing: 4) {
            if state == "processing" { ProgressView().controlSize(.mini) }
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .accessibilityIdentifier("learning.course.state.\(state)")
    }

    private var label: String {
        switch state {
        case "processing": "解析中"
        case "uploading": "上传未完成"
        case "draft": "待家长核对"
        case "published": "可以一起学"
        case "no_lesson": "没找到原声题"
        case "failed": "解析失败"
        case "waiting": "准备中"
        default: state
        }
    }
    private var foreground: Color {
        switch state {
        case "published": .white
        case "failed", "uploading": BubuTheme.Color.danger
        default: BubuTheme.Color.warmBrown
        }
    }
    private var background: Color {
        switch state {
        case "published": BubuTheme.Color.primary
        case "draft": BubuTheme.Color.butterSurface
        case "failed", "uploading": BubuTheme.Color.danger.opacity(0.12)
        default: BubuTheme.Color.softFill
        }
    }
}

// MARK: - 上传表单

struct CourseUploadSheet: View {
    let client: BubuLearningClient
    let childID: String?
    let onUploaded: (LearningCourseDetailDTO) -> Void
    @State private var day: Date
    @State private var title = ""
    @State private var kind = LearningCourseKind.teaching
    @State private var language = "en-US"
    @State private var files: [LearningUploadFile] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var preparing = false
    @State private var uploading = false
    @State private var progressText: String?
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss

    init(client: BubuLearningClient, day: Date, childID: String?, onUploaded: @escaping (LearningCourseDetailDTO) -> Void) {
        self.client = client
        self.childID = childID
        self.onUploaded = onUploaded
        _day = State(initialValue: day)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && files.contains { $0.mimeType.hasPrefix("video/") || $0.mimeType.hasPrefix("audio/") }
            && !uploading && !preparing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("上课日期", selection: $day, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .accessibilityIdentifier("learning.upload.date")
                    TextField("课程名称，例如：水果单词", text: $title)
                        .accessibilityIdentifier("learning.upload.title")
                    Picker("课程类型", selection: $kind) {
                        ForEach(LearningCourseKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("learning.upload.kind")
                    Picker("老师讲的语言", selection: $language) {
                        Text("英文").tag("en-US")
                        Text("中文").tag("zh-CN")
                    }
                } header: {
                    Text("这是哪一节课")
                } footer: {
                    Text("一次上传就是一节课。同一天的不同课程请分开上传。")
                }
                Section {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .any(of: [.videos, .images])) {
                        Label("从相册选视频或教具照片", systemImage: "photo.on.rectangle.angled")
                    }
                    .accessibilityIdentifier("learning.upload.photos")
                    Button { importing = true } label: { Label("从文件选视频或录音", systemImage: "folder") }
                        .accessibilityIdentifier("learning.upload.files")
                    if preparing { HStack { ProgressView(); Text("正在准备文件…") } }
                    ForEach(files, id: \.url) { file in
                        HStack {
                            Image(systemName: file.mimeType.hasPrefix("image/") ? "photo" : file.mimeType.hasPrefix("audio/") ? "waveform" : "video")
                                .foregroundStyle(BubuTheme.Color.deepRose)
                            Text(file.fileName).lineLimit(1)
                            Spacer()
                            Text(Self.size(file.url)).font(.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { try? FileManager.default.removeItem(at: files[index].url) }
                        files.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("课程素材（最多 8 个）")
                } footer: {
                    Text("至少需要一段有老师声音的视频或录音；教具照片可帮助出题。素材只用于每日学习，不会进入时光。")
                }
                if let progressText {
                    Section {
                        HStack { ProgressView(); Text(progressText) }
                    } footer: {
                        Label("上传中请保持在本页，屏幕不会自动锁定；锁屏上也能看到进度。", systemImage: "hand.raised.fill")
                    }
                    .accessibilityIdentifier("learning.upload.progress")
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(BubuTheme.Color.danger) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BubuTheme.Color.background)
            .navigationTitle("上传课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(uploading) }
                ToolbarItem(placement: .confirmationAction) {
                    if uploading { ProgressView() } else {
                        Button("上传") { Task { await upload() } }.disabled(!canSubmit)
                            .accessibilityIdentifier("learning.upload.submit")
                    }
                }
            }
            .interactiveDismissDisabled(uploading)
            .onDisappear {
                // Picked copies live in tmp and can be hundreds of MB; drop them if the sheet closes early.
                for file in files { try? FileManager.default.removeItem(at: file.url) }
            }
            #if DEBUG
            .task {
                // UI 测试无法操作系统相册面板；用测试环境变量直接放入宿主机上的测试视频。
                guard ProcessInfo.processInfo.arguments.contains("-uitest-server-config"),
                      let paths = ProcessInfo.processInfo.environment["BUBU_UITEST_COURSE_FILES"], files.isEmpty else { return }
                importFiles(paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
            }
            #endif
            .onChange(of: pickerItems) { _, items in Task { await importPicked(items) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .audio, .image], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importFiles(urls) }
            }
        }
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        preparing = true
        defer { preparing = false; pickerItems = [] }
        for item in items where files.count < 8 {
            do {
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
                   let movie = try await item.loadTransferable(type: PickedMovie.self) {
                    let type = UTType(filenameExtension: movie.url.pathExtension) ?? .quickTimeMovie
                    files.append(LearningUploadFile(url: movie.url, fileName: movie.url.lastPathComponent,
                                                    mimeType: type.conforms(to: .mpeg4Movie) ? "video/mp4" : "video/quicktime"))
                } else if let data = try await item.loadTransferable(type: Data.self),
                          let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.88) {
                    let url = Self.temporary("jpg")
                    try jpeg.write(to: url)
                    files.append(LearningUploadFile(url: url, fileName: "教具\(files.count + 1).jpg", mimeType: "image/jpeg"))
                }
            } catch {
                errorText = "有个文件没能读取，请换一个再试。"
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls where files.count < 8 {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let type = UTType(filenameExtension: url.pathExtension)
            let mime: String? = switch true {
            case type?.conforms(to: .mpeg4Movie) == true: "video/mp4"
            case type?.conforms(to: .movie) == true: "video/quicktime"
            case type?.conforms(to: .mpeg4Audio) == true: "audio/mp4"
            case type?.conforms(to: .mp3) == true: "audio/mpeg"
            case type?.conforms(to: .wav) == true: "audio/wav"
            case type?.conforms(to: .jpeg) == true: "image/jpeg"
            case type?.conforms(to: .png) == true: "image/png"
            case type?.conforms(to: .heic) == true: "image/heic"
            default: nil
            }
            guard let mime else { errorText = "暂不支持 \(url.lastPathComponent) 这种格式。"; continue }
            let target = Self.temporary(url.pathExtension)
            do {
                try FileManager.default.copyItem(at: url, to: target)
                files.append(LearningUploadFile(url: target, fileName: url.lastPathComponent, mimeType: mime))
            } catch { errorText = "有个文件没能读取，请换一个再试。" }
        }
    }

    /// Proxy limit per request is about 100 MB; stay clearly below it.
    nonisolated static let maxRequestBytes = 92 * 1_048_576
    /// Larger phone videos are re-encoded to 720p first. Speech stays intact for transcription.
    nonisolated static let compressAboveBytes = 40 * 1_048_576

    private func upload() async {
        uploading = true; errorText = nil
        var ready: [LearningUploadFile] = []
        var created: String?
        var finished = false
        let courseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // 压缩 + 上传最多几分钟：申请后台时间、屏幕不自动锁定，锁屏/灵动岛显示进度。
        let keepAlive = LearningUploadKeepAlive()
        BubuActivityController.startCourseUpload(title: courseTitle, childName: "布布")
        defer {
            keepAlive.end()
            if !finished { BubuActivityController.failCourseUpload() }
            uploading = false; progressText = nil
            // Compressed copies are ours; the picked originals stay for a retry.
            for file in ready where !files.contains(file) { try? FileManager.default.removeItem(at: file.url) }
        }
        do {
            let toCompress = files.filter { $0.mimeType.hasPrefix("video/") && Self.size(of: $0.url) > Self.compressAboveBytes }
            var compressed = 0
            for (index, file) in files.enumerated() {
                if toCompress.contains(file) {
                    let label = "正在压缩第 \(index + 1) 个视频…"
                    progressText = label
                    let done = compressed, total = toCompress.count
                    BubuActivityController.updateCourseUpload(phase: .compressing, progress: Double(done) / Double(total))
                    ready.append(try await Self.compress(file) { fraction in
                        Task { @MainActor in
                            let overall = (Double(done) + fraction) / Double(total)
                            progressText = "\(label) \(Int((fraction * 100).rounded()))%"
                            BubuActivityController.updateCourseUpload(phase: .compressing, progress: overall)
                        }
                    })
                    compressed += 1
                } else {
                    ready.append(file)
                }
            }
            if let large = ready.first(where: { Self.size(of: $0.url) > Self.maxRequestBytes }) {
                errorText = "「\(large.fileName)」压缩后仍超过 90 MB，请在相册里剪成几段（每段几分钟）再上传。"
                return
            }
            // Teacher audio goes first so the course always starts with real speech.
            ready.sort { !$0.mimeType.hasPrefix("image/") && $1.mimeType.hasPrefix("image/") }
            progressText = ready.count > 1 ? "正在上传第 1/\(ready.count) 个文件…" : "正在上传…"
            BubuActivityController.updateCourseUpload(phase: .uploading, step: 1, steps: ready.count)
            var course = try await client.createCourse(childID: childID, schoolDate: BubuLearningDates.dayString(day),
                                                       title: courseTitle,
                                                       kind: kind, language: language, first: ready[0], totalFiles: ready.count)
            created = course.id
            BubuActivityController.attachCourseUpload(courseID: course.id)
            for (index, file) in ready.enumerated().dropFirst() {
                progressText = "正在上传第 \(index + 1)/\(ready.count) 个文件…"
                BubuActivityController.updateCourseUpload(phase: .uploading, step: index + 1, steps: ready.count)
                course = try await client.addCourseFile(courseID: course.id, file: file)
            }
            finished = true
            // 文件都到了：服务端开始解析，之后由首页轮询推进到「草稿可审核」。
            BubuActivityController.updateCourseUpload(phase: CourseUploadActivityPhase.from(courseState: course.state) ?? .parsing)
            for file in files { try? FileManager.default.removeItem(at: file.url) }
            onUploaded(course)
            dismiss()
        } catch {
            // Don't leave a half-uploaded lesson behind; retrying creates a clean one.
            if let created {
                _ = try? await client.send("DELETE", "api/courses/\(created)", as: CourseDeleted.self)
            }
            errorText = learningErrorText(error, fallback: "上传没有完成，请检查网络后重试。如果课程里显示“上传未完成”，可以删除后重新上传。")
        }
    }

    private nonisolated struct CourseDeleted: Decodable, Sendable { let deleted: Bool }

    nonisolated static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// Sharpest first: cards and teacher gestures stay readable while long lessons still fit.
    nonisolated static let presets = [AVAssetExportPreset1280x720, AVAssetExportPreset960x540,
                                      AVAssetExportPreset640x480, AVAssetExportPresetMediumQuality]

    @concurrent
    nonisolated static func compress(_ file: LearningUploadFile,
                                     progress: (@Sendable (Double) -> Void)? = nil) async throws -> LearningUploadFile {
        let asset = AVURLAsset(url: file.url)
        // Never use fileLengthLimit: it would silently cut the end of the lesson.
        var chosen: AVAssetExportSession?
        for preset in presets {
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            exporter.outputFileType = .mp4
            let estimate: Int64 = await withCheckedContinuation { continuation in
                exporter.estimateOutputFileLength { length, _ in continuation.resume(returning: length) }
            }
            chosen = exporter
            if estimate > 0 && estimate < Int64(maxRequestBytes) * 9 / 10 { break }
        }
        guard let exporter = chosen else { return file }
        let target = temporary("mp4")
        let states = exporter.states(updateInterval: 0.5)
        let monitor = Task {
            for await state in states {
                if case .exporting(let value) = state { progress?(value.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        try await exporter.export(to: target, as: .mp4)
        progress?(1)
        guard size(of: target) > 0, size(of: target) < size(of: file.url) else {
            try? FileManager.default.removeItem(at: target)
            return file
        }
        let base = (file.fileName as NSString).deletingPathExtension
        return LearningUploadFile(url: target, fileName: base + ".mp4", mimeType: "video/mp4")
    }

    nonisolated static func temporary(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bubu-upload-\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)")
    }

    private static func size(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// 上传期间：申请后台执行时间（切走/锁屏时多撑一会儿），并关闭自动锁屏；结束时恢复原状。
@MainActor
final class LearningUploadKeepAlive {
    private var task: UIBackgroundTaskIdentifier = .invalid
    private let previousIdleDisabled: Bool
    private var ended = false

    init() {
        previousIdleDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        task = UIApplication.shared.beginBackgroundTask(withName: "bubu.learning.course-upload") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    func end() {
        guard !ended else { return }
        ended = true
        UIApplication.shared.isIdleTimerDisabled = previousIdleDisabled
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

/// Photos hands over a temporary movie file; copy it before the handler returns.
private nonisolated struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let target = CourseUploadSheet.temporary(ext)
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedMovie(url: target)
        }
    }
}
