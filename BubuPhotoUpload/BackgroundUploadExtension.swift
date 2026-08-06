import ExtensionFoundation
import Foundation
import Photos

@available(iOS 26.1, *)
@main
final class BackgroundUploadExtension: PHBackgroundResourceUploadExtension {
    private let store = PhotoIntakeStore()
    private let library = PHPhotoLibrary.shared()

    required init() {}

    func process() -> PHBackgroundResourceUploadProcessingResult {
        do {
            if try retryFailedJobs() { return .processing }
            try acknowledgeTerminalJobs()
            try registerQueuedJobs()
            let remaining = try store.uploadJobs(
                states: [.queued, .registered, .retrying], limit: 1)
            return remaining.isEmpty ? .completed : .processing
        } catch {
            return .failure
        }
    }

    func notifyTermination() {}

    /// Retry is deliberately a separate pass. A failed job must not be
    /// acknowledged in the same process call before Photos applies the retry.
    private func retryFailedJobs() throws -> Bool {
        let jobs = PHAssetResourceUploadJob.fetchJobs(action: .retry, options: nil)
        guard jobs.count > 0 else { return false }
        var retried: [(String, String)] = []
        try library.performChangesAndWait {
            jobs.enumerateObjects { job, _, _ in
                guard let ids = Self.identifiers(from: job.destination.url),
                      let local = try? self.store.uploadJobs(states: [.registered, .retrying, .failed])
                        .first(where: { $0.batchID == ids.batchID && $0.assetKey == ids.assetKey }),
                      local.retryCount == 0,
                      let request = PHAssetResourceUploadJobChangeRequest(for: job) else { return }
                request.retry(destination: job.destination)
                retried.append((ids.batchID, ids.assetKey))
            }
        }
        for (batchID, assetKey) in retried {
            try store.updateUploadJob(
                batchID: batchID, assetKey: assetKey, state: .retrying, retryCount: 1)
        }
        return !retried.isEmpty
    }

    private func acknowledgeTerminalJobs() throws {
        let jobs = PHAssetResourceUploadJob.fetchJobs(action: .acknowledge, options: nil)
        guard jobs.count > 0 else { return }
        var outcomes: [(String, String, PhotoUploadJobState)] = []
        jobs.enumerateObjects { job, _, _ in
            guard let ids = Self.identifiers(from: job.destination.url) else { return }
            let state: PhotoUploadJobState = job.state == .succeeded ? .succeeded : .failed
            outcomes.append((ids.batchID, ids.assetKey, state))
        }

        // Durable state must lead Photos acknowledgement. acknowledge() releases
        // the system job slot; if the extension is killed immediately afterwards,
        // there is no Photos job left from which SQLite could recover the outcome.
        // Replaying these idempotent writes before acknowledgement is safe.
        for (batchID, assetKey, state) in outcomes {
            try store.updateUploadJob(batchID: batchID, assetKey: assetKey, state: state)
        }

        var acknowledged: [(String, String)] = []
        try library.performChangesAndWait {
            jobs.enumerateObjects { job, _, _ in
                guard let ids = Self.identifiers(from: job.destination.url),
                      let request = PHAssetResourceUploadJobChangeRequest(for: job) else { return }
                request.acknowledge()
                acknowledged.append((ids.batchID, ids.assetKey))
            }
        }

        let expectedByBatch = Dictionary(grouping: outcomes, by: { $0.0 }).mapValues(\.count)
        let acknowledgedByBatch = Dictionary(grouping: acknowledged, by: { $0.0 }).mapValues(\.count)
        for batchID in expectedByBatch.keys where
            acknowledgedByBatch[batchID] == expectedByBatch[batchID] {
            try store.reconcileUploadBatch(batchID)
        }
    }

    private func registerQueuedJobs() throws {
        guard #available(iOS 26.4, *) else { return }
        let activeCount = try store.uploadJobs(states: [.registered, .retrying]).count
        let available = max(0, PHAssetResourceUploadJob.jobLimit - activeCount)
        guard available > 0 else { return }
        let queued = try store.uploadJobs(states: [.queued], limit: available)
        guard !queued.isEmpty else { return }
        let identifiers = Array(Set(queued.map(\.assetLocalIdentifier)))
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byID: [String: PHAsset] = [:]
        assets.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }

        var registered: [(String, String)] = []
        var missing: [(String, String)] = []
        try library.performChangesAndWait {
            for job in queued {
                guard let asset = byID[job.assetLocalIdentifier] else {
                    missing.append((job.batchID, job.assetKey))
                    continue
                }
                guard let resource = PHAssetResource.assetResources(for: asset).first(where: {
                          $0.type.rawValue == job.resourceType
                              && $0.originalFilename == job.resourceFilename
                      }), let url = URL(string: job.destinationURL) else {
                    missing.append((job.batchID, job.assetKey))
                    continue
                }
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue(job.uploadToken, forHTTPHeaderField: "X-Bubu-Upload-Token")
                request.setValue(job.mimeType, forHTTPHeaderField: "Content-Type")
                _ = PHAssetResourceUploadJobChangeRequest.creationRequestForJob(
                    destination: request, resource: resource)
                registered.append((job.batchID, job.assetKey))
            }
        }
        for (batchID, assetKey) in registered {
            try store.updateUploadJob(
                batchID: batchID, assetKey: assetKey, state: .registered)
        }
        for (batchID, assetKey) in missing {
            try store.updateUploadJob(batchID: batchID, assetKey: assetKey, state: .failed)
            try store.reconcileUploadBatch(batchID)
        }
    }

    private static func identifiers(from url: URL?) -> (batchID: String, assetKey: String)? {
        guard let components = url?.pathComponents,
              components.count >= 2 else { return nil }
        let assetKey = components[components.count - 1]
        let batchID = components[components.count - 2]
        guard UUID(uuidString: assetKey) != nil, UUID(uuidString: batchID) != nil else { return nil }
        return (batchID, assetKey)
    }
}
