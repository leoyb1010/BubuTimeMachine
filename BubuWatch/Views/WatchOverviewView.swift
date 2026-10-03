import SwiftUI
import UIKit

/// The whole first viewport is one portrait and two useful destinations.
struct WatchOverviewView: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now
    private var snapshot: WatchSnapshot? { connector.snapshot }
    private var memories: [WatchMemory] { WatchReadModel.memories(from: snapshot) }
    private var hero: WatchMemory? {
        memories.first(where: { $0.isOnThisDay && $0.photoFileName != nil })
            ?? memories.first(where: { $0.photoFileName != nil }) ?? memories.first
    }
    private var compactProbe: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-watch-compact-probe")
        #else
        false
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    if compactProbe {
                        HStack(spacing: 8) {
                            WatchPhotoSurface(fileName: nil, avatarData: snapshot?.avatarData)
                                .frame(width: 42, height: 42).clipShape(Circle())
                            identity
                            Spacer(minLength: 0)
                        }
                    }
                    NavigationLink(value: WatchReadingRoute.memories) {
                        ZStack(alignment: .bottomLeading) {
                            WatchPhotoSurface(fileName: hero?.photoFileName, avatarData: snapshot?.avatarData, fitsPhoto: true)
                            if !compactProbe {
                                LinearGradient(colors: [.clear, .black.opacity(0.8)],
                                               startPoint: .center, endPoint: .bottom)
                                HStack(spacing: 6) {
                                    if snapshot?.avatarData != nil {
                                        WatchPhotoSurface(fileName: nil, avatarData: snapshot?.avatarData)
                                            .frame(width: 30, height: 30).clipShape(Circle())
                                            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                                    }
                                    identity
                                }
                                .padding(10)
                            }
                        }
                        .frame(height: compactProbe ? 88 : max(96, min(geometry.size.width * 0.75, geometry.size.height - 76)))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("看\(snapshot?.childName ?? "布布")的回忆照片")
                    HStack(spacing: 8) {
                        destination("回忆", icon: "photo.stack", route: .memories, color: WatchTheme.rose)
                        destination("最近", icon: "book.closed", route: .recent, color: WatchTheme.lav)
                    }
                    if let birthday = snapshot?.birthday {
                        Text("陪伴第 \(AgeCalculator.daysSinceBirth(birthday: birthday, at: now)) 天")
                            .font(.caption2).foregroundStyle(WatchTheme.rose.opacity(0.9))
                    }
                    if snapshot == nil {
                        Text("先打开 iPhone 上的布布时光机\n回忆会自动来到这里")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else if let updated = snapshot?.updatedAt, now.timeIntervalSince(updated) >= 7200 {
                        Text("离线回忆 · 更新于 \(updated.formatted(.dateTime.month().day().hour().minute()))")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("时光机")
        .background(WatchReadingBackground())
        .onAppear { now = .now }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot?.childName ?? "布布")
                .font(.title3.bold()).fontDesign(.rounded).lineLimit(1).minimumScaleFactor(0.75)
            if let birthday = snapshot?.birthday {
                Text(AgeCalculator.ageDescription(birthday: birthday, at: now))
                    .font(.caption).foregroundStyle(.white.opacity(0.9))
            } else {
                Text("把她放在腕间").font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
        .foregroundStyle(.white)
    }

    private func destination(_ title: String, icon: String, route: WatchReadingRoute, color: Color) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: icon).font(.footnote.weight(.semibold)).fontDesign(.rounded)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).foregroundStyle(color)
        .accessibilityIdentifier(route == .memories ? "watch.memories" : "watch.recent")
    }
}
