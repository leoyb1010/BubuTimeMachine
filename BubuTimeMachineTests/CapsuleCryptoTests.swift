import Testing
import Foundation
import CryptoKit
@testable import BubuTimeMachine

// MARK: - 时间胶囊加解密测试
/// 重点回归:亚秒截断(同步往返)不再破坏解密;旧版(v1)blob 仍能打开;时间锁生效。
@MainActor
struct CapsuleCryptoTests {

    private let crypto = CapsuleCrypto()
    private let salt = UUID().uuidString
    private let letter = Data("亲爱的布布,十八岁生日快乐。".utf8)

    @Test("v2 正常封存解封")
    func roundTrip() throws {
        let unlockAt = Date(timeIntervalSince1970: 2_000_000_000)
        let cipher = try crypto.encrypt(letter, unlockAt: unlockAt, salt: salt)
        let plain = try crypto.decrypt(cipher, unlockAt: unlockAt, salt: salt,
                                       now: unlockAt.addingTimeInterval(1))
        #expect(plain == letter)
    }

    @Test("同步往返截断亚秒后仍可解封(原 P0 数据丢失 bug)")
    func subsecondTruncationSurvivesSync() throws {
        // 封存时 unlockAt 带亚秒小数(模拟 Calendar.date(byAdding:to: .now) 的产物)
        let fractional = Date(timeIntervalSince1970: 2_000_000_000.73421)
        let cipher = try crypto.encrypt(letter, unlockAt: fractional, salt: salt)

        // 服务器 ISO8601 序列化往返后,亚秒被截断
        let truncated = Date(timeIntervalSince1970: 2_000_000_000)
        let plain = try crypto.decrypt(cipher, unlockAt: truncated, salt: salt,
                                       now: truncated.addingTimeInterval(60))
        #expect(plain == letter)
    }

    @Test("旧版 v1 blob(整秒封存)仍能打开")
    func legacyV1WholeSecond() throws {
        let unlockAt = Date(timeIntervalSince1970: 2_000_000_000)
        let cipher = try Self.legacyEncrypt(letter, unlockAt: unlockAt, salt: salt)
        let plain = try crypto.decrypt(cipher, unlockAt: unlockAt, salt: salt,
                                       now: unlockAt.addingTimeInterval(1))
        #expect(plain == letter)
    }

    @Test("旧版 v1 blob(本地 unlockAt 未被同步覆盖)仍能打开")
    func legacyV1Fractional() throws {
        let fractional = Date(timeIntervalSince1970: 2_000_000_000.5)
        let cipher = try Self.legacyEncrypt(letter, unlockAt: fractional, salt: salt)
        let plain = try crypto.decrypt(cipher, unlockAt: fractional, salt: salt,
                                       now: fractional.addingTimeInterval(1))
        #expect(plain == letter)
    }

    @Test("到期前拒绝解封")
    func timeGate() throws {
        let unlockAt = Date(timeIntervalSince1970: 2_000_000_000)
        let cipher = try crypto.encrypt(letter, unlockAt: unlockAt, salt: salt)
        #expect(throws: CapsuleCrypto.CryptoError.self) {
            _ = try crypto.decrypt(cipher, unlockAt: unlockAt, salt: salt,
                                   now: unlockAt.addingTimeInterval(-3600))
        }
    }

    @Test("salt 不对解不开")
    func wrongSalt() throws {
        let unlockAt = Date(timeIntervalSince1970: 2_000_000_000)
        let cipher = try crypto.encrypt(letter, unlockAt: unlockAt, salt: salt)
        #expect(throws: CapsuleCrypto.CryptoError.self) {
            _ = try crypto.decrypt(cipher, unlockAt: unlockAt, salt: "wrong",
                                   now: unlockAt.addingTimeInterval(1))
        }
    }

    @Test("BTC2 跨端固定向量可由 CryptoKit 解密")
    func crossPlatformGoldenV2() throws {
        let blob = try #require(Data(base64Encoded: "QlRDMgABAgMEBQYHCAkKC8RVRItZqZOoongcxle+rusTmdOElhZRH2jtuCyln9qOMI4YPnaKfoAu27FbGkfstjdApP6OX6JwPmzp+Ew3jSmX06FB86vY3C4LeiKmNWySHzmCh5GiP07mMpWw/4KDTX2v"))
        let salt = "123e4567-e89b-12d3-a456-426614174000"
        let unlock = try #require(ISO8601DateFormatter().date(from: "2030-01-02T03:04:05Z"))
        let plain = try crypto.decrypt(blob, unlockAt: unlock, salt: salt,
                                       now: unlock.addingTimeInterval(1))
        #expect(String(data: plain, encoding: .utf8) == "{\"letter\":\"跨端胶囊\",\"voiceDuration\":0,\"voiceWaveform\":[],\"photoFileNames\":[]}")
    }

    /// 复刻 v1 历史实现,生成旧格式 blob(无魔数前缀,timeIntervalSince1970 派生)。
    private static func legacyEncrypt(_ plaintext: Data, unlockAt: Date, salt: String) throws -> Data {
        let material = "\(unlockAt.timeIntervalSince1970)|\(salt)|bubu-time-capsule"
        let key = SymmetricKey(data: SHA256.hash(data: Data(material.utf8)))
        let sealed = try AES.GCM.seal(plaintext, using: key)
        return sealed.combined!
    }
}

// MARK: - 图片格式嗅探测试
@MainActor
struct MediaSniffTests {

    @Test("老媒体空资源角色继续展示，后台保真资源不重复展示")
    func displayResourceCompatibility() {
        let media = Media(type: .photo, localFileName: "legacy.heic")
        #expect(media.isDisplayResource)
        media.resourceRoleRaw = ""
        #expect(media.isDisplayResource)
        media.resourceRoleRaw = "display"
        #expect(media.isDisplayResource)
        media.resourceRoleRaw = "original"
        #expect(!media.isDisplayResource)
        media.resourceRoleRaw = "live-paired"
        #expect(!media.isDisplayResource)
    }

    @Test("大文件流式 SHA 与内存 SHA 一致")
    func streamingSHA() throws {
        let data = Data((0..<2_100_000).map { UInt8($0 % 251) })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-sha-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)

        #expect(try MediaStore.sha256Hex(at: url, chunkSize: 65_537) == MediaStore.sha256Hex(data))
    }

    @Test("JPEG/PNG/HEIC 文件头识别")
    func sniff() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0, count: 12))
        #expect(MediaStore.sniffImageExtension(jpeg) == "jpg")

        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 8))
        #expect(MediaStore.sniffImageExtension(png) == "png")

        var heic = Data([0x00, 0x00, 0x00, 0x18])
        heic.append(Data("ftypheic".utf8))
        heic.append(Data(repeating: 0, count: 8))
        #expect(MediaStore.sniffImageExtension(heic) == "heic")

        let unknown = Data(repeating: 0x42, count: 16)
        #expect(MediaStore.sniffImageExtension(unknown) == nil)
    }
}
