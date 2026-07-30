import SwiftUI
import WatchKit

// MARK: - 一键打卡（喝奶 / 睡觉 / 喝水 / 换尿布）
/// 三个升级：
/// 1. 点完不再只是震一下——卡片 3D 翻面变成「✓ 已记 14:32」的盖章面，2.6 秒后翻回；
///    翻面期间再点一次 = 撤销（防手滑），角标同步回退。
/// 2. 角标显示今天第几次（🍼 ×4）——喂养场景最常被问的一句，原来手表上看不到。
/// 3. 「睡觉」接入哄睡计时：第一次点开始（按钮进入呼吸态 + 实时时长），再点结束并落一条
///    带起止时刻的睡眠记录。与 iPhone 健康页同一套状态，两端谁先点都行。
struct WatchQuickLogView: View {
    @Environment(WatchConnector.self) private var connector

    private let items: [QuickLogItem] = [
        .init(emoji: "🍼", title: "喝奶", kind: "meal", tint: WatchTheme.rose),
        .init(emoji: "😴", title: "睡觉", kind: "sleep", tint: WatchTheme.lav),
        .init(emoji: "💧", title: "喝水", kind: "water", tint: WatchTheme.sky),
        .init(emoji: "🧷", title: "换尿布", kind: nil, tint: WatchTheme.mint)
    ]
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    /// 各按钮的盖章态：值 = (发送时的 localId, 盖章时刻)。在字典里 = 正面朝下（可撤销窗口）。
    @State private var stamped: [String: (localId: String, at: Date)] = [:]

    private var sleepingSince: Date? { connector.snapshot?.sleepingSince }
    private var stats: [String: Int] { connector.snapshot?.todayStats ?? [:] }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    if item.kind == "sleep" {
                        sleepButton(item)
                    } else {
                        stampButton(item)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("打卡")
        .background(WatchSpaceBackground(accent: WatchTheme.mint))
    }

    // MARK: 普通打卡（翻面盖章）

    private func stampButton(_ item: QuickLogItem) -> some View {
        let isStamped = stamped[item.title] != nil
        return Button {
            if let stamp = stamped[item.title] {
                undo(item, stamp: stamp)
            } else {
                log(item)
            }
        } label: {
            ZStack {
                front(item).opacity(isStamped ? 0 : 1)
                back(item).opacity(isStamped ? 1 : 0)
                    // 背面预翻 180°，跟着容器一转正好朝前。
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(item.tint.opacity(isStamped ? 0.45 : 0.28),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .rotation3DEffect(.degrees(isStamped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.spring(duration: 0.4, bounce: 0.3), value: isStamped)
        }
        .buttonStyle(.plain)
    }

    private func front(_ item: QuickLogItem) -> some View {
        VStack(spacing: 4) {
            Text(item.emoji).font(.system(size: 28))
            HStack(spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                if let kind = item.kind, let count = stats[kind], count > 0 {
                    Text("×\(count)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(item.tint)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    private func back(_ item: QuickLogItem) -> some View {
        VStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(item.tint)
            Text("已记 \(Date.now.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Text("再点一下撤销")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func log(_ item: QuickLogItem) {
        let localId: String?
        if let kind = item.kind {
            localId = connector.sendHealth(kindRaw: kind, title: item.title)
        } else {
            localId = connector.sendText("\(item.emoji) \(item.title)了")
        }
        guard let localId else { return }
        WKInterfaceDevice.current().play(.success)
        withAnimation { stamped[item.title] = (localId, .now) }
        // 2.6 秒后翻回正面，撤销窗口关闭。
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if stamped[item.title]?.at.timeIntervalSinceNow ?? 0 < -2.5 {
                withAnimation { stamped[item.title] = nil }
            }
        }
    }

    private func undo(_ item: QuickLogItem, stamp: (localId: String, at: Date)) {
        connector.sendUndo(localId: stamp.localId)
        if let kind = item.kind { connector.revertTodayStat(kindRaw: kind) }
        WKInterfaceDevice.current().play(.retry)
        withAnimation { stamped[item.title] = nil }
    }

    // MARK: 睡觉（哄睡计时）

    private func sleepButton(_ item: QuickLogItem) -> some View {
        Button {
            if sleepingSince != nil {
                connector.sendSleepEnd()
                WKInterfaceDevice.current().play(.success)
            } else {
                connector.sendSleepStart()
                WKInterfaceDevice.current().play(.start)
            }
        } label: {
            Group {
                if let since = sleepingSince {
                    // 哄睡中：实时时长每秒跳，整卡呼吸。
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        VStack(spacing: 3) {
                            Text("🌙").font(.system(size: 24))
                            Text(elapsedText(since: since, now: timeline.date))
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(WatchTheme.lav)
                                .contentTransition(.numericText())
                            Text("睡着了 · 醒来点一下")
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        Text(item.emoji).font(.system(size: 28))
                        HStack(spacing: 3) {
                            Text("哄睡")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                            if let count = stats["sleep"], count > 0 {
                                Text("×\(count)")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundStyle(item.tint)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(item.tint.opacity(sleepingSince != nil ? 0.45 : 0.28),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .phaseAnimator([1.0, 0.75], trigger: sleepingSince != nil) { view, phase in
                view.opacity(sleepingSince != nil ? phase : 1)
            } animation: { _ in .easeInOut(duration: 1.6).repeatForever(autoreverses: true) }
        }
        .buttonStyle(.plain)
    }

    private func elapsedText(since: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(since)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct QuickLogItem: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let kind: String?
    let tint: Color
}
