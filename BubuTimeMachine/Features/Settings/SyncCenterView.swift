import SwiftUI
import SwiftData

// MARK: - 同步与备份中心
/// 全家每台设备的日常状态查询页：同步到哪了、还差多少、出了什么问题、怎么补救。
///
/// 为什么单独立一级页：同步引擎其实暴露了 9 个可观测状态（进度、当前条目、上传百分比、
/// 大文件提示、软失败、待同步数…），但过去只有首页那张小卡在用，设置侧只有 4 行静态文字，
/// 还埋在「高级 · 自托管」（一个写给装服务器的人看的页面）之下。恢复手段（全量重拉/重传）
/// 更是只有 DEBUG 启动参数入口，正式版用户无路可走。
struct SyncCenterView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context

    @State private var confirmFullPull = false
    @State private var confirmFullPush = false
    @State private var runningFullPush = false
    @State private var actionNotice: String?

    /// 上次全量导出时间戳（ExportView 完成后写入）。
    @AppStorage("bubu.lastExportAt") private var lastExportAtRaw: Double = 0

    private var theme: Color { env.theme.theme.primary }
    private var engine: SyncEngine { env.syncEngine }

    var body: some View {
        ScrollView {
            VStack(spacing: BubuTheme.Spacing.section) {
                statusCard
                detailCard
                actionCard
                backupCard
                Text("同步只在你自己的服务器和家人设备之间进行，不经过任何第三方。")
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding()
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .navigationTitle("同步与备份")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("重新拉取全部内容？", isPresented: $confirmFullPull, titleVisibility: .visible) {
            Button("重新拉取", role: .destructive) { performFullPull() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会把服务器上的记录从头核对一遍，补齐这台设备缺失的内容。已有内容不会重复，只是流量和时间多一些。")
        }
        .confirmationDialog("把本机内容全部重传一遍？", isPresented: $confirmFullPush, titleVisibility: .visible) {
            Button("开始重传", role: .destructive) { Task { await performFullPush() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("适用于「本机有、服务器没有」的情况。已经在服务器上的内容会被跳过，不会产生重复。大库可能要跑一阵子。")
        }
        .alert("同步", isPresented: Binding(
            get: { actionNotice != nil }, set: { if !$0 { actionNotice = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionNotice ?? "")
        }
    }

    // MARK: 状态大卡

    private var statusCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.14))
                    .frame(width: 84, height: 84)
                Image(systemName: statusIcon)
                    .font(BubuTheme.Font.scaled(36, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .symbolEffect(.pulse, isActive: engine.connectionState == .connecting || engine.pendingCount > 0)
            }
            Text(statusTitle)
                .font(BubuTheme.Font.title)
                .foregroundStyle(BubuTheme.Color.warmBrown)
            Text(statusSubtitle)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .multilineTextAlignment(.center)

            // 整轮进度：有待办时才显示，避免闲时一直挂个空进度条。
            if let progress = engine.syncProgress, engine.pendingCount > 0 || engine.connectionState == .connecting {
                VStack(spacing: 6) {
                    ProgressView(value: progress).tint(theme)
                    if let label = engine.currentSyncLabel {
                        HStack(spacing: 6) {
                            Text(label)
                            if let up = engine.currentUploadProgress, up > 0, up < 1 {
                                Text("· \(Int(up * 100))%")
                            }
                        }
                        .font(BubuTheme.Font.scaled(11, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                    }
                }
                .padding(.top, 2)
            }

            if let notice = engine.lastLargeFileNotice {
                noticeLine(notice, tint: theme, icon: "arrow.up.circle")
            }
            if let soft = engine.softNotice {
                noticeLine(soft, tint: BubuTheme.Color.secondaryText, icon: "clock.arrow.circlepath")
            }
            if let failure = engine.lastFailureReason, engine.pendingCount > 0 {
                noticeLine(failure, tint: BubuTheme.Color.danger, icon: "exclamationmark.triangle.fill")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func noticeLine(_ text: String, tint: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(BubuTheme.Font.scaled(11, weight: .bold))
            Text(text).font(BubuTheme.Font.scaled(11.5))
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small, style: .continuous))
    }

    private var statusIcon: String {
        if engine.connectionState == .offline { return "icloud.slash.fill" }
        if engine.connectionState == .connecting { return "arrow.triangle.2.circlepath.icloud.fill" }
        return engine.pendingCount == 0 ? "checkmark.icloud.fill" : "arrow.up.circle.fill"
    }

    private var statusTint: Color {
        switch engine.connectionState {
        case .offline:    return BubuTheme.Color.secondaryText
        case .connecting: return theme
        case .online:     return engine.pendingCount == 0 ? BubuTheme.Color.success : theme
        }
    }

    private var statusTitle: String {
        switch engine.connectionState {
        case .offline:    return "离线中"
        case .connecting: return "正在连接…"
        case .online:     return engine.pendingCount == 0 ? "全部同步好了" : "正在同步"
        }
    }

    private var statusSubtitle: String {
        switch engine.connectionState {
        case .offline:
            return env.config.isConfigured
                ? "连不上家里的服务器，记录都安全存在这台设备上，联网后会自动补传。"
                : "还没连接家里的服务器。不连也能用，只是记录不会同步到其他家人的设备。"
        case .connecting:
            return "正在和家里的服务器握手…"
        case .online:
            if engine.pendingCount == 0 {
                return engine.lastSyncedAt.map { "上次同步：\(BubuDateFormat.shortDateTime($0))" } ?? "已连接"
            }
            return "还有 \(engine.pendingCount) 项在排队，可以放着不管，它会自己传完。"
        }
    }

    // MARK: 明细

    private var detailCard: some View {
        VStack(spacing: 0) {
            detailRow("连接状态", value: statusTitle)
            Divider().padding(.leading, 16)
            detailRow("等待同步", value: engine.pendingCount == 0 ? "都同步好啦" : "\(engine.pendingCount) 项",
                      warn: engine.pendingCount > 0)
            Divider().padding(.leading, 16)
            detailRow("上次同步", value: engine.lastSyncedAt.map { BubuDateFormat.shortDateTime($0) } ?? "还没同步过",
                      warn: engine.lastSyncedAt == nil)
            if engine.totalPendingAtStart > 0 {
                Divider().padding(.leading, 16)
                detailRow("本轮进度", value: "\(engine.processedThisRun) / \(engine.totalPendingAtStart)")
            }
            Divider().padding(.leading, 16)
            detailRow("服务器", value: env.config.baseURLString.isEmpty ? "未配置" : env.config.baseURLString)
            if !env.config.lanBaseURLString.isEmpty {
                Divider().padding(.leading, 16)
                detailRow("局域网直连", value: env.config.lanBaseURLString)
            }
        }
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func detailRow(_ title: String, value: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(BubuTheme.Font.caption.weight(.medium))
                .foregroundStyle(warn ? BubuTheme.Color.warning : BubuTheme.Color.warmBrown)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: 操作

    private var actionCard: some View {
        VStack(spacing: 0) {
            actionRow("立即同步", subtitle: "手动催一次，通常不需要",
                      icon: "arrow.triangle.2.circlepath", tint: theme,
                      disabled: !env.config.isConfigured) {
                engine.syncNow()
                BubuHaptics.tapLight()
                actionNotice = "已经开始同步啦。"
            }
            Divider().padding(.leading, 54)
            actionRow("重新拉取全部内容", subtitle: "这台设备好像少了些照片时用",
                      icon: "square.and.arrow.down.on.square", tint: BubuTheme.Color.info,
                      disabled: !env.config.isConfigured) {
                confirmFullPull = true
            }
            Divider().padding(.leading, 54)
            actionRow("把本机内容全部重传", subtitle: "服务器上好像少了些内容时用",
                      icon: "square.and.arrow.up.on.square", tint: BubuTheme.Color.warning,
                      disabled: !env.config.isConfigured || runningFullPush,
                      busy: runningFullPush) {
                confirmFullPush = true
            }
        }
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private func actionRow(_ title: String, subtitle: String, icon: String, tint: Color,
                           disabled: Bool = false, busy: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(BubuTheme.Font.scaled(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small * 0.6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BubuTheme.Font.body.weight(.medium))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                    Text(subtitle)
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                }
                Spacer(minLength: 0)
                if busy { ProgressView() }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// 重新全量拉取：清空增量游标 → 下一轮从头核对。localId 去重 + merge 幂等，不会产生重复。
    private func performFullPull() {
        SyncEngine.resetAllCursors()
        engine.syncNow()
        BubuHaptics.success()
        actionNotice = "已经开始重新核对服务器上的内容，可以先去做别的，它会在后台继续。"
    }

    /// 把本机所有内容重新推一遍（原来只有 DEBUG 启动参数能触发）。
    private func performFullPush() async {
        runningFullPush = true
        defer { runningFullPush = false }
        let summary = await engine.forceUploadAllLocalData()
        BubuHaptics.success()
        actionNotice = summary.contains("FAILED")
            ? "重传没能开始，稍后再试。"
            : "本机内容已全部重新排队上传，剩下的它会自己传完。"
    }

    // MARK: 备份

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: exportStale ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(BubuTheme.Font.scaled(15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(exportStale ? BubuTheme.Color.warning : BubuTheme.Color.success,
                                in: RoundedRectangle(cornerRadius: BubuTheme.Radius.small * 0.6, style: .continuous))
                Text("离线备份")
                    .font(BubuTheme.Font.body.weight(.medium))
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Spacer()
            }
            Text(exportStale
                 ? "服务器是单点，建议每季度导出一份完整档案存到电脑或移动硬盘。"
                 : "上次全量导出：\(exportText)。保持这个习惯，布布的档案就有双保险。")
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            NavigationLink { ExportView() } label: {
                Text("去导出完整档案")
                    .font(BubuTheme.Font.caption.weight(.semibold))
                    .foregroundStyle(theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BubuTheme.Color.card, in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))
        .bubuCardShadow()
    }

    private var daysSinceExport: Int? {
        guard lastExportAtRaw > 0 else { return nil }
        let last = Date(timeIntervalSince1970: lastExportAtRaw)
        return Calendar.current.dateComponents([.day], from: last, to: .now).day
    }

    private var exportStale: Bool {
        guard let d = daysSinceExport else { return true }
        return d > 90
    }

    private var exportText: String {
        guard let d = daysSinceExport else { return "从未导出" }
        if d == 0 { return "今天" }
        return "\(d) 天前"
    }
}
