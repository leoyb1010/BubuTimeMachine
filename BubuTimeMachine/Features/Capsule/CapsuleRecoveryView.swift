import SwiftUI

// MARK: - 时间胶囊恢复码（v3 真 E2E 管理页）
/// 展示家庭恢复码，引导打印/抄写收进实体盒子；支持用纸条恢复码恢复（换新机/iCloud 丢失）。
struct CapsuleRecoveryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var restoring = false
    @State private var restoreInput = ""
    @State private var copied = false

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
                Text("你的 24 词恢复码").font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                let words = code.split(separator: " ").map(String.init)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                        Text("\(i + 1). \(w)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
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
                Button("恢复") {
                    CapsuleRecovery.restore(restoreInput)
                    code = CapsuleRecovery.current() ?? ""
                    restoreInput = ""
                    restoring = false
                    BubuHaptics.success()
                }
                .font(BubuTheme.Font.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(theme, in: Capsule())
                .disabled(restoreInput.split(separator: " ").count < 12)
            }
        }
    }

    private var warning: some View {
        Text("务必把这串词抄在纸上，收进家里的盒子。30 年后即使手机、iCloud 都不在了，有这张纸，布布依然能打开你今天写下的信。")
            .font(.system(size: 12))
            .foregroundStyle(BubuTheme.Color.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}
