import SwiftUI
import SwiftData

// MARK: - 时间胶囊 · 列表
/// 写给未来布布的信，到期前加密锁定、只显示倒计时。到期后可庄重开启。
struct CapsuleHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \TimeCapsule.unlockAt) private var capsules: [TimeCapsule]

    @State private var showCompose = false
    @State private var unlocking: TimeCapsule?

    private var theme: Color { env.theme.theme.primary }
    private var locked: [TimeCapsule] { capsules.filter { !canOpen($0) } }
    private var openable: [TimeCapsule] { capsules.filter { canOpen($0) } }

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
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCompose = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $showCompose) { CapsuleComposeView() }
        .fullScreenCover(item: $unlocking) { capsule in
            CapsuleUnlockView(capsule: capsule)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch env.theme.theme.backgroundStyle {
        case .solid(let hex): Color(hex: hex)
        case .gradient(let a, let b):
            LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
        }
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
                Button { unlocking = capsule } label: { capsuleCard(capsule, open: true) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var lockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("静静等待", systemImage: "lock.fill")
                .font(BubuTheme.Font.headline).foregroundStyle(BubuTheme.Color.warmBrown)
            ForEach(locked) { capsule in
                capsuleCard(capsule, open: false)
            }
        }
    }

    private func capsuleCard(_ capsule: TimeCapsule, open: Bool) -> some View {
        HStack(spacing: 16) {
            Text(capsule.coverEmoji ?? "💌")
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme)
                } else {
                    Text(countdownText(capsule.unlockAt))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(theme)
                }
            }
            Spacer()
            Image(systemName: open ? "chevron.right" : "lock.fill")
                .foregroundStyle(BubuTheme.Color.secondaryText)
        }
        .padding()
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Text("💌").font(.system(size: 64))
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
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(40)
    }

    private func canOpen(_ capsule: TimeCapsule) -> Bool {
        Date.now >= capsule.unlockAt
    }

    private func countdownText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if days > 365 {
            let years = days / 365
            return "还要等 \(years) 年 · \(date.formatted(.dateTime.year().month().day()))"
        }
        if days > 0 { return "还有 \(days) 天解锁" }
        return "今天就能开啦"
    }
}
