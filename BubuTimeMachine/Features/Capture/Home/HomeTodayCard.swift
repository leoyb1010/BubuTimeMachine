import SwiftUI

// MARK: - 首页「今天」主卡
/// 首屏最显眼的位置留给布布今天的样子：今日精选大图（第二大脑），
/// 没连家庭服务时用最近一条带照片的家人记录；底部是一句话记录入口。
struct HomeTodayCard: View {
    let picks: [HomeTodayPick]
    let client: BubuLearningClient?
    let fallbackEntry: Entry?
    let isLoading: Bool
    let photoHeight: CGFloat
    let onRecord: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            photo
            recordLine
        }
        .background(BubuTheme.Color.elevatedCard,
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                .stroke(BubuTheme.Color.hairline.opacity(0.5), lineWidth: 0.7)
        }
        .bubuCardShadow()
    }

    // MARK: 大图

    @ViewBuilder
    private var photo: some View {
        if let pick = picks.first, let client {
            NavigationLink {
                OnlineItemsGridView(client: client, ids: picks.map(\.id), title: "今日精选") {
                    Label("今日精选", systemImage: "sparkles")
                        .font(BubuTheme.Font.headline)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                }
            } label: {
                photoFrame(chip: pick.chip, symbol: "sparkles", caption: pick.displayCaption,
                           extra: picks.count > 1 ? "\(picks.count) 张" : nil) {
                    HomePickImage(pick: pick, client: client)
                }
            }
            .buttonStyle(BubuPressableStyle())
            .accessibilityIdentifier("home.today-pick")
        } else if isLoading, client != nil {
            BubuSkeletonBlock(cornerRadius: 0, height: photoHeight)
                .accessibilityLabel("正在取今天的照片")
        } else if let entry = fallbackEntry, let media = entry.coverMedia {
            NavigationLink(value: entry.id) {
                photoFrame(chip: BubuDateFormat.monthDay(entry.happenedAt), symbol: "heart.text.square",
                           caption: entry.note?.isEmpty == false ? entry.note : nil, extra: nil) {
                    MediaThumbnail(media: media, mediaStore: env.mediaStore, cornerRadius: 0, size: .detail)
                }
            }
            .buttonStyle(BubuPressableStyle())
            .accessibilityIdentifier("home.today-pick")
        }
    }

    private func photoFrame<Content: View>(chip: String, symbol: String, caption: String?, extra: String?,
                                           @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay { content() }
                .clipped()
            // 固定深色墨：warmBrown 深色下会变米白，压不住白字。
            LinearGradient(colors: [.clear, BubuTheme.Color.paperInk.opacity(0.70)],
                           startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: BubuTheme.Spacing.s) {
                VStack(alignment: .leading, spacing: 6) {
                    HomePhotoChip(text: chip, symbol: symbol)
                    if let caption {
                        Text(caption)
                            .font(BubuTheme.Font.scaled(15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    }
                }
                Spacer(minLength: 0)
                if let extra {
                    HStack(spacing: 4) {
                        Text(extra)
                        Image(systemName: "chevron.right")
                    }
                    .font(BubuTheme.Font.scaled(13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.28), in: Capsule())
                }
            }
            .padding(BubuTheme.Spacing.item)
        }
        .frame(height: photoHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开今天的照片")
    }

    // MARK: 一句话记录

    private var recordLine: some View {
        Button(action: onRecord) {
            HStack(spacing: BubuTheme.Spacing.m) {
                BubuMascotBadge(size: 34, expression: .happy)
                Text("写一句今天的布布…")
                    .font(BubuTheme.Font.scaled(15, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "square.and.pencil")
                    .font(BubuTheme.Font.scaled(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(BubuTheme.Gradient.primaryButton, in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(BubuPressableStyle())
        .accessibilityLabel(BubuTheme.Copy.recordNow)
        .accessibilityHint("写一句话，也可以加照片和声音")
        .accessibilityIdentifier("home.record")
    }
}

/// 照片上的小标签：固定白底 + 固定深墨字，深浅色模式下对比度都 > 7:1。
struct HomePhotoChip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(BubuTheme.Font.scaled(13, weight: .bold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(BubuTheme.Color.paperInk)
            .background(.white.opacity(0.94), in: Capsule())
    }
}

/// 先显示 App Group 里的小图（秒开、离线可用），再换成服务端大图；失败就停在小图。
struct HomePickImage: View {
    let pick: HomeTodayPick
    let client: BubuLearningClient?
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .transition(.opacity)
            } else {
                BubuTheme.Color.pinkSurface
            }
        }
        .accessibilityLabel(pick.displayCaption ?? "今天的照片")
        .task(id: pick.id) {
            if let file = pick.localFileURL, image == nil {
                image = await HomeImageDecoder.decode(file: file, maxPixel: 600)
            }
            guard let client, let path = pick.remotePath,
                  let data = try? await client.mediaData(path, cache: true),
                  !Task.isCancelled,
                  let large = await HomeImageDecoder.decode(data: data, maxPixel: 1400 * displayScale / 3)
            else { return }
            image = large
        }
    }
}

/// 首页统一的分区标题：标题 + 可选尾部动作（统一用 chevron 图标，不用「›」字符）。
struct HomeSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(BubuTheme.Font.headline)
                .foregroundStyle(BubuTheme.Color.warmBrown)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

struct HomeSectionActionLabel: View {
    var title = "全部"

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            Image(systemName: "chevron.right").font(BubuTheme.Font.scaled(12, weight: .bold))
        }
        .font(BubuTheme.Font.scaled(14, weight: .semibold, design: .rounded))
        .foregroundStyle(BubuTheme.Color.primaryInk)
        .contentShape(Rectangle())
    }
}
