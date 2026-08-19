import Foundation
import ImageIO
import Vision
import CoreGraphics

// 与 App 内 ChildIdentityRecognizer 完全同一套判据：1600px 降采样 →
// VNDetectFaceRectangles → 0.16 外扩裁脸 → VNGenerateImageFeaturePrint →
// computeDistance；阈值 0.46，负样本余量 0.04。
let kThreshold: Float = 0.46
let kNegMargin: Float = 0.04

func downsampled(_ url: URL, maxPixel: CGFloat = 1600) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    let opts = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts)
}

func cropFace(_ box: CGRect, from image: CGImage) -> CGImage? {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    let m: CGFloat = 0.16
    let ex = box.insetBy(dx: -box.width * m, dy: -box.height * m)
        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    let r = CGRect(x: ex.minX * w, y: (1 - ex.maxY) * h,
                   width: ex.width * w, height: ex.height * h)
        .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
    guard r.width >= 32, r.height >= 32 else { return nil }
    return image.cropping(to: r)
}

struct FaceInfo { let print: VNFeaturePrintObservation; let area: Float }

func facePrints(_ url: URL) -> [FaceInfo] {
    autoreleasepool {
        guard let img = downsampled(url) else { return [] }
        let fr = VNDetectFaceRectanglesRequest()
        let h = VNImageRequestHandler(cgImage: img, orientation: .up, options: [:])
        guard (try? h.perform([fr])) != nil else { return [] }
        return (fr.results ?? []).prefix(6).compactMap { face -> FaceInfo? in
            guard let crop = cropFace(face.boundingBox, from: img) else { return nil }
            let pr = VNGenerateImageFeaturePrintRequest()
            let ph = VNImageRequestHandler(cgImage: crop, orientation: .up, options: [:])
            guard (try? ph.perform([pr])) != nil,
                  let obs = pr.results?.first as? VNFeaturePrintObservation else { return nil }
            let b = face.boundingBox
            return FaceInfo(print: obs, area: Float(b.width * b.height))
        }
    }
}

func dist(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
    var d: Float = 0
    guard (try? a.computeDistance(&d, to: b)) != nil else { return nil }
    return d
}

func minDist(_ q: VNFeaturePrintObservation, _ set: [VNFeaturePrintObservation]) -> Float? {
    var best: Float?
    for s in set { if let d = dist(q, s) { best = min(best ?? d, d) } }
    return best
}

func lines(_ path: String) -> [URL] {
    (try? String(contentsOfFile: path, encoding: .utf8))?
        .split(separator: "\n").map { URL(fileURLWithPath: String($0)) } ?? []
}

/// 并发提特征
func collect(_ urls: [URL], singleFaceOnly: Bool) -> [(URL, [FaceInfo])] {
    var out = [(URL, [FaceInfo])](repeating: (URL(fileURLWithPath: "/"), []), count: urls.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: urls.count) { i in
        let f = facePrints(urls[i])
        let keep = singleFaceOnly ? (f.count == 1 ? f : []) : f
        lock.lock(); out[i] = (urls[i], keep); lock.unlock()
    }
    return out
}

let args = CommandLine.arguments
guard args.count >= 4 else { fputs("usage: bubuface pos.txt neg.txt query.txt\n", stderr); exit(2) }

// 正样本：只从"女儿"档案里的单人脸照片取——单人照里那张脸必是布布
let pos = collect(lines(args[1]), singleFaceOnly: true).flatMap { $0.1 }.map(\.print)
fputs("positives: \(pos.count)\n", stderr)
guard !pos.isEmpty else { fputs("no positive samples\n", stderr); exit(1) }

// 负样本：家人/他人单人脸，且必须离布布模型足够远（防把布布误注册成负样本）
let negRaw = collect(lines(args[2]), singleFaceOnly: true).flatMap { $0.1 }.map(\.print)
let neg = negRaw.filter { (minDist($0, pos) ?? 1) > kThreshold }
fputs("negatives: \(neg.count)/\(negRaw.count)\n", stderr)

let queries = lines(args[3])
var results = [String](repeating: "", count: queries.count)
let lock = NSLock()
var done = 0
DispatchQueue.concurrentPerform(iterations: queries.count) { i in
    let url = queries[i]
    let faces = facePrints(url)
    var bestPos: Float? = nil, bestNeg: Float? = nil, bubuArea: Float = 0
    for f in faces {
        if let d = minDist(f.print, pos) {
            if bestPos == nil || d < bestPos! { bestPos = d; bubuArea = f.area }
        }
        if let d = minDist(f.print, neg) { bestNeg = min(bestNeg ?? d, d) }
    }
    let clearsPos = bestPos.map { $0 <= kThreshold } ?? false
    let clearsNeg: Bool = {
        if let p = bestPos, let n = bestNeg { return p + kNegMargin < n }
        return true
    }()
    let likely = clearsPos && clearsNeg
    let conf = bestPos.map { max(0, min(1, 1 - Double($0 / kThreshold))) } ?? 0
    let obj: [String: Any] = [
        "file": url.lastPathComponent, "faces": faces.count,
        "bestPos": bestPos.map { Double($0) } ?? -1,
        "bestNeg": bestNeg.map { Double($0) } ?? -1,
        "likely": likely, "conf": conf, "area": Double(bubuArea),
    ]
    let data = try! JSONSerialization.data(withJSONObject: obj)
    lock.lock()
    results[i] = String(data: data, encoding: .utf8)!
    done += 1
    if done % 50 == 0 { fputs("progress \(done)/\(queries.count)\n", stderr) }
    lock.unlock()
}
print("[" + results.joined(separator: ",") + "]")
