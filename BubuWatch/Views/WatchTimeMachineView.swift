import SwiftUI
import WatchKit

/// Only this screen owns the crown. System Back stays visible at every position.
struct WatchTimeMachineView: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var selection = WatchBrowseSelection()
    @State private var crownValue = 0.0
    @State private var visible = false
    @FocusState private var crownFocused: Bool
    private var memories: [WatchMemory] { WatchReadModel.memories(from: connector.snapshot) }
    private var quietMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        reduceMotion || dimmed || ProcessInfo.processInfo.arguments.contains("-watch-reduce-motion")
        #else
        reduceMotion || dimmed
        #endif
    }

    var body: some View {
        // GeometryReader runs its content later. Freeze the same value array used
        // for the empty check so a new/empty snapshot cannot invalidate the index.
        let items = memories
        let position = selection.index(in: items)
        Group {
            if items.isEmpty {
                ScrollView {
                    WatchReadingEmptyState(title: "回忆还在路上", message: "打开 iPhone 上的布布时光机，照片和故事会自动同步。离线时也能看已收到的回忆。")
                }
            } else {
                GeometryReader { geometry in
                    let memory = items[position]
                    ZStack {
                        NavigationLink(value: WatchReadingRoute.story(memory)) {
                            WatchPhotoSurface(fileName: memory.photoFileName, emoji: memory.moodEmoji ?? "🌷", fitsPhoto: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .id(memory.id)
                            .transition(.opacity.combined(with: .offset(y: 2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("阅读\(memory.dateText)的完整故事")
                        .accessibilityValue(memory.note)
                        .accessibilityIdentifier("watch.story")
                        VStack {
                            HStack {
                                Text(memory.isOnThisDay ? "✨ \(memory.dateText)" : memory.dateText)
                                    .font(.caption.bold()).foregroundStyle(WatchTheme.butter)
                                Spacer(minLength: 4)
                                Text("\(position + 1) / \(items.count)").font(.caption).monospacedDigit()
                            }
                            .padding(6).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                            .allowsHitTesting(false)
                            .animation(nil, value: selection.selectedID)
                            Spacer(minLength: 0)
                            HStack(spacing: 6) {
                                pageButton("上一段", icon: "chevron.left", delta: -1, disabled: position == 0)
                                NavigationLink(value: WatchReadingRoute.story(memory)) {
                                    ViewThatFits(in: .horizontal) {
                                        Label("全文", systemImage: "text.alignleft").fixedSize()
                                        Image(systemName: "text.alignleft")
                                    }
                                    .font(.caption.bold())
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(.black.opacity(0.72), in: Capsule())
                                }.buttonStyle(.plain).accessibilityLabel("阅读完整故事")
                                pageButton("下一段", icon: "chevron.right", delta: 1, disabled: position == items.count - 1)
                            }
                            .animation(nil, value: selection.selectedID)
                        }
                        .padding(7)
                    }
                    .frame(width: max(0, geometry.size.width - 8), height: geometry.size.height)
                    .padding(.horizontal, 4)
                    .animation(quietMotion ? nil : .easeOut(duration: 0.18), value: selection.selectedID)
                    .focusable(visible)
                    .focused($crownFocused)
                    .digitalCrownRotation($crownValue, from: 0, through: Double(max(items.count - 1, 1)),
                                          by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                }
            }
        }
        .navigationTitle("回忆")
        .background(WatchReadingBackground())
        .onAppear { visible = true; reconcile(); crownFocused = true }
        .onDisappear { visible = false; crownFocused = false }
        .onChange(of: memories.map(\.id)) { reconcile() }
        .onChange(of: crownValue) { _, value in
            guard visible else { return }
            selection.select(crownValue: value, in: memories)
        }
    }

    private func reconcile() {
        selection.reconcile(with: memories)
        crownValue = Double(selection.index(in: memories))
        if visible { crownFocused = !memories.isEmpty }
    }

    private func pageButton(_ title: String, icon: String, delta: Int, disabled: Bool) -> some View {
        Button {
            selection.step(delta, in: memories)
            crownValue = Double(selection.index(in: memories))
            WKInterfaceDevice.current().play(.click)
        } label: {
            Image(systemName: icon).font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.72), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(disabled ? .gray : WatchTheme.rose)
        .disabled(disabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(delta < 0 ? "watch.previous" : "watch.next")
    }
}
