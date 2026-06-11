import SwiftUI
import SwiftData

// MARK: - 时间胶囊 · 庄重开启（三幕制）
/// 第一幕「破封」：重触觉 + 封蜡碎裂粒子；
/// 第二幕「时光回溯」：字幕告诉你这封信等了多久；
/// 第三幕「信纸展开」：解密内容从信封中浮现。
/// 全程可点击跳过；「减弱动态效果」时解密后直接定格第三幕（保留触觉）。
struct CapsuleUnlockView: View {
    let capsule: TimeCapsule
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .sealed
    @State private var payload: CapsulePayload?
    @State private var errorText: String?
    @State private var burst = false
    @State private var ceremonyTask: Task<Void, Never>?

    enum Phase { case sealed, cracking, retrospect, revealed }

    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.opacity(phase == .retrospect ? 0.95 : 0.85),
                                    theme.opacity(phase == .retrospect ? 0.65 : 0.5)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(BubuMotion.smooth, value: phase)

            switch phase {
            case .sealed: sealedView
            case .cracking: crackingView
            case .retrospect: retrospectView
            case .revealed: revealedView
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(.white.opacity(0.85))
                    }
                    .accessibilityLabel("关闭")
                }
                Spacer()
            }
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 典礼可跳过：破封/回溯期间点一下直达信纸
            if phase == .cracking || phase == .retrospect {
                ceremonyTask?.cancel()
                finishReveal()
            }
        }
        .onDisappear { ceremonyTask?.cancel() }
    }

    // MARK: 第〇幕 · 封存态

    private var sealedView: some View {
        VStack(spacing: 28) {
            Text(capsule.coverEmoji ?? "💌")
                .font(.system(size: 100))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            VStack(spacing: 8) {
                Text(capsule.title).font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("来自\(capsule.fromRole) · 封存于 \(BubuDateFormat.shortDate(capsule.createdAt))")
                    .font(BubuTheme.Font.caption).foregroundStyle(.white.opacity(0.85))
            }
            Button { open() } label: {
                Label("郑重地打开它", systemImage: "hand.tap.fill")
                    .font(BubuTheme.Font.headline.weight(.bold))
                    .foregroundStyle(theme)
                    .padding(.horizontal, 30).padding(.vertical, 15)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(40)
    }

    // MARK: 第一幕 · 破封

    private var crackingView: some View {
        ZStack {
            // 封蜡碎片向四周飞散
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12 * 2 * .pi
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: i.isMultiple(of: 3) ? 10 : 6)
                    .offset(x: burst ? cos(angle) * 110 : 0,
                            y: burst ? sin(angle) * 110 : 0)
                    .opacity(burst ? 0 : 1)
            }
            Text(capsule.coverEmoji ?? "💌")
                .font(.system(size: 100))
                .scaleEffect(burst ? 1.18 : 1)
                .rotationEffect(.degrees(burst ? -4 : 0))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) { burst = true }
        }
    }

    // MARK: 第二幕 · 时光回溯

    private var retrospectView: some View {
        VStack(spacing: 18) {
            Image(systemName: "hourglass")
                .font(.system(size: 56))
                .foregroundStyle(.white)
                .symbolEffect(.rotate, options: .nonRepeating)
            Text(waitedText)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("现在，它是你的了")
                .font(BubuTheme.Font.body)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(40)
        .transition(.opacity)
    }

    /// 「这封信等了你 X 年 X 个月」——封存日到今天。
    private var waitedText: String {
        let comps = Calendar.current.dateComponents([.year, .month, .day],
                                                    from: capsule.createdAt, to: .now)
        let y = comps.year ?? 0, m = comps.month ?? 0, d = comps.day ?? 0
        if y > 0 { return m > 0 ? "这封信等了你\n\(y) 年 \(m) 个月" : "这封信等了你\n整整 \(y) 年" }
        if m > 0 { return "这封信等了你\n\(m) 个月 \(d) 天" }
        return "这封信等了你\n\(max(d, 1)) 天"
    }

    // MARK: 第三幕 · 信纸展开

    @ViewBuilder
    private var revealedView: some View {
        if let errorText {
            VStack(spacing: 16) {
                BubuMascotBadge(size: 72, expression: .shy)
                Text(errorText).font(BubuTheme.Font.body).foregroundStyle(.white).multilineTextAlignment(.center)
            }
            .padding(40)
        } else if let payload {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 6) {
                        Text(capsule.coverEmoji ?? "💌").font(.system(size: 50))
                        Text(capsule.title).font(BubuTheme.Font.title).foregroundStyle(BubuTheme.Color.warmBrown)
                    }
                    .frame(maxWidth: .infinity)

                    if !payload.letter.isEmpty {
                        Text(payload.letter)
                            .font(.system(size: 19, design: .serif))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                            .lineSpacing(8)
                    }

                    if let voiceName = payload.voiceFileName {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("还有一段话想对你说", systemImage: "waveform")
                                .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                            VoicePlayerBubble(fileName: voiceName, duration: payload.voiceDuration,
                                              waveform: payload.voiceWaveform, mediaStore: env.mediaStore, tint: theme)
                        }
                    }

                    Text("—— 来自\(capsule.fromRole)，写于 \(BubuDateFormat.longDate(capsule.createdAt))")
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(26)
                .background(Color(hex: "#FFFDF8"), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                .padding()
                .padding(.top, 40)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: 典礼编排

    private func open() {
        // 先解密（本地、毫秒级），典礼只是给结果一个庄重的入场
        decrypt()

        if reduceMotion {
            BubuHaptics.breakSeal()
            phase = .revealed
            return
        }

        BubuHaptics.breakSeal()
        withAnimation(BubuMotion.quick) { phase = .cracking }
        ceremonyTask = Task {
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            withAnimation(BubuMotion.smooth) { phase = .retrospect }
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            finishReveal()
        }
    }

    private func finishReveal() {
        BubuHaptics.success()
        withAnimation(BubuMotion.ceremony) { phase = .revealed }
    }

    private func decrypt() {
        do {
            guard let blob = capsule.encryptedBlobFileName, !blob.isEmpty else {
                errorText = "这封胶囊的加密内容还没同步到本机，请先回到设置里点一次立即同步。"
                return
            }
            let p = try env.vault.unseal(fileName: blob,
                                         unlockAt: capsule.unlockAt,
                                         salt: capsule.id.uuidString)
            payload = p
            capsule.isLocked = false
            capsule.syncState = .local
            try? context.save()
            env.syncEngine.syncNow()
        } catch {
            errorText = (error as? CapsuleCrypto.CryptoError)?.errorDescription ?? "信件打不开了"
        }
    }
}
