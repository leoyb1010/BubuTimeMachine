import SwiftUI

/// Full text and an uncropped photo; the crown scrolls normally on this route.
struct WatchStoryView: View {
    let memory: WatchMemory
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if memory.photoFileName != nil {
                    WatchPhotoSurface(fileName: memory.photoFileName, emoji: memory.moodEmoji ?? "🌷", fitsPhoto: true)
                        .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(memory.dateText).font(.headline).foregroundStyle(WatchTheme.butter)
                    if !memory.ageText.isEmpty {
                        Text("那时 \(memory.ageText)").font(.caption).foregroundStyle(.secondary)
                    }
                    if memory.isOnThisDay {
                        Label("那年今日", systemImage: "sparkles").font(.caption).foregroundStyle(WatchTheme.rose)
                    }
                }
                Text(memory.note).font(.body).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8).padding(.bottom, 16)
        }
        .navigationTitle("她的故事")
        .background(WatchReadingBackground())
    }
}
