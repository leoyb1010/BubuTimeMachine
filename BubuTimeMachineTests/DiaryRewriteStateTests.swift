import Foundation
import Testing
@testable import BubuTimeMachine

@MainActor
struct DiaryRewriteStateTests {
    @Test("不同记录的并发成功各自保留草稿")
    func lateSuccessBelongsToOrigin() throws {
        var state = DiaryRewriteState(); let a = UUID(), b = UUID()
        let first = try #require(state.begin(for: a)), second = try #require(state.begin(for: b))
        #expect(state.succeed("B", for: b, request: second, revealImmediately: true))
        #expect(state.succeed("A", for: a, request: first, revealImmediately: true))
        #expect(state.draft(for: a).output == "A")
        #expect(state.draft(for: b).output == "B")
    }

    @Test("迟到失败不清除另一记录的输出或等待态")
    func failureIsIsolated() throws {
        var state = DiaryRewriteState(); let a = UUID(), b = UUID()
        let first = try #require(state.begin(for: a)), second = try #require(state.begin(for: b))
        #expect(state.fail("A failed", for: a, request: first))
        #expect(state.draft(for: b).activeRequest == second)
        #expect(state.draft(for: b).error == nil)
        #expect(state.succeed("B", for: b, request: second, revealImmediately: true))
        #expect(state.draft(for: a).error == "A failed")
        #expect(state.draft(for: b).displayed == "B")
    }

    @Test("取消先失效请求；不依赖底层 IO 真正停止")
    func cancellationRejectsEveryLateOutcome() throws {
        var state = DiaryRewriteState(); let id = UUID(); let request = try #require(state.begin(for: id))
        state.cancel(for: id)
        #expect(!state.succeed("stale", for: id, request: request, revealImmediately: true))
        #expect(!state.fail("stale error", for: id, request: request))
        #expect(state.draft(for: id).output.isEmpty && state.draft(for: id).error == nil)
    }

    @Test("同记录重试不接受旧一轮结果")
    func retryHasNewAuthority() throws {
        var state = DiaryRewriteState(); let id = UUID()
        let old = try #require(state.begin(for: id))
        #expect(state.begin(for: id) == nil, "Duplicate taps must not admit another request")
        #expect(state.draft(for: id).activeRequest == old)
        state.cancel(for: id)
        let current = try #require(state.begin(for: id))
        #expect(!state.succeed("old", for: id, request: old, revealImmediately: true))
        #expect(!state.fail("old error", for: id, request: old))
        #expect(state.succeed("current", for: id, request: current, revealImmediately: true))
        #expect(state.draft(for: id).output == "current")
    }

    @Test("切页保留完整草稿，旧打字机不能拼进下一轮")
    func presentationIsVersioned() throws {
        var state = DiaryRewriteState(); let id = UUID(); let first = try #require(state.begin(for: id))
        #expect(state.succeed("ABC", for: id, request: first, revealImmediately: false))
        #expect(state.append("A", for: id, presentation: first))
        state.finishPresentation(for: id)
        #expect(state.draft(for: id).displayed == "ABC")
        #expect(!state.append("B", for: id, presentation: first))
        let next = try #require(state.begin(for: id))
        #expect(!state.append("C", for: id, presentation: first))
        #expect(state.succeed("Next", for: id, request: next, revealImmediately: true))
        #expect(state.draft(for: id).displayed == "Next")
    }
    @Test("重新生成失败或取消保留上一份未保存输出")
    func regenerationPreservesPreviousDraft() throws {
        var state = DiaryRewriteState(); let id = UUID()
        let first = try #require(state.begin(for: id))
        #expect(state.succeed("Original draft", for: id, request: first, revealImmediately: true))
        let second = try #require(state.begin(for: id))
        #expect(state.draft(for: id).output == "Original draft")
        #expect(state.fail("Retry failed", for: id, request: second))
        #expect(state.draft(for: id).displayed == "Original draft")
        #expect(!state.draft(for: id).saved)
        _ = try #require(state.begin(for: id))
        state.cancel(for: id)
        #expect(state.draft(for: id).output == "Original draft")
    }

    @Test("离开视图取消所有请求并保留已生成完整文字")
    func leavingRetiresAllRequests() throws {
        var state = DiaryRewriteState(); let a = UUID(), b = UUID()
        let first = try #require(state.begin(for: a))
        #expect(state.succeed("ABC", for: a, request: first, revealImmediately: false))
        #expect(state.append("A", for: a, presentation: first))
        let second = try #require(state.begin(for: b))
        state.cancelAll()
        #expect(state.draft(for: a).displayed == "ABC")
        #expect(!state.append("B", for: a, presentation: first))
        #expect(!state.succeed("late B", for: b, request: second, revealImmediately: true))
        #expect(!state.fail("late B error", for: b, request: second))
    }

}
