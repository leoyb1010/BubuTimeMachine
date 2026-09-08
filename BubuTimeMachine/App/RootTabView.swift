import SwiftUI
import SwiftData

// MARK: - 根导航
/// iPhone 使用系统 Liquid Glass Tab；iPad/可调整宽窗口由 sidebarAdaptable 自动切成侧栏。
/// 记录不是第五个页面，而是跨页面一直可用的底部附件/侧栏动作。
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(BubuRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection = 0
    @State private var quickCaptureTrigger = 0
    @State private var timelinePath: [UUID] = []

    private var isWide: Bool { BubuAdaptive.isWide(sizeClass) }

    private var maximumSelectableTab: Int {
        #if targetEnvironment(macCatalyst)
        4
        #else
        3
        #endif
    }

    var body: some View {
        tabsWithRecordAccessory
            // 切 Tab 此前手上没有任何回音：内容过渡做了、记录按钮的轻触做了，
            // 唯独最高频的这个动作是哑的。bubuSensoryFeedback 全仓只用了 2 处，严重低用。
            .bubuSensoryFeedback(.selection, trigger: selection)
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewSidebarHeader {
                Label("布布时光机", systemImage: "book.pages.fill")
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(env.theme.theme.textAccent)
                    .padding(.vertical, 8)
            }
            .tabViewSidebarBottomBar {
                if isWide {
                    Button(action: openQuickCapture) {
                        Label("记一笔", systemImage: "plus.circle.fill")
                            .font(BubuTheme.Font.body.weight(.semibold))
                            .foregroundStyle(env.theme.theme.textAccent)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("root.record")
                }
            }
            .onChange(of: isWide) { _, wide in
                if !wide && selection > 3 { selection = 1 }
            }
            .background { keyboardShortcuts }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .ignoresSafeArea(.keyboard)
            .onAppear {
                #if DEBUG
                if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-tab"),
                   i + 1 < ProcessInfo.processInfo.arguments.count,
                   let tab = Int(ProcessInfo.processInfo.arguments[i + 1]) {
                    selection = min(max(tab, 0), maximumSelectableTab)
                }
                if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-openurl"),
                   i + 1 < ProcessInfo.processInfo.arguments.count,
                   let url = URL(string: ProcessInfo.processInfo.arguments[i + 1]) {
                    router.handle(url)
                }
                if ProcessInfo.processInfo.arguments.contains("-uitest-open-first-moment") {
                    openFirstMomentForUITest()
                }
                #endif
                consumePendingRoute()
            }
            .onChange(of: router.pendingTab) { _, _ in consumePendingRoute() }
            .onChange(of: router.pendingQuickCapture) { _, _ in consumePendingRoute() }
            .onChange(of: router.pendingEntryID) { _, _ in openPendingTimelineEntryIfReady() }
            .onChange(of: selection) { _, tab in
                if tab == 1 { openPendingTimelineEntryIfReady() }
            }
    }

    @ViewBuilder
    private var tabsWithRecordAccessory: some View {
        if #available(iOS 26.1, *) {
            tabs.tabViewBottomAccessory(isEnabled: !isWide) {
                BubuRecordAccessory { openQuickCapture() }
            }
        } else if !isWide {
            tabs.tabViewBottomAccessory {
                BubuRecordAccessory { openQuickCapture() }
            }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("首页", systemImage: "house.fill", value: 0) {
                NavigationStack {
                    CaptureHomeView(openTimeline: { selection = 1 },
                                    quickCaptureTrigger: quickCaptureTrigger)
                }
                .bubuTabContentTransition(isActive: selection == 0)
            }

            Tab("时光", systemImage: "clock.fill", value: 1) {
                NavigationStack(path: $timelinePath) {
                    TimelineView()
                        .onAppear { openPendingTimelineEntryIfReady() }
                }
                    .bubuTabContentTransition(isActive: selection == 1)
            }

            Tab("成长", systemImage: "chart.xyaxis.line", value: 2) {
                NavigationStack { GrowthHomeView() }
                    .bubuTabContentTransition(isActive: selection == 2)
            }

            Tab("魔法屋", systemImage: "wand.and.stars.inverse", value: 3) {
                NavigationStack { AIStudioHomeView() }
                    .bubuTabContentTransition(isActive: selection == 3)
            }

            #if targetEnvironment(macCatalyst)
            Tab("档案馆", systemImage: "archivebox.fill", value: 4) {
                NavigationStack { MacArchiveWorkspaceView() }
            }
            #endif
        }
        .tint(env.theme.theme.tabTint)
        .accessibilityIdentifier("root.tabs")
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { selection = 0 }.keyboardShortcut("1", modifiers: .command)
            Button("") { selection = 1 }.keyboardShortcut("2", modifiers: .command)
            Button("") { selection = 2 }.keyboardShortcut("3", modifiers: .command)
            Button("") { selection = 3 }.keyboardShortcut("4", modifiers: .command)
            #if targetEnvironment(macCatalyst)
            Button("") { selection = 4 }.keyboardShortcut("5", modifiers: .command)
            #endif
            Button("") { openQuickCapture() }.keyboardShortcut("n", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func openQuickCapture() {
        selection = 0
        quickCaptureTrigger += 1
        BubuHaptics.tapLight()
    }

    private func consumePendingRoute() {
        if let tab = router.pendingTab {
            selection = min(max(tab, 0), 3)
            router.pendingTab = nil
        }
        if router.pendingEntryID != nil {
            selection = 1
            // 具体详情必须等时光 NavigationStack 真正出现并注册 destination 后再推入。
            // 冷启动时在这里立刻写 path 会得到一帧没有 destination 的白屏。
        }
        if router.pendingQuickCapture {
            selection = 0
            router.pendingQuickCapture = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                quickCaptureTrigger += 1
            }
        }
    }

    private func openPendingTimelineEntryIfReady() {
        guard selection == 1, let entryID = router.pendingEntryID else { return }
        router.pendingEntryID = nil
        Task { @MainActor in
            // 原生 Tab 切换与 NavigationStack 挂载分两次 transaction；等它完成后再导航。
            try? await Task.sleep(for: .milliseconds(650))
            guard selection == 1 else { return }
            timelinePath = [entryID]
        }
    }

    #if DEBUG
    private func openFirstMomentForUITest() {
        Task { @MainActor in
            // App 外层 .task 会先注入测试种子；这里略等一拍后从真实 SwiftData 取 id，
            // 因此测试不依赖模拟器是否残留上一轮随机 UUID。
            try? await Task.sleep(for: .milliseconds(500))
            var descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate { !$0.isArchived },
                sortBy: [SortDescriptor(\Entry.happenedAt, order: .reverse)])
            descriptor.fetchLimit = 1
            guard let entryID = try? modelContext.fetch(descriptor).first?.id else { return }
            router.pendingTab = 1
            router.pendingEntryID = entryID
        }
    }
    #endif
}

/// 系统底部附件会在 Tab 展开/收缩间变形；内容跟随 placement 调整，避免压缩时塞两行文字。
private struct BubuRecordAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(AppEnvironment.self) private var env
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(BubuTheme.Font.scaled(20, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, env.theme.theme.primary)
                if placement == .expanded {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("记录此刻")
                            .font(BubuTheme.Font.body.weight(.semibold))
                            .foregroundStyle(BubuTheme.Color.warmBrown)
                        Text("照片、声音和一句话一起收好")
                            .font(BubuTheme.Font.caption)
                            .foregroundStyle(BubuTheme.Color.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(BubuTheme.Font.caption.weight(.bold))
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                } else {
                    Text("记录")
                        .font(BubuTheme.Font.caption.weight(.bold))
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: placement == .expanded ? .infinity : nil,
                   minHeight: placement == .expanded ? 48 : 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("root.record")
        .accessibilityLabel("记录此刻")
    }
}
