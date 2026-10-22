import UIKit

/// Server bytes → display-sized decoded image, shared by grid cells, detail pages and prefetch,
/// so a thumbnail decoded for the grid can stand in under the detail image the moment it opens.
nonisolated enum LearningImagePipeline {
    static func key(scope: String, path: String, bucket: Int) -> String {
        scope + "|" + path + "|" + String(bucket)
    }

    /// A decoded copy at `bucket` or sharper.
    static func cached(scope: String, path: String, atLeast bucket: Int) -> UIImage? {
        for size in LearningImageDecoder.buckets where size >= bucket {
            if let hit = LearningImageMemory.shared.image(key(scope: scope, path: path, bucket: size)) { return hit }
        }
        return nil
    }

    /// The sharpest decoded copy of any size: a placeholder under a larger image, never the final picture.
    static func anyCached(scope: String, path: String) -> UIImage? {
        for size in LearningImageDecoder.buckets.reversed() {
            if let hit = LearningImageMemory.shared.image(key(scope: scope, path: path, bucket: size)) { return hit }
        }
        return nil
    }

    /// Memory, then (optionally) disk, then network; decodes off the main actor and remembers the result.
    @concurrent
    static func load(_ path: String, client: BubuLearningClient, bucket: Int, diskCache: Bool) async throws -> UIImage {
        if let hit = cached(scope: client.scope, path: path, atLeast: bucket) { return hit }
        let data = try await client.mediaData(path, cache: diskCache)
        try Task.checkCancellation()
        guard let image = LearningImageDecoder.downsample(data, maxPixel: bucket) else {
            throw LearningServiceError.invalidResponse
        }
        LearningImageMemory.shared.store(image, for: key(scope: client.scope, path: path, bucket: bucket))
        return image
    }

    /// Warms disk and memory for an image the user is likely to open next. Failures are silent:
    /// the page loads it again on its own when it appears.
    @concurrent
    static func prefetch(_ path: String, client: BubuLearningClient, bucket: Int) async {
        guard !path.isEmpty, bucket > 0 else { return }
        _ = try? await load(path, client: client, bucket: bucket, diskCache: true)
    }
}
