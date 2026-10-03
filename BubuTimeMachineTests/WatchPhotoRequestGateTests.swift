import Foundation
import Testing
@testable import BubuTimeMachine

/// 请求失败要能重试，但不能绕过限流或抹掉其他已请求批次。
struct WatchPhotoRequestGateTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func expectBegin(_ gate: inout WatchPhotoRequestGate,
                             fingerprint: String, at date: Date, expected: Bool) {
        let result = gate.begin(fingerprint: fingerprint, at: date)
        #expect(result == expected)
    }

    @Test("首次批次允许请求，成功批次不会重复请求")
    func firstBatchAndSuccessfulDeduplication() {
        var gate = WatchPhotoRequestGate()
        expectBegin(&gate, fingerprint: "a", at: start, expected: true)
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(61), expected: false)
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(3_600), expected: false)
    }

    @Test("节流为严格超过 60 秒，遭拒新批次不污染去重状态")
    func throttledBatchCanBeRequestedLater() {
        var gate = WatchPhotoRequestGate()
        expectBegin(&gate, fingerprint: "a", at: start, expected: true)
        expectBegin(&gate, fingerprint: "b", at: start.addingTimeInterval(30), expected: false)
        expectBegin(&gate, fingerprint: "b", at: start.addingTimeInterval(60), expected: false)
        expectBegin(&gate, fingerprint: "b", at: start.addingTimeInterval(61), expected: true)
    }

    @Test("失败允许同批重试，但仍保留最后发送时间的限流")
    func failedBatchRetriesAfterThrottle() {
        var gate = WatchPhotoRequestGate()
        expectBegin(&gate, fingerprint: "a", at: start, expected: true)
        gate.failed(fingerprint: "a")
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(30), expected: false)
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(60), expected: false)
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(61), expected: true)
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(122), expected: false)
    }

    @Test("失败只移除对应批次，其他成功批次继续抑制重复")
    func failureDoesNotRemoveOtherBatches() {
        var gate = WatchPhotoRequestGate()
        expectBegin(&gate, fingerprint: "a", at: start, expected: true)
        expectBegin(&gate, fingerprint: "b", at: start.addingTimeInterval(61), expected: true)
        gate.failed(fingerprint: "b")
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(122), expected: false)
        expectBegin(&gate, fingerprint: "b", at: start.addingTimeInterval(122), expected: true)
    }

    @Test("未知批次与重复失败回调不影响成功批次")
    func unrelatedFailureIsHarmless() {
        var gate = WatchPhotoRequestGate()
        expectBegin(&gate, fingerprint: "a", at: start, expected: true)
        gate.failed(fingerprint: "unknown")
        gate.failed(fingerprint: "unknown")
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(61), expected: false)
        expectBegin(&gate, fingerprint: "b", at: start.addingTimeInterval(61), expected: true)
    }

    @Test("时钟回拨保守拒绝且不污染后续请求")
    func backwardsClockDoesNotOpenGate() {
        var gate = WatchPhotoRequestGate()
        expectBegin(&gate, fingerprint: "a", at: start, expected: true)
        gate.failed(fingerprint: "a")
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(-3_600), expected: false)
        expectBegin(&gate, fingerprint: "b", at: start.addingTimeInterval(-1), expected: false)
        expectBegin(&gate, fingerprint: "b", at: start.addingTimeInterval(60), expected: false)
        expectBegin(&gate, fingerprint: "a", at: start.addingTimeInterval(61), expected: true)
    }

    @Test("最多保留八批，按 FIFO 淘汰最旧批次而非任意批次")
    func oldestBatchIsEvictedAfterNinthRequest() {
        var gate = WatchPhotoRequestGate()
        for index in 0..<9 {
            expectBegin(&gate, fingerprint: "batch-\(index)",
                               at: start.addingTimeInterval(Double(index) * 61), expected: true)
        }
        let later = start.addingTimeInterval(9 * 61)
        for index in 1..<9 {
            expectBegin(&gate, fingerprint: "batch-\(index)", at: later, expected: false)
        }
        expectBegin(&gate, fingerprint: "batch-0", at: later, expected: true)
        expectBegin(&gate, fingerprint: "batch-8", at: later.addingTimeInterval(61), expected: false)
        expectBegin(&gate, fingerprint: "batch-1", at: later.addingTimeInterval(61), expected: true)
    }

    @Test("被限流的候选批次不会占用八批容量或触发淘汰")
    func rejectedRequestsDoNotEvictSuccessfulBatches() {
        var gate = WatchPhotoRequestGate()
        for index in 0..<8 {
            let time = start.addingTimeInterval(Double(index) * 61)
            expectBegin(&gate, fingerprint: "batch-\(index)", at: time, expected: true)
            expectBegin(&gate, fingerprint: "rejected-\(index)", at: time.addingTimeInterval(1), expected: false)
        }
        let later = start.addingTimeInterval(8 * 61)
        expectBegin(&gate, fingerprint: "batch-0", at: later, expected: false)
        expectBegin(&gate, fingerprint: "batch-7", at: later, expected: false)
        expectBegin(&gate, fingerprint: "rejected-0", at: later, expected: true)
    }
}
