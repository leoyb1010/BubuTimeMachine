import SwiftUI

// MARK: - 成长绘本 · 翻页阅读器
/// 对照设计稿 MacStoryReader：全屏 hue 渐变 + 150pt 图 + 章号/标题 + 正文逐行浮现 +
/// 进度点 + 上/下一章。翻页用 3D rotateY；reduceMotion 时退化为淡入淡出。
///
/// iPhone Duo：
/// - 竖排栏（外屏 / 内屏横拿）或矮屏：页面仍沉浸，但返回和上/下一章交给系统导航栏（进侧边竖排栏）；
/// - 书本半折 / 矮屏：做成左右两页（左图右文，像真书）；桌面半折：上图下文。用 BubuArrangement 避开折痕。
struct BubuStoryReaderView: View {
    let chapters: [StoryChapter]
    @State private var index: Int
    @State private var flipping = false
    @State private var pageOpacity: Double = 1
    @State private var pageAngle: Double = 0
    @State private var contentSeed = 0   // 改变即触发正文逐行重新浮现

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bubuLayout) private var layout

    init(chapters: [StoryChapter], startIndex: Int) {
        self.chapters = chapters
        _index = State(initialValue: max(0, min(startIndex, chapters.count - 1)))
    }

    private var chapter: StoryChapter { chapters[index] }

    /// 系统导航栏放返回 / 翻页：栏是竖排的（Duo 外屏、内屏横拿）或屏幕矮。其余保持原来的自绘上下栏。
    private var systemBars: Bool { layout.barEdge != nil || layout.isShort }
    /// 两页排版：有折痕，或矮屏（横拿一页放不下图 + 正文）。
    private var spread: Bool { layout.fold != nil || layout.isShort }
    /// 桌面姿态（水平折痕）上下两页，其余左右两页。
    private var spreadIsVertical: Bool { layout.foldAxis == .horizontal }

    var body: some View {
        ZStack {
            // 整页底走 hueSurface：
            // ① 深色模式下不再是一整片发亮的粉彩；
            // ② 浅色下也比原来的 0.92 略深，正文那层白字终于有对比度（原来白字压在近白粉彩上）。
            LinearGradient(
                colors: [BubuTheme.Color.hueSurface(chapter.hue),
                         BubuTheme.Color.hueSurface((chapter.hue + 30).truncatingRemainder(dividingBy: 360))],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: index)

            if spread {
                BubuArrangement(axes: spreadIsVertical ? .vertical : .horizontal, style: .split) {
                    picturePage
                } secondary: {
                    textPage
                }
            } else {
                VStack(spacing: 0) {
                    topBar
                    page
                        .opacity(pageOpacity)
                        .rotation3DEffect(.degrees(pageAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    if !systemBars { bottomBar }
                }
            }
        }
        .navigationBarBackButtonHidden(!systemBars)
        .toolbar(systemBars ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if systemBars {
                chapterToolbar.bubuVisibilityPriority(.high)
            }
        }
    }

    // 系统栏里的上/下一章（竖排栏只显示图标，标题给读屏和溢出菜单）。
    @ToolbarContentBuilder
    private var chapterToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { turn(-1) } label: { Label("上一章", systemImage: "arrow.backward") }
                .disabled(index == 0 || flipping)
            Button { turn(1) } label: { Label("下一章", systemImage: "arrow.forward") }
                .disabled(index >= chapters.count - 1 || flipping)
        }
    }

    // 顶部：返回 + 进度点（系统栏模式下返回交给导航栏，只留进度）
    private var topBar: some View {
        HStack {
            if !systemBars { backButton }
            Spacer()
            progress
            Spacer()
            if !systemBars { Color.clear.frame(width: 40, height: 40) }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(BubuTheme.Font.scaled(16, weight: .bold))
                // 固定白底配固定墨色：动态 warmBrown 在深色下会翻成米白，白底白字。
                .foregroundStyle(BubuTheme.Color.paperInk)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.7), in: Circle())
        }
        .accessibilityLabel("返回")
    }

    // 章节多时进度点会挤爆顶栏，超过 12 章改用"当前/总数"文本（P2l）
    @ViewBuilder
    private var progress: some View {
        if chapters.count > 12 {
            Text("\(index + 1) / \(chapters.count)")
                .font(BubuTheme.Font.scaled(14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.25), in: Capsule())
        } else {
            HStack(spacing: 5) {
                ForEach(chapters.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.white : Color.white.opacity(0.55))
                        .frame(width: i == index ? 18 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.3), value: index)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(index + 1) 章，共 \(chapters.count) 章")
        }
    }

    // 正文页（单页）
    private var page: some View {
        VStack(spacing: 0) {
            cover(side: 150)
                .padding(.top, 14)
                .padding(.bottom, 22)
            heading
            lines
                .padding(.top, 20)
                .padding(.horizontal, 26)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 两页排版

    /// 两页时图更大：书本 / 矮屏左页 180–220pt；桌面姿态上半页高度有限，保持 150。
    private var spreadCoverSide: CGFloat {
        spreadIsVertical ? 150 : layout.bubuHeight(220, short: 180)
    }

    /// 左页（桌面姿态为上页）：返回 + 图 + 章号标题 + 上一章。
    private var picturePage: some View {
        VStack(spacing: 0) {
            if !systemBars {
                HStack { backButton; Spacer() }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                cover(side: spreadCoverSide)
                    .padding(.bottom, 18)
                heading
                    .padding(.horizontal, 18)
            }
            .opacity(pageOpacity)
            .rotation3DEffect(.degrees(pageAngle), axis: (x: 0, y: 1, z: 0),
                              anchor: spreadIsVertical ? .center : .trailing, perspective: 0.6)
            Spacer(minLength: 0)
            if !systemBars {
                HStack {
                    navButton(title: "‹ 上一章", enabled: index > 0) { turn(-1) }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 右页（桌面姿态为下页）：进度 + 正文 + 下一章。
    private var textPage: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, systemBars ? 12 : 18)
            Spacer(minLength: 0)
            lines
                .padding(.horizontal, 26)
                .opacity(pageOpacity)
                .rotation3DEffect(.degrees(pageAngle), axis: (x: 0, y: 1, z: 0),
                                  anchor: spreadIsVertical ? .center : .leading, perspective: 0.6)
            Spacer(minLength: 0)
            if !systemBars {
                HStack {
                    Spacer()
                    navButton(title: "下一章 ›", enabled: index < chapters.count - 1) { turn(1) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 页面零件

    private func cover(side: CGFloat) -> some View {
        StoryCover(chapter: chapter, side: side)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 6))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private var heading: some View {
        VStack(spacing: 0) {
            Text("\(chapter.noText)\(chapter.ageText.isEmpty ? "" : " · \(chapter.ageText)")")
                .font(BubuTheme.Font.scaled(13, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
            Text(chapter.title)
                .font(BubuTheme.Font.scaled(24, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var lines: some View {
        VStack(spacing: 12) {
            ForEach(Array(chapter.lines.enumerated()), id: \.offset) { i, line in
                StoryLine(text: line, delay: Double(i) * 0.12, seed: contentSeed, reduceMotion: reduceMotion)
            }
        }
    }

    // 底部：上/下一章
    private var bottomBar: some View {
        HStack {
            navButton(title: "‹ 上一章", enabled: index > 0) { turn(-1) }
            Spacer()
            navButton(title: "下一章 ›", enabled: index < chapters.count - 1) { turn(1) }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
        .padding(.top, 8)
    }

    private func navButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BubuTheme.Font.scaled(13.5, weight: .bold))
                .foregroundStyle(BubuTheme.Color.paperInk)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(.white.opacity(enabled ? 0.85 : 0.35), in: Capsule())
        }
        .disabled(!enabled)
    }

    // 翻页：rotateY 退出 → 切章 → rotateY 进入；reduceMotion 时纯淡入淡出。
    private func turn(_ dir: Int) {
        let ni = index + dir
        guard ni >= 0, ni < chapters.count, !flipping else { return }
        BubuHaptics.tapLight()
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.25)) { pageOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                index = ni; contentSeed += 1
                withAnimation(.easeInOut(duration: 0.3)) { pageOpacity = 1 }
            }
            return
        }
        flipping = true
        withAnimation(.easeIn(duration: 0.24)) {
            pageOpacity = 0
            pageAngle = dir > 0 ? -22 : 22
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            index = ni
            contentSeed += 1
            pageAngle = dir > 0 ? 22 : -22
            withAnimation(.easeOut(duration: 0.3)) {
                pageOpacity = 1
                pageAngle = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flipping = false }
        }
    }
}

// 章节封面：有真实照片就显示照片，否则渐变兜底。
private struct StoryCover: View {
    let chapter: StoryChapter
    var side: CGFloat = 150
    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                BubuDreamPhoto(hue: chapter.hue, height: side, cornerRadius: BubuTheme.Radius.card, motif: chapter.emoji)
            }
        }
        .task(id: chapter.id) { await load() }
    }

    private func load() async {
        guard let fileName = chapter.photoFileName else { image = nil; return }
        image = await env.thumbnails.image(
            mediaId: chapter.entryId,
            thumbnailFileName: fileName,
            localFileName: fileName,
            isPhoto: true,
            size: .detail
        )
    }
}

// 单行正文：随 seed 变化重新逐行浮现（macFadeUp）。
private struct StoryLine: View {
    let text: String
    let delay: Double
    let seed: Int
    let reduceMotion: Bool

    @State private var shown = false

    var body: some View {
        Text(text)
            .font(BubuTheme.Font.scaled(16.5, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .opacity(reduceMotion ? 1 : (shown ? 1 : 0))
            .offset(y: reduceMotion ? 0 : (shown ? 0 : 12))
            .onAppear { appear() }
            .onChange(of: seed) { _, _ in shown = false; appear() }
    }

    private func appear() {
        guard !reduceMotion else { shown = true; return }
        withAnimation(.easeOut(duration: 0.5).delay(delay)) { shown = true }
    }
}
