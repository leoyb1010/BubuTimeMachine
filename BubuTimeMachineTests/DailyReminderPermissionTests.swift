import Foundation
import Testing
import UserNotifications
@testable import BubuTimeMachine

@MainActor
struct DailyReminderPermissionTests {
    private enum Failure: Error { case authorization }

    @MainActor
    private final class Gate {
        var started = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            started = true
            guard !released else { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    @Test("拒绝授权后开关保持关闭，并撤销残留每日提醒")
    func deniedAuthorizationIsNotEnabled() async {
        let permission = DailyReminderPermission(requestAuthorization: { false }, readAuthorization: { .denied })
        var applied: [Bool] = []
        let result = await permission.update(enabled: true) { applied.append($0) }
        #expect(result == .denied && permission.outcome == .denied)
        #expect(result?.isEnabled == false && !permission.isUpdating)
        #expect(applied == [false])
    }

    @Test("授权异常不被当成成功；开关关闭并提供可重试状态")
    func authorizationErrorIsExplicit() async {
        let permission = DailyReminderPermission(requestAuthorization: { throw Failure.authorization }, readAuthorization: { .notDetermined })
        var applied: [Bool] = []
        let result = await permission.update(enabled: true) { applied.append($0) }
        #expect(result == .failed && permission.outcome == .failed)
        #expect(result?.isEnabled == false && applied == [false])
    }

    @Test("允许后才真正排期，返回有效开启")
    func allowedAuthorizationEnablesOnce() async {
        var requests = 0
        let permission = DailyReminderPermission(requestAuthorization: { requests += 1; return true }, readAuthorization: { .authorized })
        var applied: [Bool] = []
        let result = await permission.update(enabled: true) { applied.append($0) }
        #expect(result == .enabled && permission.outcome == .enabled)
        #expect(requests == 1 && applied == [true] && !permission.isUpdating)
    }

    @Test("关闭不请求系统授权，只移除每日提醒")
    func disablingDoesNotRequestAuthorization() async {
        var requests = 0
        let permission = DailyReminderPermission(requestAuthorization: { requests += 1; return true }, readAuthorization: { .authorized })
        var applied: [Bool] = []
        let result = await permission.update(enabled: false) { applied.append($0) }
        #expect(result == .disabled && requests == 0 && applied == [false])
    }

    @Test("回前台发现系统拒绝时关闭失效开关，不再次弹授权")
    func foregroundReconciliationDetectsRevocation() async {
        var requests = 0
        let permission = DailyReminderPermission(requestAuthorization: { requests += 1; return true }, readAuthorization: { .denied })
        var applied: [Bool] = []
        let result = await permission.reconcile(enabled: true) { applied.append($0) }
        #expect(result == .denied && !permission.outcome.isEnabled)
        #expect(requests == 0 && applied == [false])
    }

    @Test("原本关闭的提醒回前台不请求授权，也不因系统允许而自动开启")
    func foregroundKeepsExistingOptOut() async {
        var requests = 0
        let permission = DailyReminderPermission(requestAuthorization: { requests += 1; return true }, readAuthorization: { .authorized })
        var applied: [Bool] = []
        let result = await permission.reconcile(enabled: false) { applied.append($0) }
        #expect(result == .disabled && requests == 0 && applied == [false])
    }

    @Test("已允许的各种系统状态无需再次请求授权", arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral])
    func foregroundKeepsAllowedPermission(_ status: UNAuthorizationStatus) async {
        var requests = 0
        let permission = DailyReminderPermission(requestAuthorization: { requests += 1; return true }, readAuthorization: { status })
        var applied: [Bool] = []
        let result = await permission.reconcile(enabled: true) { applied.append($0) }
        #expect(result == .enabled && requests == 0 && applied == [true])
    }

    @Test("连续开启请求单飞，不重复弹系统授权")
    func duplicateEnableIsSingleFlight() async throws {
        let gate = Gate()
        var requests = 0
        var applied: [Bool] = []
        let permission = DailyReminderPermission(requestAuthorization: {
            requests += 1
            if requests == 1 { await gate.wait() }
            return true
        }, readAuthorization: { .authorized })
        let first = Task { await permission.update(enabled: true) { applied.append($0) } }
        defer { gate.release() }
        for _ in 0..<1_000 where !gate.started { await Task.yield() }
        try #require(gate.started)
        let second = await permission.update(enabled: true) { applied.append($0) }
        #expect(second == nil && requests == 1)
        gate.release()
        #expect(await first.value == .enabled)
        #expect(applied == [true] && !permission.isUpdating)
    }

    @Test("授权尚未返回时关闭，晚回的允许结果不能重新打开或排期")
    func lateAuthorizationCannotOverwriteDisable() async throws {
        let gate = Gate()
        var applied: [Bool] = []
        let permission = DailyReminderPermission(requestAuthorization: { await gate.wait(); return true }, readAuthorization: { .authorized })
        let first = Task { await permission.update(enabled: true) { applied.append($0) } }
        defer { gate.release() }
        for _ in 0..<1_000 where !gate.started { await Task.yield() }
        try #require(gate.started)
        #expect(await permission.update(enabled: false) { applied.append($0) } == .disabled)
        gate.release()
        #expect(await first.value == nil)
        #expect(permission.outcome == .disabled && applied == [false] && !permission.isUpdating)
    }
}
