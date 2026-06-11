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
    var embeddedVoiceData: Data?
    var embeddedVoiceFileExtension: String?

    init(letter: String = "", voiceFileName: String? = nil, voiceDuration: Double = 0,
         voiceWaveform: [Float] = [], photoFileNames: [String] = [],
         embeddedVoiceData: Data? = nil, embeddedVoiceFileExtension: String? = nil) {
        self.letter = letter
        self.voiceFileName = voiceFileName
        self.voiceDuration = voiceDuration
        self.voiceWaveform = voiceWaveform
        self.photoFileNames = photoFileNames
        self.embeddedVoiceData = embeddedVoiceData
        self.embeddedVoiceFileExtension = embeddedVoiceFileExtension
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
        var payload = payload
        if let voiceFileName = payload.voiceFileName,
           payload.embeddedVoiceData == nil,
           let data = mediaStore.data(forMedia: voiceFileName) {
            payload.embeddedVoiceData = data
            let ext = URL(fileURLWithPath: voiceFileName).pathExtension
            payload.embeddedVoiceFileExtension = ext.isEmpty ? "m4a" : ext
        }
        let plain = try JSONEncoder().encode(payload)
        let cipher = try crypto.encrypt(plain, unlockAt: unlockAt, salt: salt)
        return try mediaStore.saveBlob(cipher)
    }

    /// v3 真 E2E 封存：密钥来自家庭恢复码，不随记录同步。
    func sealV3(_ payload: CapsulePayload, recoveryCode: String, salt: String) throws -> String {
        var payload = payload
        if let voiceFileName = payload.voiceFileName,
           payload.embeddedVoiceData == nil,
           let data = mediaStore.data(forMedia: voiceFileName) {
            payload.embeddedVoiceData = data
            let ext = URL(fileURLWithPath: voiceFileName).pathExtension
            payload.embeddedVoiceFileExtension = ext.isEmpty ? "m4a" : ext
        }
        let plain = try JSONEncoder().encode(payload)
        let cipher = try crypto.encryptV3(plain, recoveryCode: recoveryCode, salt: salt)
        return try mediaStore.saveBlob(cipher)
    }

    /// 到期解密读出。未到期抛 CapsuleCrypto.CryptoError.stillLocked。
    /// v3 blob 需提供 recoveryCode（来自 iCloud Keychain 或纸条）；v1/v2 自动按旧逻辑解。
    func unseal(fileName: String, unlockAt: Date, salt: String,
                recoveryCode: String? = nil, now: Date = .now) throws -> CapsulePayload {
        guard let cipher = mediaStore.blob(named: fileName) else {
            throw CapsuleCrypto.CryptoError.decryptionFailed
        }
        let plain: Data
        if CapsuleCrypto.isV3(cipher) {
            guard let recoveryCode, !recoveryCode.isEmpty else {
                throw CapsuleCrypto.CryptoError.decryptionFailed
            }
            plain = try crypto.decryptV3(cipher, recoveryCode: recoveryCode, salt: salt,
                                         unlockAt: unlockAt, now: now)
        } else {
            plain = try crypto.decrypt(cipher, unlockAt: unlockAt, salt: salt, now: now)
        }
        var payload = try JSONDecoder().decode(CapsulePayload.self, from: plain)
        if let data = payload.embeddedVoiceData {
            let existingName = payload.voiceFileName
            let hasExistingFile = existingName.map { mediaStore.fileExists(forMedia: $0) } ?? false
            if !hasExistingFile {
                let ext = payload.embeddedVoiceFileExtension ?? "m4a"
                payload.voiceFileName = try mediaStore.saveBlob(data, preferredExtension: ext)
            }
        }
        return payload
    }
}
