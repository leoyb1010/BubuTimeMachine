import SwiftUI
import SwiftData

// MARK: - 时间胶囊恢复码（v3 真 E2E 管理页）
/// 展示家庭恢复码，引导打印/抄写收进实体盒子；支持用纸条恢复码恢复（换新机/iCloud 丢失）。
struct CapsuleRecoveryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query private var capsules: [TimeCapsule]

    @State private var code: String = ""
    @State private var restoring = false
    @State private var restoreInput = ""
    @State private var copied = false
    @State private var restoreError: String?
    @State private var confirmOverwrite = false

    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                    intro
                    codeCard
                    actions
                    restoreSection
                    warning
                }
                .padding()
            }
            .background(BubuTheme.Color.background.ignoresSafeArea())
            .navigationTitle("胶囊恢复码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .onAppear { code = CapsuleRecovery.current() ?? "" }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("这是布布所有时间胶囊的钥匙", systemImage: "key.horizontal.fill")
                .font(BubuTheme.Font.headline)
                .foregroundStyle(theme)
            Text("时间胶囊用这串恢复码真正加密——服务器即使被攻破，没有它也打不开。它会随你的 iCloud 钥匙串同步到全家的设备。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var codeCard: some View {
        if code.isEmpty {
            VStack(spacing: 12) {
                BubuMascotBadge(size: 56, expression: .thinking)
                Text("还没有恢复码。写下第一封时间胶囊时会自动生成，也可以现在就生成并抄下来。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                Button("现在生成") {
                    code = CapsuleRecovery.currentOrCreate()
                    BubuHaptics.success()
                }
                .font(BubuTheme.Font.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(theme, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("你的 24 词恢复码").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.paperInkSecondary)
                let words = code.split(separator: " ").map(String.init)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                        Text("\(i + 1). \(w)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(BubuTheme.Color.paperInk)
                    }
                }
            }
            .padding()
            .background(Color(hex: "#FFFDF8"), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
            .bubuCardShadow()
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !code.isEmpty {
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    BubuHaptics.success()
                } label: {
                    Label(copied ? "已复制 ✓" : "复制", systemImage: "doc.on.doc")
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(theme)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                ShareLink(item: code) {
                    Label("打印/分享", systemImage: "printer")
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(theme)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.opacity(0.1), in: Capsule())
                }
            }
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(BubuMotion.gentle) { restoring.toggle() }
            } label: {
                Label("用纸条上的恢复码恢复", systemImage: "arrow.clockwise")
                    .font(BubuTheme.Font.caption.weight(.medium))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
            }
            if restoring {
                TextField("把 24 个词按顺序输进来，用空格隔开", text: $restoreInput, axis: .vertical)
                    .font(.system(size: 15, design: .monospaced))
                    .lineLimit(3...6)
                    .padding()
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
                Button("恢复") { attemptRestore() }
                .font(BubuTheme.Font.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(theme, in: Capsule())
                .disabled(restoreInput.split(separator: " ").count < 12)

                if let restoreError {
                    Text(restoreError)
                        .font(.system(size: 12))
                        .foregroundStyle(BubuTheme.Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .alert("覆盖现有恢复码？", isPresented: $confirmOverwrite) {
            Button("覆盖", role: .destructive) { doRestore() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这台设备上还没有可校验的胶囊，无法确认这串词是否正确。覆盖后，如果词抄错了，之前封存的信会解不开。确定要覆盖吗？")
        }
    }

    /// 恢复前先校验：词表核对 → 用现有 v3 胶囊试解（不显示内容）。
    /// 校验不过绝不写入——防止一串抄错的词静默覆盖全家的正确密钥。
    private func attemptRestore() {
        restoreError = nil
        let words = restoreInput.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
        guard words.count == 24 else {
            restoreError = "恢复码应是 24 个词，现在有 \(words.count) 个，检查一下有没有抄漏。"
            return
        }
        let badWords = words.filter { !CapsuleRecovery.wordList.contains($0) }
        guard badWords.isEmpty else {
            restoreError = "这几个词不在词表里：\(badWords.prefix(3).joined(separator: "、"))。对照纸条再检查一下拼写。"
            return
        }
        let candidate = words.joined(separator: " ")

        // 有 v3 胶囊就用密码学校验：解得开才是对的码
        let v3Capsules = capsules.filter { c in
            guard let blob = c.encryptedBlobFileName else { return false }
            return env.vault.isV3Blob(fileName: blob)
        }
        if let sample = v3Capsules.first, let blob = sample.encryptedBlobFileName {
            guard env.vault.canDecryptV3(fileName: blob, salt: sample.id.uuidString,
                                         recoveryCode: candidate, unlockAt: sample.unlockAt) else {
                restoreError = "这串词解不开家里现有的胶囊——很可能抄错了。请对照纸条逐词核对后再试。"
                return
            }
            doRestore()
            return
        }
        // 没有可校验的胶囊：如果会覆盖已有的不同恢复码，先确认
        if let current = CapsuleRecovery.current(), !current.isEmpty, current != candidate {
            confirmOverwrite = true
        } else {
            doRestore()
        }
    }

    private func doRestore() {
        CapsuleRecovery.restore(restoreInput)
        code = CapsuleRecovery.current() ?? ""
        restoreInput = ""
        restoring = false
        restoreError = nil
        BubuHaptics.success()
    }

    private var warning: some View {
        Text("务必把这串词抄在纸上，收进家里的盒子。30 年后即使手机、iCloud 都不在了，有这张纸，布布依然能打开你今天写下的信。")
            .font(.system(size: 12))
            .foregroundStyle(BubuTheme.Color.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}
