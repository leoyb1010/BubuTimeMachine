import SwiftUI

// MARK: - 布布的魔法屋
/// 自托管 AI 的创作中心。当前为完整可玩的 Mock 工作流；
/// 正式部署接入真实 LLM 后，UI 与交互不变。
struct AIStudioHomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppEnvironment.self) private var env
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ScrollView {
            // 9 个能力平铺在一张网格里时，新用户不知道该先点哪个。
            // 改成「一个主位 + 三个分区」：先给最像入口的「问问布布」一个大卡，
            // 其余按用途分成 回顾 / 创作 / 声音，各自 2-3 个，一眼能选。
            VStack(alignment: .leading, spacing: 18) {
                banner

                askBubuCard        // 主位：问问布布（三年记录变成能对话的记忆）
                storybookCard      // 成长绘本（把里程碑编织成翻页故事）
                capsuleCard        // 时间胶囊收入魔法屋，底栏不再单独占位

                section("回顾", subtitle: "把已经发生的整理给你看") {
                    capabilityTile(icon: "newspaper.fill", title: "布布周报",
                                   subtitle: "这一周的小故事", tint: BubuTheme.Color.peach) {
                        WeeklyReportView()
                    }
                    capabilityTile(icon: "chart.line.uptrend.xyaxis", title: "成长报告",
                                   subtitle: "整理成长变化", tint: BubuTheme.Color.butter) {
                        GrowthReportView()
                    }
                    capabilityTile(icon: "film.stack.fill", title: "成长电影",
                                   subtitle: "精选照片成短片", tint: BubuTheme.Color.sky) {
                        GrowthMovieView()
                    }
                }

                section("创作", subtitle: "把素材改写成新的东西") {
                    capabilityTile(icon: "quote.bubble.fill", title: "第一人称日记",
                                   subtitle: "改写成布布的话", tint: BubuTheme.Color.pink) {
                        FirstPersonDiaryView()
                    }
                    capabilityTile(icon: "person.3.sequence.fill", title: "家人合奏",
                                   subtitle: "合成完整故事", tint: BubuTheme.Color.mint) {
                        FamilyEnsembleView()
                    }
                }

                section("声音", subtitle: "听见布布慢慢长大") {
                    capabilityTile(icon: "waveform.path", title: "声音年轮",
                                   subtitle: "一圈是一岁", tint: BubuTheme.Color.lav) {
                        SoundRingView()
                    }
                    // 从「设置」搬过来：按岁归档的语音本来就是创作素材，不是配置项。
                    capabilityTile(icon: "waveform.badge.mic", title: "成长之声",
                                   subtitle: "按岁归档的语音", tint: BubuTheme.Color.info) {
                        VoiceArchiveView()
                    }
                }

                Spacer(minLength: 30)
            }
            .padding()
            .bubuContentColumn()   // 宽屏收进居中内容列，窄屏原样
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("布布的魔法屋")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                BubuMascotBadge(size: 58, expression: .drawing)
                VStack(alignment: .leading, spacing: 4) {
                    Text("布布的魔法屋").font(BubuTheme.Font.title)
                    Text("故事、电影、报告和未来胶囊")
                        .font(BubuTheme.Font.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [theme, theme.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    // 成长绘本主卡（butter→peach→pink，对照设计稿；点进翻页绘本）
    private var storybookCard: some View {
        NavigationLink {
            BubuStoryView()
        } label: {
            HStack(spacing: 14) {
                BubuDreamPhoto(hue: 18, height: 72, cornerRadius: 16, motif: "✦")
                    .frame(width: 60)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white, lineWidth: 3))
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("成长绘本")
                        .font(BubuTheme.Font.scaled(19, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    Text("由你记录的点滴，自动编织成可翻页的故事")
                        .font(BubuTheme.Font.scaled(12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(BubuTheme.Font.scaled(14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [BubuTheme.Color.butter, BubuTheme.Color.peach, BubuTheme.Color.pink],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                BubuSparkle(size: 13, color: .white.opacity(0.95)).padding(14)
            }
            .bubuCardShadow()
        }
        .buttonStyle(.plain)
    }

    private var capsuleCard: some View {
        NavigationLink {
            CapsuleHomeView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [BubuTheme.Color.lav, BubuTheme.Color.sky],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                    Image(systemName: "envelope.fill")
                        .font(BubuTheme.Font.scaled(26, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 2))
                .shadow(color: BubuTheme.Color.lav.opacity(0.35), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text("未来胶囊")
                        .font(BubuTheme.Font.scaled(17, weight: .heavy))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("把今天的话，寄给未来的布布")
                        .font(BubuTheme.Font.scaled(12.5, weight: .semibold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(BubuTheme.Font.scaled(13, weight: .black))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.60), lineWidth: 1)
            }
            .shadow(color: BubuTheme.Color.lav.opacity(0.22), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    /// 主位大卡：魔法屋里最像「入口」的能力，不该和另外 8 个挤在同一张网格里。
    private var askBubuCard: some View {
        NavigationLink { BubuQAView() } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [BubuTheme.Color.primary, BubuTheme.Color.deepRose],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(BubuTheme.Font.scaled(24, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.7), lineWidth: 2))
                .shadow(color: BubuTheme.Color.deepRose.opacity(0.30), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text("问问布布")
                        .font(BubuTheme.Font.scaled(18, weight: .heavy))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("她这几年的记录，都可以直接问")
                        .font(BubuTheme.Font.scaled(12.5, weight: .semibold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(BubuTheme.Font.scaled(13, weight: .black))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.60), lineWidth: 1)
            }
            .shadow(color: BubuTheme.Color.primary.opacity(0.20), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    /// 分区：小标题 + 一句话说明 + 一张网格。
    @ViewBuilder
    private func section<Content: View>(_ title: String, subtitle: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BubuTheme.Font.scaled(15, weight: .heavy, design: .rounded))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(subtitle)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(.leading, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: BubuAdaptive.columns(sizeClass, compact: 2, regular: 4)),
                      spacing: 10) {
                content()
            }
        }
    }

    private func capabilityTile<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(BubuTheme.Font.scaled(17, weight: .bold))
                        .foregroundStyle(BubuTheme.Color.deepRose)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(BubuTheme.Font.scaled(11, weight: .black))
                        .foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.72))
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(BubuTheme.Font.scaled(15, weight: .heavy))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(subtitle)
                    .font(BubuTheme.Font.scaled(11.5, weight: .medium))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: BubuAdaptive.value(sizeClass, compact: 112, regular: 140))
            .background(
                LinearGradient(colors: [BubuTheme.Color.card.opacity(0.98), tint.opacity(0.22)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.62), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.22), radius: 12, y: 7)
        }
        .buttonStyle(.plain)
    }

}
