import SwiftUI
import UIKit

/// One screen, no routes and no writes. A batch stays frozen while being viewed.
struct WatchPhotoView: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("bubu.watch.celebratedPicksDay") private var celebratedPicksDay = ""
    @State private var celebrating = false
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
    /// 翻页动画：轻弹簧；减弱动态效果时只做淡入淡出。
    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15)
    }
    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    var body: some View {
        let displayed = photos
        let memories = displayed.map(\.memory)
        let index = selection.index(in: memories)
        Group {
            if displayed.isEmpty && loadedSession == -1 {
                // 冷启动：缓存里的照片还在异步解码，先给一块安静的占位，不闪引导文案。
                ProgressView().tint(.pink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("正在打开照片")
            } else if displayed.isEmpty {
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
                    // 图片始终占满整屏，说明浮在底部渐变层上：翻页时照片高度不随说明行数跳动。
                    ZStack {
                        Image(uiImage: current.image).resizable().scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped().accessibilityHidden(true)
                            .id(current.memory.id)
                            .transition(pageTransition)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay(alignment: .bottom) {
                        if showsCaption { caption(current.memory).transition(.opacity) }
                    }
                    .overlay(alignment: .trailing) {
                        if displayed.count > 1 { pageDots(count: displayed.count, current: index) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showsCaption.toggle() } }
                    .gesture(DragGesture(minimumDistance: 25).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        step(value.translation.width < 0 ? 1 : -1)
                    })
                    .focusable(displayed.count > 1).focused($focused)
                    .digitalCrownRotation($crown, from: 0, through: Double(max(1, displayed.count - 1)),
                                          by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel([current.memory.reason, current.memory.dateText, current.memory.note]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，"))
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
        .overlay {
            if celebrating { WatchSparkleView().ignoresSafeArea() }
        }
        .background(.black)
        .ignoresSafeArea(.container, edges: .bottom)
        .dynamicTypeSize(previewType)
        .onOpenURL { _ in } // All former widget links open this same screen.
        .onChange(of: crown) { _, value in
            withAnimation(pageAnimation) { selection.select(crownValue: value, in: cards) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session += 1; focused = photos.count > 1 }
        }
        .task(id: LoadKey(session: session, updatedAt: connector.snapshot?.updatedAt,
                          photoVersion: connector.photoVersion, active: scenePhase == .active)) {
            guard scenePhase == .active, loadedSession != session || photos.isEmpty else { return }
            let snapshot = connector.snapshot
            let now = Date.now
            // 家人近期照片与精选合并成一组（WatchReadModel.deck），图还没到的先跳过。
            let ready = await Self.load(WatchReadModel.deck(from: snapshot, now: now))
            guard !Task.isCancelled else { return }
            // Keep the previous cached batch while its replacement is in flight.
            // An explicit empty list, however, must withdraw now-ineligible items.
            let explicitlyEmpty = snapshot?.photoCards?.isEmpty == true
                && WatchReadModel.dailyPicks(from: snapshot, now: now).isEmpty
            if !ready.isEmpty || explicitlyEmpty {
                photos = ready
                selection.reconcile(with: ready.map(\.memory))
                crown = Double(selection.index(in: ready.map(\.memory)))
            }
            loadedSession = session
            focused = photos.count > 1
            let freshPicks = DailyPicksDay.freshness(of: snapshot?.dailyPicksDay, now: now) == .today
            let showsPicks = ready.contains { $0.memory.id.hasPrefix("pick-") }
            if freshPicks, showsPicks, let day = snapshot?.dailyPicksDay, day != celebratedPicksDay {
                celebratedPicksDay = day
                if !reduceMotion {
                    celebrating = true
                    try? await Task.sleep(for: .seconds(WatchSparkleView.duration))
                    celebrating = false
                }
            }
        }
    }

    private func caption(_ memory: WatchMemory) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let reason = memory.reason, !reason.isEmpty {
                    Text(reason).font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Color(red: 0.882, green: 0.361, blue: 0.525), in: Capsule())
                }
                Text(memory.dateText).font(.caption2)
                    .foregroundStyle(Color(red: 0.88, green: 0.65, blue: 0.72))
            }
            if !memory.note.isEmpty {
                Text(memory.note).font(.footnote).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }

    /// 表冠一侧的位置小圆点：当前那张拉长成胶囊。
    private func pageDots(count: Int, current: Int) -> some View {
        VStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.pink : Color.white.opacity(0.4))
                    .frame(width: 4, height: i == current ? 10 : 4)
            }
        }
        .padding(.trailing, 3)
        .animation(pageAnimation, value: current)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func load(_ candidates: [WatchMemory]) async -> [Photo] {
        let bytes = await Task.detached(priority: .utility) {
            candidates.compactMap { card -> (WatchMemory, Data)? in
                guard let data = WatchPhotoStore.data(for: card.photoFileName) else { return nil }
                return (card, data)
            }
        }.value
        return bytes.compactMap { card, data -> Photo? in
            guard let image = UIImage(data: data) else { return nil }
            return Photo(memory: card, image: image)
        }
    }

    private func step(_ delta: Int) {
        withAnimation(pageAnimation) { selection.step(delta, in: cards) }
        crown = Double(selection.index(in: cards))
    }
}
