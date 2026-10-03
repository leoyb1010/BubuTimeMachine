import Foundation
import Testing
@testable import BubuTimeMachine

@MainActor
struct ConstellationLayoutTests {
    @Test("十二颗星在窄屏、宽屏和放大字号中保持独立可点区域")
    func slotsStayInsideBoardAndNeverIntersect() {
        let widths: [CGFloat] = [160, 288, 320, 358, 768, 1024]
        let scales: [CGFloat] = [1, 1.5, 2.5]
        for width in widths {
            for scale in scales {
                for count in 1...12 {
                    let plan = ConstellationLayout.make(count: count, width: width,
                        minimumTargetWidth: 88 * scale, targetHeight: 54 + 45 * scale,
                        maximumColumns: width > 600 ? 4 : 3)
                    let board = CGRect(x: 0, y: 0, width: width, height: plan.height)
                    let frames = plan.positions.map { point in
                        CGRect(x: point.x - plan.targetSize.width / 2,
                               y: point.y - plan.targetSize.height / 2,
                               width: plan.targetSize.width, height: plan.targetSize.height)
                    }
                    #expect(frames.count == count)
                    #expect(plan.targetSize.width >= 44 && plan.targetSize.height >= 44)
                    #expect(frames.allSatisfy { board.contains($0) })
                    for first in frames.indices {
                        for second in frames.indices where second > first {
                            #expect(!frames[first].intersects(frames[second]))
                        }
                    }
                }
            }
        }
    }

    @Test("布局确定且空清单不制造星；增大字体只增加所需纵向空间")
    func emptyAndDeterministicLayout() {
        let empty = ConstellationLayout.make(count: 0, width: 358,
            minimumTargetWidth: 88, targetHeight: 99, maximumColumns: 3)
        #expect(empty.positions.isEmpty)
        let single = ConstellationLayout.make(count: 1, width: 358,
            minimumTargetWidth: 88, targetHeight: 99, maximumColumns: 3)
        #expect(single.positions.first?.x == 179)
        let normal = ConstellationLayout.make(count: 12, width: 358,
            minimumTargetWidth: 88, targetHeight: 99, maximumColumns: 3)
        let repeated = ConstellationLayout.make(count: 12, width: 358,
            minimumTargetWidth: 88, targetHeight: 99, maximumColumns: 3)
        let large = ConstellationLayout.make(count: 12, width: 358,
            minimumTargetWidth: 176, targetHeight: 144, maximumColumns: 3)
        #expect(normal.positions == repeated.positions)
        #expect(large.height > normal.height)
    }
}
