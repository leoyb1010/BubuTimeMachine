import SwiftUI
import UIKit

/// One screen, no routes and no writes. A batch stays frozen while being viewed.
struct WatchPhotoView: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photos: [Photo] = []
    @State private var selection = WatchBrowseSelection()
    @State private var crown = 0.0
    @State private var showsCaption = true
    @State private var session = 0
    @State private var loadedSession = -1
    @FocusState private var focused: Bool

    private struct Photo { let memory: WatchMemory; let image: UIImage }
    private struct LoadKey: Hashable {
        let session: Int
        let updatedAt: Date?
        let photoVersion: Int
        let active: Bool
    }
    private var cards: [WatchMemory] { photos.map(\.memory) }
    private var previewType: DynamicTypeSize {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-watch-large-type") ? .accessibility1 : typeSize
        #else
        typeSize
        #endif
    }

    var body: some View {
        let displayed = photos
        let memories = displayed.map(\.memory)
        let index = selection.index(in: memories)
        Group {
            if displayed.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.pink)
                        Text("把布布带到腕间").font(.headline)
                        Text("打开一次手机上的时光机，照片就会来到这里。")
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }.padding(14)
                }
            } else {
                GeometryReader { geometry in
                    let current = displayed[index]
                    VStack(spacing: 0) {
                        Image(uiImage: current.image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, showsCaption ? 0 : 6)
                            .padding(.bottom, showsCaption ? 0 : 20)
                            .clipped().accessibilityHidden(true)
                        if showsCaption {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(current.memory.dateText).font(.caption2)
                                    .foregroundStyle(Color(red: 0.88, green: 0.65, blue: 0.72))
                                if !current.memory.note.isEmpty {
                                    Text(current.memory.note).font(.footnote).lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16).padding(.top, 5).padding(.bottom, 24)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { showsCaption.toggle() }
                    .gesture(DragGesture(minimumDistance: 25).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        step(value.translation.width < 0 ? 1 : -1)
                    })
                    .focusable(displayed.count > 1).focused($focused)
                    .digitalCrownRotation($crown, from: 0, through: Double(max(1, displayed.count - 1)),
                                          by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(current.memory.dateText)，\(current.memory.note)")
                    .accessibilityValue("第 \(index + 1) 张，共 \(displayed.count) 张")
                    .accessibilityHint("转动表冠或左右滑动换照片，轻点切换说明")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { showsCaption.toggle() }
                    .accessibilityAdjustableAction { direction in
                        switch direction { case .increment: step(1); case .decrement: step(-1); @unknown default: break }
                    }
                }
            }
        }
        .background(.black)
        .ignoresSafeArea(.container, edges: .bottom)
        .dynamicTypeSize(previewType)
        .onOpenURL { _ in } // All former widget links open this same screen.
        .onChange(of: crown) { _, value in selection.select(crownValue: value, in: cards) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session += 1; focused = photos.count > 1 }
        }
        .task(id: LoadKey(session: session, updatedAt: connector.snapshot?.updatedAt,
                          photoVersion: connector.photoVersion, active: scenePhase == .active)) {
            guard scenePhase == .active, loadedSession != session || photos.isEmpty else { return }
            let candidates = WatchReadModel.memories(from: connector.snapshot)
            let bytes = await Task.detached(priority: .utility) {
                candidates.compactMap { card -> (WatchMemory, Data)? in
                    guard let data = WatchPhotoStore.data(for: card.photoFileName) else { return nil }
                    return (card, data)
                }
            }.value
            guard !Task.isCancelled else { return }
            let ready = bytes.compactMap { card, data -> Photo? in
                guard let image = UIImage(data: data) else { return nil }
                return Photo(memory: card, image: image)
            }
            // Keep the previous cached batch while its replacement is in flight.
            // An explicit empty list, however, must withdraw now-ineligible items.
            if !ready.isEmpty || connector.snapshot?.photoCards?.isEmpty == true {
                photos = ready
                selection.reconcile(with: ready.map(\.memory))
                crown = Double(selection.index(in: ready.map(\.memory)))
            }
            loadedSession = session
            focused = photos.count > 1
        }
    }

    private func step(_ delta: Int) {
        selection.step(delta, in: cards)
        crown = Double(selection.index(in: cards))
    }
}
