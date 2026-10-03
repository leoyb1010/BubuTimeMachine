import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct CapsuleRemoteMergeTests {
    private let recovery = "apple baby bear bird blue boat book brave bread bright brook calm candle cat cloud clover coral cozy cream daisy dawn deer dream drift"
    private let unlock = Date(timeIntervalSince1970: 1_000_000_000)
    private let updated = Date(timeIntervalSince1970: 2_000_000_000)

    private struct Fixture {
        let root: URL
        let container: ModelContainer
        let context: ModelContext
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("CapsuleRemoteMerge-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(schema: SharedModelContainer.schema,
                url: root.appendingPathComponent("Synthetic.store"))
            container = try ModelContainer(for: SharedModelContainer.schema, configurations: [configuration])
            context = ModelContext(container)
            context.autosaveEnabled = false
        }
        func clean() {
            // SwiftData may retain SQLite handles after local contexts leave scope.
            // Remove only our synthetic payloads; let the test sandbox reap the store.
            for file in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                where ["capsule", "tmp"].contains(file.pathExtension) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        func reopen() throws -> ModelContext {
            let configuration = ModelConfiguration(schema: SharedModelContainer.schema,
                url: root.appendingPathComponent("Synthetic.store"))
            let reopened = try ModelContainer(for: SharedModelContainer.schema, configurations: [configuration])
            let context = ModelContext(reopened)
            context.autosaveEnabled = false
            return context
        }
        func write(_ data: Data, name: String = "\(UUID()).capsule") throws -> String {
            try data.write(to: root.appendingPathComponent(name), options: .atomic)
            return name
        }
        func temporary(_ data: Data) throws -> URL {
            root.appendingPathComponent(try write(data, name: "download-\(UUID()).tmp"))
        }
    }

    private func dto(id: UUID, file: String = "new-revision.capsule", version: Int = 3) -> TimeCapsuleDTO {
        TimeCapsuleDTO(id: "synthetic-remote", localId: id.uuidString, title: "远端第二版",
            fromRole: "synthetic", unlockAt: unlock, isLocked: true,
            encryptedBlobRemoteURL: "https://capsule.example.invalid/api/files/timecapsules/synthetic/\(file)",
            coverEmoji: "✉️", cryptoVersion: version, createdAt: unlock, serverUpdatedAt: updated)
    }

    private func seed(_ fixture: Fixture) throws -> (TimeCapsule, Data) {
        let capsule = TimeCapsule(title: "本地第一版", fromRole: "synthetic", unlockAt: unlock)
        let bytes = try CapsuleCrypto().encryptV3(Data("第一封信".utf8), recoveryCode: recovery,
                                                   salt: capsule.id.uuidString)
        capsule.encryptedBlobFileName = try fixture.write(bytes)
        capsule.cryptoVersion = 3
        capsule.remoteId = "synthetic-remote"
        capsule.syncState = .synced
        fixture.context.insert(capsule)
        try fixture.context.save()
        return (capsule, bytes)
    }

    private func mergeAndCheckpoint(_ remote: TimeCapsuleDTO, fixture: Fixture, context: ModelContext? = nil,
                                    isCurrent: () -> Bool = { true },
                                    download: (String) async throws -> URL) async throws {
        let context = context ?? fixture.context
        _ = try await CapsuleRemoteMerge.merge(remote, in: context, directory: fixture.root,
            resolveFile: { fixture.root.appendingPathComponent($0) }, isCurrent: isCurrent, download: download)
        // Same consumption contract as SyncEngine.apply: an error must prevent this commit.
        try SyncCheckpoint.commit(key: "synthetic:timecapsules", generation: "synthetic",
            updated: updated, in: context) { try context.save() }
    }

    @Test("已有第一版密文也必须下载远端第二版，且旧文件保留")
    func remoteRevisionReplacesOldLetter() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let (capsule, oldBytes) = try seed(fixture)
        let oldName = try #require(capsule.encryptedBlobFileName)
        let newer = try CapsuleCrypto().encryptV3(Data("第二封信".utf8), recoveryCode: recovery, salt: capsule.id.uuidString)
        var downloads = 0
        try await mergeAndCheckpoint(dto(id: capsule.id), fixture: fixture) { _ in
            downloads += 1
            return try fixture.temporary(newer)
        }
        #expect(downloads == 1)
        let name = try #require(capsule.encryptedBlobFileName)
        #expect(name != oldName)
        let loaded = try Data(contentsOf: fixture.root.appendingPathComponent(name))
        let letter = try CapsuleCrypto().decryptV3(loaded, recoveryCode: recovery, salt: capsule.id.uuidString,
                                                   unlockAt: unlock, now: updated)
        #expect(letter == Data("第二封信".utf8))
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(oldName)) == oldBytes)
        let reopened = try fixture.reopen()
        #expect(try reopened.fetch(FetchDescriptor<TimeCapsule>()).first?.encryptedBlobFileName == name)
    }

    @Test("下载失败不推进游标，重新打开上下文后相同窗口可以补拉")
    func failedDownloadCanRetryAfterReopeningStore() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let id = UUID()
        let remote = dto(id: id)
        do {
            try await mergeAndCheckpoint(remote, fixture: fixture) { _ in throw APIError.network("synthetic failure") }
            Issue.record("失败下载被确认成功并推进游标")
        } catch {}
        let reopened = try fixture.reopen()
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: reopened) == nil)
        let bytes = try CapsuleCrypto().encryptV3(Data("重试后回来的信".utf8), recoveryCode: recovery, salt: id.uuidString)
        var downloads = 0
        try await mergeAndCheckpoint(remote, fixture: fixture, context: reopened) { _ in
            downloads += 1
            return try fixture.temporary(bytes)
        }
        #expect(downloads == 1)
        let item = try #require(reopened.fetch(FetchDescriptor<TimeCapsule>()).first)
        let name = try #require(item.encryptedBlobFileName)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(name)) == bytes)
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: reopened) == updated)
    }

    @Test("下载期间本地改写不可被远端迟到文件覆盖，并保留游标")
    func editWhileDownloadingKeepsLocalLetter() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let (capsule, _) = try seed(fixture)
        let localBytes = try CapsuleCrypto().encryptV3(Data("请求期间本地新信".utf8), recoveryCode: recovery, salt: capsule.id.uuidString)
        let localName = try fixture.write(localBytes)
        let remote = dto(id: capsule.id)
        do {
            try await mergeAndCheckpoint(remote, fixture: fixture) { _ in
                capsule.title = "请求期间本地新标题"
                capsule.encryptedBlobFileName = localName
                capsule.syncState = .local
                try fixture.context.save()
                return try fixture.temporary(Data("unused late payload".utf8))
            }
            Issue.record("本地已变化的迟到响应仍被接受")
        } catch {}
        #expect(capsule.title == "请求期间本地新标题")
        #expect(capsule.encryptedBlobFileName == localName)
        #expect(capsule.syncState == .local)
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: fixture.context) == nil)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(localName)) == localBytes)
    }

    @Test("已知v3胶囊拒绝服务端伪造v2密文，元数据和旧文件保持不变")
    func downgradedCiphertextIsRejected() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let (capsule, oldBytes) = try seed(fixture)
        let oldName = try #require(capsule.encryptedBlobFileName)
        let forged = try CapsuleCrypto().encrypt(Data("伪造的信".utf8), unlockAt: unlock, salt: capsule.id.uuidString)
        do {
            try await mergeAndCheckpoint(dto(id: capsule.id, version: 2), fixture: fixture) { _ in
                try fixture.temporary(forged)
            }
            Issue.record("降级密文被接受，或旧blob让新版检查被跳过")
        } catch {}
        #expect(capsule.cryptoVersion == 3)
        #expect(capsule.encryptedBlobFileName == oldName)
        #expect(capsule.title == "本地第一版")
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(oldName)) == oldBytes)
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: fixture.context) == nil)
    }

    @Test("下载期间同步作用域失效后不接收文件也不推进游标")
    func invalidatedRunDoesNotConsumeRemoteRecord() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let id = UUID()
        var valid = true
        do {
            try await mergeAndCheckpoint(dto(id: id), fixture: fixture, isCurrent: { valid }) { _ in
                valid = false
                return try fixture.temporary(Data("unused late payload".utf8))
            }
            Issue.record("失效轮次被确认成功")
        } catch {}
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: fixture.context) == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TimeCapsule>()) == 0)
    }

    @Test("文件身份只忽略短效token，保留来源/路径/内容参数/服务端版本")
    func persistentIdentityDistinguishesContentNotAuthentication() throws {
        let id = UUID()
        let base = "https://capsule.example.invalid/api/files/capsule/a.capsule"
        let first = try CapsuleRemoteMerge.identityPrefix(for: base + "?token=first", capsuleID: id)
        #expect(try CapsuleRemoteMerge.identityPrefix(for: base + "?token=second#preview", capsuleID: id) == first)
        for changed in [base.replacingOccurrences(of: "https:", with: "http:"),
                        base.replacingOccurrences(of: "capsule.example", with: "other.example"),
                        base.replacingOccurrences(of: "a.capsule", with: "b.capsule"),
                        base + "?revision=second"] {
            #expect(try CapsuleRemoteMerge.identityPrefix(for: changed, capsuleID: id) != first)
        }
        #expect(try CapsuleRemoteMerge.identityPrefix(for: base, capsuleID: id, serverUpdatedAt: updated) !=
                CapsuleRemoteMerge.identityPrefix(for: base, capsuleID: id, serverUpdatedAt: updated.addingTimeInterval(1)))
        #expect(!first.contains("token"))
    }

    @Test("重开上下文后同一已接收版本复用，token轮换不重复下载")
    func acceptedIdentitySurvivesReopeningContext() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let id = UUID()
        var remote = dto(id: id)
        remote.encryptedBlobRemoteURL! += "?token=first"
        let bytes = try CapsuleCrypto().encryptV3(Data("同一个版本".utf8), recoveryCode: recovery, salt: id.uuidString)
        try await mergeAndCheckpoint(remote, fixture: fixture) { _ in try fixture.temporary(bytes) }
        let reopened = try fixture.reopen()
        remote.encryptedBlobRemoteURL = remote.encryptedBlobRemoteURL?.replacingOccurrences(of: "first", with: "second")
        try await mergeAndCheckpoint(remote, fixture: fixture, context: reopened) { _ in
            Issue.record("同一版本不应因token轮换再次下载")
            throw APIError.network("unexpected download")
        }
    }

    @Test("下载回执遇到任务取消必须保留游标，不能创建半张胶囊")
    func cancelledTaskDoesNotConsumeReceipt() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let id = UUID()
        let remote = dto(id: id)
        let work = Task { @MainActor in
            try await mergeAndCheckpoint(remote, fixture: fixture) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return try fixture.temporary(Data("cancelled receipt".utf8))
            }
        }
        do { try await work.value; Issue.record("已取消任务接受了回执") } catch {}
        #expect(try fixture.context.fetchCount(FetchDescriptor<TimeCapsule>()) == 0)
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: fixture.context) == nil)
    }

    @Test("密文已下载但模型保存失败时回退引用，保留旧信并清理新文件")
    func failedPersistenceKeepsOldReceipt() async throws {
        enum SyntheticFailure: Error { case diskFull }
        let fixture = try Fixture(); defer { fixture.clean() }
        let (capsule, oldBytes) = try seed(fixture)
        let oldName = try #require(capsule.encryptedBlobFileName)
        let newer = try CapsuleCrypto().encryptV3(Data("不能确认的新信".utf8), recoveryCode: recovery, salt: capsule.id.uuidString)
        do {
            _ = try await CapsuleRemoteMerge.merge(dto(id: capsule.id), in: fixture.context, directory: fixture.root,
                resolveFile: { fixture.root.appendingPathComponent($0) }, isCurrent: { true },
                persist: { throw SyntheticFailure.diskFull }) { _ in try fixture.temporary(newer) }
            Issue.record("保存失败被当作接收成功")
        } catch SyntheticFailure.diskFull {}
        #expect(capsule.encryptedBlobFileName == oldName)
        #expect(capsule.title == "本地第一版")
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(oldName)) == oldBytes)
        let payloads = try FileManager.default.contentsOfDirectory(at: fixture.root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "capsule" }
        #expect(payloads.map(\.lastPathComponent) == [oldName])
        try fixture.context.save()
        #expect(try fixture.reopen().fetch(FetchDescriptor<TimeCapsule>()).first?.encryptedBlobFileName == oldName)
    }

    @Test("真实保存已提交后才抛错，不能删除持久化记录引用的新密文")
    func errorAfterCommitDoesNotDeleteCommittedBlob() async throws {
        enum SyntheticFailure: Error { case afterCommit }
        let fixture = try Fixture(); defer { fixture.clean() }
        let (capsule, oldBytes) = try seed(fixture)
        let oldName = try #require(capsule.encryptedBlobFileName)
        let newer = try CapsuleCrypto().encryptV3(Data("实际已提交的新信".utf8), recoveryCode: recovery, salt: capsule.id.uuidString)
        do {
            _ = try await CapsuleRemoteMerge.merge(dto(id: capsule.id), in: fixture.context, directory: fixture.root,
                resolveFile: { fixture.root.appendingPathComponent($0) }, isCurrent: { true },
                persist: { try fixture.context.save(); throw SyntheticFailure.afterCommit }) { _ in
                try fixture.temporary(newer)
            }
            Issue.record("提交后异常仍必须上报，不能假装本轮同步成功")
        } catch SyntheticFailure.afterCommit {}
        let persisted = try #require(fixture.reopen().fetch(FetchDescriptor<TimeCapsule>()).first)
        let committedName = try #require(persisted.encryptedBlobFileName)
        #expect(committedName != oldName)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(committedName).path))
        #expect(capsule.encryptedBlobFileName == committedName)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(oldName)) == oldBytes)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(committedName)) == newer)
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: fixture.context) == nil)
        try await mergeAndCheckpoint(dto(id: capsule.id), fixture: fixture) { _ in
            Issue.record("已提交版本重试应该复用持久身份")
            throw APIError.network("unexpected download")
        }
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: fixture.context) == updated)
    }

    @Test("历史v3文件尚未回填cryptoVersion也不可被降级")
    func legacyUnmarkedV3FileStillProvidesVersionFloor() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let (capsule, oldBytes) = try seed(fixture)
        capsule.cryptoVersion = nil
        try fixture.context.save()
        let oldName = try #require(capsule.encryptedBlobFileName)
        let downgraded = try CapsuleCrypto().encrypt(Data("伪造旧版本".utf8), unlockAt: unlock, salt: capsule.id.uuidString)
        do {
            try await mergeAndCheckpoint(dto(id: capsule.id, version: 2), fixture: fixture) { _ in
                try fixture.temporary(downgraded)
            }
            Issue.record("没有版本数字的真实v3密文被降级")
        } catch {}
        #expect(capsule.cryptoVersion == nil)
        #expect(capsule.encryptedBlobFileName == oldName)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(oldName)) == oldBytes)
        #expect(try SyncCheckpoint.read(key: "synthetic:timecapsules", generation: "synthetic", in: fixture.context) == nil)
    }
}
