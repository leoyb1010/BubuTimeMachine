import SwiftUI
import SwiftData
import UIKit

// MARK: - 分享卡片（选版式 → 预览 → 系统面板）
/// 动线三步、零新页面层级：任意记录卡长按 →「分享这一刻」→ 选版式 → 分享。
/// 面板由系统出，微信 / 小红书 / 抖音都在里面——不接任何第三方 SDK。
struct ShareCardSheet: View {
    let entry: Entry
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var layout: ShareCard.Layout = .portrait
    @State private var showAge = true
    @State private var preview: UIImage?
    @State private var shareURL: URL?
    @State private var rendering = false

    /// 有「那年今日」的旧照片才提供对比版式——没有对比对象时这个选项是死的。
    @State private var thenEntry: Entry?

    private var availableLayouts: [ShareCard.Layout] {
        thenEntry == nil ? [.portrait, .square] : ShareCard.Layout.allCases
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewArea
                    layoutPicker
                    ageToggle
                    shareButton
                }
                .padding()
                .bubuContentColumn()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("分享这一刻")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .task {
            thenEntry = Self.findThenEntry(for: entry, context: context)
            refresh()
        }
        .onChange(of: layout) { refresh() }
        .onChange(of: showAge) { refresh() }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } },
                             set: { if $0 == nil { shareURL = nil } })) { item in
            ShareSheet(items: [item.url])
        }
    }

    // MARK: 预览

    private var previewArea: some View {
        ZStack {
            if let preview {
                Image(uiImage: preview)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                    .bubuCardShadow()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                    .fill(BubuTheme.Color.softFill)
                    .frame(height: 300)
                    .overlay { ProgressView() }
            }
        }
        .animation(BubuMotion.quick, value: preview)
        .frame(maxHeight: 420)
    }

    private var layoutPicker: some View {
        Picker("版式", selection: $layout) {
            ForEach(availableLayouts) { l in
                Text(l.title).tag(l)
            }
        }
        .pickerStyle(.segmented)
    }

    private var ageToggle: some View {
        Toggle(isOn: $showAge) {
            VStack(alignment: .leading, spacing: 2) {
                Text("显示当时年龄").font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("卡片上只会出现「2岁2个月」这样的说法，不会出现出生日期")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
        }
        .tint(env.theme.theme.primary)
        .padding(14)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
    }

    private var shareButton: some View {
        Button {
            share()
        } label: {
            Label("分享", systemImage: "square.and.arrow.up")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BubuTheme.Gradient.primaryButton,
                            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.button, style: .continuous))
        }
        .disabled(preview == nil || rendering)
        .opacity(preview == nil ? 0.5 : 1)
    }

    // MARK: 渲染

    private func refresh() {
        rendering = true
        let content = makeContent()
        preview = ShareCard.render(content, layout: layout)
        rendering = false
    }

    private func share() {
        guard let url = ShareCard.renderToFile(makeContent(), layout: layout) else { return }
        shareURL = url
        BubuHaptics.success()
    }

    private func makeContent() -> ShareCard.Content {
        let birthday = EntryWriter.currentChildProfile(in: context)?.birthday
        return ShareCard.Content(
            childName: env.config.childName,
            dateText: BubuDateFormat.monthDay(entry.happenedAt),
            ageText: showAge ? birthday.map { AgeCalculator.compactAge(birthday: $0, at: entry.happenedAt) } : nil,
            note: entry.firstPersonNote ?? entry.note ?? entry.title,
            photo: firstPhoto(of: entry),
            thenPhoto: thenEntry.flatMap(firstPhoto),
            thenDateText: thenEntry.map { BubuDateFormat.monthDay($0.happenedAt) },
            thenAgeText: showAge ? thenEntry.flatMap { e in
                birthday.map { AgeCalculator.compactAge(birthday: $0, at: e.happenedAt) }
            } : nil)
    }

    /// 取原图而非缩略图：分享卡是 1080px 输出，缩略图放大会糊。
    private func firstPhoto(of entry: Entry) -> UIImage? {
        let store = env.mediaStore
        for media in entry.media where media.type == .photo {
            guard let name = media.localFileName ?? media.thumbnailFileName else { continue }
            let url = store.mediaURL(for: name)
            let fallback = store.thumbnailURL(for: name)
            let target = FileManager.default.fileExists(atPath: url.path) ? url : fallback
            if let img = ThumbnailProvider.downsample(url: target, maxPixel: 1400) { return img }
        }
        return nil
    }

    /// 找「那年今日」的对照：同月同日、更早年份、有照片的一条。
    @MainActor
    static func findThenEntry(for entry: Entry, context: ModelContext) -> Entry? {
        let cal = Calendar.current
        let month = cal.component(.month, from: entry.happenedAt)
        let day = cal.component(.day, from: entry.happenedAt)
        var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.happenedAt, order: .reverse)])
        descriptor.fetchLimit = 400
        guard let all = try? context.fetch(descriptor) else { return nil }
        return all.first { candidate in
            candidate.id != entry.id
                && candidate.happenedAt < entry.happenedAt
                && cal.component(.month, from: candidate.happenedAt) == month
                && cal.component(.day, from: candidate.happenedAt) == day
                && candidate.media.contains { $0.type == .photo }
        }
    }
}

/// sheet(item:) 需要 Identifiable 包装。
private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}
