import SwiftUI
import UIKit

// MARK: - 抬腕即布布（概览页）
/// 抬腕 3 秒内要完成的事：看到脸 → 知道多大了 → 心情变好。
/// 所以这页的主角是照片，不是数据格——数据全部降级到照片下面一行小字。
struct WatchOverviewView: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 「陪伴第 N 天」当前显示值。进场从 N-10 滚到 N（numericText），
    /// 抬腕那一刻这个数字是数出来的，不是贴上去的。
    @State private var shownDays = 0
    /// 本次进场选中的英雄照片（小时轮换）。
    @State private var heroPhoto: UIImage?

    private var snap: WatchSnapshot? { connector.snapshot }
    private var name: String { snap?.childName ?? "布布" }
    private var birthday: Date? { snap?.birthday }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                heroCard
                if let birthday {
                    ageBlock(birthday)
                } else {
                    onboardingHint
                }
            }
        }
        .background(WatchSpaceBackground(accent: WatchTheme.rose))
        .onAppear { refresh() }
        .onChange(of: connector.photoVersion) { refresh() }
        .onChange(of: snap?.updatedAt) { refresh() }
    }

    // MARK: 英雄照片卡

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            if let heroPhoto {
                KenBurnsPhoto(image: heroPhoto, animated: !dimmed)
            } else {
                // 没有照片（新装/还没收到照片包）：头像 + 深空渐变兜底，不出现空白灰块。
                ZStack {
                    LinearGradient(colors: [WatchTheme.rose.opacity(0.45), WatchTheme.lav.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    avatarView(size: 56)
                }
            }
            // 底部渐变压字，照片再亮名字也读得出。
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
            HStack(spacing: 6) {
                if heroPhoto != nil { avatarRing }
                Text(name)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .padding(10)
        }
        .frame(height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 头像 + 生日进度环。生日前 7 天环变金色并开始呼吸。
    private var avatarRing: some View {
        let progress = birthday.map(birthdayProgress) ?? 0
        let soon = birthday.map { AgeCalculator.daysUntilNextBirthday(birthday: $0) <= 7 } ?? false
        return avatarView(size: 30)
            .overlay {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(soon ? WatchTheme.butter : WatchTheme.rose,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .phaseAnimator([1.0, 0.6], trigger: soon) { view, phase in
                        view.opacity(soon && !dimmed ? phase : 1)
                    } animation: { _ in .easeInOut(duration: 1.2).repeatForever(autoreverses: true) }
            }
    }

    private func avatarView(size: CGFloat) -> some View {
        Group {
            if let data = snap?.avatarData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text("👶").font(.system(size: size * 0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
    }

    private func birthdayProgress(_ b: Date) -> Double {
        let d = Double(AgeCalculator.daysUntilNextBirthday(birthday: b))
        return max(0, min(1, (365 - d) / 365))
    }

    // MARK: 活的年龄行

    private func ageBlock(_ birthday: Date) -> some View {
        let days = AgeCalculator.daysSinceBirth(birthday: birthday)
        let toBirthday = AgeCalculator.daysUntilNextBirthday(birthday: birthday)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("陪伴第")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(shownDays)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(WatchTheme.rose)
                    .contentTransition(.numericText(value: Double(shownDays)))
                Text("天")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(AgeCalculator.ageDescription(birthday: birthday, at: .now))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            HStack(spacing: 8) {
                if toBirthday == 0 {
                    chip("🎂 今天生日快乐！", tint: WatchTheme.butter)
                } else {
                    chip("🎂 \(toBirthday) 天后生日", tint: WatchTheme.butter)
                }
                if let s = snap, s.totalMilestones > 0 {
                    chip("⭐ \(s.achievedMilestones)/\(s.totalMilestones)", tint: WatchTheme.lav)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .onAppear { animateDays(to: days) }
        .onChange(of: days) { animateDays(to: days) }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
    }

    private var onboardingHint: some View {
        Text("打开手机上的布布时光机\n建立档案后，这里就有内容啦")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }

    // MARK: 数据

    private func animateDays(to days: Int) {
        // AOD 下不做进场动画（降亮渲染预算内不该跑 spring）。
        guard !dimmed else { shownDays = days; return }
        shownDays = max(0, days - 10)
        withAnimation(.spring(duration: 1.1)) { shownDays = days }
    }

    /// 从有照片的回忆里按小时轮换选一张（同一小时内稳定，不闪换）。
    private func refresh() {
        let withPhotos = (snap?.memories ?? []).compactMap(\.photoFileName)
        guard !withPhotos.isEmpty else { heroPhoto = nil; return }
        let hourIndex = Int(Date.now.timeIntervalSince1970 / 3600)
        for offset in 0..<withPhotos.count {
            let name = withPhotos[(hourIndex + offset) % withPhotos.count]
            if let data = WatchPhotoStore.data(for: name), let img = UIImage(data: data) {
                heroPhoto = img
                return
            }
        }
        heroPhoto = nil
    }
}

// MARK: - Ken Burns 照片
/// 20 秒一个来回的缓慢推近（1.0 → 1.06）。用 keyframeAnimator 不用 Timer——
/// 离屏即停，不留常驻定时器。
struct KenBurnsPhoto: View {
    let image: UIImage
    var animated = true

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .modifier(KenBurnsEffect(animated: animated))
                .clipped()
        }
    }
}

private struct KenBurnsEffect: ViewModifier {
    let animated: Bool

    func body(content: Content) -> some View {
        if animated {
            content.keyframeAnimator(initialValue: 1.0, repeating: true) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1.06, duration: 10)
                    LinearKeyframe(1.0, duration: 10)
                }
            }
        } else {
            content
        }
    }
}
