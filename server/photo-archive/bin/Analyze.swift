import Foundation
import ImageIO
import Vision
import CoreGraphics

// 内容识别：VNClassifyImage(视觉标签) + VNRecognizeText(中英 OCR) + 人脸数
// 输出格式与档案库历史一致：visual_labels = "label:score;label:score"
func img(_ url: URL, _ maxPixel: CGFloat) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(s, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ] as CFDictionary)
}

func analyze(_ url: URL) -> [String: Any] {
    autoreleasepool {
        var out: [String: Any] = ["file": url.lastPathComponent, "labels": "", "ocr": "", "faces": 0]
        guard let big = img(url, 1600) else { out["error"] = "decode"; return out }
        let h = VNImageRequestHandler(cgImage: big, orientation: .up, options: [:])

        let cls = VNClassifyImageRequest()
        let txt = VNRecognizeTextRequest()
        txt.recognitionLanguages = ["zh-Hans", "en-US"]
        txt.recognitionLevel = .accurate
        txt.usesLanguageCorrection = true
        let face = VNDetectFaceRectanglesRequest()
        try? h.perform([cls, txt, face])

        if let obs = cls.results {
            let kept = obs.filter { $0.confidence >= 0.20 }
                .sorted { $0.confidence > $1.confidence }.prefix(12)
            out["labels"] = kept.map { "\($0.identifier):\(String(format: "%.2f", $0.confidence))" }
                .joined(separator: ";")
        }
        if let obs = txt.results {
            out["ocr"] = obs.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
        out["faces"] = face.results?.count ?? 0
        return out
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else { fputs("usage: analyze list.txt\n", stderr); exit(2) }
let urls = ((try? String(contentsOfFile: args[1], encoding: .utf8)) ?? "")
    .split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
var res = [String](repeating: "", count: urls.count)
let lock = NSLock(); var done = 0
DispatchQueue.concurrentPerform(iterations: urls.count) { i in
    let o = analyze(urls[i])
    let d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
    lock.lock(); res[i] = String(data: d, encoding: .utf8)!
    done += 1; if done % 50 == 0 { fputs("progress \(done)/\(urls.count)\n", stderr) }
    lock.unlock()
}
print("[" + res.joined(separator: ",") + "]")
