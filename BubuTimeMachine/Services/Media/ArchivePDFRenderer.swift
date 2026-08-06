import CoreGraphics
import CoreText
import Foundation

/// 生成不依赖 App 的长期阅读 PDF。只排版已经进入开放档案的文字事实；原媒体仍保留在 media/。
nonisolated enum ArchivePDFRenderer {
    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let content = CGRect(x: 54, y: 54, width: 487, height: 734)

    static func write(_ input: ArchiveExporter.ExportInput, to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw CocoaError(.fileWriteUnknown) }

        let body = document(input)
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        var location = 0
        repeat {
            context.beginPDFPage([kCGPDFContextMediaBox as String: page] as CFDictionary)
            context.saveGState()
            let path = CGPath(rect: content, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            location += visible.length
            context.restoreGState()
            context.endPDFPage()
            if visible.length == 0 { break }
        } while location < CFAttributedStringGetLength(body)
        context.closePDF()
    }

    private static func document(_ input: ArchiveExporter.ExportInput) -> CFAttributedString {
        let result = NSMutableAttributedString()
        append("\(input.childName)的成长档案\n", style: .title, to: result)
        append("由布布时光机生成 · 开放阅读版\n\n", style: .muted, to: result)

        let date = DateFormatter()
        date.locale = Locale(identifier: "zh_CN")
        date.dateFormat = "yyyy年M月d日"
        append("出生日期：\(date.string(from: input.birthday))\n", style: .body, to: result)
        append(
            "共 \(input.entries.count) 段时光 · \(input.growthMeasurements.count) 条成长测量 · \(input.healthRecords.count) 条健康记录 · \(input.timeCapsules.count) 封时间胶囊\n\n",
            style: .body, to: result)

        section("成长里程碑", to: result)
        let achieved = input.milestones.filter(\.achieved)
        if achieved.isEmpty {
            append("还没有点亮的里程碑。\n\n", style: .muted, to: result)
        } else {
            for item in achieved {
                append("• \(item.emoji) \(item.title) \(item.ageDescription ?? "")\n", style: .body, to: result)
            }
            append("\n", style: .body, to: result)
        }

        section("时光目录", to: result)
        let timestamp = DateFormatter()
        timestamp.locale = Locale(identifier: "zh_CN")
        timestamp.dateFormat = "yyyy-MM-dd HH:mm"
        for entry in input.entries.sorted(by: { $0.happenedAt < $1.happenedAt }) {
            append("\(timestamp.string(from: entry.happenedAt)) · \(entry.authorRole) · \(entry.ageDescription)\n",
                   style: .entryTitle, to: result)
            let text = entry.note ?? entry.firstPersonNote ?? "（无文字）"
            append(text.replacingOccurrences(of: "\n", with: " ") + "\n", style: .body, to: result)
            if !entry.tags.isEmpty {
                append(entry.tags.map { "#\($0)" }.joined(separator: "  ") + "\n", style: .accent, to: result)
            }
            append("\n", style: .body, to: result)
        }
        return result
    }

    private static func section(_ title: String, to result: NSMutableAttributedString) {
        append(title + "\n", style: .section, to: result)
    }

    private enum Style {
        case title, section, entryTitle, body, muted, accent
    }

    private static func append(
        _ text: String, style: Style, to result: NSMutableAttributedString
    ) {
        let fontName: String
        let fontSize: CGFloat
        let color: CGColor
        switch style {
        case .title:
            fontName = "PingFangSC-Semibold"; fontSize = 26
            color = CGColor(red: 0.36, green: 0.30, blue: 0.28, alpha: 1)
        case .section:
            fontName = "PingFangSC-Semibold"; fontSize = 17
            color = CGColor(red: 0.86, green: 0.35, blue: 0.48, alpha: 1)
        case .entryTitle:
            fontName = "PingFangSC-Semibold"; fontSize = 11
            color = CGColor(red: 0.36, green: 0.30, blue: 0.28, alpha: 1)
        case .body:
            fontName = "PingFangSC-Regular"; fontSize = 11
            color = CGColor(red: 0.36, green: 0.30, blue: 0.28, alpha: 1)
        case .muted:
            fontName = "PingFangSC-Regular"; fontSize = 10
            color = CGColor(gray: 0.48, alpha: 1)
        case .accent:
            fontName = "PingFangSC-Regular"; fontSize = 9
            color = CGColor(red: 0.86, green: 0.35, blue: 0.48, alpha: 1)
        }
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        result.append(NSAttributedString(
            string: text,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            ]))
    }
}
