import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 全量档案导出
/// 一键把布布的一切导出成可双击打开的网页 + 媒体包，并分享出去（存文件/隔空投送/发给家人）。
struct ExportView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var milestones: [Milestone]
    @Query private var profiles: [ChildProfile]

    @State private var exporting = false
    @State private var exportedURL: URL?
    @State private var showShare = false
    @State private var errorText: String?

    private var theme: Color { env.theme.theme.primary }
    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    infoCard
                    exportButton
                    if let errorText {
                        Text(errorText).font(BubuTheme.Font.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("全量导出")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch env.theme.theme.backgroundStyle {
        case .solid(let hex): Color(hex: hex)
        case .gradient(let a, let b):
            LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 56)).foregroundStyle(theme)
            Text("布布的一生，装进一个文件夹")
                .font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
            Text("导出成一个网页 + 全部媒体。双击 index.html 就能看，永久离线可读——即使将来 App 和服务器都不在了。")
                .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            row("瞬间", "\(entries.count) 个")
            Divider()
            row("照片视频", "\(entries.reduce(0) { $0 + $1.media.count }) 个")
            Divider()
            row("里程碑", "\(milestones.filter(\.isAchieved).count) 个")
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer()
            Text(v).fontWeight(.semibold).foregroundStyle(BubuTheme.Color.warmBrown)
        }
        .font(BubuTheme.Font.body)
        .padding(.vertical, 10)
    }

    private var exportButton: some View {
        Button {
            Task { await runExport() }
        } label: {
            HStack {
                if exporting { ProgressView().tint(.white) }
                else { Image(systemName: "square.and.arrow.up") }
                Text(exporting ? "正在打包…" : "导出并分享")
            }
            .font(BubuTheme.Font.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(theme, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(exporting || profile == nil)
    }

    private func runExport() async {
        guard let profile else { return }
        exporting = true
        errorText = nil
        defer { exporting = false }

        // 主线程收集快照（SwiftData 模型不跨线程）
        let snapshots = entries.map { e in
            ArchiveExporter.EntrySnapshot(
                happenedAt: e.happenedAt, authorRole: e.authorRole, note: e.note,
                firstPersonNote: e.firstPersonNote, locationName: e.locationName,
                moodEmoji: e.mood?.emoji,
                ageDescription: AgeCalculator.ageDescription(birthday: profile.birthday, at: e.happenedAt),
                mediaFileNames: e.media.filter { $0.type == .photo }.compactMap { $0.localFileName },
                tags: Array(Set(e.media.flatMap { $0.aiTags })))
        }
        let ms = milestones.map { m in
            ArchiveExporter.MilestoneSnapshot(
                title: m.title, emoji: m.emoji, achieved: m.isAchieved, ageDescription: m.ageDescription)
        }
        let input = ArchiveExporter.ExportInput(
            childName: profile.name, birthday: profile.birthday,
            entries: snapshots, milestones: ms)

        let exporter = ArchiveExporter(mediaStore: env.mediaStore)
        do {
            // 后台导出 + zip
            let folder = try await Task.detached(priority: .userInitiated) {
                try exporter.export(input)
            }.value
            let zip = try await Task.detached(priority: .userInitiated) {
                try Self.zip(folder: folder)
            }.value
            exportedURL = zip
            showShare = true
        } catch {
            errorText = "导出失败：\(error.localizedDescription)"
        }
    }

    /// 用系统 ditto 压缩文件夹为 zip（在沙盒可用）。
    nonisolated private static func zip(folder: URL) throws -> URL {
        let zipURL = folder.deletingPathExtension().appendingPathExtension("zip")
        try? FileManager.default.removeItem(at: zipURL)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: URL?
        var thrown: Error?
        coordinator.coordinate(readingItemAt: folder, options: [.forUploading], error: &coordError) { tmpURL in
            do {
                try FileManager.default.moveItem(at: tmpURL, to: zipURL)
                result = zipURL
            } catch { thrown = error }
        }
        if let coordError { throw coordError }
        if let thrown { throw thrown }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return result
    }
}

// MARK: - 分享 sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
