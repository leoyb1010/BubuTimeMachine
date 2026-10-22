import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 2.27b：实时活动收尾 / 深链、统一「第一次」、成长曲线分段

@MainActor
struct Learning2_27bTests {

    // MARK: 课程上传实时活动：启动/回前台核对

    @Test func reconcileDismissesWhenTimedOut() {
        #expect(CourseUploadReconciler.action(phase: .parsing, trackedID: "c1", timedOut: true, hasClient: true) == .dismiss)
    }

    @Test func reconcileMarksInterruptedUploadFailed() {
        // 被杀/挂起前还没建好课程：只能如实显示「没有完成」。
        #expect(CourseUploadReconciler.action(phase: .compressing, trackedID: nil, timedOut: false, hasClient: true) == .markFailed)
        #expect(CourseUploadReconciler.action(phase: .uploading, trackedID: nil, timedOut: false, hasClient: true) == .markFailed)
        // 课程已建好：先问服务端，也许其实传完了。
        #expect(CourseUploadReconciler.action(phase: .uploading, trackedID: "c1", timedOut: false, hasClient: true) == .askServer("c1"))
    }

    @Test func reconcileAsksServerWhileParsing() {
        #expect(CourseUploadReconciler.action(phase: .parsing, trackedID: "c1", timedOut: false, hasClient: true) == .askServer("c1"))
        #expect(CourseUploadReconciler.action(phase: .parsing, trackedID: "c1", timedOut: false, hasClient: false) == .keep)
        // 解析中却找不到跟踪的课程（旧版本留下的）：收起。
        #expect(CourseUploadReconciler.action(phase: .parsing, trackedID: nil, timedOut: false, hasClient: true) == .dismiss)
    }

    @Test func reconcileKeepsFinalStates() {
        #expect(CourseUploadReconciler.action(phase: .ready, trackedID: nil, timedOut: false, hasClient: true) == .keep)
        #expect(CourseUploadReconciler.action(phase: .failed, trackedID: nil, timedOut: false, hasClient: true) == .keep)
    }

    @Test func liveActivityDeepLinks() {
        let url = BubuActivityAttributes.learningURL(schoolDate: "2026-10-21")
        #expect(url.absoluteString == "bubu://learning?date=2026-10-21")
        let course = BubuActivityAttributes(kind: .courseUpload, title: "水果", unlockAt: nil, childName: "布布", deepLink: url)
        #expect(course.widgetURL == url)
        let sleep = BubuActivityAttributes(kind: .sleepTimer, title: "睡着啦", unlockAt: nil, childName: "布布")
        #expect(sleep.widgetURL.host == "growth")
        // 深链能被路由识别：每日学习切到那一天。
        let router = BubuRouter()
        router.handle(url)
        #expect(router.pendingLearningDay == "2026-10-21")
    }

    @Test func parsingHintDoesNotPromiseLockScreenProgress() {
        #expect(CourseUploadActivityPhase.parsing.hint(childName: "布布").contains("回 App"))
        #expect(CourseUploadActivityPhase.failed.hint(childName: "布布").contains("接着传"))
    }

    @Test func sleepDurationText() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(SleepActivityText.duration(from: start, to: start.addingTimeInterval(95 * 60)) == "1小时35分钟")
        #expect(SleepActivityText.duration(from: start, to: start.addingTimeInterval(2 * 3600)) == "2小时")
        #expect(SleepActivityText.duration(from: start, to: start.addingTimeInterval(20 * 60)) == "20分钟")
    }

    // MARK: 统一「第一次」

    @Test func firstsUnionDeduplicatesAcrossSources() throws {
        let json = """
        {"items":[
          {"id":"f1","concept":"walk","title":"第一次独立行走","date":"2025-06-14","status":"confirmed"},
          {"id":"f2","concept":"swim","title":"第一次游泳","date":"2024-06-10","status":"confirmed"}
        ]}
        """
        let brain = try JSONDecoder.learningDecoderForTests.decode(GrowthFirstListDTO.self, from: Data(json.utf8)).items
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let merged = GrowthFirstsUnion.merge(
            family: [(id: "a", title: "第一次独立行走！", date: day)],
            litFromBrain: [(id: "m", title: "第一次游泳", date: nil)],
            confirmedBrain: brain)
        #expect(merged.count == 2)
        // 本机记录优先保留。
        #expect(merged.first { GrowthFirstsUnion.key($0.title) == GrowthFirstsUnion.key("第一次独立行走") }?.source == .family)
        #expect(merged.contains { $0.title == "第一次游泳" && $0.source == .secondBrain })
    }

    @Test func firstsUnionSortsNewestFirst() {
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        let merged = GrowthFirstsUnion.merge(family: [(id: "1", title: "第一次笑", date: old), (id: "2", title: "第一次爬", date: new)],
                                             litFromBrain: [], confirmedBrain: [])
        #expect(merged.map(\.title) == ["第一次爬", "第一次笑"])
    }

    // MARK: 成长曲线：24 月卧位/立位分段

    @Test func heightBandsSplitAtTwoYears() {
        let bands = WHOGrowthStandard.bands(metric: .height, gender: nil).filter { $0.month <= 36 }
        let segments = GrowthCurveView.bandSegments(bands, splitAtTwoYears: true)
        #expect(segments.count == 2)
        #expect(segments[0].bands.allSatisfy { $0.month < 24 })
        #expect(segments[1].bands.allSatisfy { $0.month >= 24 })
        // 只到 24 月时立位段只有一个点，不画（避免末端的钩）。
        let toTwo = GrowthCurveView.bandSegments(bands.filter { $0.month <= 24 }, splitAtTwoYears: true)
        #expect(toTwo.count == 1)
        #expect(GrowthCurveView.bandSegments(bands, splitAtTwoYears: false).count == 1)
    }
}

private extension JSONDecoder {
    static var learningDecoderForTests: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
