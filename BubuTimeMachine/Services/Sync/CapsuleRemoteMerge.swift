import Foundation
import SwiftData
import CryptoKit

/// Capsule file receipt and model merge share one boundary, exercised with a real store.
@MainActor
enum CapsuleRemoteMerge {
    static func merge(_ dto: TimeCapsuleDTO, in context: ModelContext, directory: URL,
                      resolveFile: (String) -> URL, isCurrent: () -> Bool,
                      persist: (() throws -> Void)? = nil,
                      download: (String) async throws -> URL) async throws -> Bool {
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        guard let id = UUID(uuidString: dto.localId) else { return true }
        let descriptor = FetchDescriptor<TimeCapsule>(predicate: #Predicate { $0.id == id })
        let existing = try context.fetch(descriptor).first
        if let existing, existing.syncState != .synced { return false }
        let before = existing.map(Snapshot.init)
        guard let remote = dto.encryptedBlobRemoteURL else {
            throw APIError.network("时间胶囊密文尚未上传完成")
        }
        let prefix = try identityPrefix(for: remote, capsuleID: id, serverUpdatedAt: dto.serverUpdatedAt)
        // A legacy v3 file is also a local version floor even before cryptoVersion
        // was backfilled. No recovery code or plaintext is needed for this check.
        var minimumVersion = max(existing?.cryptoVersion ?? 0, dto.cryptoVersion ?? 0)
        if let oldName = before?.fileName,
           let handle = try? FileHandle(forReadingFrom: resolveFile(oldName)) {
            defer { try? handle.close() }
            if (try? handle.read(upToCount: 4)) == CapsuleCrypto.v3Magic { minimumVersion = max(minimumVersion, 3) }
        }
        let name: String
        var newFile: URL?
        var accepted = false
        defer { if !accepted, let newFile { try? FileManager.default.removeItem(at: newFile) } }
        let actualVersion: Int
        if let cached = before?.fileName, cached.hasPrefix(prefix),
           let version = try? validateBlob(at: resolveFile(cached), minimumVersion: minimumVersion) {
            name = cached
            actualVersion = version
        } else {
            let temporary = try await download(remote)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard isCurrent(), !Task.isCancelled,
                  try context.fetch(descriptor).first.map(Snapshot.init) == before else {
                throw CancellationError()
            }
            actualVersion = try validateBlob(at: temporary, minimumVersion: minimumVersion)
            // Unique suffix: never overwrite an old revision or another in-flight receipt.
            name = prefix + UUID().uuidString + ".capsule"
            let destination = directory.appendingPathComponent(name)
            newFile = destination
            try FileManager.default.copyItem(at: temporary, to: destination)
        }
        guard isCurrent(), !Task.isCancelled,
              try context.fetch(descriptor).first.map(Snapshot.init) == before else { throw CancellationError() }
        let capsule = existing ?? TimeCapsule(title: dto.title, fromRole: dto.fromRole, unlockAt: dto.unlockAt)
        if existing == nil {
            capsule.id = id
            context.insert(capsule)
        }
        apply(dto, to: capsule)
        capsule.remoteId = dto.id
        capsule.encryptedBlobFileName = name
        capsule.cryptoVersion = max(minimumVersion, actualVersion)
        capsule.syncState = .synced
        do {
            if let persist { try persist() } else { try context.save() }
        } catch {
            let persistenceError = error
            // A persistence boundary can throw after the transaction committed.
            // Read from another context before deleting a file that the store may
            // already reference. An unreadable outcome retains both copies safely.
            do {
                let verification = ModelContext(context.container)
                verification.autosaveEnabled = false
                let saved = try verification.fetch(descriptor).first
                if saved?.encryptedBlobFileName == name {
                    accepted = true
                } else {
                    // Only a confirmed uncommitted receipt may restore its fields.
                    // Never roll back unrelated edits in the shared context.
                    if let before { before.restore(capsule) }
                    else { context.delete(capsule) }
                }
            } catch {
                accepted = true
            }
            // Retaining a committed/uncertain file does not acknowledge the pull:
            // propagate the failure so its checkpoint stays available for retry.
            throw persistenceError
        }
        accepted = true
        return true
    }

    /// PocketBase reuploads produce new filenames. Only its short-lived `token`
    /// query item is ignored; origin, path and content-selecting query items remain.
    static func identityPrefix(for remote: String, capsuleID: UUID, serverUpdatedAt: Date? = nil) throws -> String {
        guard var parts = URLComponents(string: remote),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil else { throw APIError.network("时间胶囊文件地址无效") }
        parts.scheme = scheme
        parts.host = host
        parts.fragment = nil
        if let query = parts.queryItems {
            let retained = query.filter { $0.name != "token" }
            parts.queryItems = retained.isEmpty ? nil : retained
        }
        guard let canonical = parts.string else { throw APIError.network("时间胶囊文件地址无效") }
        // Also bind the server revision when available: a backend reusing a file
        // path must not make an updated ciphertext look like the cached version.
        let revision = serverUpdatedAt.map { String($0.timeIntervalSince1970) } ?? "unknown"
        let digest = SHA256.hash(data: Data("\(canonical)|updated=\(revision)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "capsule-\(capsuleID.uuidString)-\(digest)-"
    }

    private static func validateBlob(at url: URL, minimumVersion: Int) throws -> Int {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let version = data.starts(with: CapsuleCrypto.v3Magic) ? 3 : (data.starts(with: CapsuleCrypto.v2Magic) ? 2 : 1)
        guard minimumVersion <= 3, minimumVersion < 3 || version == 3 else {
            throw CapsuleCrypto.CryptoError.decryptionFailed
        }
        let body = version == 1 ? data : Data(data.dropFirst(4))
        _ = try AES.GCM.SealedBox(combined: body)
        // Structural/version validation only; AEAD authentication still occurs at unseal.
        return version
    }

    private struct Snapshot: Equatable {
        let remoteID: String?
        let title: String
        let fromRole: String
        let unlockAt: Date
        let locked: Bool
        let fileName: String?
        let emoji: String?
        let version: Int?
        let state: String
        let createdAt: Date

        init(_ item: TimeCapsule) {
            remoteID = item.remoteId; title = item.title; fromRole = item.fromRole
            unlockAt = item.unlockAt; locked = item.isLocked; fileName = item.encryptedBlobFileName
            emoji = item.coverEmoji; version = item.cryptoVersion; state = item.syncStateRaw; createdAt = item.createdAt
        }
        func restore(_ item: TimeCapsule) {
            item.remoteId = remoteID; item.title = title; item.fromRole = fromRole
            item.unlockAt = unlockAt; item.isLocked = locked; item.encryptedBlobFileName = fileName
            item.coverEmoji = emoji; item.cryptoVersion = version; item.syncStateRaw = state; item.createdAt = createdAt
        }
    }

    private static func apply(_ dto: TimeCapsuleDTO, to item: TimeCapsule) {
        item.title = dto.title
        item.fromRole = dto.fromRole
        // Legacy v1 keys depend on the exact local unlock timestamp.
        item.isLocked = dto.isLocked
        item.coverEmoji = dto.coverEmoji
        if let remote = dto.cryptoVersion, remote > (item.cryptoVersion ?? 0) {
            item.cryptoVersion = remote
        }
        item.createdAt = dto.createdAt
    }
}
