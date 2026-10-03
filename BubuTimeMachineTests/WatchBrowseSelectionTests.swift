import Foundation
import Testing
@testable import BubuTimeMachine

/// 浏览状态按回忆 ID 固定，不让手机推送的新快照把正在看的照片挤走。
struct WatchBrowseSelectionTests {
    private func memory(_ id: String, note: String = "回忆") -> WatchMemory {
        WatchMemory(id: id, dateText: "10月3日", note: note, ageText: "2岁",
                    moodEmoji: "🌸", photoFileName: "\(id).jpg")
    }

    private func snapshot(memories: [WatchMemory]? = nil,
                          recent: [WatchRecent] = []) -> WatchSnapshot {
        WatchSnapshot(childName: "测试宝宝", birthday: nil, roleRaw: "爸爸",
                      achievedMilestones: 1, totalMilestones: 10,
                      recent: recent, updatedAt: Date(timeIntervalSince1970: 0),
                      memories: memories)
    }

    @Test("首次接收快照选中第一段回忆")
    func initialSelection() {
        var selection = WatchBrowseSelection()
        let items = [memory("a"), memory("b")]
        #expect(selection.selectedID == nil)
        #expect(selection.index(in: items) == 0)
        selection.reconcile(with: items)
        #expect(selection.selectedID == "a")
        #expect(selection.index(in: items) == 0)
    }

    @Test("快照前插新回忆时保留正在看的 ID")
    func insertionKeepsSelectedPhoto() {
        var selection = WatchBrowseSelection(selectedID: "b")
        let updated = [memory("new"), memory("a"), memory("b")]
        selection.reconcile(with: updated)
        #expect(selection.selectedID == "b")
        #expect(selection.index(in: updated) == 2)
    }

    @Test("选中的回忆被移除时回到第一段")
    func removedSelectionFallsBackToFirst() {
        var selection = WatchBrowseSelection(selectedID: "removed")
        let items = [memory("a"), memory("b")]
        #expect(selection.index(in: items) == 0)
        selection.reconcile(with: items)
        #expect(selection.selectedID == "a")
        #expect(selection.index(in: items) == 0)
    }

    @Test("快照缩短但选中 ID 仍存在时不跳图")
    func shortenedSnapshotKeepsSelection() {
        var selection = WatchBrowseSelection(selectedID: "b")
        selection.reconcile(with: [memory("b")])
        #expect(selection.selectedID == "b")
        #expect(selection.index(in: [memory("b")]) == 0)
    }

    @Test("清空快照后清空选择，新快照恢复从第一段开始")
    func emptySnapshotClearsSelection() {
        var selection = WatchBrowseSelection(selectedID: "b")
        selection.reconcile(with: [])
        #expect(selection.selectedID == nil)
        #expect(selection.index(in: []) == 0)
        selection.reconcile(with: [memory("new")])
        #expect(selection.selectedID == "new")
    }

    @Test("非有限表冠值不会跳图")
    func nonFiniteCrownDoesNotChangeSelection() {
        let items = [memory("a"), memory("b"), memory("c")]
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            var selection = WatchBrowseSelection(selectedID: "b")
            selection.select(crownValue: value, in: items)
            #expect(selection.selectedID == "b")
            #expect(selection.index(in: items) == 1)
        }
    }

    @Test("有限但超出 Int 范围的表冠值安全夹到首尾")
    func enormousCrownClampsSafely() {
        let items = [memory("a"), memory("b"), memory("c")]
        var selection = WatchBrowseSelection(selectedID: "b")
        selection.select(crownValue: Double.greatestFiniteMagnitude, in: items)
        #expect(selection.selectedID == "c")
        selection.select(crownValue: -Double.greatestFiniteMagnitude, in: items)
        #expect(selection.selectedID == "a")
    }

    @Test("正常表冠值选中对应回忆并夹住越界值")
    func crownSelectsAndClamps() {
        let items = [memory("a"), memory("b"), memory("c")]
        var selection = WatchBrowseSelection()
        selection.select(crownValue: 1, in: items)
        #expect(selection.selectedID == "b")
        selection.select(crownValue: 50, in: items)
        #expect(selection.selectedID == "c")
        selection.select(crownValue: -50, in: items)
        #expect(selection.selectedID == "a")
    }

    @Test("上一段下一段在序列边界停住，不循环")
    func steppingStopsAtEdges() {
        let items = [memory("a"), memory("b"), memory("c")]
        var selection = WatchBrowseSelection(selectedID: "b")
        selection.step(1, in: items)
        #expect(selection.selectedID == "c")
        selection.step(1, in: items)
        #expect(selection.selectedID == "c")
        selection.step(-1, in: items)
        #expect(selection.selectedID == "b")
        selection.step(-1, in: items)
        selection.step(-1, in: items)
        #expect(selection.selectedID == "a")
    }

    @Test("Int 极值翻页安全饱和，不发生加减溢出")
    func extremeStepsDoNotOverflow() {
        let items = [memory("a"), memory("b"), memory("c")]
        var selection = WatchBrowseSelection(selectedID: "b")
        selection.step(Int.max, in: items)
        #expect(selection.selectedID == "c")
        selection.step(Int.max, in: items)
        #expect(selection.selectedID == "c")
        selection.step(Int.min, in: items)
        #expect(selection.selectedID == "a")
        selection.step(Int.min, in: items)
        #expect(selection.selectedID == "a")
    }

    @Test("空序列的表冠与翻页操作保持无选择")
    func emptyNavigationIsSafe() {
        var selection = WatchBrowseSelection(selectedID: "stale")
        selection.select(crownValue: Double.greatestFiniteMagnitude, in: [])
        #expect(selection.selectedID == nil)
        #expect(selection.index(in: []) == 0)
        selection.step(Int.min, in: [])
        #expect(selection.selectedID == nil)
    }

    @Test("读取 nil 或完全空快照返回空序列")
    func nilAndEmptyReadModels() {
        #expect(WatchReadModel.memories(from: nil).isEmpty)
        #expect(WatchReadModel.memories(from: snapshot()).isEmpty)
        #expect(WatchReadModel.memories(from: snapshot(memories: [])).isEmpty)
    }

    @Test("有 v2 回忆时优先回忆而不是混入 recent")
    func memoriesTakePriority() {
        let item = memory("m", note: "当时的回忆")
        let recent = WatchRecent(id: "r", dateText: "今天", note: "最近", moodEmoji: nil)
        let result = WatchReadModel.memories(from: snapshot(memories: [item], recent: [recent]))
        #expect(result == [item])
    }

    @Test("空 v2 回忆回落 recent，保留日期摘要心情与照片")
    func emptyMemoriesFallBackToRecent() throws {
        let recent = WatchRecent(id: "r", dateText: "10月2日", note: "第一次画画",
                                 moodEmoji: "🎨", photoFileName: "drawing.jpg")
        let result = WatchReadModel.memories(from: snapshot(memories: [], recent: [recent]))
        let item = try #require(result.first)
        #expect(result.count == 1)
        #expect(item.id == recent.id)
        #expect(item.dateText == recent.dateText)
        #expect(item.note == recent.note)
        #expect(item.moodEmoji == recent.moodEmoji)
        #expect(item.photoFileName == recent.photoFileName)
        #expect(item.ageText.isEmpty)
        #expect(item.isOnThisDay == false)
    }

    @Test("真实 v1 形状解码后仍可浏览文字回忆")
    func legacySnapshotFallsBackToRecent() throws {
        let json = """
        {"childName":"测试宝宝","birthday":null,"roleRaw":"爸爸",
         "achievedMilestones":1,"totalMilestones":10,
         "recent":[{"id":"legacy","dateText":"7月28日","note":"旧版回忆","moodEmoji":null}],
         "avatarData":null,"updatedAt":"2026-07-30T00:00:00Z"}
        """
        let decoded = try #require(WatchLink.decode(WatchSnapshot.self, from: Data(json.utf8)))
        #expect(decoded.memories == nil)
        let result = WatchReadModel.memories(from: decoded)
        let item = try #require(result.first)
        #expect(result.count == 1)
        #expect(item.id == "legacy")
        #expect(item.note == "旧版回忆")
        #expect(item.ageText.isEmpty)
        #expect(item.isOnThisDay == false)
        #expect(item.photoFileName == nil)
    }

    @Test("回忆与 recent 都按 ID 保序去重，保留第一条内容")
    func duplicateIDsKeepFirstOccurrence() {
        let first = memory("a", note: "第一条")
        let last = memory("b")
        let result = WatchReadModel.memories(from: snapshot(
            memories: [first, memory("a", note: "重复"), last, memory("b", note: "重复")]))
        #expect(result == [first, last])

        let recent = [
            WatchRecent(id: "a", dateText: "今天", note: "第一条", moodEmoji: nil),
            WatchRecent(id: "a", dateText: "今天", note: "重复", moodEmoji: nil),
            WatchRecent(id: "b", dateText: "昨天", note: "第二条", moodEmoji: nil)
        ]
        let fallback = WatchReadModel.memories(from: snapshot(recent: recent))
        #expect(fallback.map(\.id) == ["a", "b"])
        #expect(fallback.map(\.note) == ["第一条", "第二条"])
    }
}
