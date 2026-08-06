import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 上传批次状态机守卫回归
/// 钉死两道防重复 Entry 的闸：
/// ① 已 committed 的批次不被迟到的 failed job 降级（降级会把资产还原回候选箱，
///    用户再确认就是服务器上的第二个 Entry）；
/// ② uploadBatchHasSucceededJobs 是 404 对账的判据——有成功上传记录的批次
///    大概率服务端已 commit 后被清理周期删行，此时绝不还原候选。
@MainActor
struct PhotoUploadBatchGuardTests {

    private func makeStore() throws -> (PhotoIntakeStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-guard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (PhotoIntakeStore(databaseURL: directory.appendingPathComponent("intake.sqlite")), directory)
    }

    private func job(_ key: String, batch: String) -> PhotoUploadJob {
        PhotoUploadJob(assetKey: key, batchID: batch,
                       assetLocalIdentifier: "asset-\(key)",
                       resourceType: 1, resourceFilename: "\(key).jpg",
                       destinationURL: "https://bubu-ai.leoyuan.top/intake/upload/\(key)",
                       uploadToken: "tok-\(key)", mimeType: "image/jpeg",
                       state: .queued, retryCount: 0)
    }

    @Test("committed 批次不被迟到的 failed job 降级回 failed")
    func committedBatchIsNotDowngraded() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let batch = "batch-committed"
        try store.saveUploadBatch(batchID: batch, entryLocalID: UUID().uuidString,
                                  assetIdentifiers: ["asset-a", "asset-b"],
                                  jobs: [job("a", batch: batch), job("b", batch: batch)])
        // 第一个 job 成功 → 服务端 commit → 本地收口为 committed
        try store.updateUploadJob(batchID: batch, assetKey: "a", state: .succeeded)
        try store.updateUploadJob(batchID: batch, assetKey: "b", state: .succeeded)
        try store.finishUploadBatchFromServer(batch)
        let afterCommit = try store.uploadQueueSummary()
        #expect(afterCommit.failedBatches == 0)

        // 迟到的重复 job 副本报 failed（撞 409 的形状）→ reconcile 不得把批次拉回 failed
        try store.updateUploadJob(batchID: batch, assetKey: "b", state: .failed)
        try store.reconcileUploadBatch(batch)
        let summary = try store.uploadQueueSummary()
        #expect(summary.failedBatches == 0, "committed 批次被降级回 failed——防重复 Entry 的闸失效")
    }

    @Test("uploadBatchHasSucceededJobs：有成功记录返回 true，全失败返回 false")
    func succeededJobsProbe() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let winner = "batch-win"
        try store.saveUploadBatch(batchID: winner, entryLocalID: UUID().uuidString,
                                  assetIdentifiers: ["asset-w"], jobs: [job("w", batch: winner)])
        try store.updateUploadJob(batchID: winner, assetKey: "w", state: .succeeded)
        #expect(try store.uploadBatchHasSucceededJobs(winner))

        let loser = "batch-lose"
        try store.saveUploadBatch(batchID: loser, entryLocalID: UUID().uuidString,
                                  assetIdentifiers: ["asset-l"], jobs: [job("l", batch: loser)])
        try store.updateUploadJob(batchID: loser, assetKey: "l", state: .failed)
        #expect(!(try store.uploadBatchHasSucceededJobs(loser)))
        #expect(!(try store.uploadBatchHasSucceededJobs("no-such-batch")))
    }
}

// MARK: - 服务器信任边界补测
/// ServerConfigTrustTests 只测了主线（受信接受/外部拒绝/loopback 开关），
/// isTrustedAIURL 里逐条写的防御（http 降级、userinfo、端口）此前零覆盖。
struct ServerTrustHardeningTests {

    private let packaged = URL(string: "https://bubu-ai.leoyuan.top")!

    private func trusted(_ candidate: String, loopback: Bool = false) -> Bool {
        guard let url = URL(string: candidate) else { return false }
        return ServerConfig.isTrustedAIURL(url, serverURL: nil,
                                           packagedAIURL: packaged, allowLoopback: loopback)
    }

    @Test("http 降级被拒（同主机也不行）")
    func rejectsHTTPDowngrade() {
        #expect(!trusted("http://bubu-ai.leoyuan.top/intake"))
    }

    @Test("URL 带 userinfo 被拒（钓鱼形态 user@evil）")
    func rejectsUserinfo() {
        #expect(!trusted("https://bubu-ai.leoyuan.top@evil.example.com/steal"))
        #expect(!trusted("https://user:pass@bubu-ai.leoyuan.top/intake"))
    }

    @Test("端口不一致被拒")
    func rejectsPortMismatch() {
        #expect(!trusted("https://bubu-ai.leoyuan.top:8443/intake"))
    }

    @Test("受信主机同端口接受")
    func acceptsPackagedHost() {
        #expect(trusted("https://bubu-ai.leoyuan.top/intake/upload/x"))
    }
}
