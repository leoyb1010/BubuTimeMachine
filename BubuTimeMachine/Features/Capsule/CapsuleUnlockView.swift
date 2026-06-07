import SwiftUI
import SwiftData

// MARK: - 时间胶囊 · 庄重开启
/// 到期解锁的仪式动画：信封缓缓开启 → 解密 → 信纸浮现，可读信、听语音。
struct CapsuleUnlockView: View {
    let capsule: TimeCapsule
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .sealed
    @State private var payload: CapsulePayload?
    @State private var errorText: String?

    enum Phase { case sealed, opening, revealed }

    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.opacity(0.85), theme.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            switch phase {
            case .sealed: sealedView
            case .opening: openingView
            case .revealed: revealedView
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
            }
            .padding()
        }
    }

    // MARK: 封存态

    private var sealedView: some View {
        VStack(spacing: 28) {
            Text(capsule.coverEmoji ?? "💌")
                .font(.system(size: 100))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            VStack(spacing: 8) {
                Text(capsule.title).font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("来自\(capsule.fromRole) · 封存于 \(capsule.createdAt.formatted(date: .abbreviated, time: .omitted))")
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

    // MARK: 开启中

    private var openingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 90)).foregroundStyle(.white)
                .symbolEffect(.bounce)
            Text("正在解封……").font(BubuTheme.Font.headline).foregroundStyle(.white)
        }
    }

    // MARK: 已开启

    @ViewBuilder
    private var revealedView: some View {
        if let errorText {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.lock").font(.system(size: 50)).foregroundStyle(.white)
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

                    Text("—— 来自\(capsule.fromRole)，写于 \(capsule.createdAt.formatted(date: .long, time: .omitted))")
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

    private func open() {
        withAnimation(.easeInOut(duration: 0.5)) { phase = .opening }
        Task {
            try? await Task.sleep(for: .milliseconds(1100))
            do {
                let p = try env.vault.unseal(fileName: capsule.encryptedBlobFileName ?? "",
                                             unlockAt: capsule.unlockAt,
                                             salt: capsule.id.uuidString)
                payload = p
                capsule.isLocked = false
                try? context.save()
            } catch {
                errorText = (error as? CapsuleCrypto.CryptoError)?.errorDescription ?? "信件打不开了"
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { phase = .revealed }
        }
    }
}
