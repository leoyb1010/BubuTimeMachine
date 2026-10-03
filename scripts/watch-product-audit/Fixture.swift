import SwiftUI
import Observation

// Isolated screenshot adapter. No WatchConnectivity, family files, account,
// entitlements or networking. Production WatchPhotoView is copied unchanged.
@MainActor @Observable final class WatchConnector {
    var snapshot: WatchSnapshot?
    var photoVersion = 0
    init() {
        let empty = ProcessInfo.processInfo.arguments.contains("-audit-empty")
        let long = ProcessInfo.processInfo.arguments.contains("-audit-long")
        snapshot = WatchSnapshot(childName: "测试宝宝", birthday: nil, roleRaw: "家人",
            achievedMilestones: 0, totalMilestones: 0, recent: [], updatedAt: .now,
            photoCards: empty ? [] : (0..<3).map {
                WatchMemory(id: "synthetic-\($0)", dateText: "10月3日",
                    note: long ? String(repeating: "测试说明：一起看风景。", count: 12) : "测试相片：一起看风景。",
                    ageText: "测试", photoFileName: "synthetic-\($0).png")
            })
    }
    func withdraw() {
        snapshot?.photoCards = []
        snapshot?.updatedAt = .now
        print("AUDIT_AUTHORITATIVE_EMPTY_SNAPSHOT_APPLIED")
    }
}
nonisolated enum WatchPhotoStore {
    static func data(for name: String?) -> Data? {
        guard name != nil, !ProcessInfo.processInfo.arguments.contains("-audit-missing"),
              let url = Bundle.main.url(forResource: "synthetic", withExtension: "png") else { return nil }
        return try? Data(contentsOf: url)
    }
}
@main struct WatchProductAuditApp: App {
    @State private var connector = WatchConnector()
    var body: some Scene {
        WindowGroup {
            WatchPhotoView()
                .environment(connector)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("-audit-withdraw") {
                        try? await Task.sleep(for: .seconds(6))
                        connector.withdraw()
                    }
                }
        }
    }
}
