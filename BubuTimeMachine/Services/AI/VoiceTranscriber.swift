import Foundation
import Speech
import SwiftData

// MARK: - 语音自动转写（R4 E-1）
/// 三年语音变成可搜索的文字：每段「说给布布」的录音自动转写落库（transcript 字段早已预留）。
/// 路径①：端侧 SFSpeechRecognizer（离线、免费、快，中文支持好）；
/// 路径②：自托管服务器 Whisper 兜底（端侧不可用/失败时）。
/// 转写是尽力而为的增强：失败静默留空，不打扰任何主流程。
@MainActor
enum VoiceTranscriber {

    /// 单文件转写结果：区分「转出文字」「单文件失败」「整体服务不可用」。
    /// 后两者对批量补写的处置不同：单文件失败应跳过继续，服务不可用才该停这一轮。
    enum Outcome {
        case text(String)
        case fileFailed          // 识别器/服务器可用，但这个文件转不出来
        case serviceUnavailable  // 端侧不可用且服务器也不可达 → 停止本轮
    }

    /// 单文件转写：先端侧后服务器。返回 nil 表示没转出来（供 CaptureModel 等只关心文本的调用方）。
    static func transcribe(url: URL, aiService: AIService? = nil, aiConfigured: Bool = false) async -> String? {
        if case .text(let text) = await transcribeOutcome(url: url, aiService: aiService, aiConfigured: aiConfigured) {
            return text
        }
        return nil
    }

    /// 带原因的单文件转写。
    static func transcribeOutcome(url: URL, aiService: AIService? = nil, aiConfigured: Bool = false) async -> Outcome {
        let device = await onDevice(url: url)
        if case .text(let text) = device, !text.isEmpty {
            return .text(text)
        }

        // 服务器兜底
        var serverReachable = false
        if aiConfigured, let aiService, let text = try? await aiService.transcribe(audioURL: url) {
            if text.hasPrefix("（") {
                serverReachable = false   // 服务器未装 whisper 的降级提示：视为服务不可用，别当转写
            } else {
                serverReachable = true
                if !text.isEmpty { return .text(text) }
            }
        }

        switch device {
        case .recognizerUnavailable:
            // 端侧不可用：服务器可达仅代表这个文件没转出来；都不可达才是整体服务不可用。
            return serverReachable ? .fileFailed : .serviceUnavailable
        case .fileFailed, .text:   // .text 落到这里代表端侧识别为空 → 视为单文件问题
            return .fileFailed
        }
    }

    // MARK: 端侧（SFSpeechRecognizer，优先设备端识别）

    private enum DeviceOutcome {
        case text(String)
        case fileFailed             // 识别器可用，但这个文件转写报错
        case recognizerUnavailable  // 识别器不存在/不可用/未授权
    }

    private static func onDevice(url: URL) async -> DeviceOutcome {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else { return .recognizerUnavailable }
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { return .recognizerUnavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true   // 语音不出设备
        }
        return await withCheckedContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    guard !resumed else { return }
                    resumed = true
                    cont.resume(returning: .text(result.bestTranscription.formattedString))
                } else if error != nil {
                    guard !resumed else { return }
                    resumed = true
                    cont.resume(returning: .fileFailed)
                }
            }
        }
    }

    // MARK: 批量补写（App 启动 / 保存语音后调用）

    /// 单文件失败计数存储：超过阈值的坏文件永久跳过，不再卡死队列。
    static let maxFileFailures = 3
    private static let failureCountsKey = "bubu.voice.transcribeFailures"

    private static func failureCounts(_ defaults: UserDefaults) -> [String: Int] {
        guard let raw = defaults.dictionary(forKey: failureCountsKey) else { return [:] }
        return raw.reduce(into: [:]) { acc, kv in
            if let count = kv.value as? Int { acc[kv.key] = count }
        }
    }

    private static func recordFailure(_ file: String, _ defaults: UserDefaults) {
        var counts = failureCounts(defaults)
        counts[file, default: 0] += 1
        defaults.set(counts, forKey: failureCountsKey)
    }

    private static func clearFailure(_ file: String, _ defaults: UserDefaults) {
        var counts = failureCounts(defaults)
        guard counts.removeValue(forKey: file) != nil else { return }
        defaults.set(counts, forKey: failureCountsKey)
    }

    /// 找出还没有转写的语音（VoiceNote + VoiceMemo），每轮最多补 N 条，避免长时间占用。
    /// - 单文件失败：计数并跳过，继续处理后面的语音；累计超过阈值的文件永久跳过。
    /// - 整体服务不可用：停止本轮（避免空转），下轮再来。
    static func backfill(context: ModelContext, mediaStore: MediaStore,
                         aiService: AIService, aiConfigured: Bool, limit: Int = 4,
                         defaults: UserDefaults = .standard) async {
        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>(
            predicate: #Predicate { $0.transcript == nil && $0.localFileName != nil }))) ?? []
        let memos = (try? context.fetch(FetchDescriptor<VoiceMemo>(
            predicate: #Predicate { $0.transcript == nil && $0.localFileName != nil }))) ?? []

        var done = 0
        var serviceDown = false

        func handle(fileName: String, apply: (String) -> Void) async {
            guard failureCounts(defaults)[fileName, default: 0] < maxFileFailures else { return }
            switch await transcribeOutcome(url: mediaStore.mediaURL(for: fileName),
                                           aiService: aiService, aiConfigured: aiConfigured) {
            case .text(let text):
                apply(text)
                clearFailure(fileName, defaults)
                done += 1
            case .fileFailed:
                recordFailure(fileName, defaults)   // 记账后继续，坏文件不再卡死后面的语音
            case .serviceUnavailable:
                serviceDown = true                  // 端侧+服务器都不可用：这轮别再空转
            }
        }

        for note in notes {
            guard done < limit, !serviceDown, let fileName = note.localFileName else { continue }
            await handle(fileName: fileName) { note.transcript = $0 }
        }
        for memo in memos {
            guard done < limit, !serviceDown, let fileName = memo.localFileName else { continue }
            await handle(fileName: fileName) { memo.transcript = $0 }
        }
        if done > 0 { try? context.save() }
    }
}
