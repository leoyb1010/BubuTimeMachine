import SwiftUI
import UIKit

/// What every page of the online detail pager reads: which page is in front, whether the
/// chrome (navigation bar + caption) is showing, and which page's info sheet is open.
@Observable @MainActor
final class OnlineDetailPagerState {
    var current: String
    var chromeVisible = true
    var infoID: String?
    /// A vertical fold across the pager (safe-area coordinates): photo before it, analysis after it.
    var split: BubuLayout.ColumnSplit?
    /// Bars stand vertically at the side (iPhone Duo): photos stay clear of them and extend under them.
    var extendsUnderBar = false

    init(current: String) { self.current = current }
}

/// UIPageViewController instead of SwiftUI TabView(.page): paging stays aligned while a page holds a
/// zoomable UIScrollView (same reason as MediaViewer's PhotoPager), and nothing vertical sits in the way
/// of the swipe-down that closes the zoom transition.
struct OnlineDetailPageController: UIViewControllerRepresentable {
    let items: [OnlineTimelineItem]
    let state: OnlineDetailPagerState
    let page: (OnlineTimelineItem) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal,
                                         options: [.interPageSpacing: 16])
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        pager.view.backgroundColor = .clear
        if let item = items.first(where: { $0.id == state.current }) ?? items.first {
            pager.setViewControllers([context.coordinator.controller(for: item)], direction: .forward, animated: false)
        }
        context.coordinator.lastIDs = items.map(\.id)
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let ids = items.map(\.id)
        defer { coordinator.lastIDs = ids }
        guard !items.isEmpty else { return }
        let shown = (pager.viewControllers?.first as? OnlineDetailHostingController)?.itemID
        if shown != state.current, let target = items.firstIndex(where: { $0.id == state.current }) {
            // Moved from outside, e.g. the page in front was removed ("不是布布").
            let from = shown.flatMap { coordinator.lastIDs.firstIndex(of: $0) } ?? target
            pager.setViewControllers([coordinator.controller(for: items[target])],
                                     direction: target >= from ? .forward : .reverse, animated: false)
            coordinator.evict(around: state.current)
        } else if ids != coordinator.lastIDs, let front = pager.viewControllers?.first, let shown,
                  shown == coordinator.lastIDs.last || shown == coordinator.lastIDs.first {
            // Pages arrived past an edge UIKit already found empty (load more): make it ask again.
            pager.setViewControllers([front], direction: .forward, animated: false)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: OnlineDetailPageController
        var lastIDs: [String] = []
        private var cache: [String: OnlineDetailHostingController] = [:]

        init(_ parent: OnlineDetailPageController) { self.parent = parent }

        func controller(for item: OnlineTimelineItem) -> OnlineDetailHostingController {
            if let cached = cache[item.id] { return cached }
            let controller = OnlineDetailHostingController(itemID: item.id, rootView: parent.page(item))
            cache[item.id] = controller
            return controller
        }

        /// Keeps the front page ±1; each holds a full-screen decoded image and maybe an AVPlayer.
        func evict(around id: String) {
            let items = parent.items
            guard let center = items.firstIndex(where: { $0.id == id }) else { return }
            let keep = Set(items[max(0, center - 1)...min(items.count - 1, center + 1)].map(\.id))
            cache = cache.filter { keep.contains($0.key) }
        }

        private func index(of controller: UIViewController) -> Int? {
            guard let page = controller as? OnlineDetailHostingController else { return nil }
            return parent.items.firstIndex { $0.id == page.itemID }
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerBefore controller: UIViewController) -> UIViewController? {
            guard let i = index(of: controller), i > 0 else { return nil }
            return self.controller(for: parent.items[i - 1])
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerAfter controller: UIViewController) -> UIViewController? {
            guard let i = index(of: controller), i < parent.items.count - 1 else { return nil }
            return self.controller(for: parent.items[i + 1])
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let front = pvc.viewControllers?.first as? OnlineDetailHostingController else { return }
            parent.state.current = front.itemID
            evict(around: front.itemID)
        }
    }
}

final class OnlineDetailHostingController: UIHostingController<AnyView> {
    let itemID: String

    init(itemID: String, rootView: AnyView) {
        self.itemID = itemID
        super.init(rootView: rootView)
        view.backgroundColor = .clear
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) unavailable") }
}

/// Full-screen photo: the grid's decoded thumbnail shows at once (so the zoom transition lands on the
/// picture), the large image crossfades in over it, and pinch / double-tap zoom stays put and pans.
struct OnlineDetailPhoto: View {
    let item: OnlineTimelineItem
    let client: BubuLearningClient
    var isActive = true
    var onSingleTap: (() -> Void)? = nil
    /// Mirror the picture under vertical side bars (backgroundExtensionEffect) instead of leaving them on black.
    var extendsUnderBars = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var large: UIImage?
    @State private var preview: UIImage?
    @State private var bucket = 0
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        let shown = large
            ?? LearningImagePipeline.anyCached(scope: client.scope, path: item.largeUrl)
            ?? preview
            ?? LearningImagePipeline.anyCached(scope: client.scope, path: item.previewUrl)
        ZStack {
            if let shown {
                ZoomableImageView(image: shown, onSingleTap: onSingleTap, crossfade: !reduceMotion, isActive: isActive)
                    .background {
                        // The UIKit zoom view can't be mirrored; a SwiftUI copy sits exactly behind it (same
                        // aspect-fit frame) and carries the extension into the side bars' area.
                        if extendsUnderBars {
                            Image(uiImage: shown).resizable().scaledToFit()
                                .bubuBackgroundExtension()
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(item.description.isEmpty ? "布布的照片" : item.description)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityHint("双指捏合或轻点两下可以放大，放大后可以拖动")
                    .accessibilityIdentifier("timeline.photo")
            } else {
                Color.clear.contentShape(Rectangle()).onTapGesture { onSingleTap?() }
                    .accessibilityHidden(true)
            }
            if failed && large == nil {
                Button { retry += 1 } label: {
                    Label(shown == nil ? "照片没加载出来，点这里重试" : "高清图没加载出来，点这里重试",
                          systemImage: "arrow.clockwise")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.5), in: Capsule())
                }
                .buttonStyle(BubuPressableStyle())
                .accessibilityIdentifier("remote-image.retry")
            }
        }
        .onGeometryChange(for: CGFloat.self) { max($0.size.width, $0.size.height) } action: { side in
            guard side > 0 else { return }
            let wanted = LearningImageDecoder.bucket(forPixels: side * displayScale)
            if wanted > bucket { bucket = wanted }
        }
        // Opened from somewhere that never showed the grid thumbnail: fetch it too, it is far smaller.
        .task(id: retry) {
            guard LearningImagePipeline.anyCached(scope: client.scope, path: item.largeUrl) == nil,
                  LearningImagePipeline.anyCached(scope: client.scope, path: item.previewUrl) == nil,
                  let thumb = try? await LearningImagePipeline.load(item.previewUrl, client: client, bucket: 512, diskCache: true),
                  large == nil else { return }
            preview = thumb
        }
        .task(id: "\(bucket)|\(retry)") {
            guard bucket > 0 else { return }
            failed = false
            do {
                large = try await LearningImagePipeline.load(item.largeUrl, client: client, bucket: bucket, diskCache: true)
            } catch where isCancellation(error) {
            } catch { failed = true }
        }
    }
}
