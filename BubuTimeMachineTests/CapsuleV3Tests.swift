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
}
