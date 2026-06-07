import Foundation
import SwiftData

// MARK: - 全量档案导出
/// 把布布的一切导出成一个自包含文件夹：
///   index.html（按时光轴排版，可双击直接看）+ media/（媒体原文件）+ data.json（结构化备份）。
/// 即使将来 App / 后端都没了，硬盘里仍是一个能直接打开的"布布的一生"。
/// nonisolated：在后台线程完成 IO 与字符串拼接。
nonisolated struct ArchiveExporter: Sendable {
    let mediaStore: MediaStore

    struct ExportInput: Sendable {
        let childName: String
        let birthday: Date
        let entries: [EntrySnapshot]
        let milestones: [MilestoneSnapshot]
    }
    struct EntrySnapshot: Sendable {
        let happenedAt: Date
        let authorRole: String
        let note: String?
        let firstPersonNote: String?
        let locationName: String?
        let moodEmoji: String?
        let ageDescription: String
        let mediaFileNames: [String]      // 沙盒相对名（图片）
        let tags: [String]
    }
    struct MilestoneSnapshot: Sendable {
        let title: String
        let emoji: String
        let achieved: Bool
        let ageDescription: String?
    }

    /// 执行导出，返回打包文件夹的 URL（位于临时目录）。
    func export(_ input: ExportInput) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("布布的一生_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        let mediaDir = root.appendingPathComponent("media", isDirectory: true)
        try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        // 拷贝媒体
        for entry in input.entries {
            for name in entry.mediaFileNames {
                let src = mediaStore.mediaURL(for: name)
                if fm.fileExists(atPath: src.path) {
                    try? fm.copyItem(at: src, to: mediaDir.appendingPathComponent(name))
                }
            }
        }

        // data.json
        let json = Self.buildJSON(input)
        try json.write(to: root.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)

        // index.html
        let html = Self.buildHTML(input)
        try html.write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        return root
    }

    // MARK: HTML

    private static func buildHTML(_ input: ExportInput) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年M月d日"

        var cards = ""
        for e in input.entries.sorted(by: { $0.happenedAt > $1.happenedAt }) {
            var imgs = ""
            for name in e.mediaFileNames {
                imgs += "<img src=\"media/\(name)\" loading=\"lazy\">"
            }
            let mood = e.moodEmoji ?? ""
            let place = e.locationName.map { " · 📍\(esc($0))" } ?? ""
            let note = e.note.map { "<p class=\"note\">\(esc($0))</p>" } ?? ""
            let fp = e.firstPersonNote.map { "<p class=\"fp\">「\(esc($0))」</p>" } ?? ""
            let tags = e.tags.isEmpty ? "" :
                "<div class=\"tags\">" + e.tags.map { "<span>#\(esc($0))</span>" }.joined() + "</div>"
            cards += """
            <div class="card">
              <div class="meta">\(mood) \(df.string(from: e.happenedAt)) · \(esc(e.authorRole))\(place) · <em>\(esc(e.ageDescription))</em></div>
              <div class="imgs">\(imgs)</div>
              \(note)\(fp)\(tags)
            </div>
            """
        }

        var milestoneItems = ""
        for m in input.milestones where m.achieved {
            milestoneItems += "<li>\(m.emoji) \(esc(m.title)) <em>\(esc(m.ageDescription ?? ""))</em></li>"
        }

        return """
        <!DOCTYPE html><html lang="zh"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(esc(input.childName))的一生</title>
        <style>
          :root{--pink:#F28C9E;--brown:#5C4D47;--bg:#FBF6F0}
          *{box-sizing:border-box}
          body{margin:0;background:var(--bg);color:var(--brown);
               font-family:-apple-system,"PingFang SC",sans-serif;line-height:1.7}
          header{text-align:center;padding:48px 20px 24px}
          header h1{font-size:34px;margin:0}
          header p{color:#8a7d76;margin:6px 0}
          .wrap{max-width:720px;margin:0 auto;padding:0 16px 80px}
          .milestones{background:#fff;border-radius:18px;padding:20px 24px;margin:16px 0 28px;
                      box-shadow:0 4px 16px rgba(0,0,0,.05)}
          .milestones h2{font-size:18px;margin:0 0 10px}
          .milestones ul{margin:0;padding-left:18px}
          .milestones em{color:var(--pink);font-style:normal;font-size:13px;margin-left:6px}
          .card{background:#fff;border-radius:18px;padding:18px 20px;margin:16px 0;
                box-shadow:0 4px 16px rgba(0,0,0,.05)}
          .meta{font-size:13px;color:#8a7d76;margin-bottom:10px}
          .meta em{color:var(--pink);font-style:normal}
          .imgs{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:6px}
          .imgs img{width:100%;aspect-ratio:1;object-fit:cover;border-radius:10px}
          .note{font-size:17px;margin:12px 0 4px}
          .fp{color:var(--pink);font-style:italic}
          .tags span{display:inline-block;background:rgba(242,140,158,.1);color:var(--pink);
                     border-radius:20px;padding:2px 10px;font-size:12px;margin:4px 4px 0 0}
          footer{text-align:center;color:#b0a59e;font-size:13px;padding:30px}
        </style></head><body>
        <header>
          <h1>\(esc(input.childName))的一生</h1>
          <p>出生于 \(df.string(from: input.birthday))</p>
          <p>共 \(input.entries.count) 个瞬间 · 由布布时光机生成</p>
        </header>
        <div class="wrap">
          \(milestoneItems.isEmpty ? "" : "<div class=\"milestones\"><h2>🌟 成长里程碑</h2><ul>\(milestoneItems)</ul></div>")
          \(cards)
        </div>
        <footer>这是布布的时光机 · 永久离线可读</footer>
        </body></html>
        """
    }

    private static func buildJSON(_ input: ExportInput) -> String {
        // 简洁、稳定的手写 JSON（避免对 SwiftData 类型的编码耦合）
        let iso = ISO8601DateFormatter()
        func entryJSON(_ e: EntrySnapshot) -> String {
            let media = e.mediaFileNames.map { "\"media/\($0)\"" }.joined(separator: ",")
            let tags = e.tags.map { "\"\(jsonEsc($0))\"" }.joined(separator: ",")
            return """
            {"happenedAt":"\(iso.string(from: e.happenedAt))","author":"\(jsonEsc(e.authorRole))",
            "age":"\(jsonEsc(e.ageDescription))","note":\(e.note.map { "\"\(jsonEsc($0))\"" } ?? "null"),
            "firstPerson":\(e.firstPersonNote.map { "\"\(jsonEsc($0))\"" } ?? "null"),
            "location":\(e.locationName.map { "\"\(jsonEsc($0))\"" } ?? "null"),
            "media":[\(media)],"tags":[\(tags)]}
            """
        }
        let entries = input.entries.map(entryJSON).joined(separator: ",\n")
        return """
        {"childName":"\(jsonEsc(input.childName))","birthday":"\(iso.string(from: input.birthday))",
        "entries":[\(entries)]}
        """
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    private static func jsonEsc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
