import SwiftUI
import SwiftData

/// A lens over the shared timeline, never a second database or a second copy of the same memory.
struct MemoryJournalView: View {
    var kind: MemoryJournalKind = .school
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var composing = false
    @State private var limit = 40
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BubuTheme.Spacing.section) {
                hero
                if kind == .school {
                    NavigationLink { MemoryJournalView(kind: .saying) } label: {
                        HStack(spacing: 12) {
                            BubuMascotBadge(size: 44, expression: .music)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("布布说").font(BubuTheme.Font.headline)
                                Text("放学路上的小故事，也录下来")
                                    .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(14).background(BubuTheme.Color.card,
                            in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md))
                    }.buttonStyle(.plain)
                }
                JournalEntries(kind: kind, search: search, limit: limit) { limit += 40 }
                if kind == .saying {
                    NavigationLink { VoiceArchiveView() } label: {
                        Label("以前的成长之声", systemImage: "waveform.path")
                    }
                }
            }
            .padding().bubuContentColumn(760)
        }
        .foregroundStyle(BubuTheme.Color.warmBrown)
        .background(BubuThemedBackground().ignoresSafeArea())
        .tint(env.theme.theme.textAccent)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: kind == .school ? "找老师的话、餐食或小故事" : "找她说过的话")
        .onChange(of: search) { _, _ in limit = 40 }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { composing = true } label: {
                    Label(kind == .school ? "记一天" : "录一句", systemImage: kind == .school ? "plus" : "mic.badge.plus")
                }.accessibilityIdentifier("journal.new")
            }
        }
        .sheet(isPresented: $composing) { MemoryJournalComposer(kind: kind) }
        .accessibilityIdentifier(kind == .school ? "school.home" : "sayings.home")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))) {
                BubuMascotBadge(size: 86, expression: kind == .school ? .playing : .music)
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind == .school ? "她的小小世界" : "小嘴巴，大世界")
                        .font(BubuTheme.Font.title)
                    Text(kind == .school ? "吃得香不香，睡得甜不甜，\n今天又发现了什么？" : "把奶声奶气的现在，\n留给长大后的她。")
                        .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                }
            }
            Button { composing = true } label: {
                Label(kind == .school ? "收好老师发来的今天" : "留住她刚说的那句话",
                      systemImage: kind.symbol).frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(.white)
            }.buttonStyle(.borderedProminent).tint(env.theme.theme.actionFill)
                .accessibilityIdentifier("journal.primary")
        }
        .padding(20)
        .background(LinearGradient(colors: [BubuTheme.Color.warmSurfaceTop, BubuTheme.Color.warmSurfaceMid],
                                    startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.card))
    }
}

private struct JournalEntries: View {
    let kind: MemoryJournalKind
    let limit: Int
    let more: () -> Void
    @Query private var entries: [Entry]
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [ChildProfile]

    init(kind: MemoryJournalKind, search: String, limit: Int, more: @escaping () -> Void) {
        self.kind = kind; self.limit = limit; self.more = more
        let marker = kind.marker + "\n"
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate {
            !$0.isArchived && ($0.note?.starts(with: marker) ?? false)
                && (query.isEmpty || ($0.note?.localizedStandardContains(query) ?? false))
        }, sortBy: [SortDescriptor(\Entry.happenedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        _entries = Query(descriptor)
    }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if entries.isEmpty {
                Text(kind == .school ? "小书包还空着，收进第一天吧。\n保存后，这里和时光里都能找到。" : "还没找到这句话。\n录一段声音，或写下她的原话。")
                    .font(BubuTheme.Font.body).foregroundStyle(BubuTheme.Color.secondaryText)
                    .padding(.vertical, 24)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink { EntryDetailView(entry: entry) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(BubuDateFormat.shortDate(entry.happenedAt), systemImage: kind.symbol)
                                    .font(BubuTheme.Font.caption.weight(.semibold))
                                    .foregroundStyle(env.theme.theme.textAccent)
                                Spacer()
                                if let birthday = profiles.first?.birthday {
                                    Text(AgeCalculator.compactAge(birthday: birthday, at: entry.happenedAt))
                                        .font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                                }
                            }
                            Text(kind.body(entry.note)).font(BubuTheme.Font.body).lineLimit(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let cover = entry.coverMedia {
                                MediaThumbnail(media: cover, mediaStore: env.mediaStore, cornerRadius: BubuTheme.Radius.sm)
                                    .frame(height: 180).clipped()
                            }
                            HStack {
                                if !entry.media.isEmpty { Text("\(entry.sortedMedia.count) 个素材") }
                                Spacer()
                                Label("打开这段时光", systemImage: "chevron.right")
                            }.font(BubuTheme.Font.caption).foregroundStyle(BubuTheme.Color.secondaryText)
                        }
                    }.buttonStyle(.plain)
                    if let voice = entry.voiceNotes.sorted(by: { $0.createdAt < $1.createdAt }).first {
                        if let name = voice.localFileName, env.mediaStore.fileExists(forMedia: name) {
                            VoicePlayerBubble(fileName: name, duration: voice.durationSeconds,
                                              waveform: voice.waveformSamples, mediaStore: env.mediaStore,
                                              tint: env.theme.theme.textAccent)
                        } else {
                            Label("原声待下载，请在同步中心核对", systemImage: "icloud.and.arrow.down")
                                .font(BubuTheme.Font.caption)
                        }
                    }
                }
                .padding(16).background(BubuTheme.Color.card,
                    in: RoundedRectangle(cornerRadius: BubuTheme.Radius.md))
            }
            if entries.count == limit { Button("再看一些") { more() }.frame(maxWidth: .infinity, minHeight: 44) }
        }
    }
}
