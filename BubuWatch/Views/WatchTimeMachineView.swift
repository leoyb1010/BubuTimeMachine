import SwiftUI
import WatchKit
import UIKit

// MARK: - 表冠时光机（本次重做的灵魂页）
/// 产品叫"时光机"，手表上有全世界最好的时间旋钮——把表冠做成时光旅行的把手。
/// 拧一档 = 穿越到一段回忆；序列按时间倒序（Phase E 保证），越拧越远。
/// 拧到「那年今日」金徽章 + 双震——那个瞬间是这页存在的意义。
struct WatchTimeMachineView: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 表冠的连续值。四舍五入成回忆索引；系统按 by:1 给档位触觉。
    @State private var crownValue: Double = 0
    @State private var index = 0
    /// 点按卡片后的爱心迸发触发器。
    @State private var heartBurst = 0
    /// 已发过 ❤️ 的回忆（一段只发一次，拧回来重看不重复轰炸手机）。
    @State private var lovedIds: Set<String> = []
    @State private var photos: [String: UIImage] = [:]

    private var memories: [WatchMemory] { connector.snapshot?.memories ?? [] }

    var body: some View {
        Group {
            if memories.isEmpty {
                emptyState
            } else {
                machineBody
            }
        }
        .background(WatchSpaceBackground(accent: WatchTheme.lav))
        .onAppear { loadPhotos() }
        .onChange(of: connector.photoVersion) { loadPhotos() }
    }

    // MARK: 主体

    private var machineBody: some View {
        let memory = memories[min(index, memories.count - 1)]
        return ZStack(alignment: .top) {
            memoryCard(memory)
                .id(memory.id)
                // 换卡：旧卡缩小淡出、新卡从景深弹入——"穿越"的体感。
                .transition(.scale(scale: 0.88).combined(with: .opacity))

            timeScale(memory)
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: index)
        .focusable()
        .digitalCrownRotation($crownValue,
                              from: 0, through: Double(max(memories.count - 1, 0)),
                              by: 1, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crownValue) { _, value in
            let next = min(max(Int(value.rounded()), 0), memories.count - 1)
            guard next != index else { return }
            index = next
            // 拧到「那年今日」双震惊喜；普通档位系统的表冠触觉已经够。
            if memories[next].isOnThisDay {
                WKInterfaceDevice.current().play(.notification)
            }
        }
        .sensoryFeedback(.selection, trigger: index)
    }

    // MARK: 回忆卡

    private func memoryCard(_ memory: WatchMemory) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let name = memory.photoFileName, let img = photos[name] {
                KenBurnsPhoto(image: img, animated: !dimmed)
            } else {
                // 无照片回忆：心情 emoji 当主视觉，深空渐变底。
                ZStack {
                    LinearGradient(colors: [WatchTheme.lav.opacity(0.4), WatchTheme.sky.opacity(0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(memory.moodEmoji ?? "✨").font(.system(size: 54))
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(memory.dateText)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(WatchTheme.butter)
                    if !memory.ageText.isEmpty {
                        Text("那时 \(memory.ageText)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Text(memory.note)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if memory.isOnThisDay {
                Label("那年今日", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(WatchTheme.butter, in: Capsule())
                    .padding(8)
            }
        }
        .overlay { HeartBurst(trigger: heartBurst) }
        .onTapGesture { love(memory) }
        .ignoresSafeArea(edges: .bottom)
    }

    /// 点一下 = 给那条记录点个亲亲。
    ///
    /// 走 reaction 而不是发一条文字记录：文字记录会变成时光轴里的正式一条，
    /// 重温十次就多十条「又看了一遍」的垃圾，布布 18 岁翻相册会看到它们。
    /// reaction 落在 App 已有的亲亲机制上——同一人只算一颗心，家人在时光轴卡片上看得到。
    private func love(_ memory: WatchMemory) {
        heartBurst += 1
        guard !lovedIds.contains(memory.id) else { return }
        lovedIds.insert(memory.id)
        connector.sendReaction(entryId: memory.id)
        WKInterfaceDevice.current().play(.success)
    }

    // MARK: 年代刻度

    /// 顶部微缩刻度尺：一条轨道 + 位置点，越拧越远点越靠右。
    private func timeScale(_ memory: WatchMemory) -> some View {
        let progress = memories.count > 1 ? Double(index) / Double(memories.count - 1) : 0
        return VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 3)
                    Circle()
                        .fill(memory.isOnThisDay ? WatchTheme.butter : WatchTheme.rose)
                        .frame(width: 7, height: 7)
                        .offset(x: progress * (geo.size.width - 7))
                        .animation(.spring(duration: 0.3), value: index)
                }
                .frame(height: 7)
            }
            .frame(height: 7)
            HStack {
                Text("现在").font(.system(size: 8, weight: .bold, design: .rounded))
                Spacer()
                Text("更早").font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("🕰️").font(.system(size: 36))
            Text("时光机正在装填回忆\n打开手机上的布布时光机就好")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: 照片

    /// 把当前序列引用的缓存图一次解码进内存。20 张 × 400px ≈ 数 MB，手表可承受；
    /// 换批时旧字典整体释放。
    private func loadPhotos() {
        var loaded: [String: UIImage] = [:]
        for memory in memories {
            guard let name = memory.photoFileName else { continue }
            if let data = WatchPhotoStore.data(for: name), let img = UIImage(data: data) {
                loaded[name] = img
            }
        }
        photos = loaded
    }
}

// MARK: - 爱心迸发
/// 点按卡片：一颗大爱心弹出 + 6 颗小星从中心散开。纯 phaseAnimator，无定时器。
private struct HeartBurst: View {
    let trigger: Int

    var body: some View {
        ZStack {
            Text("❤️")
                .font(.system(size: 40))
                .phaseAnimator([0, 1, 0], trigger: trigger) { view, phase in
                    view.scaleEffect(phase == 1 ? 1.0 : 0.3)
                        .opacity(phase == 1 ? 1 : 0)
                } animation: { phase in
                    phase == 1 ? .spring(duration: 0.3, bounce: 0.5) : .easeOut(duration: 0.4)
                }
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i) / 6 * 2 * .pi
                Text("✨")
                    .font(.system(size: 13))
                    .phaseAnimator([0, 1], trigger: trigger) { view, phase in
                        view.offset(x: phase == 1 ? cos(angle) * 46 : 0,
                                    y: phase == 1 ? sin(angle) * 46 : 0)
                            .opacity(phase == 1 ? 0 : (trigger > 0 ? 1 : 0))
                    } animation: { _ in .easeOut(duration: 0.6) }
            }
        }
        .allowsHitTesting(false)
    }
}
