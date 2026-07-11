import SwiftUI
import SwiftData

// MARK: - 设置（Wave L §5.1 重构）
/// 信息架构按使用频率重排：个人化在前、资料中间、机房（服务器/AI Key）收进「高级 · 自托管」二级页。
/// 自绘卡片组取代系统 Form 平铺；同步状态压成一颗徽章。
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var members: [FamilyMember]
    @State private var soundOn = BubuSound.isEnabled
    @State private var showFrame = false

    private var currentMember: FamilyMember? {
        members.first { $0.id == env.currentMemberId } ?? members.first
    }

    var body: some View {
        @Bindable var config = env.config
        ScrollView {
            VStack(spacing: 18) {
                identityCard
                group("布布") {
                    row("布布的档案", icon: "figure.child", tint: env.theme.theme.primary) { ChildProfileView() }
                    row("成长之声", icon: "waveform.badge.mic", tint: BubuTheme.Color.info) { VoiceArchiveView() }
                    row("健康记录", icon: "heart.text.square", tint: BubuTheme.Color.success) { HealthHomeView() }
                }
                group("这个家") {
                    row("家人登录", icon: "person.crop.circle.badge.checkmark",
                        tint: env.theme.theme.primary) { AccountView() }
                    row("家庭成员", icon: "person.2.fill", tint: env.theme.theme.secondary) { MembersView() }
                }
                group("外观") {
                    row("主题与外观", icon: "paintpalette.fill", tint: env.theme.theme.primary) { ThemeSettingsView() }
                    Toggle(isOn: Binding(get: { soundOn }, set: { soundOn = $0; BubuSound.isEnabled = $0 })) {
                        settingRowLabel("声音反馈", icon: "speaker.wave.2.fill",
                                        tint: BubuTheme.Color.info, subtitle: "保存、封存、开启时的轻声音效")
                    }
                    .onChange(of: soundOn) { _, on in if on { BubuSound.play(.save) } }
                    .tint(env.theme.theme.primary)

                    Toggle(isOn: $config.simpleModeEnabled) {
                        settingRowLabel(config.currentRole.simpleModeName, icon: "hand.tap.fill",
                                        tint: BubuTheme.Color.success,
                                        subtitle: "大字大按钮，只保留 拍照 / 录音 / 看布布。切到长辈身份会自动开启")
                    }
                    .tint(env.theme.theme.primary)
                    .popoverTip(SimpleModeTip())

                    Button { showFrame = true } label: {
                        settingRowLabel("相框模式", icon: "photo.stack.fill",
                                        tint: BubuTheme.Color.pink,
                                        subtitle: "把 iPad / 旧手机变成布布的数字相框，全屏轮播精选照片")
                    }
                    .buttonStyle(.plain)
                }
                reminderCard(config: config)
                dataCard
                group("高级 · 自托管") {
                    NavigationLink { AdvancedSettingsView() } label: {
                        settingRowLabel("服务器与 AI 配置", icon: "lock.shield.fill",
                                        tint: BubuTheme.Color.secondaryText,
                                        subtitle: "给装服务器的那个人")
                    }
                    .buttonStyle(.plain)
                }
                group("Apple Watch") {
                    row("布布上表盘", icon: "applewatch.watchface", tint: env.theme.theme.primary) { WatchFaceGuideView() }
                }
                if BubuStoreHealth.loadFailed {
                    Label("数据保护模式：本次升级打开数据库失败，你的全部数据仍安全保存在手机里，当前修改不会保存。请把 App 升级到最新版或联系管理员修复。",
                          systemImage: "exclamationmark.shield.fill")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.danger)
                        .padding(12)
                        .background(BubuTheme.Color.danger.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                group("关于") {
                    row("更新记录", icon: "sparkles", tint: env.theme.theme.primary) { WhatsNewListView() }
                }
                footer
            }
            .padding()
        }
        .navigationTitle("设置")
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showFrame) { PhotoFrameView() }
    }

    // MARK: 顶卡 · 当前身份

    private var identityCard: some View {
        NavigationLink { MembersView() } label: {
            HStack(spacing: 14) {
                Text(currentMember?.avatarEmoji ?? "🙂")
                    .font(.system(size: 36))
                    .frame(width: 60, height: 60)
                    .background(Color(hex: currentMember?.themeColorHex ?? "#F28C9E").opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(currentMember?.name ?? "未设置").font(BubuTheme.Font.title)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text("点我换人").font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer()
                syncBadge
            }
            .padding(16)
            .background(
                LinearGradient(colors: [BubuTheme.Color.peach.opacity(0.40),
                                        BubuTheme.Color.pink.opacity(0.32),
                                        BubuTheme.Color.lav.opacity(0.32)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                BubuSparkle(size: 12, color: .white.opacity(0.9)).padding(14)
            }
            .bubuCardShadow()
        }
        .buttonStyle(.plain)
    }

    /// 同步状态徽章：状态正常时不抢注意力，点开进诊断页。
    private var syncBadge: some View {
        NavigationLink { AdvancedSettingsView() } label: {
            HStack(spacing: 5) {
                Circle().fill(syncColor).frame(width: 9, height: 9)
                Text(syncText).font(BubuTheme.Font.caption.weight(.medium))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(env.themedSoftFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var syncColor: Color {
        switch env.syncEngine.connectionState {
        case .online: return BubuTheme.Color.success
        case .connecting: return BubuTheme.Color.warning
        case .offline: return BubuTheme.Color.secondaryText
        }
    }
    private var syncText: String {
        switch env.syncEngine.connectionState {
        case .online: return env.syncEngine.pendingCount == 0 ? "已同步" : "同步中"
        case .connecting: return "连接中"
        case .offline: return "离线"
        }
    }

    // MARK: 提醒卡

    private func reminderCard(config: ServerConfig) -> some View {
        group("提醒") {
            Toggle(isOn: Binding(get: { config.dailyReminderEnabled },
                                 set: { config.dailyReminderEnabled = $0 })) {
                settingRowLabel("那年今日 · 每日回忆", icon: "bell.badge.fill",
                                tint: BubuTheme.Color.warning, subtitle: "每天提醒：往年的今天")
            }
            .onChange(of: config.dailyReminderEnabled) { _, on in
                Task { await ReminderScheduler.shared.update(enabled: on, context: context) }
            }
            .tint(env.theme.theme.primary)
        }
    }

    // MARK: 数据卡

    private var dataCard: some View {
        group("数据") {
            BackupHealthCard()
            row("做一本 PDF 年册", icon: "book.closed.fill",
                tint: env.theme.theme.primary) { YearbookView() }
            row("导出布布的全量档案", icon: "square.and.arrow.up.on.square.fill",
                tint: env.theme.theme.secondary) { ExportView() }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("布布时光机").font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Text("为布布而做，2025 ❤️").font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Text(AppVersion.displayFull).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    // MARK: 卡组与行构件

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(BubuTheme.Font.caption.weight(.semibold))
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .padding(.vertical, 4)
                .background(env.themedCard, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                .bubuCardShadow()
        }
    }

    private func row<Destination: View>(_ title: String, icon: String, tint: Color,
                                        @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            settingRowLabel(title, icon: icon, tint: tint, subtitle: nil)
        }
        .buttonStyle(.plain)
    }

    private func settingRowLabel(_ title: String, icon: String, tint: Color, subtitle: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(BubuTheme.Font.body)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                if let subtitle {
                    Text(subtitle).font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BubuTheme.Color.secondaryText.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
