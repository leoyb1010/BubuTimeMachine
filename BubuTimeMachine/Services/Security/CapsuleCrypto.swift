import Foundation
import CryptoKit

// MARK: - 时间胶囊加解密
/// AES-GCM 加密。密钥派生绑定解锁时间——到期前 UI 不可解。
///
/// v2（当前）：密钥由「规范化 ISO8601 字符串(整秒, UTC) + salt」派生，
/// 与服务器存储格式（ISO8601 整秒）天然一致——同步往返不会再改变派生输入。
/// v1（历史）：密钥由 `timeIntervalSince1970`（含亚秒小数）派生；
/// 该小数会被 ISO8601 序列化截断，同步一轮后本地 unlockAt 被覆盖 → 永久解不开。
/// v2 blob 带 "BTC2" 魔数前缀；无前缀按 v1 解，并尝试整秒取整两种候选。
struct CapsuleCrypto: Sendable {

    enum CryptoError: LocalizedError {
        case stillLocked(unlockAt: Date)
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .stillLocked(let date):
                return "这封信要到 \(BubuDateFormat.longDate(date)) 才能打开哦"
            case .decryptionFailed:
                return "信件打不开了，请检查备份"
            }
        }
    }

    /// v2 blob 魔数前缀。
    static let v2Magic = Data("BTC2".utf8)

    /// 把解锁时间规整到整秒——封存与派生都必须用规整后的值。
    static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// 规范化字符串：整秒 UTC ISO8601，跨设备/跨序列化稳定。
    private static func canonicalString(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")
        return iso.string(from: normalized(date))
    }

    private func deriveKeyV2(unlockAt: Date, salt: String) -> SymmetricKey {
        let material = "\(Self.canonicalString(unlockAt))|\(salt)|bubu-time-capsule-v2"
        let hash = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: hash)
    }

    /// v1 历史派生（仅用于解开旧 blob）。
    private func deriveKeyV1(unlockInterval: TimeInterval, salt: String) -> SymmetricKey {
        let material = "\(unlockInterval)|\(salt)|bubu-time-capsule"
        let hash = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: hash)
    }

    /// 加密明文（信件文本 / 序列化后的音视频引用）。输出带 v2 魔数前缀。
    func encrypt(_ plaintext: Data, unlockAt: Date, salt: String) throws -> Data {
        let key = deriveKeyV2(unlockAt: unlockAt, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.decryptionFailed }
        return Self.v2Magic + combined
    }

    /// 解密。到期前拒绝（UI 层也会拦截，这里是第二道防线）。
    func decrypt(_ ciphertext: Data, unlockAt: Date, salt: String, now: Date = .now) throws -> Data {
        guard now >= Self.normalized(unlockAt) else {
            throw CryptoError.stillLocked(unlockAt: unlockAt)
        }
        if ciphertext.starts(with: Self.v2Magic) {
            let body = ciphertext.dropFirst(Self.v2Magic.count)
            return try open(body, with: deriveKeyV2(unlockAt: unlockAt, salt: salt))
        }
        // v1 旧 blob：先按当前值原样尝试，再尝试整秒取整（同步截断前后的两种可能）。
        let interval = unlockAt.timeIntervalSince1970
        var candidates: [TimeInterval] = [interval]
        if interval != interval.rounded(.down) {
            candidates.append(interval.rounded(.down))
        }
        for candidate in candidates {
            if let plain = try? open(ciphertext, with: deriveKeyV1(unlockInterval: candidate, salt: salt)) {
                return plain
            }
        }
        throw CryptoError.decryptionFailed
    }

    private func open(_ combined: Data, with key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: Data(combined))
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
}
