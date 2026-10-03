#if DEBUG
import SwiftUI
import SwiftData

/// Test-only delayed responder. Completion ignores cancellation deliberately:
/// a remote callback may still arrive after the user selects another entry.
@MainActor @Observable
private final class DiaryRewriteAuditResponder {
    struct Request: Identifiable {
        let id: String
        let note: String
    }
    enum SyntheticError: Error { case rejected }
    var pending: [Request] = []
    var completed: [String] = []
    var processed = 0
    var cancelledRequests: [String] = []
    private var sequence = 0
    @ObservationIgnored private var replies: [String: CheckedContinuation<String, any Error>] = [:]

    func rewrite(note: String, childName: String) async throws -> String {
        sequence += 1
        let id = (note.contains("沙发") ? "A" : "B") + String(sequence)
        defer { if Task.isCancelled { cancelledRequests.append(id) } }
        return try await withCheckedThrowingContinuation { reply in
            replies[id] = reply
            pending.append(Request(id: id, note: note))
        }
    }

    func complete(_ id: String, fail: Bool) {
        guard let reply = replies.removeValue(forKey: id) else { return }
        pending.removeAll { $0.id == id }
        completed.append(id + (fail ? "-failed" : "-success"))
        if fail { reply.resume(throwing: SyntheticError.rejected) }
        else { reply.resume(returning: "合成回复" + id) }
    }
}

/// The real diary view, real @Query records and save action. Only AI IO is replaced.
/// This route is reachable only with both explicit DEBUG/in-memory launch flags.
struct DiaryRewriteAuditHost: View {
    @State private var responder = DiaryRewriteAuditResponder()
    @State private var showingDiary = true
    @State private var archiveResult = ""
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.happenedAt, order: .reverse) private var entries: [Entry]

    var body: some View {
        Group {
            if showingDiary {
                FirstPersonDiaryView(auditRewrite: responder.rewrite, auditDidHandleReply: { responder.processed += 1 })
            } else {
                Text("已离开合成日记场景").accessibilityIdentifier("diary-audit.left")
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    HStack {
                        Button(showingDiary ? "离开日记" : "返回日记") { showingDiary.toggle() }
                            .accessibilityIdentifier("diary-audit.toggle-view")
                        Button("归档A") {
                            guard let entry = entries.first(where: { $0.id.uuidString.hasSuffix("000000000001") }) else { return }
                            entry.isArchived = true
                            do { try context.save(); archiveResult = "archived" }
                            catch { archiveResult = "failed" }
                        }.accessibilityIdentifier("diary-audit.archive-A")
                    }
                    Text(archiveResult).accessibilityIdentifier("diary-audit.archive-result")
                    Text(String(responder.cancelledRequests.count)).accessibilityIdentifier("diary-audit.cancelled-count")
                    ForEach(responder.pending) { request in
                        HStack {
                            Text("pending " + request.id)
                                .accessibilityIdentifier("diary-audit.pending." + request.id)
                            Button("返回" + request.id) { responder.complete(request.id, fail: false) }
                                .accessibilityIdentifier("diary-audit.success." + request.id)
                            Button("失败" + request.id) { responder.complete(request.id, fail: true) }
                                .accessibilityIdentifier("diary-audit.failure." + request.id)
                        }
                    }
                    Text(responder.completed.joined(separator: "|"))
                        .accessibilityIdentifier("diary-audit.completed")
                    Text(String(responder.processed)).accessibilityIdentifier("diary-audit.processed")
                    Text(String(responder.pending.count)).accessibilityIdentifier("diary-audit.pending-count")
                    ForEach(entries.prefix(2)) { entry in
                        Text((entry.firstPersonNote ?? "<empty>"))
                            .accessibilityIdentifier("diary-audit.saved." + entry.id.uuidString)
                    }
                }
                .font(.caption)
                .padding(6)
                .background(.regularMaterial)
            }
    }
}
#endif
