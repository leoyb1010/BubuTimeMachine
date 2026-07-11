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

    /// 单文件转写：先端侧后服务器。返回 nil 表示两条路都没成。
    static func transcribe(url: URL, aiService: AIService? = nil, aiConfigured: Bool = false) async -> String? {
        if let text = await onDevice(url: url), !text.isEmpty {
            return text
        }
        if aiConfigured, let aiService,
           let text = try? await aiService.transcribe(audioURL: url),
           !text.isEmpty, !text.hasPrefix("（") {   // 服务器未装 whisper 时回降级提示文案，不当转写
            return text
        }
        return nil
    }

    // MARK: 端侧（SFSpeechRecognizer，优先设备端识别）

    private static func onDevice(url: URL) async -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else { return nil }
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { return nil }

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
                    cont.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    guard !resumed else { return }
                    resumed = true
                    cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: 批量补写（App 启动 / 保存语音后调用）

    /// 找出还没有转写的语音（VoiceNote + VoiceMemo），每轮最多补 N 条，避免长时间占用。
    static func backfill(context: ModelContext, mediaStore: MediaStore,
                         aiService: AIService, aiConfigured: Bool, limit: Int = 4) async {
        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>(
            predicate: #Predicate { $0.transcript == nil && $0.localFileName != nil }))) ?? []
        let memos = (try? context.fetch(FetchDescriptor<VoiceMemo>(
            predicate: #Predicate { $0.transcript == nil && $0.localFileName != nil }))) ?? []

        var done = 0
        for note in notes {
            guard done < limit, let fileName = note.localFileName else { continue }
            if let text = await transcribe(url: mediaStore.mediaURL(for: fileName),
                                           aiService: aiService, aiConfigured: aiConfigured) {
                note.transcript = text
                done += 1
            } else {
                break   // 端侧+服务器都不可用：这轮别再空转
            }
        }
        for memo in memos {
            guard done < limit, let fileName = memo.localFileName else { continue }
            if let text = await transcribe(url: mediaStore.mediaURL(for: fileName),
                                           aiService: aiService, aiConfigured: aiConfigured) {
                memo.transcript = text
                done += 1
            } else {
                break
            }
        }
        if done > 0 { try? context.save() }
    }
}
