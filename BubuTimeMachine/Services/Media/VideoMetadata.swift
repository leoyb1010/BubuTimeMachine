import Foundation
import AVFoundation

nonisolated enum VideoStartPosition {
    static func seconds(requested: Double?, duration: Double) -> Double? {
        guard let requested, requested.isFinite, duration.isFinite, duration > 0 else { return nil }
        return min(max(0, requested), duration)
    }
}

nonisolated struct VideoMetadata: Sendable {
    var duration: Double?
    var width: Int?
    var height: Int?

    @concurrent
    static func read(from url: URL) async -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        var result = VideoMetadata()
        if let time = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite && seconds > 0 { result.duration = seconds }
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let display = CGRect(origin: .zero, size: size).applying(transform).standardized.size
            if display.width.isFinite, display.height.isFinite,
               display.width >= 1, display.height >= 1,
               display.width < CGFloat(Int.max), display.height < CGFloat(Int.max) {
                result.width = Int(display.width.rounded())
                result.height = Int(display.height.rounded())
            }
        }
        return result
    }
}
