import SwiftUI
import SwiftData
import UIKit

// MARK: - 相框模式（家里的第二块屏）
/// 把 iPad / 旧手机变成布布的数字相框：精选照片全屏轮播，缓慢的 Ken Burns 推拉 + 交叉淡入，
/// 「那年今日」的照片优先浮现，角落是名字、年龄与实时时钟。轻点唤出控制条。
struct PhotoFrameView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Entry> { !$0.isArchived }, sort: \Entry.happenedAt, order: .reverse)
    private var entries: [Entry]
    @Query private var profiles: [ChildProfile]

    @State private var slides: [FrameSlide] = []
    @State private var index = 0
    @State private var images: [UUID: UIImage] = [:]
    @State private var paused = false
    @State private var showControls = false
    @State private var now = Date.now

    private let dwell: TimeInterval = 8
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var childName: String { profiles.first?.name ?? env.config.childName }
    private var current: FrameSlide? { slides.indices.contains(index) ? slides[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if slides.isEmpty {
                emptyState
            } else {
                photoLayer
                gradientScrim
                captionLayer
                cornerClock
                if showControls { controlBar }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        // 跨天（那年今日过期）或新照片同步进来都重建播放列表（R4 P2-33）
        .task(id: RebuildKey(day: Calendar.current.startOfDay(for: now), count: entries.count)) {
            buildSlides()
        }
        // 索引或暂停态变化都重排：驱动自动轮播 + 预取
        .task(id: TickKey(index: index, paused: paused, count: slides.count)) {
            await loadAround()
            guard !paused, slides.count > 1 else { return }
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled, !paused else { return }
            advance(1)
        }
        .onReceive(clock) { now = $0 }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: 图层

    private var photoLayer: some View {
        ZStack {
            if let current, let img = images[current.id] {
                KenBurnsImage(image: img, seed: current.id.bubuStableSeed, animating: !paused)
                    .id(current.id)
                    .transition(.opacity)
            } else {
                ProgressView().tint(.white)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.1), value: current?.id)
    }

    private var gradientScrim: some View {
        LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.6)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var captionLayer: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if let current, current.isOnThisDay {
                        Label("那年今日", systemImage: "calendar.badge.clock")
                            .font(BubuTheme.Font.scaled(13, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.orange.opacity(0.85), in: Capsule())
                    }
                    if let current {
                        Text(current.caption)
                            .font(BubuTheme.Font.scaled(22, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                            .lineLimit(2)
                        Text(current.dateText + (current.ageText.isEmpty ? "" : " · " + current.ageText))
                            .font(BubuTheme.Font.scaled(14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                    }
                }
                Spacer()
            }
            .padding(28)
        }
        .allowsHitTesting(false)
    }

    private var cornerClock: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(BubuDateFormat.shortTime(now))
                        .font(BubuTheme.Font.scaled(34, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    Text(childName + "的相册")
                        .font(BubuTheme.Font.scaled(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                }
            }
            Spacer()
        }
        .padding(28)
        .allowsHitTesting(false)
    }

    private var controlBar: some View {
        VStack {
            HStack {
                circleButton("xmark") { dismiss() }
                Spacer()
                Text("\(index + 1) / \(slides.count)")
                    .font(BubuTheme.Font.scaled(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.35), in: Capsule())
            }
            Spacer()
            HStack(spacing: 28) {
                circleButton("backward.fill") { advance(-1) }
                circleButton(paused ? "play.fill" : "pause.fill") { paused.toggle(); bumpControls() }
                circleButton("forward.fill") { advance(1) }
            }
            .padding(.bottom, 24)
        }
        .padding(28)
        .transition(.opacity)
    }

    private func circleButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(BubuTheme.Font.scaled(20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(BubuTheme.Font.scaled(46)).foregroundStyle(.white.opacity(0.7))
            Text("还没有可播放的照片")
                .font(BubuTheme.Font.scaled(18, weight: .heavy)).foregroundStyle(.white)
            Text("先去记录几段带照片的时光，就能把这里变成布布的相框。")
                .font(BubuTheme.Font.scaled(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            Button("返回") { dismiss() }
                .font(BubuTheme.Font.scaled(15, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(.white, in: Capsule())
                .padding(.top, 6)
        }
        .padding(40)
    }

    // MARK: 逻辑

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        if showControls { bumpControls() }
    }

    /// 控制条 3 秒后自动隐藏。
    private func bumpControls() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { withAnimation { showControls = false } }
        }
    }

    private func advance(_ delta: Int) {
        guard !slides.isEmpty else { return }
        withAnimation(.easeInOut(duration: 1.1)) {
            index = (index + delta + slides.count) % slides.count
        }
    }

    /// 组织播放列表：那年今日（按年份新→旧）优先，其余精选/近照打散，营造惊喜。
    private func buildSlides() {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: .now)
        let birthday = profiles.first?.birthday

        var onThisDay: [FrameSlide] = []
        var rest: [FrameSlide] = []

        for entry in entries {
            guard let photo = entry.sortedMedia.first(where: {
                $0.type == .photo && ($0.localFileName != nil || $0.thumbnailFileName != nil)
            }) else { continue }
            let comp = cal.dateComponents([.month, .day, .year], from: entry.happenedAt)
            let isOnThisDay = comp.month == today.month && comp.day == today.day
                && (comp.year ?? 0) < (cal.component(.year, from: .now))
            let caption = entry.note?.isEmpty == false ? entry.note!
                : (entry.title?.isEmpty == false ? entry.title! : "布布的一天")
            let age = birthday.map { AgeCalculator.ageDescription(birthday: $0, at: entry.happenedAt) } ?? ""
            let slide = FrameSlide(
                id: photo.id, media: photo,
                caption: String(caption.prefix(40)),
                dateText: BubuDateFormat.yearMonthDay(entry.happenedAt),
                ageText: age, isOnThisDay: isOnThisDay)
            if isOnThisDay { onThisDay.append(slide) } else { rest.append(slide) }
        }
        onThisDay.sort { $0.dateText > $1.dateText }        // 年份新→旧
        slides = onThisDay + rest.shuffled()
        if index >= slides.count { index = 0 }
    }

    /// 加载当前帧并预取下一帧，顺手回收远处缓存（内存红线）。
    private func loadAround() async {
        guard !slides.isEmpty else { return }
        let nextIdx = (index + 1) % slides.count
        for i in [index, nextIdx] {
            let s = slides[i]
            if images[s.id] == nil {
                let img = await env.thumbnails.image(
                    mediaId: s.media.id, thumbnailFileName: s.media.thumbnailFileName,
                    localFileName: s.media.localFileName, isPhoto: true, size: .detail)
                if let img { images[s.id] = img }
            }
        }
        // 只保留当前±1 附近，避免整册常驻内存
        let keep = Set([index, nextIdx, (index - 1 + slides.count) % slides.count].map { slides[$0].id })
        images = images.filter { keep.contains($0.key) }
    }
}

// MARK: - 数据 & 组件

private struct FrameSlide: Identifiable {
    let id: UUID
    let media: Media
    let caption: String
    let dateText: String
    let ageText: String
    let isOnThisDay: Bool
}

private struct TickKey: Equatable {
    let index: Int
    let paused: Bool
    let count: Int
}

private struct RebuildKey: Equatable {
    let day: Date
    let count: Int
}

/// 缓慢推拉 + 平移的 Ken Burns 效果，方向由 seed 决定（同一帧稳定，不随父级每秒重绘跳动）。
private struct KenBurnsImage: View {
    let image: UIImage
    let seed: Int
    let animating: Bool
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 由 seed 确定性推导起止锚点：避免机械重复，又不受重绘影响
    private var dx: CGFloat { (seed & 1 == 0 ? 1 : -1) * (10 + CGFloat(abs(seed) % 17)) }
    private var dy: CGFloat { (seed & 2 == 0 ? 1 : -1) * (8 + CGFloat(abs(seed / 17) % 13)) }

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                // reduceMotion 时定格满幅、不推拉（全 App 唯一漏网的动效，参考 GrowthMoviePlayer，P2h）
                .scaleEffect(reduceMotion ? 1 : (animate ? 1.14 : 1.02))
                .offset(x: reduceMotion ? 0 : (animate ? dx : -dx),
                        y: reduceMotion ? 0 : (animate ? dy : -dy))
                .clipped()
                .onAppear {
                    animate = false
                    guard animating, !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 10)) { animate = true }
                }
        }
    }
}
