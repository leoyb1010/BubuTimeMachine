import Foundation
import CryptoKit

// MARK: - 时间胶囊加解密
/// AES-GCM 加密。密钥派生绑定解锁时间——到期前 UI 不可解。
/// M1 阶段提供可用的加解密原语；密钥托管/Keychain 绑定在胶囊模块深入时完善。
struct CapsuleCrypto: Sendable {

    enum CryptoError: LocalizedError {
        case stillLocked(unlockAt: Date)
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .stillLocked(let date):
                return "这封信要到 \(date.formatted(date: .long, time: .omitted)) 才能打开哦"
            case .decryptionFailed:
                return "信件打不开了，请检查备份"
            }
        }
    }

    /// 由解锁时间 + 标题派生对称密钥。绑定 unlockAt：篡改时间无法解出。
    private func deriveKey(unlockAt: Date, salt: String) -> SymmetricKey {
        let material = "\(unlockAt.timeIntervalSince1970)|\(salt)|bubu-time-capsule"
        let hash = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: hash)
    }

    /// 加密明文（信件文本 / 序列化后的音视频引用）。
    func encrypt(_ plaintext: Data, unlockAt: Date, salt: String) throws -> Data {
        let key = deriveKey(unlockAt: unlockAt, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.decryptionFailed }
        return combined
    }

    /// 解密。到期前拒绝（UI 层也会拦截，这里是第二道防线）。
    func decrypt(_ ciphertext: Data, unlockAt: Date, salt: String, now: Date = .now) throws -> Data {
        guard now >= unlockAt else { throw CryptoError.stillLocked(unlockAt: unlockAt) }
        let key = deriveKey(unlockAt: unlockAt, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
}
