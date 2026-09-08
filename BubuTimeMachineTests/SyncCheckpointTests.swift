import Foundation
import SwiftData
import Testing
@testable import BubuTimeMachine

@MainActor
struct SyncCheckpointTests {
    enum InjectedFailure: Error { case diskUnavailable }

    @Test("进度时间戳从初始化到落盘保持一致")
    func timestampRoundTrip() throws {
        let context = try context()
        for seconds in [100.0, 1_788_800_000.0] {
            let date = Date(timeIntervalSince1970: seconds)
            let row = SyncCheckpoint(key: "date-\(seconds)", updated: date, generation: "one")
            #expect(row.serverUpdatedAt == date)
            context.insert(row)
            #expect(row.serverUpdatedAt == date)
            try context.save()
            #expect(row.serverUpdatedAt == date)
        }
    }

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SharedModelContainer.schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("保存失败不推进已有游标，也不清除用户编辑")
    func failedCommitRestoresProgressAndKeepsEdits() throws {
        let context = try context()
        let initial = Date(timeIntervalSince1970: 100)
        try SyncCheckpoint.commit(key: "family:entries", generation: "one", updated: initial, in: context) { try context.save() }
        context.insert(Entry(authorRole: "audit", note: "尚未保存的用户编辑"))
        do {
            try SyncCheckpoint.commit(key: "family:entries", generation: "one", updated: initial.addingTimeInterval(100), in: context) {
                throw InjectedFailure.diskUnavailable
            }
            Issue.record("必须抛出存储失败")
        } catch InjectedFailure.diskUnavailable {}
        let checkpoint = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first
        #expect(checkpoint?.generation == "one")
        #expect(checkpoint?.serverUpdatedAt == initial)
        #expect(try context.fetch(FetchDescriptor<Entry>()).first?.note == "尚未保存的用户编辑")
        try context.save()
        #expect(try SyncCheckpoint.read(key: "family:entries", generation: "one", in: context) == initial)
    }

    @Test("新游标保存失败后不会被后续自动保存带进数据库")
    func failedNewCheckpointIsRemoved() throws {
        let context = try context()
        do {
            try SyncCheckpoint.commit(key: "new", generation: "one", updated: .now, in: context) {
                throw InjectedFailure.diskUnavailable
            }
            Issue.record("必须抛出存储失败")
        } catch InjectedFailure.diskUnavailable {}
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SyncCheckpoint>()) == 0)
    }

    @Test("不同家庭进度隔离，全量核对可重置且正常游标不倒退")
    func scopesAndResetGeneration() throws {
        let context = try context()
        let initial = Date(timeIntervalSince1970: 100)
        try SyncCheckpoint.commit(key: "a:entries", generation: "one", updated: initial, in: context) { try context.save() }
        #expect(try SyncCheckpoint.read(key: "b:entries", generation: "one", in: context) == nil)
        #expect(try SyncCheckpoint.read(key: "a:entries", generation: "two", in: context) == nil)
        try SyncCheckpoint.commit(key: "a:entries", generation: "one", updated: initial.addingTimeInterval(-10), in: context) { try context.save() }
        let checkpoint = try context.fetch(FetchDescriptor<SyncCheckpoint>()).first
        #expect(checkpoint?.key == "a:entries")
        #expect(checkpoint?.generation == "one")
        #expect(checkpoint?.serverUpdatedAt == initial)
    }
}
