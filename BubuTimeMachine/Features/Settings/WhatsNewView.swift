import SwiftUI

// MARK: - 更新记录 / 升级弹窗
/// - WhatsNewListView：设置页进入，按版本倒序展示全部更新记录。
/// - WhatsNewSheet：升级后首次启动自动弹出，只展示最新一版。
/// - WhatsNewGate：判断是否需要弹窗（比对上次见过的版本）。

// MARK: 升级弹窗判定
enum WhatsNewGate {
    private static let key = "bubu.whatsnew.lastSeenVersion"

    /// 当前版本是否还没给用户看过更新弹窗。全新安装（从未记录过）不弹，避免打扰。
    static var shouldPresent: Bool {
        let seen = UserDefaults.standard.string(forKey: key)
        // 全新安装：记下当前版本，不弹（首次进来不该被更新弹窗打扰）。
        guard let seen else {
            markSeen()
            return false
        }
        return seen != AppVersion.marketing
    }

    static func markSeen() {
        UserDefaults.standard.set(AppVersion.marketing, forKey: key)
    }
}

// MARK: 升级弹窗（只展示最新一版）
struct WhatsNewSheet: View {
    let note: ReleaseNote
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("✨").font(.system(size: 44))
                Text("更新好啦")
                    .font(BubuTheme.Font.hugeTitle)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text("v\(note.version) · \(note.title)")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(note.highlights, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BubuTheme.Color.primary)
                                .padding(.top, 2)
                            Text(item)
                                .font(BubuTheme.Font.body)
                                .foregroundStyle(BubuTheme.Color.warmBrown)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }

            Button {
                WhatsNewGate.markSeen()
                onClose()
            } label: {
                Text("知道了")
                    .font(BubuTheme.Font.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BubuTheme.Color.primary, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(BubuTheme.Color.cream)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }
}

// MARK: 更新记录全列表（设置页进入）
struct WhatsNewListView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Changelog.all) { note in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("v\(note.version)")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(BubuTheme.Color.warmBrown)
                            Spacer()
                            Text(note.date)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                        Text(note.title)
                            .font(BubuTheme.Font.caption.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.primary)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(note.highlights, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("·").foregroundStyle(BubuTheme.Color.primary)
                                    Text(item)
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(BubuTheme.Color.warmBrown)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
                }
            }
            .padding()
        }
        .background(BubuTheme.Color.cream.ignoresSafeArea())
        .navigationTitle("更新记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}
