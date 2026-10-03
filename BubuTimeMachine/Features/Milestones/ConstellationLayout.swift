import Foundation

/// Each star owns a non-overlapping cell. Slight vertical staggering preserves
/// the constellation appearance without placing extra stars on earlier labels.
struct ConstellationLayout {
    let targetSize: CGSize
    let positions: [CGPoint]
    let height: CGFloat

    static func make(count: Int, width: CGFloat, minimumTargetWidth: CGFloat,
                     targetHeight: CGFloat, maximumColumns: Int) -> Self {
        let padding: CGFloat = 16
        let gap: CGFloat = 16
        let available = max(1, width - padding * 2)
        let minimumWidth = max(44, minimumTargetWidth)
        let columnLimit = min(max(1, count), max(1, maximumColumns))
        let columns = max(1, min(columnLimit, Int((available + gap) / (minimumWidth + gap))))
        let targetWidth = max(1, (available - CGFloat(columns - 1) * gap) / CGFloat(columns))
        let height = max(44, targetHeight)
        let rowHeight = height + 24
        let rows = max(1, (max(0, count) + columns - 1) / columns)
        let positions = (0..<max(0, count)).map { index in
            let column = index % columns, row = index / columns
            let stagger: CGFloat = column % 2 == 0 ? -5 : 5
            return CGPoint(x: padding + targetWidth / 2 + CGFloat(column) * (targetWidth + gap),
                           y: padding + rowHeight * (CGFloat(row) + 0.5) + stagger)
        }
        return Self(targetSize: CGSize(width: targetWidth, height: height), positions: positions,
                    height: padding * 2 + CGFloat(rows) * rowHeight)
    }
}
