import SwiftUI

// MARK: - 回忆与作品
/// 按家长的心智分组：先「问」，再看最新的几样，其后是 回顾、写给布布、声音。
/// - 第一屏：一个「布布问答」主卡 + 新鲜出炉（生日影片 / 成长小报 / 语言成长线 / 去过的地方 / 认一认）。
/// - 同名功能合并：问答只剩一个「布布问答」（连上家里服务时问全家相册，否则问本机记录）；
///   两支影片、三种报告各自写清楚是什么，不再让人猜。
/// - 每个分区按行铺满：列数按可用宽度取（窄屏两列，宽屏 / 横拿偶数列），末行自动拉宽，不留空格子；
///   书本半折时改成对齐折痕的网格（末行不拉宽，格子不跨折痕）。
struct AIStudioHomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.bubuLayout) private var layout
    @Environment(AppEnvironment.self) private var env
    /// 分区内容的实际宽度（内容列 + 内边距之后），用来算列数。
    @State private var gridWidth: CGFloat?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                askHeroCard

                section("新鲜出炉", subtitle: "最近加的几样，点开就能看", isNew: true, tiles: [
                    StudioTile(icon: "birthday.cake.fill", title: "生日影片",
                               subtitle: "上个生日到今天，一键成片", tint: BubuTheme.Color.butter) { AnyView(BirthdayFilmView()) },
                    StudioTile(icon: "newspaper.fill", title: "成长小报",
                               subtitle: "每月 1 号出一期", tint: BubuTheme.Color.mint) { AnyView(MonthlyReportView()) },
                    StudioTile(icon: "character.bubble.fill", title: "语言成长线",
                               subtitle: "会说的词一月月变多", tint: BubuTheme.Color.peach) { AnyView(WordsGrowthView()) },
                    StudioTile(icon: "map.fill", title: "去过的地方",
                               subtitle: "照片里的小地图", tint: BubuTheme.Color.sky) { AnyView(PlacesMapView()) },
                    StudioTile(icon: "person.crop.square.badge.camera", title: "认一认",
                               subtitle: "左滑右滑，帮相册把布布认得更准", tint: BubuTheme.Color.lav) { AnyView(RecognitionView()) }
                ])

                section("回顾与报告", subtitle: "把已经发生的整理给你看", tiles: [
                    StudioTile(icon: "text.book.closed.fill", title: "布布周报",
                               subtitle: "这一周的小故事", tint: BubuTheme.Color.peach) { AnyView(WeeklyReportView()) },
                    StudioTile(icon: "chart.line.uptrend.xyaxis", title: "成长报告",
                               subtitle: "档案记了什么、还缺什么", tint: BubuTheme.Color.butter) { AnyView(GrowthReportView()) },
                    StudioTile(icon: "film.stack.fill", title: "年度成长电影",
                               subtitle: "挑一年的照片配乐成片", tint: BubuTheme.Color.sky) { AnyView(GrowthMovieView()) },
                    StudioTile(icon: "book.pages.fill", title: "成长绘本",
                               subtitle: "点滴编成可翻页的故事", tint: BubuTheme.Color.pink) { AnyView(BubuStoryView()) }
                ])

                section("写给布布", subtitle: "留给长大后的她", tiles: [
                    StudioTile(icon: "envelope.fill", title: "时间胶囊",
                               subtitle: "把今天的话寄给未来", tint: BubuTheme.Color.lav) { AnyView(CapsuleHomeView()) },
                    StudioTile(icon: "pencil.and.scribble", title: "第一人称日记",
                               subtitle: "用她的口吻写一天", tint: BubuTheme.Color.mint) { AnyView(FirstPersonDiaryView()) },
                    StudioTile(icon: "person.3.fill", title: "家人合奏",
                               subtitle: "全家写的同一天", tint: BubuTheme.Color.pink) { AnyView(FamilyEnsembleView()) }
                ])
                if !env.config.isAIConfigured {
                    Text("日记与合奏需要在设置里启用家庭 AI 服务，原始记录始终保留。")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.top, -12)
                }

                section("布布的声音", subtitle: "听见她慢慢长大", tiles: [
                    StudioTile(icon: "waveform.path", title: "声音年轮",
                               subtitle: "一圈是一岁", tint: BubuTheme.Color.lav) { AnyView(SoundRingView()) },
                    // 从「设置」搬过来：按岁归档的语音本来就是创作素材，不是配置项。
                    StudioTile(icon: "waveform.badge.mic", title: "成长之声",
                               subtitle: "家人录下的语音，按岁归档", tint: BubuTheme.Color.sky) { AnyView(VoiceArchiveView()) },
                    StudioTile(icon: "quote.bubble.fill", title: "布布的声音",
                               subtitle: "视频里她亲口说的话", tint: BubuTheme.Color.pink) { AnyView(BubuVoicesView()) }
                ])

                Spacer(minLength: 30)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .padding()
            .bubuContentColumn()   // 宽屏收进居中内容列，窄屏原样
        }
        .background(BubuThemedBackground().ignoresSafeArea())
        .navigationTitle("回忆与作品")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 布布问答主卡
    /// 唯一的问答入口。连上家里服务时问全家相册（AskBubuView），离线时问本机记录（BubuQAView），
    /// 名字都叫「布布问答」，家长不必分辨两个几乎同名的框。
    private var askHeroCard: some View {
        NavigationLink {
            if BubuLearningClient(env: env) != nil {
                AskBubuView()
            } else {
                BubuQAView()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(BubuTheme.Font.scaled(22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(BubuTheme.Gradient.primaryButton,
                                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("布布问答")
                            .font(BubuTheme.Font.scaled(19, weight: .heavy))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("她这几年的记录，都可以直接问")
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(BubuTheme.Font.scaled(13, weight: .black))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                // 像一个搜索框：告诉家长「可以这样问」。
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("她第一次去海边是什么时候？")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(BubuTheme.Color.softFill, in: Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [BubuTheme.Color.card, BubuTheme.Color.pinkSurface.opacity(0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
            .contentShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("studio.ask")
    }

    // MARK: 分区
    private func section(_ title: String, subtitle: String, isNew: Bool = false,
                         tiles: [StudioTile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(BubuTheme.Font.scaled(16, weight: .heavy))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    if isNew {
                        Text("新")
                            .font(BubuTheme.Font.scaled(11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(BubuTheme.Color.actionFill, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(.leading, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            tileRows(tiles)
        }
    }

    /// 列数按宽度取（bubuFoldGrid：窄屏 2 列，宽屏 / 横拿 / 半折按最小格宽取偶数列）。
    /// 没有折痕时按行铺满、末行不足时每格拉宽，永远没有孤零零的空格子；
    /// 书本半折时用对齐折痕的网格（正中间距 = 折痕），格子不跨折痕。
    @ViewBuilder
    private func tileRows(_ tiles: [StudioTile]) -> some View {
        let columns = layout.bubuFoldGrid(compactColumns: 2, minItemWidth: 130, spacing: 10, availableWidth: gridWidth)
        if layout.foldAxis == .vertical {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(tiles) { tile in tileView(tile) }
            }
        } else {
            let perRow = max(1, min(columns.count, tiles.count))
            let rows = stride(from: 0, to: tiles.count, by: perRow).map {
                Array(tiles[$0..<min($0 + perRow, tiles.count)])
            }
            VStack(spacing: 10) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        ForEach(rows[index]) { tile in tileView(tile) }
                    }
                }
            }
        }
    }

    private func tileView(_ tile: StudioTile) -> some View {
        NavigationLink {
            tile.destination()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: tile.icon)
                        .font(BubuTheme.Font.scaled(17, weight: .bold))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                        .frame(width: 36, height: 36)
                        .background(tile.tint.opacity(0.72), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.xs, style: .continuous))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(BubuTheme.Font.scaled(11, weight: .black))
                        .foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.72))
                }
                Spacer(minLength: 0)
                Text(tile.title)
                    .font(BubuTheme.Font.scaled(15, weight: .heavy))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(tile.subtitle)
                    .font(BubuTheme.Font.scaled(11.5, weight: .medium))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: BubuAdaptive.value(sizeClass, compact: 118, regular: 140))
            .background(
                LinearGradient(colors: [BubuTheme.Color.card.opacity(0.98), tile.tint.opacity(0.22)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous)
                    .stroke(.white.opacity(0.62), lineWidth: 1)
            }
            .shadow(color: tile.tint.opacity(0.22), radius: 12, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: BubuTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.title)，\(tile.subtitle)")
    }
}

private struct StudioTile: Identifiable {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let destination: () -> AnyView
    var id: String { title }

    init(icon: String, title: String, subtitle: String, tint: Color,
         destination: @escaping () -> AnyView) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.destination = destination
    }
}
