import CryptoKit
import Foundation
import SQLite3

// MARK: - 智能收件箱持久状态

nonisolated enum PhotoIntakeState: String, Sendable {
    case discovered
    case accepted
    case ignored
    case failed
    case deleted
}

nonisolated enum PhotoIntakeMediaKind: Int, Sendable {
    case photo = 1
    case video = 2
}

/// PhotoKit 资产的轻量镜像，只保存摄取所需元数据，不复制照片字节。
nonisolated struct PhotoIntakeCandidate: Sendable, Equatable {
    let localIdentifier: String
    let creationDate: Date
    let mediaKind: PhotoIntakeMediaKind
    let latitude: Double?
    let longitude: Double?
    let width: Int
    let height: Int
    let duration: Double
    let burstIdentifier: String?
    let isLivePhoto: Bool
}

nonisolated struct PhotoIdentitySample: Sendable, Equatable {
    let label: Int
    let featureData: Data
}

/// App 与未来 PhotoKit 后台扩展共享的独立摄取库。
/// 候选是可重建派生状态，绝不为它修改 SwiftData 事实 schema。
nonisolated struct PhotoIntakeStore: Sendable {
    enum StoreError: Error, LocalizedError {
        case open(String)
        case sqlite(String)

        var errorDescription: String? {
            switch self {
            case .open(let message): "无法打开照片摄取库：\(message)"
            case .sqlite(let message): "照片摄取库操作失败：\(message)"
            }
        }
    }

    let databaseURL: URL
    private let excludeFromBackup: Bool

    init(
        databaseURL: URL = BubuStorage.intakeDatabaseURL,
        excludeFromBackup: Bool = false
    ) {
        self.databaseURL = databaseURL
        self.excludeFromBackup = excludeFromBackup
    }

    func upsertDiscovered(_ candidates: [PhotoIntakeCandidate]) throws {
        guard !candidates.isEmpty else { return }
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                let sql = """
                INSERT INTO intake_assets(
                    local_identifier, state, created_at, media_type, latitude, longitude,
                    width, height, duration, burst_identifier, is_live_photo, last_seen_at, updated_at
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(local_identifier) DO UPDATE SET
                    created_at = excluded.created_at,
                    media_type = excluded.media_type,
                    latitude = excluded.latitude,
                    longitude = excluded.longitude,
                    width = excluded.width,
                    height = excluded.height,
                    duration = excluded.duration,
                    burst_identifier = excluded.burst_identifier,
                    is_live_photo = excluded.is_live_photo,
                    last_seen_at = excluded.last_seen_at,
                    updated_at = excluded.updated_at
                """
                let statement = try prepare(sql, db: db)
                defer { sqlite3_finalize(statement) }
                let now = Date().timeIntervalSince1970

                for item in candidates {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(item.localIdentifier, at: 1, to: statement)
                    bind(PhotoIntakeState.discovered.rawValue, at: 2, to: statement)
                    sqlite3_bind_double(statement, 3, item.creationDate.timeIntervalSince1970)
                    sqlite3_bind_int(statement, 4, Int32(item.mediaKind.rawValue))
                    bind(item.latitude, at: 5, to: statement)
                    bind(item.longitude, at: 6, to: statement)
                    sqlite3_bind_int64(statement, 7, Int64(item.width))
                    sqlite3_bind_int64(statement, 8, Int64(item.height))
                    sqlite3_bind_double(statement, 9, item.duration)
                    bind(item.burstIdentifier, at: 10, to: statement)
                    sqlite3_bind_int(statement, 11, item.isLivePhoto ? 1 : 0)
                    sqlite3_bind_double(statement, 12, now)
                    sqlite3_bind_double(statement, 13, now)
                    try stepDone(statement, db: db)
                }
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func mark(_ identifiers: [String], state: PhotoIntakeState) throws {
        guard !identifiers.isEmpty else { return }
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                let sql = """
                INSERT INTO intake_assets(local_identifier, state, created_at, media_type,
                                          width, height, duration, is_live_photo,
                                          last_seen_at, updated_at)
                VALUES(?, ?, 0, 1, 0, 0, 0, 0, ?, ?)
                ON CONFLICT(local_identifier) DO UPDATE SET
                    state = excluded.state,
                    updated_at = excluded.updated_at
                """
                let statement = try prepare(sql, db: db)
                defer { sqlite3_finalize(statement) }
                let now = Date().timeIntervalSince1970
                for identifier in identifiers {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(identifier, at: 1, to: statement)
                    bind(state.rawValue, at: 2, to: statement)
                    sqlite3_bind_double(statement, 3, now)
                    sqlite3_bind_double(statement, 4, now)
                    try stepDone(statement, db: db)
                }
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func pendingIdentifiers() throws -> [String] {
        try withDatabase { db in
            let statement = try prepare(
                """
                SELECT local_identifier FROM intake_assets
                WHERE state IN ('discovered', 'failed')
                ORDER BY created_at DESC
                """, db: db)
            defer { sqlite3_finalize(statement) }
            var result: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    result.append(String(cString: text))
                }
            }
            return result
        }
    }

    func states(for identifiers: [String]) throws -> [String: PhotoIntakeState] {
        guard !identifiers.isEmpty else { return [:] }
        let wanted = Set(identifiers)
        return try withDatabase { db in
            let statement = try prepare(
                "SELECT local_identifier, state FROM intake_assets", db: db)
            defer { sqlite3_finalize(statement) }
            var result: [String: PhotoIntakeState] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idText = sqlite3_column_text(statement, 0),
                      let stateText = sqlite3_column_text(statement, 1) else { continue }
                let identifier = String(cString: idText)
                guard wanted.contains(identifier),
                      let state = PhotoIntakeState(rawValue: String(cString: stateText)) else { continue }
                result[identifier] = state
            }
            return result
        }
    }

    func data(forMetadataKey key: String) throws -> Data? {
        try withDatabase { db in
            let statement = try prepare(
                "SELECT value FROM intake_metadata WHERE key = ? LIMIT 1", db: db)
            defer { sqlite3_finalize(statement) }
            bind(key, at: 1, to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { return Data() }
            return Data(bytes: bytes, count: count)
        }
    }

    func setData(_ data: Data?, forMetadataKey key: String) throws {
        try withDatabase { db in
            if let data {
                let statement = try prepare(
                    """
                    INSERT INTO intake_metadata(key, value) VALUES(?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                bind(key, at: 1, to: statement)
                _ = data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, 2, raw.baseAddress, Int32(raw.count), Self.transient)
                }
                try stepDone(statement, db: db)
            } else {
                let statement = try prepare(
                    "DELETE FROM intake_metadata WHERE key = ?", db: db)
                defer { sqlite3_finalize(statement) }
                bind(key, at: 1, to: statement)
                try stepDone(statement, db: db)
            }
        }
    }

    // MARK: - 本机身份样本

    /// `label`: 1 = 这是布布，-1 = 不是布布。每类只保留最近 40 张脸，避免模型无限增长。
    func addIdentitySamples(_ featurePrints: [Data], label: Int) throws {
        guard !featurePrints.isEmpty, label == 1 || label == -1 else { return }
        try withDatabase { db in
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                let statement = try prepare(
                    """
                    INSERT INTO identity_samples(id, label, feature_print, created_at)
                    VALUES(?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET label = excluded.label, created_at = excluded.created_at
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                let now = Date().timeIntervalSince1970
                for feature in featurePrints {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    let digest = SHA256.hash(data: feature).map { String(format: "%02x", $0) }.joined()
                    bind(digest, at: 1, to: statement)
                    sqlite3_bind_int(statement, 2, Int32(label))
                    _ = feature.withUnsafeBytes { raw in
                        sqlite3_bind_blob(statement, 3, raw.baseAddress, Int32(raw.count), Self.transient)
                    }
                    sqlite3_bind_double(statement, 4, now)
                    try stepDone(statement, db: db)
                }
                let prune = try prepare(
                    """
                    DELETE FROM identity_samples
                    WHERE label = ? AND id NOT IN (
                        SELECT id FROM identity_samples WHERE label = ?
                        ORDER BY created_at DESC LIMIT 40
                    )
                    """, db: db)
                defer { sqlite3_finalize(prune) }
                sqlite3_bind_int(prune, 1, Int32(label))
                sqlite3_bind_int(prune, 2, Int32(label))
                try stepDone(prune, db: db)
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
    }

    func identitySamples() throws -> [PhotoIdentitySample] {
        try withDatabase { db in
            let statement = try prepare(
                "SELECT label, feature_print FROM identity_samples ORDER BY created_at DESC", db: db)
            defer { sqlite3_finalize(statement) }
            var result: [PhotoIdentitySample] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let label = Int(sqlite3_column_int(statement, 0))
                let count = Int(sqlite3_column_bytes(statement, 1))
                guard count > 0, let bytes = sqlite3_column_blob(statement, 1) else { continue }
                result.append(PhotoIdentitySample(
                    label: label,
                    featureData: Data(bytes: bytes, count: count)
                ))
            }
            return result
        }
    }

    func identitySampleCounts() throws -> (positive: Int, negative: Int) {
        let samples = try identitySamples()
        return (samples.count { $0.label == 1 }, samples.count { $0.label == -1 })
    }

    func clearIdentitySamples() throws {
        try withDatabase { db in try execute("DELETE FROM identity_samples", db: db) }
    }

    // MARK: SQLite

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        let code = sqlite3_open_v2(databaseURL.path, &database,
                                   SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                                   nil)
        guard code == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if let database { sqlite3_close(database) }
            throw StoreError.open(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        try execute("PRAGMA journal_mode=WAL", db: database)
        try execute("PRAGMA foreign_keys=ON", db: database)
        try createSchema(db: database)
        applyFileProtection()
        return try body(database)
    }

    /// 候选库含拍摄时间与可选 GPS，使用系统数据保护；后台任务在首次解锁后仍可继续。
    /// 身份库额外标记为不进入系统备份，保证人脸特征只留在当前设备。
    private func applyFileProtection() {
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: path)
            if excludeFromBackup {
                var fileURL = URL(fileURLWithPath: path)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? fileURL.setResourceValues(values)
            }
        }
        #endif
    }

    private func createSchema(db: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS intake_metadata(
                key TEXT PRIMARY KEY NOT NULL,
                value BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS intake_assets(
                local_identifier TEXT PRIMARY KEY NOT NULL,
                cloud_identifier TEXT,
                state TEXT NOT NULL,
                group_id TEXT,
                content_hash TEXT,
                created_at REAL NOT NULL,
                media_type INTEGER NOT NULL,
                latitude REAL,
                longitude REAL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                duration REAL NOT NULL,
                burst_identifier TEXT,
                is_live_photo INTEGER NOT NULL DEFAULT 0,
                last_seen_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_intake_assets_state_created
                ON intake_assets(state, created_at DESC);
            CREATE TABLE IF NOT EXISTS identity_samples(
                id TEXT PRIMARY KEY NOT NULL,
                label INTEGER NOT NULL CHECK(label IN (-1, 1)),
                feature_print BLOB NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_identity_samples_label_created
                ON identity_samples(label, created_at DESC);
            """, db: db)
    }

    private func execute(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw StoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, db: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, Self.transient)
        }
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value { bind(value, at: index, to: statement) }
        else { sqlite3_bind_null(statement, index) }
    }

    private func bind(_ value: Double?, at index: Int32, to statement: OpaquePointer) {
        if let value { sqlite3_bind_double(statement, index, value) }
        else { sqlite3_bind_null(statement, index) }
    }

    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
