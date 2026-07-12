import Foundation

// MARK: - 时间胶囊载荷
/// 一封时间胶囊的全部内容，序列化后整体 AES-GCM 加密落盘。
/// 语音以"沙盒文件名 + 波形"引用（音频原文件单独加密保存）。
struct CapsulePayload: Codable, Sendable {
    var letter: String                  // 写给未来布布的信
    var voiceFileName: String?          // 语音文件名（已加密的 .m4a blob）
    var voiceDuration: Double
    var voiceWaveform: [Float]
    var photoFileNames: [String]        // 预留字段：附带照片文件名（当前写信流程未启用；勿删，删除会破坏旧 blob 解码）
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

    /// 该 blob 是否 v3（恢复码加密）。恢复码校验时用来挑选可验证的胶囊。
    func isV3Blob(fileName: String) -> Bool {
        guard let cipher = mediaStore.blob(named: fileName) else { return false }
        return CapsuleCrypto.isV3(cipher)
    }

    /// 只验证恢复码能否解开该 v3 blob（不返回内容、无副作用、绕过时间锁——
    /// v3 密钥与时间无关，时间锁只是软件层约束，校验不算"偷看"）。
    func canDecryptV3(fileName: String, salt: String, recoveryCode: String, unlockAt: Date) -> Bool {
        guard let cipher = mediaStore.blob(named: fileName), CapsuleCrypto.isV3(cipher) else { return false }
        let futureNow = max(.now, unlockAt.addingTimeInterval(1))
        return (try? crypto.decryptV3(cipher, recoveryCode: recoveryCode, salt: salt,
                                      unlockAt: unlockAt, now: futureNow)) != nil
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
            // 内嵌语音解密到临时目录（幂等、按 salt 固定命名）——不落媒体目录、不产生孤儿 blob。
            // 之前每次开启都 saveBlob 到媒体目录，会留下明文并每开一次多一个孤儿；现改为 tmp 复用。
            let ext = payload.embeddedVoiceFileExtension ?? "m4a"
            if let scratchName = mediaStore.materializeCapsuleVoice(data, salt: salt, ext: ext) {
                payload.voiceFileName = scratchName
            }
        }
        // 极旧 blob（无内嵌语音、仅媒体目录引用）保持原样：voiceFileName 指向媒体目录，playbackURL 会回退命中。
        return payload
    }
}
