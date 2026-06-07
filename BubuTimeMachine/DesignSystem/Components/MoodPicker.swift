import SwiftUI

// MARK: - 心情选择器
/// 横向一排心情 emoji，给每个此刻一种情绪。
struct MoodPicker: View {
    @Binding var selection: Mood?
    var tint: Color = BubuTheme.Color.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("此刻的心情")
                .font(BubuTheme.Font.body)
                .foregroundStyle(BubuTheme.Color.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        let selected = selection == mood
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                selection = selected ? nil : mood
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Text(mood.emoji).font(.system(size: 26))
                                Text(mood.rawValue).font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(BubuTheme.Color.warmBrown)
                            }
                            .frame(width: 58, height: 62)
                            .background(selected ? tint.opacity(0.18) : BubuTheme.Color.card,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected ? tint : .clear, lineWidth: 2)
                            }
                            .scaleEffect(selected ? 1.05 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
