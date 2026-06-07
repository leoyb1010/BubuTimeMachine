import Foundation

// MARK: - 时间胶囊载荷
/// 一封时间胶囊的全部内容，序列化后整体 AES-GCM 加密落盘。
/// 语音以"沙盒文件名 + 波形"引用（音频原文件单独加密保存）。
struct CapsulePayload: Codable, Sendable {
    var letter: String                  // 写给未来布布的信
    var voiceFileName: String?          // 语音文件名（已加密的 .m4a blob）
    var voiceDuration: Double
    var voiceWaveform: [Float]
    var photoFileNames: [String]        // 附带照片（已加密的 blob）

    init(letter: String = "", voiceFileName: String? = nil, voiceDuration: Double = 0,
         voiceWaveform: [Float] = [], photoFileNames: [String] = []) {
        self.letter = letter
        self.voiceFileName = voiceFileName
        self.voiceDuration = voiceDuration
        self.voiceWaveform = voiceWaveform
        self.photoFileNames = photoFileNames
    }
}

// MARK: - 时间胶囊保险库
/// 负责把 CapsulePayload 加密写入沙盒、到期解密读出。
/// 密钥由 CapsuleCrypto 依据 unlockAt 派生——篡改解锁时间则无法解出。
struct CapsuleVault: Sendable {
    let crypto: CapsuleCrypto
    let mediaStore: MediaStore

    /// 加密并落盘，返回加密 blob 文件名。salt 用胶囊 id 保证每封信密钥唯一。
    func seal(_ payload: CapsulePayload, unlockAt: Date, salt: String) throws -> String {
        let plain = try JSONEncoder().encode(payload)
        let cipher = try crypto.encrypt(plain, unlockAt: unlockAt, salt: salt)
        return try mediaStore.saveBlob(cipher)
    }

    /// 到期解密读出。未到期抛 CapsuleCrypto.CryptoError.stillLocked。
    func unseal(fileName: String, unlockAt: Date, salt: String, now: Date = .now) throws -> CapsulePayload {
        guard let cipher = mediaStore.blob(named: fileName) else {
            throw CapsuleCrypto.CryptoError.decryptionFailed
        }
        let plain = try crypto.decrypt(cipher, unlockAt: unlockAt, salt: salt, now: now)
        return try JSONDecoder().decode(CapsulePayload.self, from: plain)
    }
}
