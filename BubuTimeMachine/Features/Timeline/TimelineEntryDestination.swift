import SwiftUI
import SwiftData

/// 通知、Spotlight、小组件直达某条家人记录时使用；时光主列表已换成合成流。
struct TimelineEntryDestination: View {
    @Query private var entries: [Entry]

    init(entryID: UUID) {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate {
            $0.id == entryID && !$0.isArchived
        })
        descriptor.fetchLimit = 1
        _entries = Query(descriptor)
    }

    var body: some View {
        if let entry = entries.first {
            EntryDetailView(entry: entry)
        } else {
            BubuStateView(.empty, title: "这条时光暂时找不到", message: "可能已经被家人归档或删除了。")
                .frame(maxHeight: .infinity)
                .background(BubuTheme.Color.background.ignoresSafeArea())
        }
    }
}
