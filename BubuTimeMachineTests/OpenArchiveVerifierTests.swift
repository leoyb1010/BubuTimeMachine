import Testing
import Foundation
import CryptoKit
@testable import BubuTimeMachine

// MARK: - 开放档案校验器回归
/// 校验器面对的是"来路不明的档案文件夹"——它的职责是把一切异常变成
/// 可读的报告，而不是把 App 崩掉或挂死。此前恶意 manifest 的多字节行
/// 能触发 String.index 越界 fatal trap（护栏按字节数、偏移按 Character 数），
/// 符号链接/FIFO 能让哈希循环永不返回。这里把这些钉死。
@MainActor
struct OpenArchiveVerifierTests {

    private func makeArchive(manifest: String, dataJSON: String = #"{"childName":"布布","entries":[]}"#,
                             files: [String: Data] = [:]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("verifier-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try manifest.write(to: root.appendingPathComponent("manifest.sha256"),
                           atomically: true, encoding: .utf8)
        try dataJSON.write(to: root.appendingPathComponent("data.json"),
                           atomically: true, encoding: .utf8)
        for (name, data) in files {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return root
    }

    private func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    @Test("恶意 manifest：一行全是汉字（字节数够、字符数不够）抛格式错误而不是崩溃")
    func multibyteManifestLineDoesNotTrap() throws {
        // 30 个汉字 = 90 utf8 字节（≥67 过旧护栏），但只有 30 个 Character——
        // 旧代码 index(offsetBy: 64) 在这里直接 fatal trap。
        let evil = String(repeating: "布", count: 30)
        let root = try makeArchive(manifest: evil)
        defer { cleanup(root) }
        #expect(throws: (any Error).self) {
            _ = try OpenArchiveVerifier.verify(folder: root)
        }
    }

    @Test("../ 路径穿越与绝对路径都被拒绝")
    func rejectsTraversalAndAbsolutePaths() throws {
        let hash = String(repeating: "a", count: 64)
        for path in ["../outside.txt", "/etc/passwd", "a/../../escape.txt"] {
            let root = try makeArchive(manifest: "\(hash)  \(path)")
            defer { cleanup(root) }
            #expect(throws: (any Error).self, "\(path) 应被拒绝") {
                _ = try OpenArchiveVerifier.verify(folder: root)
            }
        }
    }

    @Test("符号链接不参与哈希：计入不匹配而不是跟着链接读档案外文件")
    func symlinkCountsAsMismatch() throws {
        let hash = String(repeating: "b", count: 64)
        let root = try makeArchive(manifest: "\(hash)  media/link.jpg")
        defer { cleanup(root) }
        let mediaDir = root.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        // 指向档案外的真实文件（/etc/hosts 一定存在且可读）
        try FileManager.default.createSymbolicLink(
            at: mediaDir.appendingPathComponent("link.jpg"),
            withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        let report = try OpenArchiveVerifier.verify(folder: root)
        #expect(!report.isValid)
    }

    @Test("正常档案：哈希全对判有效，篡改一字节判无效")
    func happyPathAndTamperDetection() throws {
        let payload = Data("布布第一次自己穿鞋".utf8)
        let hash = OpenArchiveVerifierTests.sha256Hex(payload)
        let root = try makeArchive(manifest: "\(hash)  media/note.txt",
                                   files: ["media/note.txt": payload])
        defer { cleanup(root) }
        let good = try OpenArchiveVerifier.verify(folder: root)
        #expect(good.isValid)

        var tampered = payload
        tampered[0] ^= 0xFF
        try tampered.write(to: root.appendingPathComponent("media/note.txt"))
        let bad = try OpenArchiveVerifier.verify(folder: root)
        #expect(!bad.isValid)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
