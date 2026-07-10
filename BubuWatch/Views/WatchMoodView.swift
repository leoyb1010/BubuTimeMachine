import SwiftUI
import WatchKit

// MARK: - 心情快记（点一下即记）
struct WatchMoodView: View {
    @Environment(WatchConnector.self) private var connector
    @Environment(\.dismiss) private var dismiss

    // 手表上给一组最常用心情，避免选择过载。
    private let moods: [Mood] = [.happy, .laughing, .eating, .sleepy, .curious,
                                 .naughty, .crying, .cuddly, .brave, .love,
                                 .surprised, .milestone]

    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(moods, id: \.rawValue) { mood in
                    Button {
                        connector.sendMood(rawValue: mood.rawValue, emoji: mood.emoji)
                        WKInterfaceDevice.current().play(.success)
                        dismiss()
                    } label: {
                        VStack(spacing: 2) {
                            Text(mood.emoji).font(.system(size: 26))
                            Text(mood.rawValue)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.plain)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("心情")
    }
}
