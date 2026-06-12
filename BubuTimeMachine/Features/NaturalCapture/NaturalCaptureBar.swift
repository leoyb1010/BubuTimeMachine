import SwiftUI
import SwiftData

// MARK: - 全局一句话记录入口
/// 轻盈的「AI 记录卡」：写一句（语音入口 Phase 5 接入）→ 解析 → 确认页 → 各模块落库。
/// 不做聊天界面；失败温和降级，不暴露异常原文。
struct NaturalCaptureBar: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]

    @State private var text = ""
    @State private var isParsing = false
    @State private var errorText: String?
    @State private var reviewPayload: ReviewPayload?

    private var profile: ChildProfile? { profiles.first }
    private var theme: Color { env.theme.theme.primary }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme)
                    .frame(width: 34, height: 34)
                    .background(theme.opacity(0.10), in: Circle())

                TextField("一句话记录：布布今天吃了……", text: $text, axis: .vertical)
                    .font(BubuTheme.Font.body)
                    .lineLimit(1...3)
                    .submitLabel(.send)
                    .onSubmit { Task { await parseText() } }

                Button {
                    Task { await parseText() }
                } label: {
                    if isParsing {
                        ProgressView().tint(theme)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(text.bubuTrimmed.isEmpty
                                             ? BubuTheme.Color.secondaryText.opacity(0.5)
                                             : theme)
                    }
                }
                .disabled(text.bubuTrimmed.isEmpty || isParsing)
                .accessibilityLabel("识别并保存这句话")
            }
            .padding(12)
            .background(BubuTheme.Color.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .bubuGlassSurface(cornerRadius: 22, tint: theme, interactive: true)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(BubuTheme.Color.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .sheet(item: $reviewPayload) { payload in
            NaturalCaptureReviewSheet(result: payload.result, originalText: payload.originalText) {
                text = ""
            }
        }
    }

    @MainActor
    private func parseText() async {
        let input = text.bubuTrimmed
        guard !input.isEmpty, !isParsing else { return }

        isParsing = true
        errorText = nil
        defer { isParsing = false }

        do {
            let request = NaturalCaptureRequest(
                text: input,
                childName: profile?.name ?? "布布",
                timezone: TimeZone.current.identifier,
                referenceDate: .now
            )
            let result = try await env.aiService.parseNaturalCapture(request)
            reviewPayload = ReviewPayload(result: result, originalText: input)
        } catch {
            errorText = "智能识别暂时不可用，可以先用「记录此刻」保存。"
            #if DEBUG
            print("[NaturalCapture] parse failed:", error)
            #endif
        }
    }
}

private struct ReviewPayload: Identifiable {
    let id = UUID()
    let result: NaturalCaptureResult
    let originalText: String
}
