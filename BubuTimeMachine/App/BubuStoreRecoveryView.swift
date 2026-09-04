import SwiftUI
import UIKit

// MARK: - 数据保护模式挡页
/// store 打不开时（`BubuStoreHealth.loadFailed`）挡在主界面之前的全屏说明页。
///
/// 为什么必须挡：降级到内存容器本身是对的（比 fatalError 好太多），但降级之后
/// 主界面看起来只是「一个还没记过东西的新家」——首页空态甚至写着「记第一笔」，
/// 主动邀请用户从头开始。妈妈重建一个布布档案、记一整天，退出 App 全丢；
/// 更糟的是若这期间同步跑通一轮，假的 ChildProfile/FamilyMember 会被推上服务器，
/// 污染全家其它设备。
///
/// 磁盘上的 store 原样保留、一个字节都没动，所以这里的首要动作是**把它导出来**。
struct BubuStoreRecoveryView: View {
    /// 用户已明确知情并选择临时使用（本次进程有效，不落盘——下次启动仍然拦）。
    @State private var bypassed = false
    @State private var showBypassConfirm = false
    @State private var exporting = false
    @State private var exportError: String?
    @State private var shareURL: URL?

    let onContinue: () -> Void

    var body: some View {
        if bypassed {
            Color.clear.onAppear { onContinue() }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 22) {
                BubuMascotBadge(size: 92, expression: .shy)
                    .padding(.top, 30)

                VStack(spacing: 10) {
                    Text("布布的记录暂时打不开")
                        .font(BubuTheme.Font.title)
                        .foregroundStyle(BubuTheme.Color.warmBrown)
                        .multilineTextAlignment(.center)
                    Text("这台手机上的数据库这次没能打开。\n**你的记录没有丢** —— 它们还完整地在手机里，一个字节都没动。")
                        .font(BubuTheme.Font.body)
                        .foregroundStyle(BubuTheme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    row("1", "先把数据导出来", "生成一个压缩包，发给自己存好。这是最重要的一步。")
                    row("2", "再试一次", "完全退出 App 再打开。临时占用导致的失败重启就好了。")
                    row("3", "还是不行就找回来", "把导出的压缩包留着，装回旧版本或在电脑上都能读。")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BubuTheme.Color.card,
                            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card, style: .continuous))

                Button {
                    Task { await exportStore() }
                } label: {
                    HStack(spacing: 8) {
                        if exporting { ProgressView().tint(.white) }
                        Text(exporting ? "正在打包…" : "导出数据（推荐先做）")
                            .font(BubuTheme.Font.headline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(BubuTheme.Color.primary, in: Capsule())
                }
                .buttonStyle(BubuPressableStyle())
                .disabled(exporting)

                if let exportError {
                    Text(exportError)
                        .font(BubuTheme.Font.caption)
                        .foregroundStyle(BubuTheme.Color.deepRose)
                        .multilineTextAlignment(.center)
                }

                Button("仍要临时使用（这次记的东西不会保存）") {
                    showBypassConfirm = true
                }
                .font(BubuTheme.Font.caption)
                .foregroundStyle(BubuTheme.Color.secondaryText)
                .frame(minHeight: 44)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(BubuTheme.Color.background.ignoresSafeArea())
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .alert("这次记的东西不会保存", isPresented: $showBypassConfirm) {
            Button("我知道，先用一下", role: .destructive) {
                BubuHaptics.warning()
                bypassed = true
            }
            Button("先去导出", role: .cancel) {}
        } message: {
            Text("数据库没打开，App 现在跑在临时内存里。你现在记的照片和文字，退出 App 就会消失，也可能被同步到家人的手机上造成混乱。建议先导出数据。")
        }
    }

    private func row(_ index: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index)
                .font(BubuTheme.Font.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(BubuTheme.Color.primary, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BubuTheme.Font.headline)
                    .foregroundStyle(BubuTheme.Color.warmBrown)
                Text(detail)
                    .font(BubuTheme.Font.caption)
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 把 store 三件套 + 迁移备份目录清单打包成 zip 交给系统分享。
    /// 不解析、不修复——只是原样搬出来，越少动越好。
    @MainActor
    private func exportStore() async {
        exporting = true
        exportError = nil
        defer { exporting = false }

        let source = BubuStorage.storeURL
        let stamp = StoreBackupStamp.now()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("布布数据库备份_\(stamp)", isDirectory: true)

        do {
            let result = try await Task.detached(priority: .userInitiated) { () -> URL in
                let fm = FileManager.default
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                var copied = false
                for suffix in ["", "-wal", "-shm"] {
                    let src = URL(fileURLWithPath: source.path + suffix)
                    guard fm.fileExists(atPath: src.path) else { continue }
                    try fm.copyItem(at: src, to: folder.appendingPathComponent(src.lastPathComponent))
                    copied = true
                }
                guard copied else { throw CocoaError(.fileNoSuchFile) }
                let readme = """
                布布时光机 · 数据库原样备份
                导出时间：\(stamp)

                这是 SwiftData / SQLite 数据库文件本体，未做任何解析或修复。
                .store 是主文件，-wal 与 -shm 是日志与共享内存，三个一起才完整，请勿单独删除。

                恢复方式：把三个文件放回同名位置，或在电脑上用任意 SQLite 工具打开 .store 读取。
                """
                try readme.write(to: folder.appendingPathComponent("请先读我.txt"),
                                 atomically: true, encoding: .utf8)
                return try Self.zip(folder: folder)
            }.value
            try? FileManager.default.removeItem(at: folder)
            BubuHaptics.success()
            shareURL = result
        } catch {
            try? FileManager.default.removeItem(at: folder)
            exportError = "导出失败：\(error.localizedDescription)。可以在「文件」App 里找到布布时光机的文件夹手动拷贝。"
        }
    }

    /// 与 ExportView 同款：系统 ditto 压缩，沙盒内可用，不引第三方。
    nonisolated private static func zip(folder: URL) throws -> URL {
        let zipURL = folder.deletingPathExtension().appendingPathExtension("zip")
        try? FileManager.default.removeItem(at: zipURL)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: URL?
        var thrown: Error?
        coordinator.coordinate(readingItemAt: folder, options: [.forUploading], error: &coordError) { tmpURL in
            do {
                try FileManager.default.moveItem(at: tmpURL, to: zipURL)
                result = zipURL
            } catch { thrown = error }
        }
        if let coordError { throw coordError }
        if let thrown { throw thrown }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return result
    }
}

// MARK: - 让 URL 能直接喂给 .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private enum StoreBackupStamp {
    /// 文件名友好的时间戳。ISO8601 的 .withTime 会带冒号，冒号在 Files/分享链路上会被改写，
    /// 这里直接用无分隔的形式。
    static func now() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now)
    }
}
