import Foundation

// MARK: - 手表待传语音持久仓（watchOS）
/// 为什么不用 temporaryDirectory：WCSessionFileTransfer 要求源文件在传输完成前一直存在，
/// 后台排队可跨小时/天，其间 tmp 可能被系统清空 → 传输失败且文件已没，录音两端永久丢失。
/// 因此录音落到 Application Support/PendingVoice/（持久，不会被系统回收）。
///
/// 幂等机制：每个待传 m4a 的文件名 stem 即稳定 localId，并配一份同名 .json 边车
/// （编码后的 WatchRecordRequest，随传输 metadata 一并送达 iPhone 用于去重）。
/// 传输成功(didFinish error==nil)才删文件+边车；失败保留，激活/进前台时对账重新入队。
///
/// nonisolated（enum 纯静态、仅 FileManager 计算，无共享可变状态）：可从任意隔离域调用。
nonisolated enum WatchPendingVoiceStore {
    /// 持久目录：Application Support/PendingVoice/。首次创建（含中间目录）。
    /// Application Support 在 watchOS 首次访问可能不存在，withIntermediateDirectories 一并建出。
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingVoice", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 新建一个待传语音文件 URL；stem 即 localId（稳定幂等键），供录音器直接写入。
    static func newFileURL(localId: String = UUID().uuidString) -> URL {
        directory.appendingPathComponent("\(localId).m4a")
    }

    /// 从待传文件 URL 反推 localId（= stem）。
    static func localId(forFile fileURL: URL) -> String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    private static func sidecarURL(forFile fileURL: URL) -> URL {
        fileURL.deletingPathExtension().appendingPathExtension("json")
    }

    /// 写边车（记录意图）。传输前调用，保证失败后能据此原样重发（含稳定 localId、时长、身份）。
    static func writeSidecar(_ request: WatchRecordRequest, forFile fileURL: URL) {
        guard let data = WatchLink.encode(request) else { return }
        try? data.write(to: sidecarURL(forFile: fileURL), options: .atomic)
    }

    /// 读边车 → 记录意图（对账重发时用）。
    static func readSidecar(forFile fileURL: URL) -> WatchRecordRequest? {
        guard let data = try? Data(contentsOf: sidecarURL(forFile: fileURL)) else { return nil }
        return WatchLink.decode(WatchRecordRequest.self, from: data)
    }

    /// 传输成功后清理文件 + 边车。
    static func remove(fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: sidecarURL(forFile: fileURL))
    }

    /// 目录里所有「带边车」的待传 m4a（对账用）。
    /// 只认有边车的文件：无边车者（极小概率：录音停止后、写边车前 App 被杀）缺少 localId/时长/身份，
    /// 无法安全重发，保留不动（可靠性优先，不误删可能是有效录音的文件）。
    static func pendingFiles() -> [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "m4a" && fm.fileExists(atPath: sidecarURL(forFile: $0).path) }
    }
}
