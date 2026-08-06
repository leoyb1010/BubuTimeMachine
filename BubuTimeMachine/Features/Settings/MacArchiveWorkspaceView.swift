import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 开放档案校验
/// 只读校验导出的开放档案。真正的数据库灾备恢复仍由服务器 restic 完成；
/// 这里不把 JSON 静默写回 SwiftData，避免旧档案覆盖现有家庭数据。
nonisolated enum OpenArchiveVerifier {
    struct Report: Sendable, Equatable {
        let folderName: String
        let childName: String
        let entryCount: Int
        let checkedFileCount: Int
        let missingFiles: [String]
        let mismatchedFiles: [String]

        var isValid: Bool { missingFiles.isEmpty && mismatchedFiles.isEmpty }
    }

    enum VerificationError: LocalizedError {
        case missingManifest
        case malformedManifest
        case missingData
        case malformedData

        var errorDescription: String? {
            switch self {
            case .missingManifest: return "没有找到 manifest.sha256，这不是完整的布布开放档案。"
            case .malformedManifest: return "校验清单格式不正确，已停止读取。"
            case .missingData: return "没有找到 data.json，档案无法恢复阅读。"
            case .malformedData: return "data.json 无法解析，档案可能已损坏。"
            }
        }
    }

    static func verify(folder: URL) throws -> Report {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

        let manifestURL = folder.appendingPathComponent("manifest.sha256")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw VerificationError.missingManifest
        }
        let dataURL = folder.appendingPathComponent("data.json")
        guard FileManager.default.fileExists(atPath: dataURL.path) else {
            throw VerificationError.missingData
        }

        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        var missing: [String] = []
        var mismatched: [String] = []
        var checked = 0
        let rootPath = folder.standardizedFileURL.path

        for rawLine in manifest.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine)
            guard line.utf8.count >= 67 else { throw VerificationError.malformedManifest }
            let hashEnd = line.index(line.startIndex, offsetBy: 64)
            let expected = String(line[..<hashEnd]).lowercased()
            let separatorEnd = line.index(hashEnd, offsetBy: 2)
            guard line[hashEnd..<separatorEnd] == "  ",
                  expected.count == 64,
                  expected.allSatisfy({ $0.isHexDigit })
            else { throw VerificationError.malformedManifest }
            let relative = String(line[separatorEnd...])
            guard !relative.isEmpty, !relative.hasPrefix("/") else {
                throw VerificationError.malformedManifest
            }
            let fileURL = folder.appendingPathComponent(relative).standardizedFileURL
            guard fileURL.path.hasPrefix(rootPath + "/") else {
                throw VerificationError.malformedManifest
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                missing.append(relative)
                continue
            }
            checked += 1
            if try sha256(fileURL) != expected { mismatched.append(relative) }
        }

        guard checked + missing.count > 0 else { throw VerificationError.malformedManifest }
        let data = try Data(contentsOf: dataURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let childName = root["childName"] as? String,
              let entries = root["entries"] as? [Any]
        else { throw VerificationError.malformedData }

        return Report(
            folderName: folder.lastPathComponent,
            childName: childName,
            entryCount: entries.count,
            checkedFileCount: checked,
            missingFiles: missing.sorted(),
            mismatchedFiles: mismatched.sorted()
        )
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

#if targetEnvironment(macCatalyst)
// MARK: - Mac 档案馆
/// 同一数据引擎上的桌面整理台：搜索、批量收录、软归档、开放档案导出与只读恢复校验。
struct MacArchiveWorkspaceView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all, storybook, pending, archived
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .storybook: return "成长绘本"
            case .pending: return "待同步"
            case .archived: return "已归档"
            }
        }
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.happenedAt, order: .reverse) private var entries: [Entry]

    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var selectedIDs: Set<UUID> = []
    @State private var showArchiveConfirmation = false
    @State private var showArchiveImporter = false
    @State private var verificationState: VerificationState = .idle

    private enum VerificationState {
        case idle
        case checking
        case valid(OpenArchiveVerifier.Report)
        case invalid(OpenArchiveVerifier.Report)
        case failed(String)
    }

    private var visibleEntries: [Entry] {
        entries.filter { entry in
            let matchesFilter = switch filter {
            case .all: !entry.isArchived
            case .storybook: entry.inStorybook && !entry.isArchived
            case .pending: entry.syncState != .synced && !entry.isArchived
            case .archived: entry.isArchived
            }
            guard matchesFilter else { return false }
            let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return true }
            return [entry.title, entry.note, entry.firstPersonNote, entry.locationName, entry.authorRole]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    private var selectedEntries: [Entry] {
        entries.filter { selectedIDs.contains($0.id) }
    }

    private var focusedEntry: Entry? {
        selectedEntries.sorted { $0.happenedAt > $1.happenedAt }.first
    }

    var body: some View {
        HStack(spacing: 0) {
            archiveList
                .frame(minWidth: 330, idealWidth: 380, maxWidth: 440)
            Divider()
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("档案馆")
        .searchable(text: $searchText, prompt: "搜索标题、文字、地点或记录人")
        .toolbar { toolbarContent }
        .confirmationDialog("将选中的 \(selectedIDs.count) 条时光移入归档？", isPresented: $showArchiveConfirmation) {
            Button("移入归档", role: .destructive) { applyArchive(true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("记录只会从日常时光轴隐藏，不会删除；可随时在“已归档”中恢复。")
        }
        .fileImporter(isPresented: $showArchiveImporter, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else {
                if case let .failure(error) = result { verificationState = .failed(error.localizedDescription) }
                return
            }
            verificationState = .checking
            Task {
                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        try OpenArchiveVerifier.verify(folder: url)
                    }.value
                    verificationState = report.isValid ? .valid(report) : .invalid(report)
                } catch {
                    verificationState = .failed(error.localizedDescription)
                }
            }
        }
        .onChange(of: filter) { _, _ in selectedIDs.removeAll() }
    }

    private var archiveList: some View {
        VStack(spacing: 0) {
            Picker("范围", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(14)

            if visibleEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "这里还没有时光" : "没有找到匹配的时光",
                    systemImage: searchText.isEmpty ? "archivebox" : "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleEntries) { entry in
                    Button {
                        if selectedIDs.contains(entry.id) {
                            selectedIDs.remove(entry.id)
                        } else {
                            selectedIDs.insert(entry.id)
                        }
                    } label: {
                        archiveRow(entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedIDs.contains(entry.id) ? .isSelected : [])
                    .listRowBackground(
                        selectedIDs.contains(entry.id)
                            ? env.theme.theme.primary.opacity(0.14)
                            : Color.clear)
                }
                .listStyle(.plain)
            }

            HStack {
                Text("\(visibleEntries.count) 条")
                Spacer()
                Text(selectedIDs.isEmpty ? "点击记录即可多选" : "已选 \(selectedIDs.count) 条")
            }
            .font(BubuTheme.Font.caption)
            .foregroundStyle(BubuTheme.Color.secondaryText)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(BubuTheme.Color.card)
        }
    }

    private func archiveRow(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            if let media = entry.coverMedia {
                MediaThumbnail(media: media, mediaStore: env.mediaStore, cornerRadius: 10, size: .grid)
                    .frame(width: 58, height: 58)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BubuTheme.Color.cream2)
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: "text.page").foregroundStyle(BubuTheme.Color.secondaryText))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle(entry))
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(1)
                Text(BubuDateFormat.shortDateTime(entry.happenedAt))
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                HStack(spacing: 6) {
                    if entry.inStorybook { Label("绘本", systemImage: "book.closed.fill") }
                    if entry.syncState != .synced { Label("待同步", systemImage: "arrow.triangle.2.circlepath") }
                }
                .font(BubuTheme.Font.scaled(11, weight: .semibold))
                .foregroundStyle(env.theme.theme.primary)
            }
            Spacer(minLength: 8)
            Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                .font(BubuTheme.Font.scaled(18, weight: .semibold))
                .foregroundStyle(selectedIDs.contains(entry.id)
                                 ? env.theme.theme.primary : BubuTheme.Color.hairline)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detailPane: some View {
        if selectedIDs.count > 1 {
            batchSummary
        } else if let entry = focusedEntry {
            entryPreview(entry)
        } else {
            archiveOverview
        }
    }

    private var archiveOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("布布的一生，始终可读")
                        .font(BubuTheme.Font.hugeTitle)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("在 Mac 上集中整理成长绘本、检查待同步记录，并把完整档案导出为网页、PDF、JSON、Markdown 和原始媒体。")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                stats
                verificationCard
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var stats: some View {
        HStack(spacing: 14) {
            statCard("全部时光", entries.filter { !$0.isArchived }.count, "clock.fill")
            statCard("成长绘本", entries.filter { $0.inStorybook && !$0.isArchived }.count, "book.closed.fill")
            statCard("等待同步", entries.filter { $0.syncState != .synced && !$0.isArchived }.count, "arrow.triangle.2.circlepath")
        }
    }

    private func statCard(_ title: String, _ value: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(env.theme.theme.primary)
            Text("\(value)").font(BubuTheme.Font.hugeTitle).foregroundStyle(BubuTheme.Color.warmBrown)
            Text(title).font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var batchSummary: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(BubuTheme.Font.scaled(54))
                .foregroundStyle(env.theme.theme.primary)
            Text("已选择 \(selectedIDs.count) 条时光")
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("可以一次收进成长绘本，或安全地移入归档。所有变更都继续走现有同步引擎。")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button { applyStorybook(true) } label: { Label("收进绘本", systemImage: "book.closed.fill") }
                    .buttonStyle(.borderedProminent).tint(env.theme.theme.primary)
                Button { applyStorybook(false) } label: { Label("移出绘本", systemImage: "book.closed") }
                    .buttonStyle(.bordered)
                if filter == .archived {
                    Button { applyArchive(false) } label: { Label("恢复到时光轴", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                } else {
                    Button(role: .destructive) { showArchiveConfirmation = true } label: { Label("移入归档", systemImage: "archivebox") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func entryPreview(_ entry: Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let media = entry.coverMedia {
                    MediaThumbnail(media: media, mediaStore: env.mediaStore, cornerRadius: 22, size: .detail)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .frame(maxWidth: 760)
                }
                Text(displayTitle(entry))
                    .font(BubuTheme.Font.hugeTitle)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(BubuDateFormat.longDate(entry.happenedAt)
                     + " · " + BubuDateFormat.shortTime(entry.happenedAt)
                     + " · " + entry.authorRole)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.warmBrown)
                }
                HStack(spacing: 12) {
                    Button { applyStorybook(!entry.inStorybook) } label: {
                        Label(entry.inStorybook ? "移出成长绘本" : "收进成长绘本",
                              systemImage: entry.inStorybook ? "book.closed" : "book.closed.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(env.theme.theme.primary)
                    if entry.isArchived {
                        Button { applyArchive(false) } label: { Label("恢复到时光轴", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(.bordered)
                    } else {
                        Button(role: .destructive) { showArchiveConfirmation = true } label: { Label("移入归档", systemImage: "archivebox") }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var verificationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("恢复前先验档", systemImage: "checkmark.shield.fill")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("选择一份已经解压的开放档案。档案馆只读核对 SHA-256 和 data.json，不会覆盖当前 App 数据。")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            verificationResult
            Button { showArchiveImporter = true } label: {
                Label("选择开放档案文件夹", systemImage: "folder.badge.questionmark")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    @ViewBuilder
    private var verificationResult: some View {
        switch verificationState {
        case .idle: EmptyView()
        case .checking: Label("正在逐个核对文件…", systemImage: "hourglass")
        case let .valid(report):
            Label("校验通过 · \(report.childName) · \(report.entryCount) 条时光 · \(report.checkedFileCount) 个文件",
                  systemImage: "checkmark.seal.fill")
                .foregroundStyle(BubuTheme.Color.success)
        case let .invalid(report):
            Label("档案不完整：缺少 \(report.missingFiles.count) 个、校验不符 \(report.mismatchedFiles.count) 个文件",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(BubuTheme.Color.warning)
        case let .failed(message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(BubuTheme.Color.danger)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showArchiveImporter = true } label: { Label("校验档案", systemImage: "checkmark.shield") }
            NavigationLink { ExportView() } label: { Label("导出完整档案", systemImage: "square.and.arrow.up") }
        }
    }

    private func displayTitle(_ entry: Entry) -> String {
        if let title = entry.title, !title.isEmpty { return title }
        if let note = entry.note, !note.isEmpty { return note }
        return "这一天的时光"
    }

    private func applyStorybook(_ included: Bool) {
        guard !selectedEntries.isEmpty else { return }
        selectedEntries.forEach {
            $0.inStorybook = included
            $0.editedAt = .now
            $0.syncState = .local
        }
        saveAndSync()
    }

    private func applyArchive(_ archived: Bool) {
        guard !selectedEntries.isEmpty else { return }
        selectedEntries.forEach {
            $0.isArchived = archived
            $0.editedAt = .now
            $0.syncState = .local
        }
        saveAndSync()
        selectedIDs.removeAll()
    }

    private func saveAndSync() {
        do {
            try context.save()
            env.syncEngine.syncNow()
        } catch {
            context.rollback()
        }
    }
}
#endif
