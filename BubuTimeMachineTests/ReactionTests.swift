import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 亲一下反应编解码与聚合测试
/// 反应零迁移地编码进 Comment.text；本测试回归编解码、普通评论不被误判、同人单选、聚合计数。
@MainActor
struct ReactionTests {

    @Test("编码可被还原，普通文本不误判")
    func encodeDecode() {
        #expect(Reaction.decode(Reaction.heart.encodedText) == .heart)
        #expect(Reaction.decode(Reaction.moved.encodedText) == .moved)
        #expect(Reaction.decode("今天布布会走路了！") == nil)
        #expect(Reaction.decode(nil) == nil)
        #expect(Reaction.decode("") == nil)
    }

    @Test("反应判定区分普通评论")
    func isReaction() {
        let reaction = Comment(authorRole: "妈妈", text: Reaction.hug.encodedText)
        let normal = Comment(authorRole: "爸爸", text: "她笑得好甜")
        #expect(Reaction.isReaction(reaction))
        #expect(!Reaction.isReaction(normal))
    }

    @Test("聚合计数：同人单选取最新，去重")
    func summary() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let c1 = Comment(authorRole: "妈妈", text: Reaction.heart.encodedText)
        c1.createdAt = base
        // 妈妈改主意：后一条 hug 应覆盖前一条 heart。
        let c2 = Comment(authorRole: "妈妈", text: Reaction.hug.encodedText)
        c2.createdAt = base.addingTimeInterval(10)
        let c3 = Comment(authorRole: "姥姥", text: Reaction.heart.encodedText)
        c3.createdAt = base
        let normal = Comment(authorRole: "爸爸", text: "真可爱")

        let summary = ReactionSummary.from([c1, c2, c3, normal], myRole: "妈妈")
        #expect(summary.mine == .hug)               // 妈妈最新是 hug
        #expect(summary.counts[.hug] == 1)          // 妈妈
        #expect(summary.counts[.heart] == 1)        // 姥姥
        #expect((summary.counts[.laugh] ?? 0) == 0)
        #expect(!summary.isEmpty)
    }

    @Test("无反应时为空")
    func emptySummary() {
        let normal = Comment(authorRole: "爸爸", text: "真可爱")
        let summary = ReactionSummary.from([normal], myRole: "妈妈")
        #expect(summary.isEmpty)
        #expect(summary.mine == nil)
    }
}
