import Foundation

// MARK: - 全量档案导出
/// 导出 index.html + data.json + media/，覆盖照片、视频、语音、家人合奏与成长之声。
nonisolated struct ArchiveExporter: Sendable {
    let mediaStore: MediaStore

    struct ExportInput: Sendable {
        let childName: String
        let birthday: Date
        let entries: [EntrySnapshot]
        let milestones: [MilestoneSnapshot]
        let voiceMemos: [VoiceMemoSnapshot]
        let healthRecords: [HealthRecordSnapshot]
        let firstTimes: [FirstTimeSnapshot]
        let timeCapsules: [TimeCapsuleSnapshot]
    }

    struct EntrySnapshot: Sendable {
        let happenedAt: Date
        let authorRole: String
        let note: String?
        let firstPersonNote: String?
        let locationName: String?
        let moodEmoji: String?
        let ageDescription: String
        let media: [MediaSnapshot]
        let voiceNotes: [VoiceSnapshot]
        let comments: [CommentSnapshot]
        let tags: [String]
    }

    struct MediaSnapshot: Sendable {
        let fileName: String
        let type: String
    }

    struct VoiceSnapshot: Sendable {
        let fileName: String
        let duration: Double
        let authorRole: String
        let transcript: String?
    }

    struct CommentSnapshot: Sendable {
        let authorRole: String
        let text: String?
        let voiceFileName: String?
        let voiceDuration: Double
        let createdAt: Date
    }

    struct VoiceMemoSnapshot: Sendable {
        let kind: String
        let fileName: String?
        let transcript: String?
        let ageYears: Int?
        let recordedAt: Date
        let durationSeconds: Double?
    }

    struct MilestoneSnapshot: Sendable {
        let title: String
        let emoji: String
        let achieved: Bool
        let ageDescription: String?
    }

    struct HealthRecordSnapshot: Sendable {
        let kind: String
        let title: String
        let detail: String?
        let recordedAt: Date
        let amountText: String?
        let reaction: String?
    }

    struct FirstTimeSnapshot: Sendable {
        let what: String
        let happenedAt: Date
        let confirmed: Bool
    }

    struct TimeCapsuleSnapshot: Sendable {
        let title: String
        let fromRole: String
        let unlockAt: Date
        let isLocked: Bool
        let coverEmoji: String?
    }

    func export(_ input: ExportInput) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("布布的一生_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        let mediaDir = root.appendingPathComponent("media", isDirectory: true)
        try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        var names = Set<String>()
        for entry in input.entries {
            entry.media.forEach { names.insert($0.fileName) }
            entry.voiceNotes.forEach { names.insert($0.fileName) }
            entry.comments.compactMap(\.voiceFileName).forEach { names.insert($0) }
        }
        input.voiceMemos.compactMap(\.fileName).forEach { names.insert($0) }
        for name in names {
            let src = mediaStore.mediaURL(for: name)
            let dest = mediaDir.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: src, to: dest)
            }
        }

        try Self.buildJSON(input).write(to: root.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
        try Self.buildHTML(input).write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        return root
    }

    private static func buildHTML(_ input: ExportInput) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年M月d日"

        let milestones = input.milestones.filter(\.achieved).map { item in
            "<li>\(item.emoji) \(esc(item.title)) <em>\(esc(item.ageDescription ?? ""))</em></li>"
        }.joined()

        let voiceMemos = input.voiceMemos.sorted { $0.recordedAt > $1.recordedAt }.map { memo in
            let title = memo.kind == "childVoice" ? "布布的声音" : "家人对她说"
            let audio = memo.fileName.map { "<audio controls src=\"media/\(urlEsc($0))\"></audio>" } ?? ""
            let transcript = memo.transcript.map { "<p>\(esc($0))</p>" } ?? ""
            let age = memo.ageYears.map { "\($0)岁" } ?? "未知年龄"
            return "<div class=\"memo\"><b>\(title)</b><span>\(df.string(from: memo.recordedAt)) · \(age)</span>\(audio)\(transcript)</div>"
        }.joined()

        let health = input.healthRecords.sorted { $0.recordedAt > $1.recordedAt }.map { item in
            let detail = item.detail.map { "<p>\(esc($0))</p>" } ?? ""
            let amount = item.amountText.map { " · \(esc($0))" } ?? ""
            let reaction = item.reaction.map { " · 反应：\(esc($0))" } ?? ""
            return "<li><b>\(esc(item.title))</b><span>\(df.string(from: item.recordedAt)) · \(esc(item.kind))\(amount)\(reaction)</span>\(detail)</li>"
        }.joined()

        let firstTimes = input.firstTimes.sorted { $0.happenedAt > $1.happenedAt }.map { item in
            "<li>✨ \(esc(item.what)) <em>\(df.string(from: item.happenedAt))</em></li>"
        }.joined()

        let capsules = input.timeCapsules.sorted { $0.unlockAt < $1.unlockAt }.map { item in
            let state = item.isLocked ? "未到开启时间" : "已开启"
            let emoji = item.coverEmoji ?? "💌"
            return "<li>\(esc(emoji)) \(esc(item.title)) · \(esc(item.fromRole)) <em>\(df.string(from: item.unlockAt)) · \(state)</em></li>"
        }.joined()

        let cards = input.entries.sorted { $0.happenedAt > $1.happenedAt }.map { entry in
            let media = entry.media.map(mediaHTML).joined()
            let voices = entry.voiceNotes.map { voice in
                let transcript = voice.transcript.map { "<p>\(esc($0))</p>" } ?? ""
                return "<div class=\"audio\"><span>🎙️ \(esc(voice.authorRole))</span><audio controls src=\"media/\(urlEsc(voice.fileName))\"></audio>\(transcript)</div>"
            }.joined()
            let comments = entry.comments.sorted { $0.createdAt < $1.createdAt }.map { comment in
                let text = comment.text.map { "<p>\(esc($0))</p>" } ?? ""
                let audio = comment.voiceFileName.map { "<audio controls src=\"media/\(urlEsc($0))\"></audio>" } ?? ""
                return "<div class=\"comment\"><b>\(esc(comment.authorRole))</b>\(text)\(audio)</div>"
            }.joined()
            let mood = entry.moodEmoji ?? ""
            let place = entry.locationName.map { " · 📍\(esc($0))" } ?? ""
            let note = entry.note.map { "<p class=\"note\">\(esc($0))</p>" } ?? ""
            let fp = entry.firstPersonNote.map { "<p class=\"fp\">「\(esc($0))」</p>" } ?? ""
            let tags = entry.tags.isEmpty ? "" : "<div class=\"tags\">" + entry.tags.map { "<span>#\(esc($0))</span>" }.joined() + "</div>"
            let voiceBlock = voices.isEmpty ? "" : "<div class=\"voices\"><h3>语音记录</h3>\(voices)</div>"
            let commentBlock = comments.isEmpty ? "" : "<div class=\"comments\"><h3>家人合奏</h3>\(comments)</div>"
            return """
            <div class="card">
              <div class="meta">\(mood) \(df.string(from: entry.happenedAt)) · \(esc(entry.authorRole))\(place) · <em>\(esc(entry.ageDescription))</em></div>
              <div class="media">\(media)</div>
              \(note)\(fp)\(tags)\(voiceBlock)\(commentBlock)
            </div>
            """
        }.joined()

        return """
        <!DOCTYPE html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(esc(input.childName))的一生</title>
        <style>
        :root{--pink:#F28C9E;--brown:#5C4D47;--bg:#FBF6F0}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--brown);font-family:-apple-system,"PingFang SC",sans-serif;line-height:1.7}header{text-align:center;padding:48px 20px 24px}header h1{font-size:34px;margin:0}header p{color:#8a7d76;margin:6px 0}.wrap{max-width:760px;margin:0 auto;padding:0 16px 80px}.card,.milestones,.voice-memos{background:#fff;border-radius:18px;padding:18px 20px;margin:16px 0;box-shadow:0 4px 16px rgba(0,0,0,.05)}h2{font-size:18px;margin:0 0 10px}.meta{font-size:13px;color:#8a7d76;margin-bottom:10px}.meta em,.milestones em{color:var(--pink);font-style:normal}.media{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px}.media img,.media video{width:100%;aspect-ratio:1;object-fit:cover;border-radius:10px;background:#eee}.note{font-size:17px;margin:12px 0 4px}.fp{color:var(--pink);font-style:italic}.tags span{display:inline-block;background:rgba(242,140,158,.1);color:var(--pink);border-radius:20px;padding:2px 10px;font-size:12px;margin:4px 4px 0 0}h3{font-size:15px;margin:14px 0 6px}.audio,.comment,.memo{border-top:1px solid #f1e8e1;padding-top:10px;margin-top:10px}.audio audio,.comment audio,.memo audio{width:100%;margin-top:6px}.memo span{display:block;color:#8a7d76;font-size:12px}footer{text-align:center;color:#b0a59e;font-size:13px;padding:30px}
        </style></head><body><header><h1>\(esc(input.childName))的一生</h1><p>出生于 \(df.string(from: input.birthday))</p><p>共 \(input.entries.count) 个瞬间 · 由布布时光机生成</p></header><div class="wrap">
        \(milestones.isEmpty ? "" : "<div class=\"milestones\"><h2>🌟 成长里程碑</h2><ul>\(milestones)</ul></div>")
        \(firstTimes.isEmpty ? "" : "<div class=\"milestones\"><h2>✨ 人生第一次</h2><ul>\(firstTimes)</ul></div>")
        \(health.isEmpty ? "" : "<div class=\"voice-memos\"><h2>🩺 健康照护</h2><ul>\(health)</ul></div>")
        \(capsules.isEmpty ? "" : "<div class=\"milestones\"><h2>💌 时间胶囊</h2><ul>\(capsules)</ul></div>")
        \(voiceMemos.isEmpty ? "" : "<div class=\"voice-memos\"><h2>🎙️ 成长之声</h2>\(voiceMemos)</div>")
        \(cards)</div><footer>这是布布的时光机 · 永久离线可读</footer></body></html>
        """
    }

    private static func mediaHTML(_ media: MediaSnapshot) -> String {
        let path = "media/\(urlEsc(media.fileName))"
        switch media.type {
        case "video": return "<video controls src=\"\(path)\"></video>"
        case "audio": return "<audio controls src=\"\(path)\"></audio>"
        default: return "<img src=\"\(path)\" loading=\"lazy\">"
        }
    }

    private static func buildJSON(_ input: ExportInput) -> String {
        let iso = ISO8601DateFormatter()
        let entries = input.entries.map { entry -> String in
            let media = entry.media.map { "{\"type\":\"\(jsonEsc($0.type))\",\"file\":\"media/\(jsonEsc($0.fileName))\"}" }.joined(separator: ",")
            let voices = entry.voiceNotes.map { "{\"author\":\"\(jsonEsc($0.authorRole))\",\"file\":\"media/\(jsonEsc($0.fileName))\",\"duration\":\($0.duration)}" }.joined(separator: ",")
            let comments = entry.comments.map { "{\"author\":\"\(jsonEsc($0.authorRole))\",\"text\":\($0.text.map { "\"\(jsonEsc($0))\"" } ?? "null"),\"voice\":\($0.voiceFileName.map { "\"media/\(jsonEsc($0))\"" } ?? "null")}" }.joined(separator: ",")
            let tags = entry.tags.map { "\"\(jsonEsc($0))\"" }.joined(separator: ",")
            return "{\"happenedAt\":\"\(iso.string(from: entry.happenedAt))\",\"author\":\"\(jsonEsc(entry.authorRole))\",\"age\":\"\(jsonEsc(entry.ageDescription))\",\"note\":\(entry.note.map { "\"\(jsonEsc($0))\"" } ?? "null"),\"firstPerson\":\(entry.firstPersonNote.map { "\"\(jsonEsc($0))\"" } ?? "null"),\"location\":\(entry.locationName.map { "\"\(jsonEsc($0))\"" } ?? "null"),\"media\":[\(media)],\"voiceNotes\":[\(voices)],\"comments\":[\(comments)],\"tags\":[\(tags)]}"
        }.joined(separator: ",")
        return "{\"childName\":\"\(jsonEsc(input.childName))\",\"birthday\":\"\(iso.string(from: input.birthday))\",\"entries\":[\(entries)]}"
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func jsonEsc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
    private static func urlEsc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}
