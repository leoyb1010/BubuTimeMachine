import CryptoKit
import Foundation

nonisolated struct PhotoEventGroup: Identifiable, Sendable, Equatable {
    let id: String
    let assetIdentifiers: [String]
    let startedAt: Date
    let endedAt: Date
    let photoCount: Int
    let videoCount: Int
    let livePhotoCount: Int

    var totalCount: Int { assetIdentifiers.count }
}

/// 第一阶段只使用可解释的时间、地点和连拍规则；视觉相似度在 G1B 接入。
nonisolated enum PhotoEventClusterer {
    static func cluster(
        _ candidates: [PhotoIntakeCandidate],
        maximumTimeGap: TimeInterval = 90 * 60,
        locationSplitDistance: Double = 1_500,
        minimumGapForLocationSplit: TimeInterval = 15 * 60,
        calendar: Calendar = .current
    ) -> [PhotoEventGroup] {
        let sorted = candidates.sorted {
            if $0.creationDate != $1.creationDate { return $0.creationDate < $1.creationDate }
            return $0.localIdentifier < $1.localIdentifier
        }
        guard let first = sorted.first else { return [] }

        var buckets: [[PhotoIntakeCandidate]] = [[first]]
        for candidate in sorted.dropFirst() {
            guard let previous = buckets[buckets.count - 1].last else { continue }
            if shouldSplit(previous: previous, next: candidate,
                           maximumTimeGap: maximumTimeGap,
                           locationSplitDistance: locationSplitDistance,
                           minimumGapForLocationSplit: minimumGapForLocationSplit,
                           calendar: calendar) {
                buckets.append([candidate])
            } else {
                buckets[buckets.count - 1].append(candidate)
            }
        }

        return buckets.map(makeGroup).sorted { $0.startedAt > $1.startedAt }
    }

    private static func shouldSplit(
        previous: PhotoIntakeCandidate,
        next: PhotoIntakeCandidate,
        maximumTimeGap: TimeInterval,
        locationSplitDistance: Double,
        minimumGapForLocationSplit: TimeInterval,
        calendar: Calendar
    ) -> Bool {
        if let burst = previous.burstIdentifier,
           burst == next.burstIdentifier { return false }

        let gap = max(0, next.creationDate.timeIntervalSince(previous.creationDate))
        if gap > maximumTimeGap { return true }
        if !calendar.isDate(previous.creationDate, inSameDayAs: next.creationDate),
           gap > 30 * 60 { return true }

        if gap >= minimumGapForLocationSplit,
           let distance = distanceMeters(from: previous, to: next),
           distance > locationSplitDistance {
            return true
        }
        return false
    }

    private static func makeGroup(_ candidates: [PhotoIntakeCandidate]) -> PhotoEventGroup {
        let identifiers = candidates.map(\.localIdentifier)
        let digest = SHA256.hash(data: Data(identifiers.sorted().joined(separator: "\n").utf8))
        let id = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return PhotoEventGroup(
            id: id,
            assetIdentifiers: identifiers,
            startedAt: candidates.first?.creationDate ?? .distantPast,
            endedAt: candidates.last?.creationDate ?? .distantPast,
            photoCount: candidates.count { $0.mediaKind == .photo },
            videoCount: candidates.count { $0.mediaKind == .video },
            livePhotoCount: candidates.count { $0.isLivePhoto }
        )
    }

    private static func distanceMeters(
        from lhs: PhotoIntakeCandidate,
        to rhs: PhotoIntakeCandidate
    ) -> Double? {
        guard let lat1 = lhs.latitude, let lon1 = lhs.longitude,
              let lat2 = rhs.latitude, let lon2 = rhs.longitude else { return nil }
        let radius = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
