import Foundation
import Observation

/// The signed URL belongs to this playback attempt, not the lifetime of a cached gallery page.
@MainActor @Observable
final class RemoteVideoPlayback {
    private(set) var playableURL: URL?
    private(set) var isLoading = false
    private(set) var failed = false
    private var requestID = UUID()

    func resolve(using signer: () async throws -> URL) async {
        let request = UUID()
        requestID = request
        playableURL = nil
        isLoading = true
        failed = false
        do {
            let url = try await signer()
            guard requestID == request else { return }
            isLoading = false
            guard !Task.isCancelled else { return }
            playableURL = url
        } catch {
            guard requestID == request else { return }
            isLoading = false
            failed = !Task.isCancelled
        }
    }

    func playbackFailed(for url: URL) {
        guard playableURL == url else { return }
        playableURL = nil
        failed = true
    }

    func cancel() {
        requestID = UUID()
        playableURL = nil
        isLoading = false
    }
}
