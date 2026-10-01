import Foundation
import Testing
@testable import BubuTimeMachine

/// Synthetic bytes in a UUID temporary directory only. Never reads installed stores or fixtures.
@MainActor
struct StoreRecoveryExportTests {
    private struct Fixture {
        let root: URL
        var sources: URL { root.appendingPathComponent("Sources") }
        var activeStore: URL { sources.appendingPathComponent("AppGroup/BubuTimeMachine.store") }
        var documents: URL { sources.appendingPathComponent("Documents") }
        var applicationSupport: URL { sources.appendingPathComponent("ApplicationSupport") }
        var destination: URL { root.appendingPathComponent("Package") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("StoreRecoveryExport-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        @discardableResult
        func write(_ path: String, _ text: String) throws -> URL {
            let url = sources.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            return url
        }

        @discardableResult
        func prepare(destination: URL? = nil, activeStore: URL? = nil) throws -> Int {
            try BubuStoreRecoveryPackage.prepare(
                activeStore: activeStore ?? self.activeStore,
                legacyDocuments: documents, legacyApplicationSupport: applicationSupport,
                destination: destination ?? self.destination, stamp: "synthetic-test")
        }

        func bytes(_ path: String, exported: Bool = false) throws -> Data {
            try Data(contentsOf: (exported ? destination : sources).appendingPathComponent(path))
        }
    }

    @Test("活动库缺失时仍导出两个旧沙盒三件套，并保留来源区别")
    func exportsBothLegacyTriosWithoutActiveStore() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("AppGroup/Documents/UpgradeBackups/migration.lock", "")
        for suffix in ["", "-wal", "-shm"] {
            try fixture.write("Documents/BubuTimeMachine.store" + suffix, "documents" + suffix)
            try fixture.write("ApplicationSupport/default.store" + suffix, "application-support" + suffix)
        }

        #expect(try fixture.prepare() == 4)
        for suffix in ["", "-wal", "-shm"] {
            #expect(try fixture.bytes("LegacyDocuments/BubuTimeMachine.store" + suffix, exported: true)
                    == Data(("documents" + suffix).utf8))
            #expect(try fixture.bytes("LegacyApplicationSupport/default.store" + suffix, exported: true)
                    == Data(("application-support" + suffix).utf8))
            #expect(try fixture.bytes("Documents/BubuTimeMachine.store" + suffix) == Data(("documents" + suffix).utf8))
            #expect(try fixture.bytes("ApplicationSupport/default.store" + suffix) == Data(("application-support" + suffix).utf8))
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.activeStore.path))
    }

    @Test("活动库与同名旧库不混配，导出说明明确不包含媒体原文件")
    func preservesActiveAndLegacySourcesWithoutMedia() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let files = [
            "AppGroup/BubuTimeMachine.store": "damaged active database bytes",
            "Documents/BubuTimeMachine.store": "older database bytes",
            "ApplicationSupport/default.store": "oldest database bytes",
            "AppGroup/Media/photo.jpg": "synthetic photo",
            "Documents/Media/voice.m4a": "synthetic audio"
        ]
        for (path, text) in files { try fixture.write(path, text) }
        let originalDate = try FileManager.default.attributesOfItem(atPath: fixture.activeStore.path)[.modificationDate] as? Date

        #expect(try fixture.prepare() == 3)
        #expect(try fixture.bytes("BubuTimeMachine.store", exported: true) == Data(files["AppGroup/BubuTimeMachine.store"]!.utf8))
        #expect(try fixture.bytes("LegacyDocuments/BubuTimeMachine.store", exported: true) == Data(files["Documents/BubuTimeMachine.store"]!.utf8))
        for (path, text) in files { #expect(try fixture.bytes(path) == Data(text.utf8)) }
        #expect(try FileManager.default.attributesOfItem(atPath: fixture.activeStore.path)[.modificationDate] as? Date == originalDate)
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("Media").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("LegacyDocuments/Media").path))
        let readme = try String(contentsOf: fixture.destination.appendingPathComponent("请先读我.txt"), encoding: .utf8)
        #expect(readme.contains("不包含照片、视频、录音等媒体原文件"))
        #expect(readme.contains("不代表文件相互一致或已验证可恢复"))
    }

    @Test("只有嵌套保护副本也可导出，并保留日志和校验材料")
    func exportsNestedProtectionBackups() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let files = [
            "Documents/UpgradeBackups/pre-v2.store": "upgrade database",
            "Documents/UpgradeBackups/pre-v2.store.sha256": "synthetic checksum",
            "Documents/UpgradeBackups/migration.lock": "",
            "MigrationBackups/old-run/BubuTimeMachine.store": "old database",
            "MigrationBackups/old-run/BubuTimeMachine.store-wal": "old journal",
            "MigrationBackups/old-run/BubuTimeMachine.store-shm": "old shared memory"
        ]
        for (path, text) in files { try fixture.write("AppGroup/" + path, text) }

        #expect(try fixture.prepare() == 3)
        for (path, text) in files {
            #expect(try fixture.bytes(path, exported: true) == Data(text.utf8))
            #expect(try fixture.bytes("AppGroup/" + path) == Data(text.utf8))
        }
    }

    @Test("锁、清单、校验、空数据库或单独 SHM 不能假报导出成功", arguments: [
        "Documents/UpgradeBackups/migration.lock",
        "Documents/UpgradeBackups/pre-v2.store.sha256",
        "Documents/UpgradeBackups/manifest.json",
        "BubuTimeMachine.store-shm",
        "Documents/UpgradeBackups/pre-v2.store-shm",
        "Documents/UpgradeBackups/pre-v2.store"
    ])
    func auxiliaryOrEmptyFilesDoNotCount(path: String) throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let text = path.hasSuffix(".store") ? "" : "synthetic auxiliary bytes"
        try fixture.write("AppGroup/" + path, text)

        #expect(throws: BubuStoreRecoveryPackage.PackageError.noDatabaseFiles) { try fixture.prepare() }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(try fixture.bytes("AppGroup/" + path) == Data(text.utf8))
    }

    @Test("空目录不能假报导出成功")
    func emptyProtectionDirectoriesDoNotCount() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        for name in ["AppGroup/Documents/UpgradeBackups", "AppGroup/MigrationBackups/empty"] {
            try FileManager.default.createDirectory(at: fixture.sources.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        #expect(throws: BubuStoreRecoveryPackage.PackageError.noDatabaseFiles) { try fixture.prepare() }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(FileManager.default.fileExists(atPath: fixture.sources.appendingPathComponent("AppGroup/MigrationBackups/empty").path))
    }

    @Test("孤立 WAL 仍作为待检查的恢复材料保留", arguments: [
        "AppGroup/BubuTimeMachine.store-wal",
        "Documents/BubuTimeMachine.store-wal",
        "ApplicationSupport/default.store-wal",
        "AppGroup/Documents/UpgradeBackups/pre-v2.store-wal"
    ])
    func preservesOrphanWAL(path: String) throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write(path, "synthetic orphan WAL")
        #expect(try fixture.prepare() == 1)
        #expect(try fixture.bytes(path) == Data("synthetic orphan WAL".utf8))
    }

    @Test("启动保护保留的孤立回滚日志也可原样导出", arguments: [
        "AppGroup/BubuTimeMachine.store-journal",
        "Documents/BubuTimeMachine.store-journal",
        "ApplicationSupport/default.store-journal",
        "AppGroup/Documents/UpgradeBackups/pre-v2.store-journal"
    ])
    func preservesOrphanRollbackJournal(path: String) throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let bytes = Data("synthetic orphan rollback journal".utf8)
        try fixture.write(path, "synthetic orphan rollback journal")
        #expect(try fixture.prepare() == 1)
        #expect(try fixture.bytes(path) == bytes)
        let exported: String
        if path.hasPrefix("AppGroup/") {
            exported = String(path.dropFirst("AppGroup/".count))
        } else if path.hasPrefix("Documents/") {
            exported = "LegacyDocuments/" + String(path.dropFirst("Documents/".count))
        } else {
            exported = "LegacyApplicationSupport/" + String(path.dropFirst("ApplicationSupport/".count))
        }
        #expect(try fixture.bytes(exported, exported: true) == bytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.activeStore.path))
        let readme = try String(contentsOf: fixture.destination.appendingPathComponent("请先读我.txt"), encoding: .utf8)
        #expect(readme.contains("未验证内容"))
        #expect(readme.contains("不代表文件相互一致或已验证可恢复"))
    }

    @Test("复制部分文件后遇到异常必须失败并清理输出，不删除任何源文件")
    func partialCopyFailureDoesNotLeavePackage() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("AppGroup/BubuTimeMachine.store", "preserve database")
        // The main file is copied first; a directory where its WAL should be then fails safely.
        try fixture.write("AppGroup/BubuTimeMachine.store-wal/keep.txt", "preserve unexpected source")

        #expect(throws: BubuStoreRecoveryPackage.PackageError.unsupportedSource) { try fixture.prepare() }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(try fixture.bytes("AppGroup/BubuTimeMachine.store") == Data("preserve database".utf8))
        #expect(try fixture.bytes("AppGroup/BubuTimeMachine.store-wal/keep.txt") == Data("preserve unexpected source".utf8))
    }

    @Test("实际文件复制报错不能分享已复制的半包，重试可以成功")
    func copyErrorCleansStagingAndAllowsRetry() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("AppGroup/BubuTimeMachine.store", "keep database")
        try fixture.write("AppGroup/BubuTimeMachine.store-wal", "keep journal")
        var attempted: [String] = []
        #expect(throws: CocoaError.self) {
            try BubuStoreRecoveryPackage.prepare(
                activeStore: fixture.activeStore, legacyDocuments: fixture.documents,
                legacyApplicationSupport: fixture.applicationSupport,
                destination: fixture.destination, stamp: "synthetic-copy-failure") { source, destination in
                    attempted.append(source.lastPathComponent)
                    if source.lastPathComponent.hasSuffix("-wal") { throw CocoaError(.fileReadNoPermission) }
                    try FileManager.default.copyItem(at: source, to: destination)
                }
        }
        #expect(attempted == ["BubuTimeMachine.store", "BubuTimeMachine.store-wal"])
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(try fixture.bytes("AppGroup/BubuTimeMachine.store") == Data("keep database".utf8))
        #expect(try fixture.bytes("AppGroup/BubuTimeMachine.store-wal") == Data("keep journal".utf8))
        #expect(try fixture.prepare() == 2)
        #expect(try fixture.bytes("BubuTimeMachine.store", exported: true) == Data("keep database".utf8))
        #expect(try fixture.bytes("BubuTimeMachine.store-wal", exported: true) == Data("keep journal".utf8))
    }

    @Test("已有输出目录不能覆盖或被失败清理删除")
    func existingOutputIsNeverRemoved() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        let sentinel = fixture.destination.appendingPathComponent("keep.txt")
        try Data("previous export".utf8).write(to: sentinel)
        #expect(throws: BubuStoreRecoveryPackage.PackageError.unsafeDestination) { try fixture.prepare() }
        #expect(try Data(contentsOf: sentinel) == Data("previous export".utf8))
    }

    @Test("导出目录不能放到任何源目录内部", arguments: ["AppGroup", "Documents", "ApplicationSupport"])
    func sourceTreesCannotBecomeOutput(root: String) throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("AppGroup/BubuTimeMachine.store", "keep")
        let destination = fixture.sources.appendingPathComponent(root + "/NewExport")
        #expect(throws: BubuStoreRecoveryPackage.PackageError.unsafeDestination) {
            try fixture.prepare(destination: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try fixture.bytes("AppGroup/BubuTimeMachine.store") == Data("keep".utf8))
    }

    @Test("符号链接不能冒充数据库日志或带出无关内容")
    func rejectsLinkedJournal() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.write("AppGroup/BubuTimeMachine.store", "keep database")
        let unrelated = try fixture.write("Unrelated/private.txt", "unrelated bytes")
        let link = URL(fileURLWithPath: fixture.activeStore.path + "-wal")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)

        #expect(throws: BubuStoreRecoveryPackage.PackageError.unsupportedSource) { try fixture.prepare() }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(try Data(contentsOf: unrelated) == Data("unrelated bytes".utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == unrelated.path)
    }

    @Test("App Group 回退到 Documents 时同一来源只复制一次")
    func fallbackDocumentsStoreIsNotDuplicated() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try fixture.write("Documents/BubuTimeMachine.store", "fallback database")
        #expect(try fixture.prepare(activeStore: source) == 1)
        #expect(try fixture.bytes("BubuTimeMachine.store", exported: true) == Data("fallback database".utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("LegacyDocuments").path))
        #expect(try Data(contentsOf: source) == Data("fallback database".utf8))
    }
}
