import Foundation
import Testing
@testable import BubuTimeMachine

struct PhotoIntakeTests {
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
}
