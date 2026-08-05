import Foundation
import Testing
@testable import BubuTimeMachine

struct PhotoIntakeTests {
    @Test("身份特征与照片候选物理分库")
    func identityDatabaseIsIsolated() {
        #expect(BubuStorage.identityDatabaseURL != BubuStorage.intakeDatabaseURL)
        #expect(BubuStorage.identityDatabaseURL.lastPathComponent == "PhotoIdentity.sqlite")
    }

    @Test("身份特征库明确排除系统备份")
    func identityDatabaseIsExcludedFromBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-identity-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("PhotoIdentity.sqlite")
        let store = PhotoIntakeStore(databaseURL: databaseURL, excludeFromBackup: true)

        try store.addIdentitySamples([Data("face".utf8)], label: 1)

        let values = try databaseURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    private func candidate(
        _ id: String,
        minute: Int,
        latitude: Double? = nil,
        longitude: Double? = nil,
        kind: PhotoIntakeMediaKind = .photo,
        burst: String? = nil,
        live: Bool = false
    ) -> PhotoIntakeCandidate {
        PhotoIntakeCandidate(
            localIdentifier: id,
            creationDate: Date(timeIntervalSince1970: 1_780_000_000 + Double(minute * 60)),
            mediaKind: kind,
            latitude: latitude,
            longitude: longitude,
            width: 4_032,
            height: 3_024,
            duration: kind == .video ? 12 : 0,
            burstIdentifier: burst,
            isLivePhoto: live
        )
    }

    private func makeStore() throws -> (PhotoIntakeStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bubu-intake-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (PhotoIntakeStore(databaseURL: directory.appendingPathComponent("intake.sqlite")), directory)
    }

    @Test("相隔九十分钟以上自动拆成两段时光")
    func splitsByTimeGap() {
        let groups = PhotoEventClusterer.cluster([
            candidate("a", minute: 0),
            candidate("b", minute: 20),
            candidate("c", minute: 130),
        ])
        #expect(groups.count == 2)
        #expect(groups.map(\.totalCount).sorted() == [1, 2])
    }

    @Test("相隔较远且已有时间间隔时按地点拆分")
    func splitsByLocation() {
        let groups = PhotoEventClusterer.cluster([
            candidate("home", minute: 0, latitude: 31.2304, longitude: 121.4737),
            candidate("park", minute: 20, latitude: 31.2500, longitude: 121.5000),
        ])
        #expect(groups.count == 2)
    }

    @Test("同一连拍不会被跨日或地点规则误拆")
    func burstStaysTogether() {
        let groups = PhotoEventClusterer.cluster([
            candidate("a", minute: 0, latitude: 31.2, longitude: 121.4, burst: "burst-1"),
            candidate("b", minute: 180, latitude: 32.2, longitude: 122.4, burst: "burst-1"),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.totalCount == 2)
    }

    @Test("事件 ID 与输入顺序无关且媒体计数准确")
    func stableGroupIdentityAndCounts() throws {
        let items = [
            candidate("photo", minute: 0, live: true),
            candidate("video", minute: 2, kind: .video),
        ]
        let first = try #require(PhotoEventClusterer.cluster(items).first)
        let second = try #require(PhotoEventClusterer.cluster(items.reversed()).first)
        #expect(first.id == second.id)
        #expect(first.photoCount == 1)
        #expect(first.videoCount == 1)
        #expect(first.livePhotoCount == 1)
    }

    @Test("已确认状态不会被再次发现重置")
    func acceptedStateSurvivesRediscovery() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = candidate("asset-1", minute: 0)

        try store.upsertDiscovered([item])
        #expect(try store.pendingIdentifiers() == ["asset-1"])
        try store.mark(["asset-1"], state: .accepted)
        try store.upsertDiscovered([item])

        #expect(try store.pendingIdentifiers().isEmpty)
        #expect(try store.states(for: ["asset-1"])["asset-1"] == .accepted)
    }

    @Test("摄取元数据可跨实例读取与清除")
    func metadataPersists() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let value = Data("change-token".utf8)
        try store.setData(value, forMetadataKey: "token")

        let reopened = PhotoIntakeStore(databaseURL: store.databaseURL)
        #expect(try reopened.data(forMetadataKey: "token") == value)
        try reopened.setData(nil, forMetadataKey: "token")
        #expect(try store.data(forMetadataKey: "token") == nil)
    }

    @Test("已忽略候选跨重启仍不会重新提示")
    func ignoredStateSurvivesRediscovery() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = candidate("ignored-asset", minute: 0)

        try store.upsertDiscovered([item])
        try store.mark([item.localIdentifier], state: .ignored)
        let reopened = PhotoIntakeStore(databaseURL: store.databaseURL)
        try reopened.upsertDiscovered([item])

        #expect(try reopened.pendingIdentifiers().isEmpty)
        #expect(try reopened.states(for: [item.localIdentifier])[item.localIdentifier] == .ignored)
    }

    @Test("一千个候选可稳定分组且不丢素材")
    func clustersLargeBatchWithoutLoss() {
        let items = (0..<1_000).map { index in
            candidate("asset-\(index)", minute: index * 2)
        }
        let groups = PhotoEventClusterer.cluster(items)
        #expect(groups.reduce(0) { $0 + $1.totalCount } == items.count)
        #expect(Set(groups.flatMap(\.assetIdentifiers)).count == items.count)
    }

    @Test("身份样本正负分离、去重且可一键清除")
    func identitySamplesAreLocalAndClearable() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.addIdentitySamples([Data("bubu-face".utf8), Data("bubu-face".utf8)], label: 1)
        try store.addIdentitySamples([Data("other-face".utf8)], label: -1)

        let counts = try store.identitySampleCounts()
        #expect(counts.positive == 1)
        #expect(counts.negative == 1)
        #expect(try store.identitySamples().count == 2)

        try store.clearIdentitySamples()
        #expect(try store.identitySamples().isEmpty)
    }

    @Test("每类身份样本最多保留最近四十张脸")
    func identitySampleCap() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = (0..<55).map { Data("face-\($0)".utf8) }

        try store.addIdentitySamples(samples, label: 1)

        #expect(try store.identitySampleCounts().positive == 40)
    }

    @Test("感知哈希距离与相似组代表图选择稳定")
    func perceptualHashGrouping() throws {
        let base = PhotoSelectionSignals(
            perceptualHash: 0b1111, sharpness: 0.4, exposure: 0.8,
            qualityScore: 0.5, shouldSuppress: false, suppressionReason: nil)
        let better = PhotoSelectionSignals(
            perceptualHash: 0b1110, sharpness: 0.8, exposure: 0.8,
            qualityScore: 0.8, shouldSuppress: false, suppressionReason: nil)
        let far = PhotoSelectionSignals(
            perceptualHash: UInt64.max, sharpness: 0.9, exposure: 0.9,
            qualityScore: 0.9, shouldSuppress: false, suppressionReason: nil)

        #expect(PhotoSelectionAnalyzer.hammingDistance(base.perceptualHash, better.perceptualHash) == 1)
        let groups = PhotoSelectionAnalyzer.groupSimilar([
            PhotoSelectionItem(identifier: "a", signals: base),
            PhotoSelectionItem(identifier: "b", signals: better),
            PhotoSelectionItem(identifier: "c", signals: far),
        ], maximumHammingDistance: 2)

        #expect(groups.count == 2)
        #expect(try #require(groups.first { $0.memberIdentifiers.contains("a") })
            .representativeIdentifier == "b")
    }

    @Test("截图信号不会进入精选相似组")
    func screenshotsAreNotRecommended() {
        let screenshot = PhotoSelectionSignals(
            perceptualHash: 1, sharpness: 1, exposure: 1,
            qualityScore: 1, shouldSuppress: true, suppressionReason: "截图默认不推荐")
        let groups = PhotoSelectionAnalyzer.groupSimilar([
            PhotoSelectionItem(identifier: "screen", signals: screenshot)
        ])
        #expect(groups.isEmpty)
    }
}
