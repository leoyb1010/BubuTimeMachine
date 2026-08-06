import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - 开放阅读档案
/// 面向长期阅读和素材迁移的开放包；服务器灾后无损恢复仍以加密 restic 备份为准。
struct ExportView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var milestones: [Milestone]
    @Query(sort: \VoiceMemo.recordedAt, order: .reverse) private var voiceMemos: [VoiceMemo]
    @Query(sort: \HealthRecord.recordedAt, order: .reverse) private var healthRecords: [HealthRecord]
    @Query(sort: \GrowthMeasurement.measuredAt, order: .reverse) private var growthMeasurements: [GrowthMeasurement]
    @Query(sort: \VaccineRecord.injectedAt, order: .reverse) private var vaccines: [VaccineRecord]
    @Query(sort: \FirstTime.happenedAt, order: .reverse) private var firstTimes: [FirstTime]
    @Query(sort: \TimeCapsule.unlockAt) private var timeCapsules: [TimeCapsule]
    @Query private var profiles: [ChildProfile]

    @State private var exporting = false
    @State private var exportedURL: URL?
    @State private var showShare = false
    @State private var errorText: String?
    @State private var missingNote: String?
    @State private var showIncompleteExportAlert = false

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
                    if let missingNote {
                        Text(missingNote).font(BubuTheme.Font.caption).foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                    if let errorText {
                        Text(errorText).font(BubuTheme.Font.caption).foregroundStyle(.red)
                    }
                }
                .padding()
                .bubuContentColumn()   // 宽屏收进居中内容列，窄屏原样
            }
        }
        .navigationTitle("开放阅读档案")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
        .alert("这份档案还不完整", isPresented: $showIncompleteExportAlert) {
            Button("仍然分享不完整包", role: .destructive) { showShare = true }
            Button("先不分享", role: .cancel) {}
        } message: {
            Text(missingNote ?? "有原片尚未下载完成，请先到同步中心补齐后再导出。")
        }
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(BubuTheme.Font.scaled(56)).foregroundStyle(theme)
            Text("布布的时光，装进一个可读文件夹")
                .font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.center)
            Text("导出成网页、JSON、Markdown、原始媒体与 SHA-256 校验清单，适合长期阅读和迁移素材；它不替代服务器加密备份，也不能直接无损还原 App。缺原片会明确标为不完整。")
                .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            row("瞬间", "\(entries.count) 个")
            Divider()
            row("照片视频", "\(entries.reduce(0) { $0 + $1.sortedMedia.count }) 个")
            Divider()
            row("声音", "\(entries.reduce(0) { $0 + $1.voiceNotes.count + $1.comments.filter { $0.voiceFileName != nil }.count } + voiceMemos.count) 段")
            Divider()
            row("里程碑", "\(milestones.filter(\.isAchieved).count) 个")
            Divider()
            row("健康/第一次/胶囊", "\(healthRecords.count + firstTimes.count + timeCapsules.count) 项")
            Divider()
            row("成长/疫苗", "\(growthMeasurements.count + vaccines.count) 项")
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
        missingNote = nil
        defer { exporting = false }

        // 主线程收集快照（SwiftData 模型不跨线程）
        var unavailableReferences: [String] = []
        let snapshots = entries.map { e in
            ArchiveExporter.EntrySnapshot(
                happenedAt: e.happenedAt, authorRole: e.authorRole, note: e.note,
                firstPersonNote: e.firstPersonNote, locationName: e.locationName,
                moodEmoji: e.mood?.emoji,
                ageDescription: AgeCalculator.ageDescription(birthday: profile.birthday, at: e.happenedAt),
                media: e.media.compactMap { media in
                    guard let fileName = media.localFileName else {
                        unavailableReferences.append("media:\(media.id.uuidString)")
                        return nil
                    }
                    return ArchiveExporter.MediaSnapshot(
                        fileName: fileName, type: media.type.rawValue,
                        resourceRole: media.resourceRoleRaw)
                },
                voiceNotes: e.voiceNotes.compactMap { voice in
                    guard let fileName = voice.localFileName else {
                        unavailableReferences.append("voice-note:\(voice.id.uuidString)")
                        return nil
                    }
                    return ArchiveExporter.VoiceSnapshot(fileName: fileName, duration: voice.durationSeconds,
                                                         authorRole: voice.authorRole, transcript: voice.transcript)
                },
                comments: e.comments.map { comment in
                    if comment.remoteURL != nil && comment.voiceFileName == nil {
                        unavailableReferences.append("comment-voice:\(comment.id.uuidString)")
                    }
                    return ArchiveExporter.CommentSnapshot(
                        authorRole: comment.authorRole, text: comment.text,
                        voiceFileName: comment.voiceFileName,
                        voiceDuration: comment.voiceDuration,
                        createdAt: comment.createdAt)
                },
                tags: Array(Set(e.media.flatMap { $0.aiTags })))
        }
        let ms = milestones.map { m in
            ArchiveExporter.MilestoneSnapshot(
                title: m.title, emoji: m.emoji, achieved: m.isAchieved, ageDescription: m.ageDescription)
        }
        let memoSnapshots = voiceMemos.map { memo in
            if memo.localFileName == nil {
                unavailableReferences.append("voice-memo:\(memo.id.uuidString)")
            }
            return ArchiveExporter.VoiceMemoSnapshot(
                kind: memo.kindRaw, fileName: memo.localFileName,
                transcript: memo.transcript, ageYears: memo.ageYears,
                recordedAt: memo.recordedAt, durationSeconds: memo.durationSeconds)
        }
        let healthSnapshots = healthRecords.map { record in
            ArchiveExporter.HealthRecordSnapshot(kind: record.kind.title, title: record.title,
                                                 detail: record.detail, recordedAt: record.recordedAt,
                                                 amountText: healthAmountText(record), reaction: record.reaction)
        }
        let firstTimeSnapshots = firstTimes.map { item in
            ArchiveExporter.FirstTimeSnapshot(what: item.what, happenedAt: item.happenedAt,
                                              confirmed: item.confirmedByParent)
        }
        let growthSnapshots = growthMeasurements.map { item in
            ArchiveExporter.GrowthSnapshot(
                measuredAt: item.measuredAt, heightCm: item.heightCm,
                weightKg: item.weightKg, headCircumferenceCm: item.headCircumferenceCm,
                note: item.note, source: item.sourceRaw)
        }
        let vaccineSnapshots = vaccines.map { item in
            ArchiveExporter.VaccineSnapshot(
                vaccineName: item.vaccineName, doseLabel: item.doseLabel,
                injectedAt: item.injectedAt, hospital: item.hospital,
                injectionSite: item.injectionSite, reaction: item.reaction, note: item.note)
        }
        let capsuleSnapshots = timeCapsules.map { capsule in
            if capsule.encryptedBlobFileName == nil {
                unavailableReferences.append("time-capsule:\(capsule.id.uuidString)")
            }
            return ArchiveExporter.TimeCapsuleSnapshot(
                id: capsule.id,
                title: capsule.title, fromRole: capsule.fromRole,
                unlockAt: capsule.unlockAt, isLocked: capsule.isLocked,
                coverEmoji: capsule.coverEmoji,
                encryptedBlobFileName: capsule.encryptedBlobFileName)
        }
        let input = ArchiveExporter.ExportInput(
            childName: profile.name, birthday: profile.birthday,
            entries: snapshots, milestones: ms, voiceMemos: memoSnapshots,
            healthRecords: healthSnapshots, growthMeasurements: growthSnapshots,
            vaccines: vaccineSnapshots, firstTimes: firstTimeSnapshots,
            timeCapsules: capsuleSnapshots,
            unavailableReferences: unavailableReferences)

        let exporter = ArchiveExporter(mediaStore: env.mediaStore)
        do {
            // 后台导出 + zip
            let result = try await Task.detached(priority: .userInitiated) {
                try exporter.export(input)
            }.value
            let folder = result.root
            let zip = try await Task.detached(priority: .userInitiated) {
                try Self.zip(folder: folder)
            }.value
            exportedURL = zip
            // 诚实告知：有媒体因源文件缺失或拷贝失败未能纳入档案。
            if !result.incompleteReferences.isEmpty {
                missingNote = "本次档案不完整：有 \(result.incompleteReferences.count) 个文件引用未能纳入。请先在同步中心下载完整原片后重新导出。"
                showIncompleteExportAlert = true
            } else {
                showShare = true
            }
            // 记录导出时间戳，供「备份健康度卡」判断是否过期。
            if result.incompleteReferences.isEmpty {
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "bubu.lastExportAt")
            }
        } catch {
            errorText = "导出失败：\(error.localizedDescription)"
        }
    }

    private func healthAmountText(_ record: HealthRecord) -> String? {
        if let amount = record.amountText, !amount.isEmpty { return amount }
        if record.kind == .sleep, let start = record.startAt, let end = record.endAt, end > start {
            return HealthRecordDraft.durationText(from: start, to: end)
        }
        if let value = record.amountValue, let unit = record.amountUnit {
            return "\(HealthRecordDraft.cleanAmount(value))\(unit)"
        }
        if let temp = record.temperatureCelsius {
            return String(format: "%.1f℃", temp)
        }
        return nil
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
