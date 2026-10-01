import SwiftUI
import UIKit

// MARK: - 数据保护模式挡页
/// store 打不开时（`BubuStoreHealth.loadFailed`）挡在主界面之前的全屏说明页。
///
/// 为什么必须挡：降级到内存容器本身是对的（比 fatalError 好太多），但降级之后
/// 主界面看起来只是「一个还没记过东西的新家」——首页空态甚至写着「记第一笔」，
/// 主动邀请用户从头开始。妈妈重建一个布布档案、记一整天，退出 App 全丢；
/// 更糟的是若这期间同步跑通一轮，假的 ChildProfile/FamilyMember 会被推上服务器，
/// 污染全家其它设备。
///
/// 打开失败不代表已经确认数据完整；先保留现有数据库和保护副本，再安排诊断。
struct BubuStoreRecoveryView: View {
    /// 用户已明确知情并选择临时使用（本次进程有效，不落盘——下次启动仍然拦）。
    @State private var bypassed = false
    @State private var showBypassConfirm = false
    @State private var exporting = false
    @State private var exportError: String?
    @State private var shareURL: URL?

    let onContinue: () -> Void

    var body: some View {
        if bypassed {
            Color.clear.onAppear { onContinue() }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 22) {
                BubuMascotBadge(size: 92, expression: .shy)
                    .padding(.top, 30)

                VStack(spacing: 10) {
                    Text("布布的记录暂时打不开")
                        .font(BubuTheme.Font.title)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .multilineTextAlignment(.center)
                    Text("这台手机上的数据库这次没能打开。\n现有数据库和保护副本会保留，但暂时无法确认记录是否完整。请先导出可用文件，再安排检查。")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    row("1", "先把数据库导出来", "保存数据库和迁移保护文件的压缩包；不包含照片、视频、录音等媒体原文件。")
                    row("2", "再试一次", "完全退出 App 再打开。临时占用导致的失败重启就好了。")
                    row("3", "还是不行就找回来", "保留导出的压缩包，请熟悉数据库恢复的人协助检查；旧版本不一定能打开升级后的数据库。")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BubuTheme.Color.card,
                            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))

                Button {
                    Task { await exportStore() }
                } label: {
                    HStack(spacing: 8) {
                        if exporting { ProgressView().tint(.white) }
                        Text(exporting ? "正在打包…" : "导出数据库（推荐先做）")
                            .font(BubuTheme.Font.headline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(BubuTheme.Color.primary, in: Capsule())
                }
                .buttonStyle(BubuPressableStyle())
                .disabled(exporting)

                if let exportError {
                    Text(exportError)
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.deepRose)
                        .multilineTextAlignment(.center)
                }

                Button("仍要临时使用（这次记的东西不会保存）") {
                    showBypassConfirm = true
                }
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .frame(minHeight: 44)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .alert("这次记的东西不会保存", isPresented: $showBypassConfirm) {
            Button("我知道，先用一下", role: .destructive) {
                BubuHaptics.warning()
                bypassed = true
            }
            Button("先去导出", role: .cancel) {}
        } message: {
            Text("数据库没打开，App 现在跑在临时内存里。你现在记的照片和文字，退出 App 后可能无法找回。同步与后台导入已暂停，建议先导出数据。")
        }
    }

    private func row(_ index: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index)
                .font(BubuTheme.Font.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(BubuTheme.Color.primary, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(detail)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 只复制数据库及迁移保护材料，不打开或修复源数据库，也不导出媒体原文件。
    @MainActor
    private func exportStore() async {
        exporting = true
        exportError = nil
        shareURL = nil
        defer { exporting = false }

        let source = BubuStorage.storeURL
        let legacyDocuments = BubuStorage.legacyDocumentsURL
        let legacyApplicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let stamp = StoreBackupStamp.now()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("布布数据库备份_\(stamp)_\(UUID().uuidString)", isDirectory: true)

        do {
            let result = try await Task.detached(priority: .userInitiated) { () -> URL in
                try BubuStoreRecoveryPackage.prepare(
                    activeStore: source, legacyDocuments: legacyDocuments,
                    legacyApplicationSupport: legacyApplicationSupport,
                    destination: folder, stamp: stamp)
                defer { try? FileManager.default.removeItem(at: folder) }
                return try Self.zip(folder: folder)
            }.value
            BubuHaptics.success()
            shareURL = result
        } catch {
            exportError = "导出失败：\(error.localizedDescription)。请勿卸载 App 或清理文件，先保留现有数据再安排检查。"
        }
    }

    /// 由系统文件协调器创建归档；仅发布完整压缩包，重试不覆盖已有导出。
    nonisolated private static func zip(folder: URL) throws -> URL {
        let fm = FileManager.default
        let zipURL = folder.appendingPathExtension("zip")
        let stagedZip = folder.appendingPathExtension("\(UUID().uuidString).zip-partial")
        defer { try? fm.removeItem(at: stagedZip) }
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var thrown: Error?
        var copied = false
        coordinator.coordinate(readingItemAt: folder, options: [.forUploading], error: &coordError) { tmpURL in
            do {
                try fm.copyItem(at: tmpURL, to: stagedZip)
                copied = true
            } catch { thrown = error }
        }
        if let coordError { throw coordError }
        if let thrown { throw thrown }
        guard copied else { throw CocoaError(.fileWriteUnknown) }
        try fm.moveItem(at: stagedZip, to: zipURL)
        return zipURL
    }
}

/// Injectable, copy-only packaging so recovery can be tested without touching installed stores.
/// A failed copy never publishes a partial package. No source is opened with SQLite/SwiftData.
nonisolated enum BubuStoreRecoveryPackage {
    enum PackageError: LocalizedError, Equatable {
        case noDatabaseFiles, unsafeDestination, unsupportedSource

        var errorDescription: String? {
            switch self {
            case .noDatabaseFiles: "没有找到可导出的非空数据库或日志文件"
            case .unsafeDestination: "导出位置已存在或与源文件目录重叠"
            case .unsupportedSource: "数据库保护材料中存在非普通文件，无法安全打包"
            }
        }
    }

    @discardableResult
    static func prepare(activeStore: URL, legacyDocuments: URL,
                        legacyApplicationSupport: URL, destination: URL,
                        stamp: String,
                        copyFile: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }) throws -> Int {
        let fm = FileManager.default
        let roots = [activeStore.deletingLastPathComponent(), legacyDocuments, legacyApplicationSupport]
        let output = destination.resolvingSymlinksInPath().standardizedFileURL.path
        // Never create output within a source tree or remove a caller's pre-existing directory.
        guard try attributesIfPresent(destination) == nil,
              !roots.contains(where: {
                  let path = $0.resolvingSymlinksInPath().standardizedFileURL.path
                  return output == path || output.hasPrefix(path.hasSuffix("/") ? path : path + "/")
              }) else { throw PackageError.unsafeDestination }
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? fm.removeItem(at: destination) } }

        var databaseFiles = 0
        var seenStores = Set<URL>()
        let stores: [(URL, String)] = [
            (activeStore, ""),
            (legacyDocuments.appendingPathComponent(BubuStorage.storeFileName), "LegacyDocuments"),
            (legacyApplicationSupport.appendingPathComponent("default.store"), "LegacyApplicationSupport")
        ]
        for (store, namespace) in stores {
            guard seenStores.insert(store.resolvingSymlinksInPath().standardizedFileURL).inserted else { continue }
            let target = namespace.isEmpty ? destination : destination.appendingPathComponent(namespace)
            for suffix in ["", "-wal", "-shm", "-journal"] {
                let source = URL(fileURLWithPath: store.path + suffix)
                guard let attributes = try attributesIfPresent(source) else { continue }
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                databaseFiles += try copy(source, to: target.appendingPathComponent(source.lastPathComponent),
                                          attributes: attributes, allowDirectory: false, copyFile: copyFile)
            }
        }
        for name in ["Documents/UpgradeBackups", "MigrationBackups"] {
            let source = activeStore.deletingLastPathComponent().appendingPathComponent(name)
            guard let attributes = try attributesIfPresent(source) else { continue }
            let target = destination.appendingPathComponent(name)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            databaseFiles += try copy(source, to: target, attributes: attributes, allowDirectory: true, copyFile: copyFile)
        }
        // Locks, manifests, empty directories, checksums and SHM alone are not database content.
        // Damaged stores and orphan WAL/rollback journals are useful forensic material; never open them.
        guard databaseFiles > 0 else { throw PackageError.noDatabaseFiles }
        let readme = """
        布布时光机 · 数据库原样备份
        导出时间：\(stamp)
        包含 \(databaseFiles) 个非空数据库 / WAL / 回滚日志文件（未验证内容）。

        这是 SwiftData / SQLite 数据库及迁移保护文件的原样副本，未做解析或修复。
        本包不包含照片、视频、录音等媒体原文件，也不是完整的 App 备份。
        保留找到的 .store、-wal、-shm、-journal；请将同一目录的文件一起保留，不要混配不同来源。

        根目录：当前数据库；LegacyDocuments：旧 Documents 数据库；
        LegacyApplicationSupport：旧 Application Support 数据库。
        如有 UpgradeBackups / MigrationBackups，它们是历史保护材料，不保证包含最新记录。
        复制期间数据库可能变化，导出不代表文件相互一致或已验证可恢复。
        请熟悉 SwiftData / SQLite 的人先检查副本，不要直接覆盖当前数据库；
        旧版本 App 不一定能打开升级后的数据。
        """
        try readme.write(to: destination.appendingPathComponent("请先读我.txt"), atomically: true, encoding: .utf8)
        complete = true
        return databaseFiles
    }

    private static func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain,
               error.code == CocoaError.Code.fileNoSuchFile.rawValue || error.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
                return nil
            }
            throw error
        }
    }

    private static func copy(_ source: URL, to destination: URL,
                             attributes: [FileAttributeKey: Any], allowDirectory: Bool,
                             copyFile: (URL, URL) throws -> Void) throws -> Int {
        let fm = FileManager.default
        let type = attributes[.type] as? FileAttributeType
        if type == .typeDirectory, allowDirectory {
            try fm.createDirectory(at: destination, withIntermediateDirectories: false)
            var count = 0
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let childAttributes = try fm.attributesOfItem(atPath: child.path)
                count += try copy(child, to: destination.appendingPathComponent(child.lastPathComponent),
                                  attributes: childAttributes, allowDirectory: true, copyFile: copyFile)
            }
            return count
        }
        // Symlinks must not pull unrelated data into a recovery export or count as a database.
        guard type == .typeRegular else { throw PackageError.unsupportedSource }
        try copyFile(source, destination)
        let copiedSize = (try fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        let name = destination.lastPathComponent
        return copiedSize > 0 && (name.hasSuffix(".store") || name.hasSuffix(".store-wal")
                                 || name.hasSuffix(".store-journal")) ? 1 : 0
    }
}

// MARK: - 让 URL 能直接喂给 .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private enum StoreBackupStamp {
    /// 文件名友好的时间戳。ISO8601 的 .withTime 会带冒号，冒号在 Files/分享链路上会被改写，
    /// 这里直接用无分隔的形式。
    static func now() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now)
    }
}
