import SwiftUI
import UIKit

/// Quiet OLED material, shared by the reading surfaces. No always-running renderer.
struct WatchReadingBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.14, green: 0.08, blue: 0.12), .black],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct WatchPhotoSurface: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.scenePhase) private var scenePhase
    let fileName: String?
    var avatarData: Data? = nil
    var emoji: String = "🌷"
    var fitsPhoto = false
    @State private var image: UIImage?
    @State private var waitingForPhoto = false

    private struct Request: Hashable {
        let name: String?
        let version: Int
        let avatar: Data?
        let active: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [WatchTheme.rose.opacity(0.24), WatchTheme.lav.opacity(0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: fitsPhoto ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack(spacing: 6) {
                        Text(emoji).font(.system(size: 32))
                        if fileName != nil {
                            Text("照片待同步").font(.caption).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                if waitingForPhoto, image != nil {
                    Text("照片待同步").font(.caption2)
                        .padding(5).background(.black.opacity(0.65), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 6)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: Request(name: fileName, version: connector.photoVersion, avatar: avatarData, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            let name = fileName
            let bytes = await Task.detached(priority: .utility) {
                name.flatMap { WatchPhotoStore.data(for: $0) }
            }.value
            guard !Task.isCancelled else { return }
            image = bytes.flatMap { UIImage(data: $0) }
            waitingForPhoto = name != nil && image == nil
            if image == nil { image = avatarData.flatMap { UIImage(data: $0) } }
        }
    }
}

struct WatchReadingEmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2).foregroundStyle(WatchTheme.rose)
            Text(title).font(.headline).fontDesign(.rounded)
            Text(message).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(12)
    }
}

/// Deterministic simulator verification, compiled out of the installed release.
struct WatchReadingPreviewOverrides: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isLuminanceReduced) private var dimmed
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        content
            .environment(\.dynamicTypeSize, arguments.contains("-watch-large-type") ? .accessibility1 : typeSize)
            .environment(\.isLuminanceReduced, dimmed || arguments.contains("-watch-aod"))
            .frame(maxWidth: arguments.contains("-watch-narrow-probe") ? 164 : .infinity)
        #else
        content
        #endif
    }
}
