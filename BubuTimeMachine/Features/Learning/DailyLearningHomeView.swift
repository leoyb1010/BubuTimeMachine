import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
    @State private var day: Date
    @State private var context: LearningContextDTO?
    @State private var courses: [LearningCourseDTO] = []
    @State private var weekDays: Set<String> = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var uploading = false
    @State private var opened: LearningCourseDTO?
    @State private var review: String?
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
    }

    // MARK: Sections

    private var weekHeader: some View {
        SchoolPanel(title: day.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))),
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
                    .accessibilityLabel(date.formatted(.dateTime.month().day()) + (weekDays.contains(key) ? "，有课程" : ""))
                }
            }
            HStack {
                Button { shift(-7) } label: { Label("上一周", systemImage: "chevron.left") }
                Spacer()
                DatePicker("日期", selection: $day, in: ...Date.now.addingTimeInterval(86_400 * 30), displayedComponents: .date)
                    .labelsHidden()
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
        SchoolPanel(title: "这一天的课", symbol: "books.vertical.fill", subtitle: courses.isEmpty ? "" : "\(courses.count) 节") {
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
        SchoolPanel(title: "复习", symbol: "arrow.triangle.2.circlepath", subtitle: "只用已开放的课程", accent: SchoolPalette.violet) {
            HStack(spacing: BubuTheme.Spacing.s) {
                reviewButton("本周复习", detail: "近 7 天", period: "week", tint: SchoolPalette.orange)
                reviewButton("本月复习", detail: "近 30 天", period: "month", tint: SchoolPalette.green)
            }
        }
    }

    private func reviewButton(_ title: String, detail: String, period: String, tint: Color) -> some View {
        Button { review = period } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(BubuTheme.Font.body.weight(.bold))
                Text(detail).font(BubuTheme.Font.caption).opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BubuTheme.Spacing.m)
            .background(tint, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
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
            let list = try await client.get("api/courses", query: dayQuery, as: LearningCourseList.self)
            courses = list.items
            if let first = weekDates.first, let last = weekDates.last {
                let weekQuery = base + [URLQueryItem(name: "start", value: BubuLearningDates.dayString(first)),
                                        URLQueryItem(name: "end", value: BubuLearningDates.dayString(last))]
                let week = try await client.get("api/courses", query: weekQuery, as: LearningCourseList.self)
                weekDays = Set(week.items.map(\.schoolDate))
            }
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
        case "failed": BubuTheme.Color.danger
        default: BubuTheme.Color.warmBrown
        }
    }
    private var background: Color {
        switch state {
        case "published": BubuTheme.Color.primary
        case "draft": BubuTheme.Color.butterSurface
        case "failed": BubuTheme.Color.danger.opacity(0.12)
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
                    .onDelete { files.remove(atOffsets: $0) }
                } header: {
                    Text("课程素材（最多 8 个）")
                } footer: {
                    Text("至少需要一段有老师声音的视频或录音；教具照片可帮助出题。素材只用于每日学习，不会进入时光。")
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

    private func upload() async {
        uploading = true; errorText = nil
        defer { uploading = false }
        do {
            let course = try await client.uploadCourse(childID: childID, schoolDate: BubuLearningDates.dayString(day),
                                                       title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       kind: kind, language: language, files: files)
            for file in files { try? FileManager.default.removeItem(at: file.url) }
            onUploaded(course)
            dismiss()
        } catch {
            errorText = learningErrorText(error, fallback: "上传没有完成，请检查网络后重试。")
        }
    }

    nonisolated static func temporary(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bubu-upload-\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)")
    }

    private static func size(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
