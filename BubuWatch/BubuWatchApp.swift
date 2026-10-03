import SwiftUI

@main
struct BubuWatchApp: App {
    @State private var connector = WatchConnector()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchPhotoView()
                .environment(connector)
                .task { connector.activate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { connector.reconcilePending() }
        }
    }
}
