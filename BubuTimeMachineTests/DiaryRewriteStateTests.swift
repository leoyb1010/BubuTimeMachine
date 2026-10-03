import Foundation
import Testing
@testable import BubuTimeMachine

@MainActor
struct DiaryRewriteStateTests {
    @Test("不同记录的并发成功各自保留草稿")
    func lateSuccessBelongsToOrigin() throws {
        var state = DiaryRewriteState()
        let a = UUID(), b = UUID()
        let firstRequest = state.begin(for: a)
        let secondRequest = state.begin(for: b)
        let first = try #require(firstRequest), second = try #require(secondRequest)
        let acceptedB = state.succeed("B", for: b, request: second, revealImmediately: true)
        #expect(acceptedB)
        let acceptedA = state.succeed("A", for: a, request: first, revealImmediately: true)
        #expect(acceptedA)
        #expect(state.draft(for: a).output == "A")
        #expect(state.draft(for: b).output == "B")
    }

    @Test("迟到失败不清除另一记录的输出或等待态")
    func failureIsIsolated() throws {
        var state = DiaryRewriteState()
        let a = UUID(), b = UUID()
        let firstRequest = state.begin(for: a)
        let secondRequest = state.begin(for: b)
        let first = try #require(firstRequest), second = try #require(secondRequest)
        let acceptedFailure = state.fail("A failed", for: a, request: first)
        #expect(acceptedFailure)
        #expect(state.draft(for: b).activeRequest == second)
        #expect(state.draft(for: b).error == nil)
        let acceptedB = state.succeed("B", for: b, request: second, revealImmediately: true)
        #expect(acceptedB)
        #expect(state.draft(for: a).error == "A failed")
        #expect(state.draft(for: b).displayed == "B")
    }

    @Test("取消先失效请求；不依赖底层 IO 真正停止")
    func cancellationRejectsEveryLateOutcome() throws {
        var state = DiaryRewriteState()
        let id = UUID()
        let requestToken = state.begin(for: id)
        let request = try #require(requestToken)
        state.cancel(for: id)
        let acceptedLateSuccess = state.succeed("stale", for: id, request: request, revealImmediately: true)
        #expect(!acceptedLateSuccess)
        let acceptedLateFailure = state.fail("stale error", for: id, request: request)
        #expect(!acceptedLateFailure)
        #expect(state.draft(for: id).output.isEmpty && state.draft(for: id).error == nil)
    }

    @Test("同记录重试不接受旧一轮结果")
    func retryHasNewAuthority() throws {
        var state = DiaryRewriteState()
        let id = UUID()
        let oldRequest = state.begin(for: id)
        let old = try #require(oldRequest)
        let duplicateRequest = state.begin(for: id)
        #expect(duplicateRequest == nil, "Duplicate taps must not admit another request")
        #expect(state.draft(for: id).activeRequest == old)
        state.cancel(for: id)
        let currentRequest = state.begin(for: id)
        let current = try #require(currentRequest)
        let acceptedOldSuccess = state.succeed("old", for: id, request: old, revealImmediately: true)
        #expect(!acceptedOldSuccess)
        let acceptedOldFailure = state.fail("old error", for: id, request: old)
        #expect(!acceptedOldFailure)
        let acceptedCurrentSuccess = state.succeed("current", for: id, request: current, revealImmediately: true)
        #expect(acceptedCurrentSuccess)
        #expect(state.draft(for: id).output == "current")
    }

    @Test("切页保留完整草稿，旧打字机不能拼进下一轮")
    func presentationIsVersioned() throws {
        var state = DiaryRewriteState()
        let id = UUID()
        let firstRequest = state.begin(for: id)
        let first = try #require(firstRequest)
        let acceptedFirst = state.succeed("ABC", for: id, request: first, revealImmediately: false)
        #expect(acceptedFirst)
        let appendedFirst = state.append("A", for: id, presentation: first)
        #expect(appendedFirst)
        state.finishPresentation(for: id)
        #expect(state.draft(for: id).displayed == "ABC")
        let appendedAfterFinish = state.append("B", for: id, presentation: first)
        #expect(!appendedAfterFinish)
        let nextRequest = state.begin(for: id)
        let next = try #require(nextRequest)
        let appendedOldPresentation = state.append("C", for: id, presentation: first)
        #expect(!appendedOldPresentation)
        let acceptedNext = state.succeed("Next", for: id, request: next, revealImmediately: true)
        #expect(acceptedNext)
        #expect(state.draft(for: id).displayed == "Next")
    }
    @Test("重新生成失败或取消保留上一份未保存输出")
    func regenerationPreservesPreviousDraft() throws {
        var state = DiaryRewriteState()
        let id = UUID()
        let firstRequest = state.begin(for: id)
        let first = try #require(firstRequest)
        let acceptedFirst = state.succeed("Original draft", for: id, request: first, revealImmediately: true)
        #expect(acceptedFirst)
        let secondRequest = state.begin(for: id)
        let second = try #require(secondRequest)
        #expect(state.draft(for: id).output == "Original draft")
        let acceptedFailure = state.fail("Retry failed", for: id, request: second)
        #expect(acceptedFailure)
        #expect(state.draft(for: id).displayed == "Original draft")
        #expect(!state.draft(for: id).saved)
        let thirdRequest = state.begin(for: id)
        _ = try #require(thirdRequest)
        state.cancel(for: id)
        #expect(state.draft(for: id).output == "Original draft")
    }

    @Test("离开视图取消所有请求并保留已生成完整文字")
    func leavingRetiresAllRequests() throws {
        var state = DiaryRewriteState()
        let a = UUID(), b = UUID()
        let firstRequest = state.begin(for: a)
        let first = try #require(firstRequest)
        let acceptedA = state.succeed("ABC", for: a, request: first, revealImmediately: false)
        #expect(acceptedA)
        let appendedA = state.append("A", for: a, presentation: first)
        #expect(appendedA)
        let secondRequest = state.begin(for: b)
        let second = try #require(secondRequest)
        state.cancelAll()
        #expect(state.draft(for: a).displayed == "ABC")
        let appendedAfterLeave = state.append("B", for: a, presentation: first)
        #expect(!appendedAfterLeave)
        let acceptedLateSuccess = state.succeed("late B", for: b, request: second, revealImmediately: true)
        #expect(!acceptedLateSuccess)
        let acceptedLateFailure = state.fail("late B error", for: b, request: second)
        #expect(!acceptedLateFailure)
    }

}
