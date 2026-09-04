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

    @Test("BTC3 跨端固定向量可由 CryptoKit 解密")
    func crossPlatformGoldenV3() throws {
        let blob = try #require(Data(base64Encoded: "QlRDMwABAgMEBQYHCAkKC0kMpJR9rObGRNCFXwzvqGDhCAFAEy2oc+hJ1rEQvFnVpqIRiQ9HCNp7XEAKLbDAJ91InDjqNUMaD42gq0zTOZVe117eAJfjmTv5KBnntvvJxkrSBLS/W470KBicXRqpF6dt"))
        let recovery = "apple baby bear bird blue boat book brave bread bright brook calm candle cat cloud clover coral cozy cream daisy dawn deer dream drift"
        let salt = "123e4567-e89b-12d3-a456-426614174000"
        let unlock = try #require(ISO8601DateFormatter().date(from: "2030-01-02T03:04:05Z"))
        let plain = try crypto.decryptV3(blob, recoveryCode: recovery, salt: salt,
                                         unlockAt: unlock, now: unlock.addingTimeInterval(1))
        #expect(String(data: plain, encoding: .utf8) == "{\"letter\":\"跨端胶囊\",\"voiceDuration\":0,\"voiceWaveform\":[],\"photoFileNames\":[]}")
    }

    // MARK: 版本降级伪造（安全回归）

    /// 攻击面：`unseal` 完全按 blob 头部魔数分派版本，而 v2 的密钥只由 unlockAt 与
    /// salt(=胶囊 id) 派生——这两项都是随记录同步到服务器的**明文字段**。
    /// 拿到数据库或备份的人可以自己派生 v2 密钥、封一段自己写的正文替换上去，
    /// 换机后同步拉回，解封认魔数就成功了。布布 18 岁打开的会是别人写的信。
    /// 记住封存版本之后，v3 的信必须拒绝一切非 v3 的 blob。
    @Test("v3 的信拒绝被换成 v2 blob（版本降级伪造）")
    func rejectsDowngradedBlob() throws {
        let media = MediaStore()
        let vault = CapsuleVault(crypto: crypto, mediaStore: media)
        let capsuleId = UUID().uuidString
        let unlockAt = Date(timeIntervalSince1970: 1_000_000_000)
        let now = unlockAt.addingTimeInterval(1)

        // 攻击者只用两个公开字段就能造出一份「合法」的 v2 密文。
        // 明文得是货真价实的 CapsulePayload JSON——真实攻击者当然会照着格式写，
        // 否则解密成功也会卡在 JSON 解码上，测不到我们要测的那一层。
        let forgedPayload = CapsulePayload(letter: "这不是爸爸写的信")
        let forged = try crypto.encrypt(JSONEncoder().encode(forgedPayload),
                                        unlockAt: unlockAt, salt: capsuleId)
        let forgedName = try media.saveBlob(forged, preferredExtension: "capsule")
        #expect(!CapsuleCrypto.isV3(forged), "前提：伪造的是旧版格式")

        // 不带版本信息时，旧行为会照解不误——这正是漏洞本身
        let legacyOpen = try? vault.unseal(fileName: forgedName, unlockAt: unlockAt,
                                           salt: capsuleId, recoveryCode: nil, now: now)
        #expect(legacyOpen?.letter == "这不是爸爸写的信",
                "前提：不知道版本时伪造的信确实读得出来，所以必须记住版本")

        // 这封信当初是 v3 封的 → 必须拒绝
        #expect(throws: CapsuleCrypto.CryptoError.self) {
            _ = try vault.unseal(fileName: forgedName, unlockAt: unlockAt, salt: capsuleId,
                                 recoveryCode: self.code, expectedVersion: 3, now: now)
        }

        // 真正的 v3 blob 在同样的版本要求下照常打开
        let real = try vault.sealV3(CapsulePayload(letter: "这才是爸爸写的信"),
                                    recoveryCode: code, salt: capsuleId)
        let out = try vault.unseal(fileName: real, unlockAt: unlockAt, salt: capsuleId,
                                   recoveryCode: code, expectedVersion: 3, now: now)
        #expect(out.letter == "这才是爸爸写的信")
        #expect(vault.detectedVersion(fileName: real) == 3)

        media.deleteMedia(named: forgedName)
        media.deleteMedia(named: real)
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
