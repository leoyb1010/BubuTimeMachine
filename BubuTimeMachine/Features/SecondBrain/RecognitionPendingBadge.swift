import SwiftUI

/// "1296 张待认" capsule for entry points into 认一认 (魔法屋 tile, 时光 menu, a home card).
/// Asks the family service for one candidate just to read `remaining`; shows nothing when
/// the service isn't connected, fails, or nothing is waiting.
struct RecognitionPendingBadge: View {
    @Environment(AppEnvironment.self) private var env
    @State private var remaining: Int?

    var body: some View {
        let client = BubuLearningClient(env: env)
        Group {
            if let remaining, remaining > 0 {
                Text("\(remaining) 张待认")
                    .font(BubuTheme.Font.scaled(12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(BubuTheme.Color.actionFill, in: Capsule())
                    .accessibilityLabel("有 \(remaining) 张照片等你确认是不是布布")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task(id: client?.scope) {
            guard let client else { remaining = nil; return }
            remaining = await Self.fetch(client)
        }
    }

    static func fetch(_ client: BubuLearningClient) async -> Int? {
        guard let list = try? await client.get("api/recognition/candidates", query: [URLQueryItem(name: "limit", value: "1")],
                                               as: RecognitionCandidateList.self) else { return nil }
        return list.remaining ?? list.items.count
    }
}
