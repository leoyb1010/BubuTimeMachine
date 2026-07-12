import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 时间胶囊 v3 真 E2E 测试
/// 回归：恢复码派生密钥可正常加解密；错误恢复码解不开；大小写/多空格规范化；
/// v3 魔数识别；到期前拒绝；旧 v2 blob 仍能用原路径解（向后兼容）。
@MainActor
struct CapsuleV3Tests {

    private let crypto = CapsuleCrypto()
    private let salt = UUID().uuidString
    private let code = CapsuleRecovery.generate(wordCount: 24)
    private let letter = Data("亲爱的布布，这是用恢复码加密的信。".utf8)

    @Test("v3 恢复码正常加解密")
    func roundTrip() throws {
        let unlockAt = Date(timeIntervalSince1970: 1_000_000_000)
        let cipher = try crypto.encryptV3(letter, recoveryCode: code, salt: salt)
        #expect(CapsuleCrypto.isV3(cipher))
        let plain = try crypto.decryptV3(cipher, recoveryCode: code, salt: salt,
                                         unlockAt: unlockAt, now: unlockAt.addingTimeInterval(1))
        #expect(plain == letter)
    }

    @Test("错误恢复码解不开")
    func wrongCode() throws {
        let unlockAt = Date(timeIntervalSince1970: 1_000_000_000)
        let cipher = try crypto.encryptV3(letter, recoveryCode: code, salt: salt)
        #expect(throws: CapsuleCrypto.CryptoError.self) {
            _ = try crypto.decryptV3(cipher, recoveryCode: CapsuleRecovery.generate(),
                                     salt: salt, unlockAt: unlockAt, now: unlockAt.addingTimeInterval(1))
        }
    }

    @Test("恢复码大小写/多空格规范化后仍可解")
    func normalization() throws {
        let unlockAt = Date(timeIntervalSince1970: 1_000_000_000)
        let cipher = try crypto.encryptV3(letter, recoveryCode: code, salt: salt)
        let messy = "  " + code.uppercased().replacingOccurrences(of: " ", with: "   ") + "  "
        let plain = try crypto.decryptV3(cipher, recoveryCode: messy, salt: salt,
                                         unlockAt: unlockAt, now: unlockAt.addingTimeInterval(1))
        #expect(plain == letter)
    }

    @Test("到期前拒绝解封")
    func stillLocked() throws {
        let unlockAt = Date(timeIntervalSince1970: 4_000_000_000)  // 远未来
        let cipher = try crypto.encryptV3(letter, recoveryCode: code, salt: salt)
        #expect(throws: CapsuleCrypto.CryptoError.self) {
            _ = try crypto.decryptV3(cipher, recoveryCode: code, salt: salt,
                                     unlockAt: unlockAt, now: Date(timeIntervalSince1970: 1_000_000_000))
        }
    }

    @Test("salt 不对解不开")
    func wrongSalt() throws {
        let unlockAt = Date(timeIntervalSince1970: 1_000_000_000)
        let cipher = try crypto.encryptV3(letter, recoveryCode: code, salt: salt)
        #expect(throws: CapsuleCrypto.CryptoError.self) {
            _ = try crypto.decryptV3(cipher, recoveryCode: code, salt: "wrong-salt",
                                     unlockAt: unlockAt, now: unlockAt.addingTimeInterval(1))
        }
    }

    @Test("v2 旧 blob 不被误判为 v3，原路径仍可解")
    func v2BackwardCompat() throws {
        let unlockAt = Date(timeIntervalSince1970: 2_000_000_000)
        let v2cipher = try crypto.encrypt(letter, unlockAt: unlockAt, salt: salt)
        #expect(!CapsuleCrypto.isV3(v2cipher))
        let plain = try crypto.decrypt(v2cipher, unlockAt: unlockAt, salt: salt,
                                       now: unlockAt.addingTimeInterval(1))
        #expect(plain == letter)
    }

    @Test("生成的助记词为 24 词且来自词表")
    func mnemonicShape() {
        let words = CapsuleRecovery.generate(wordCount: 24).split(separator: " ").map(String.init)
        #expect(words.count == 24)
        #expect(words.allSatisfy { CapsuleRecovery.wordList.contains($0) })
    }

    // MARK: 媒体闭环回归（C1）
    /// 封存把语音嵌进加密 blob → 明文源可删 → 解封拿回正文与语音内容；
    /// 语音落临时目录而非媒体目录（不留明文）、按 salt 幂等命名（不产生孤儿）。
    @Test("媒体闭环：封存嵌语音删明文、解封拿回内容且不落媒体目录明文、幂等无孤儿")
    func mediaClosureRoundTrip() throws {
        let media = MediaStore()
        let vault = CapsuleVault(crypto: crypto, mediaStore: media)
        let capsuleId = UUID().uuidString
        let unlockAt = Date(timeIntervalSince1970: 1_000_000_000)
        let now = unlockAt.addingTimeInterval(1)

        // 明文语音先落媒体目录（模拟录音导入）
        let voiceBytes = Data("FAKE-M4A-VOICE-BYTES-\(capsuleId)".utf8)
        let plainVoiceName = try media.saveBlob(voiceBytes, preferredExtension: "m4a")
        #expect(media.fileExists(forMedia: plainVoiceName))

        let payload = CapsulePayload(letter: "给布布的信", voiceFileName: plainVoiceName,
                                     voiceDuration: 1, voiceWaveform: [0.2, 0.4])

        // 封存（先写密文 blob）
        let blob = try vault.sealV3(payload, recoveryCode: code, salt: capsuleId)
        #expect(media.fileExists(forMedia: blob))

        // 模拟 compose：密文落地后删明文源
        media.deleteMedia(named: plainVoiceName)
        #expect(!media.fileExists(forMedia: plainVoiceName))

        // 解封：正文与语音内容都拿得回
        let out = try vault.unseal(fileName: blob, unlockAt: unlockAt, salt: capsuleId,
                                   recoveryCode: code, now: now)
        #expect(out.letter == "给布布的信")
        let voiceOut = try #require(out.voiceFileName)
        let url = media.playbackURL(for: voiceOut)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect((try? Data(contentsOf: url)) == voiceBytes)

        // 不留媒体目录明文：解封后的语音名在媒体目录里不存在（只在 tmp scratch）
        #expect(!media.fileExists(forMedia: voiceOut))

        // 幂等无孤儿：二次解封复用同一按 salt 命名的文件
        let out2 = try vault.unseal(fileName: blob, unlockAt: unlockAt, salt: capsuleId,
                                    recoveryCode: code, now: now)
        #expect(out2.voiceFileName == voiceOut)

        // 清理
        media.deleteMedia(named: blob)
        try? FileManager.default.removeItem(at: url)
    }
}
