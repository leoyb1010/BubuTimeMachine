import SwiftUI
import SwiftData

// MARK: - 时间胶囊 · 列表
/// 写给未来布布的信，到期前加密锁定、只显示倒计时。到期后可庄重开启。
struct CapsuleHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TimeCapsule.unlockAt) private var capsules: [TimeCapsule]

    @State private var showCompose = false
    @State private var editing: TimeCapsule?
    @State private var unlocking: TimeCapsule?
    @State private var glowPulse = false
    @State private var showRecovery = false
    @State private var currentDate = Date.now

    private var theme: Color { env.theme.theme.primary }
    private var locked: [TimeCapsule] { capsules.filter { !canOpen($0, at: currentDate) } }
    private var openable: [TimeCapsule] { capsules.filter { canOpen($0, at: currentDate) } }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            if capsules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                        intro
                        if !openable.isEmpty { openableSection }
                        if !locked.isEmpty { lockedSection }
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("时间胶囊")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showRecovery = true } label: { Image(systemName: "key.horizontal.fill") }
                    .accessibilityLabel("恢复码")
                    .bubuGlassButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCompose = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("写时间胶囊")
                    .bubuGlassButton()
            }
        }
        .sheet(isPresented: $showCompose) { CapsuleComposeView() }
        .sheet(isPresented: $showRecovery) { CapsuleRecoveryView() }
        .sheet(item: $editing) { capsule in CapsuleComposeView(editing: capsule) }
        .fullScreenCover(item: $unlocking) { capsule in
            CapsuleUnlockView(capsule: capsule)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            currentDate = date
        }
    }

    @ViewBuilder
    private var background: some View {
        BubuThemedBackground()
    }

    private var intro: some View {
        Text("把此刻的心里话，封存给某个未来的日子。到那天之前，谁也打不开。")
            .font(BubuTheme.Font.body)
            .foregroundStyle(BubuTheme.Color.secondaryText)
    }

    private var openableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("可以开启了", systemImage: "envelope.open.fill")
                .font(BubuTheme.Font.headline).foregroundStyle(theme)
            ForEach(openable) { capsule in
                capsuleRow(capsule, open: true)
            }
        }
    }

    /// 倒计时随 currentDate（唯一的 30s 计时器）刷新；最后 24 小时进入「即将开启」呼吸发光。
    /// 合并原来的双计时：不再额外套一层 TimelineView(.periodic)（P2m）。
    private var lockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("静静等待", systemImage: "lock.fill")
                .font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            ForEach(locked) { capsule in
                capsuleRow(capsule, open: false, now: currentDate)
            }
        }
        .onAppear {
            guard !reduceMotion, !glowPulse else { return }
            withAnimation(BubuMotion.breathe) { glowPulse = true }
        }
    }

    private func capsuleCard(_ capsule: TimeCapsule, open: Bool, now: Date = .now) -> some View {
        let imminent = !open && capsule.unlockAt.timeIntervalSince(now) < 86_400
        return HStack(spacing: 16) {
            Text(capsule.coverEmoji ?? "💌")
                // 固定字号：emoji 徽标锁在 60pt 圆内，随 Dynamic Type 放大会明显溢出圆形
                .font(.system(size: 40))
                .frame(width: 60, height: 60)
                .background((open ? theme : BubuTheme.Color.secondaryText).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(capsule.title)
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                    .lineLimit(1)
                Text("来自\(capsule.fromRole)")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                if open {
                    Label("轻触庄重开启", systemImage: "hand.tap")
                        .font(BubuTheme.Font.scaled(12, weight: .semibold))
                        .foregroundStyle(theme)
                } else {
                    Text(countdownText(capsule.unlockAt, now: now))
                        .font(BubuTheme.Font.scaled(13, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(theme)
                }
            }
            Spacer()
            Image(systemName: open ? "chevron.right" : (imminent ? "lock.open" : "lock.fill"))
                .foregroundStyle(imminent ? theme : BubuTheme.Color.secondaryText)
        }
        .padding()
        .background(BubuTheme.Color.card.opacity(open ? 0.72 : 0.62), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuGlassSurface(cornerRadius: BubuTheme.Radius.card, tint: open ? theme : BubuTheme.Color.secondaryText, interactive: open)
        // 静态阴影只做层次，不再随呼吸变半径（避免每帧重栅格化 shadow，P2m）
        .shadow(color: imminent ? theme.opacity(0.20) : .black.opacity(0.10),
                radius: imminent ? 10 : 12, y: 4)
        .background {
            // 即将开启的呼吸光：预渲染模糊光晕层，只动 opacity，光栅化一次即可
            if imminent {
                RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous)
                    .fill(theme)
                    .blur(radius: 18)
                    .opacity(glowPulse ? 0.45 : 0.16)
                    .allowsHitTesting(false)
            }
        }
    }

    private func capsuleRow(_ capsule: TimeCapsule, open: Bool, now: Date = .now) -> some View {
        HStack(spacing: 10) {
            Group {
                if open {
                    Button { unlocking = capsule } label: { capsuleCard(capsule, open: true, now: now) }
                        .buttonStyle(.plain)
                } else {
                    capsuleCard(capsule, open: false, now: now)
                }
            }
            .contextMenu { capsuleActions(capsule) }

            Menu {
                capsuleActions(capsule)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(BubuTheme.Color.card.opacity(0.75), in: Circle())
            }
            .accessibilityLabel("胶囊操作")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            BubuMascotBadge(size: 84, expression: .love)
            Text("还没有时间胶囊")
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text("写第一封信，给 18 岁的布布，\n或是给明年今天的她。")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)
            Button { showCompose = true } label: {
                Label("写一封", systemImage: "square.and.pencil")
                    .font(BubuTheme.Font.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(theme, in: Capsule())
            }
            .bubuGlassButton(prominent: true)
            .padding(.top, 8)
        }
        .padding(40)
    }

    private func canOpen(_ capsule: TimeCapsule, at date: Date) -> Bool {
        date >= capsule.unlockAt
    }

    private func countdownText(_ date: Date, now: Date = .now) -> String {
        let days = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
        if days > 365 {
            let years = days / 365
            return "还要等 \(years) 年 · \(BubuDateFormat.yearMonthDay(date))"
        }
        if days > 0 { return "还有 \(days) 天解锁" }
        let hours = max(0, Calendar.current.dateComponents([.hour], from: now, to: date).hour ?? 0)
        if hours > 0 { return "还有 \(hours) 小时就能打开啦" }
        return "马上就能开啦"
    }

    @ViewBuilder
    private func capsuleActions(_ capsule: TimeCapsule) -> some View {
        Button { editing = capsule } label: { Label("修改", systemImage: "pencil") }
        Button(role: .destructive) { deleteCapsule(capsule) } label: { Label("删除", systemImage: "trash") }
    }

    private func deleteCapsule(_ capsule: TimeCapsule) {
        if let blob = capsule.encryptedBlobFileName {
            env.mediaStore.deleteMedia(named: blob)
        }
        PendingDeletion.enqueue(collection: "timecapsules", remoteId: capsule.remoteId, in: context)
        context.delete(capsule)
        try? context.save()
        env.syncEngine.syncNow()
    }
}
