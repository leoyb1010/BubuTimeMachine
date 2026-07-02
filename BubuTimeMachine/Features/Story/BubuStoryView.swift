import SwiftUI
import SwiftData

// MARK: - 布布的成长绘本（首页）
/// 对照设计稿 MacStory：butter→peach→pink 大横幅 +「共 N 章」+ 倾斜书卡列表。
/// 章节由已达成里程碑实时编织（StoryChapterBuilder），点进翻页阅读器。
struct BubuStoryView: View {
    // 绘本来源 = 你的记录。收进绘本的记录按发生时间排序。
    @Query(filter: #Predicate<Entry> { $0.inStorybook && !$0.isArchived },
           sort: \Entry.happenedAt, order: .forward)
    private var pickedEntries: [Entry]
    @Query private var profiles: [ChildProfile]
    @Environment(AppEnvironment.self) private var env

    private var birthday: Date? { profiles.first?.birthday }
    private var chapters: [StoryChapter] { StoryChapterBuilder.chapters(from: pickedEntries, birthday: birthday) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                banner
                if chapters.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 14) {
                        ForEach(Array(zip(chapters.indices, chapters)), id: \.1.id) { idx, ch in
                            NavigationLink {
                                BubuStoryReaderView(chapters: chapters, startIndex: idx)
                            } label: {
                                // 按 entryId 精确配对（不靠下标：并列时间的记录排序顺序可能与章节顺序不一致）
                                chapterCard(ch, entry: pickedEntries.first { $0.id == ch.entryId }, index: idx)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle("布布的故事")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 大横幅
    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("一本正在生长的书")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
            Text("布布的成长绘本")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            Text("由你记录的点滴，自动编织成故事 · 共 \(chapters.count) 章")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: [BubuTheme.Color.butter, BubuTheme.Color.peach, BubuTheme.Color.pink],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            BubuSparkle(size: 14, color: .white.opacity(0.95)).padding(18)
        }
        .overlay(alignment: .trailing) {
            BubuSparkle(size: 10, color: .white.opacity(0.8), delay: 0.7).padding(.trailing, 34)
        }
        .bubuCardShadow()
    }

    // 倾斜书卡：优先真实照片，无照片走渐变兜底
    private func chapterCard(_ ch: StoryChapter, entry: Entry?, index: Int) -> some View {
        HStack(spacing: 14) {
            chapterCover(ch, entry: entry)
                .frame(width: 64, height: 80)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white, lineWidth: 3))
                .rotationEffect(.degrees(index % 2 == 0 ? -3 : 3))
                .shadow(color: .black.opacity(0.16), radius: 7, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(ch.noText)\(ch.ageText.isEmpty ? "" : " · \(ch.ageText)")")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.deepRose)
                Text(ch.title)
                    .font(.system(size: 16.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(1)
                Text(ch.lines.first ?? "")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(BubuTheme.Color.peach)
        }
        .padding(14)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .bubuCardShadow()
    }

    /// 章节封面：记录里有照片就用真实照片，否则渐变兜底。
    @ViewBuilder
    private func chapterCover(_ ch: StoryChapter, entry: Entry?) -> some View {
        if let photo = entry?.media.first(where: { $0.type == .photo }) {
            MediaThumbnail(media: photo, mediaStore: env.mediaStore, cornerRadius: 12, size: .card)
        } else {
            BubuDreamPhoto(hue: ch.hue, height: 80, cornerRadius: 12, motif: ch.emoji)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("✦").font(.system(size: 44)).foregroundStyle(BubuTheme.Color.peach)
            Text("绘本还是空白的")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("在「时光」里选中喜欢的记录，\n点「收进绘本」，这里就会长出一章一章的故事")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}
