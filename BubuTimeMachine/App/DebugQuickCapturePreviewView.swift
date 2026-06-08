import SwiftUI

#if DEBUG
struct DebugQuickCapturePreviewView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: CaptureModel?

    var body: some View {
        Group {
            if let model {
                QuickCaptureSheet(model: model)
            } else {
                ProgressView("准备记录面板…")
                    .task {
                        model = CaptureModel(mediaStore: env.mediaStore,
                                             analyzer: env.photoAnalyzer,
                                             role: env.config.currentRole)
                    }
            }
        }
    }
}
#endif
