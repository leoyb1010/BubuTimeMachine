import SwiftUI
import VisionKit
import Vision
import UIKit

// MARK: - 作品扫描（系统文稿相机）
/// 幼儿园三年会产生几百张画和手工。它们物理上一定会丢：会皱、会被水泡、
/// 会在某次搬家或大扫除里被当成废纸扔掉。**拍下来是唯一能留住的方式。**
///
/// 为什么不直接用普通拍照：一张贴在冰箱上的画，随手一拍必然是斜的、带桌面、带手指。
/// `VNDocumentCameraViewController` 是系统自带的文稿相机——自动找边、自动去畸变、
/// 自动裁掉背景，还能连续拍多页（一次拍完整本手工册）。零依赖、零训练、免费。
///
/// 顺带跑一次中文 OCR：老师常把日期和一句评语写在画的角落里，
/// 认出来当作记录正文的初稿，家长改一改就存。**只做初稿，绝不自动写事实。**
struct ArtworkScannerView: UIViewControllerRepresentable {
    /// 扫描完成：交回裁好的每一页，以及 OCR 认出来的文字（可能为空）。
    var onFinish: ([UIImage], String) -> Void
    var onCancel: () -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    @MainActor
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([UIImage], String) -> Void
        private let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage], String) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var pages: [UIImage] = []
            for index in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: index))
            }
            // OCR 不在主线程上跑：`recognizeText` 是 nonisolated async，
            // await 会自然让出主线程，识别完再回到 MainActor 回调。
            // 用 Task 而不是 Task.detached——detached 要求把回调闭包跨隔离域送出去，
            // Swift 6 严格并发下这是数据竞争。
            Task { @MainActor in
                let text = await ArtworkScannerView.recognizeText(in: pages)
                self.onFinish(pages, text)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onCancel()
        }
    }

    /// 端侧中文 OCR。全程不出设备，与项目「人脸/图片分析一律端侧」的原则一致。
    /// 认不出来就返回空串——宁可让家长自己写，也不要塞一段错的。
    nonisolated static func recognizeText(in pages: [UIImage]) async -> String {
        var lines: [String] = []
        for page in pages {
            guard let cgImage = page.cgImage else { continue }
            var request = RecognizeTextRequest()
            request.recognitionLanguages = [
                Locale.Language(identifier: "zh-Hans"),
                Locale.Language(identifier: "en-US"),
            ]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            guard let observations = try? await request.perform(on: cgImage) else { continue }
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                // 低置信度的多半是画里的线条被当成了字，留着只会污染正文。
                guard candidate.confidence > 0.5 else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { lines.append(text) }
            }
        }
        return lines.joined(separator: " ")
    }
}
