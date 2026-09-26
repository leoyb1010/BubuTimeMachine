import Foundation
import CoreGraphics
import Vision

/// Read ink INSIDE the box. OCR alone often turns both checked and empty boxes into 口.
nonisolated enum SchoolCheckboxReader {
    static let choices = ["不佳", "普通", "佳", "快", "慢", "很安静", "容易醒", "睡不着", "没有排便", "役有排便",
        "健康", "发烧", "咳嗽", "流鼻水", "流県水", "痰音", "尿布疹", "整洁良好", "有受伤", "其他",
        "主动", "生动", "被动", "很少互动", "较无积极参与", "奶瓶", "奶粉", "80", "袜子", "上衣", "裤子",
        "母奶", "牛奶", "喝完", "没喝完", "正常", "多", "少", "硬", "稀"]
    private static let markers = Set("☑✓√✔✅口□☐▢凶区必収巴已四図日■")

    static func selected(in candidate: VNRecognizedText, image: CGImage) -> [String] {
        scores(in: candidate, image: image).filter { $0.value >= 0.12 }.map(\.key).sorted()
    }
    static func scores(in candidate: VNRecognizedText, image: CGImage) -> [String: Double] {
        let text = candidate.string
        var result: [String: Double] = [:]
        for choice in choices {
            guard let range = text.range(of: choice), range.lowerBound > text.startIndex else { continue }
            var index = text.index(before: range.lowerBound)
            while text[index].isWhitespace && index > text.startIndex { index = text.index(before: index) }
            guard markers.contains(text[index]),
                  let box = try? candidate.boundingBox(for: index..<text.index(after: index)) else { continue }
            let b = box.boundingBox
            let bounds = CGRect(x: b.minX * Double(image.width), y: (1 - b.maxY) * Double(image.height),
                                width: b.width * Double(image.width), height: b.height * Double(image.height))
            guard let labelBox = try? candidate.boundingBox(for: range) else { continue }
            let expanded = bounds.insetBy(dx: -bounds.width * 0.3, dy: -bounds.height * 0.2)
            let right = min(expanded.maxX, labelBox.boundingBox.minX * Double(image.width))
            guard right > expanded.minX else { continue }
            let rect = CGRect(x: expanded.minX, y: expanded.minY, width: right - expanded.minX, height: expanded.height).integral
            guard let glyph = image.cropping(to: rect) else { continue }
            let normalized: String
            switch choice {
            case "役有排便": normalized = "没有排便"
            case "生动": normalized = "主动"
            case "流県水": normalized = "流鼻水"
            case "80": normalized = "80抽大包湿巾"
            default: normalized = choice
            }
            result[normalized] = markFraction(in: glyph)
        }
        return result
    }

    static func containsMark(in glyph: CGImage) -> Bool {
        markFraction(in: glyph) >= 0.12
    }
    private static func markFraction(in glyph: CGImage) -> Double {
        let width = glyph.width, height = glyph.height
        guard width >= 6, height >= 6, width <= 256, height <= 256 else { return 0 }
        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return 0 }
        context.draw(glyph, in: CGRect(x: 0, y: 0, width: width, height: height))
        // OCR character boxes can include a border or start before the actual checkbox.
        // Locate the four printed sides first; a dark border is NOT a check mark.
        let stride = width + 1
        var integral = [Int](repeating: 0, count: stride * (height + 1))
        for y in 0..<height {
            for x in 0..<width {
                let p = (y + 1) * stride + x + 1
                integral[p] = (pixels[y * width + x] < 150 ? 1 : 0) + integral[p - 1] + integral[p - stride] - integral[p - stride - 1]
            }
        }
        func sum(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Int {
            integral[(y + h) * stride + x + w] - integral[y * stride + x + w]
                - integral[(y + h) * stride + x] + integral[y * stride + x]
        }
        var best: (x: Int, y: Int, w: Int, h: Int)?
        var bestScore = 0.0
        let maximum = min(width, height) - 2
        // Reject tiny closed strokes from the neighbouring Chinese label (e.g. the 口 in 咳).
        let minimum = max(7, Int(Double(height) * 0.48))
        guard maximum >= minimum else { return 0 }
        for side in minimum...maximum {
            for delta in [-2, 0, 2] {
                let h = side + delta
                guard h >= 7, h < height else { continue }
                for y in 1..<(height - h) {
                    for x in 1..<(width - side) {
                        let top = Double(max(sum(x, y - 1, side, 1), sum(x, y, side, 1), sum(x, y + 1, side, 1))) / Double(side)
                        guard top >= 0.65 else { continue }
                        let bottom = Double(max(sum(x, y + h - 2, side, 1), sum(x, y + h - 1, side, 1), sum(x, y + h, side, 1))) / Double(side)
                        guard bottom >= 0.65 else { continue }
                        let left = Double(max(sum(x - 1, y, 1, h), sum(x, y, 1, h), sum(x + 1, y, 1, h))) / Double(h)
                        let right = Double(max(sum(x + side - 2, y, 1, h), sum(x + side - 1, y, 1, h), sum(x + side, y, 1, h))) / Double(h)
                        guard left >= 0.65, right >= 0.65 else { continue }
                        let centerDistance = abs(Double(x) + Double(side) / 2 - Double(width) / 2) / Double(width)
                            + abs(Double(y) + Double(h) / 2 - Double(height) / 2) / Double(height)
                        let score = (top + bottom + left + right) / 4 - centerDistance * 0.08 + Double(side * h) * 0.00002
                        if score > bestScore { bestScore = score; best = (x, y, side, h) }
                    }
                }
            }
        }
        guard let box = best else { return 0 }
        let inset = max(2, min(box.w, box.h) / 5)
        let w = box.w - inset * 2, h = box.h - inset * 2
        guard w >= 3, h >= 3 else { return 0 }
        // Reject isolated specks. A check may leave just one connected leg inside
        // the printed box, so do not require its outside flourish to be in this crop.
        var seen = [Bool](repeating: false, count: w * h)
        var largest = 0
        for sy in 0..<h {
            for sx in 0..<w {
                let start = sy * w + sx
                guard !seen[start], pixels[(box.y + inset + sy) * width + box.x + inset + sx] < 150 else { continue }
                var stack = [(sx, sy)], count = 0
                seen[start] = true
                while let (x, y) = stack.popLast() {
                    count += 1
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, nx < w, ny >= 0, ny < h, !seen[ny * w + nx],
                                  pixels[(box.y + inset + ny) * width + box.x + inset + nx] < 150 else { continue }
                            seen[ny * w + nx] = true
                            stack.append((nx, ny))
                        }
                    }
                }
                if count >= 4 { largest = max(largest, count) }
            }
        }
        return Double(largest) / Double(w * h)
    }
}
