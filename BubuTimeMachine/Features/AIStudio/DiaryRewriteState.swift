import Foundation

/// Every generated draft belongs to one record and one request, never to whichever
/// record happens to be selected when an asynchronous callback arrives.
struct DiaryRewriteState {
    struct Draft: Equatable {
        var activeRequest: UUID?
        var presentation: UUID?
        var output = ""
        var displayed = ""
        var error: String?
        var saveError: String?
        var saved = false
    }
    private var drafts: [UUID: Draft] = [:]

    func draft(for entryID: UUID) -> Draft { drafts[entryID] ?? Draft() }

    mutating func begin(for entryID: UUID) -> UUID? {
        guard drafts[entryID]?.activeRequest == nil else { return nil }
        let token = UUID()
        drafts[entryID] = Draft(activeRequest: token)
        return token
    }

    @discardableResult
    mutating func succeed(_ text: String, for entryID: UUID, request: UUID,
                          revealImmediately: Bool) -> Bool {
        guard drafts[entryID]?.activeRequest == request else { return false }
        drafts[entryID] = Draft(presentation: request, output: text,
                                displayed: revealImmediately ? text : "")
        return true
    }

    @discardableResult
    mutating func fail(_ message: String, for entryID: UUID, request: UUID) -> Bool {
        guard drafts[entryID]?.activeRequest == request else { return false }
        drafts[entryID] = Draft(error: message)
        return true
    }

    mutating func cancel(for entryID: UUID) {
        guard var draft = drafts[entryID] else { return }
        draft.activeRequest = nil
        draft.presentation = nil
        draft.displayed = draft.output
        drafts[entryID] = draft
    }

    mutating func finishPresentation(for entryID: UUID) {
        guard var draft = drafts[entryID] else { return }
        draft.displayed = draft.output
        draft.presentation = nil
        drafts[entryID] = draft
    }

    @discardableResult
    mutating func append(_ character: Character, for entryID: UUID, presentation: UUID) -> Bool {
        guard drafts[entryID]?.presentation == presentation else { return false }
        drafts[entryID]?.displayed.append(character)
        return true
    }
    mutating func saved(for entryID: UUID) {
        drafts[entryID]?.saved = true
        drafts[entryID]?.saveError = nil
    }

    mutating func saveFailed(for entryID: UUID, message: String?) {
        drafts[entryID]?.saveError = message
    }

}
