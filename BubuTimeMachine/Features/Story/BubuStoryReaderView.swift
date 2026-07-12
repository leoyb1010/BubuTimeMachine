import SwiftUI

// MARK: - 成长绘本 · 翻页阅读器
/// 对照设计稿 MacStoryReader：全屏 hue 渐变 + 150pt 图 + 章号/标题 + 正文逐行浮现 +
/// 进度点 + 上/下一章。翻页用 3D rotateY；reduceMotion 时退化为淡入淡出。
struct BubuStoryReaderView: View {
    let chapters: [StoryChapter]
    @State private var index: Int
    @State private var flipping = false
    @State private var pageOpacity: Double = 1
    @State private var pageAngle: Double = 0
    @State private var contentSeed = 0   // 改变即触发正文逐行重新浮现

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(chapters: [StoryChapter], startIndex: Int) {
        self.chapters = chapters
        _index = State(initialValue: max(0, min(startIndex, chapters.count - 1)))
    }

    private var chapter: StoryChapter { chapters[index] }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BubuTheme.Color.hue(chapter.hue, lightness: 0.92),
                         BubuTheme.Color.hue((chapter.hue + 30).truncatingRemainder(dividingBy: 360), lightness: 0.88)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: index)

            VStack(spacing: 0) {
                topBar
                page
                    .opacity(pageOpacity)
                    .rotation3DEffect(.degrees(pageAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                bottomBar
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // 顶部：返回 + 进度点
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(BubuTheme.Font.scaled(16, weight: .bold))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.7), in: Circle())
            }
            Spacer()
            // 章节多时进度点会挤爆顶栏，超过 12 章改用"当前/总数"文本（P2l）
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
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // 正文页
    private var page: some View {
        VStack(spacing: 0) {
            StoryCover(chapter: chapter)
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 6))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .padding(.top, 14)
                .padding(.bottom, 22)

            Text("\(chapter.noText)\(chapter.ageText.isEmpty ? "" : " · \(chapter.ageText)")")
                .font(BubuTheme.Font.scaled(13, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
            Text(chapter.title)
                .font(BubuTheme.Font.scaled(24, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            VStack(spacing: 12) {
                ForEach(Array(chapter.lines.enumerated()), id: \.offset) { i, line in
                    StoryLine(text: line, delay: Double(i) * 0.12, seed: contentSeed, reduceMotion: reduceMotion)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 26)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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
                .foregroundStyle(BubuTheme.Color.warmBrown)
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
    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                BubuDreamPhoto(hue: chapter.hue, height: 150, cornerRadius: 30, motif: chapter.emoji)
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
