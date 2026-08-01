import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 手表照片引用完整性
/// 回归 P0：回忆序列若引用一张手机本地没有的照片，会形成补发死循环——
/// 组包跳过 → 手表数出缺图 → 请求补发 → 手机重传整包 → 下轮再缺 → 无限。
/// 家人发来的照片在缩略图下载完之前，正是这个状态。
@MainActor
struct WatchPhotoIntegrityTests {

    /// 造一个临时媒体目录当 MediaStore 的沙盒替身，只验"存在性判断"这一层。
    private func makeStore() -> MediaStore { MediaStore() }

    @Test("本地没有的文件名一律判为不可用")
    func rejectsMissingFile() {
        let store = makeStore()
        let ghost = "definitely-not-here-\(UUID().uuidString).jpg"
        #expect(WatchSnapshotBuilder.hasLocalFile(ghost, store: store) == false)
    }

    @Test("落在缩略图目录的文件判为可用")
    func acceptsThumbnailFile() throws {
        let store = makeStore()
        let name = "watch-test-thumb-\(UUID().uuidString).jpg"
        let url = store.thumbnailURL(for: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WatchSnapshotBuilder.hasLocalFile(name, store: store))
    }

    @Test("只有原图、没有缩略图时也判为可用（组包侧会回退取原图）")
    func acceptsOriginalOnly() throws {
        let store = makeStore()
        let name = "watch-test-orig-\(UUID().uuidString).jpg"
        let url = store.mediaURL(for: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WatchSnapshotBuilder.hasLocalFile(name, store: store))
    }

    @Test("组包对不存在的名字会整条跳过，不产出空数据条目")
    func packagingSkipsMissingFiles() {
        let names = ["ghost-a-\(UUID().uuidString).jpg", "ghost-b-\(UUID().uuidString).jpg"]
        let packed = WatchSnapshotBuilder.photosData(for: names)
        #expect(packed.isEmpty)
    }

    // MARK: 重温回执

    @Test("手表重温走 Reaction 哨兵编码，能被 App 的解码器识别为亲亲")
    func watchReactionUsesExistingMechanism() {
        let encoded = Reaction.heart.encodedText
        #expect(Reaction.decode(encoded) == .heart)
        // 关键：它不是一条普通评论文本——不会在评论区当正文显示。
        #expect(encoded.hasPrefix("\u{1}"))
    }

    @Test("同一作者重温多次仍只计一颗心（不会刷屏）")
    func reactionDedupesByAuthor() {
        let comments = [
            Comment(authorRole: "妈妈", text: Reaction.heart.encodedText),
            Comment(authorRole: "妈妈", text: Reaction.heart.encodedText),
            Comment(authorRole: "妈妈", text: Reaction.heart.encodedText),
        ]
        let summary = ReactionSummary.from(comments, myRole: "妈妈")
        #expect(summary.counts[.heart] == 1)
        #expect(summary.mine == .heart)
    }
}
