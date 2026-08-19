import Testing
import Foundation
@testable import BubuTimeMachine

// MARK: - 同步韧性回归测试
/// 钉两件在真机上很难复现、但一旦错了就长期不被发现的事：
/// ① 断网时的退避曲线（错了只表现为「有点费电」，没人会报）
/// ② 一轮同步的处理上限（没有上限时，首次全家上云会把主线程占几分钟）
struct SyncResilienceTests {

    @Test("没有失败时保持 30 秒基础节奏")
    func baseIntervalWhenHealthy() {
        #expect(SyncBackoff.interval(failures: 0) == 30)
    }

    @Test("连续失败按 2 的幂退避：30 → 60 → 120 → 240 → 480")
    func exponentialGrowth() {
        #expect(SyncBackoff.interval(failures: 1) == 60)
        #expect(SyncBackoff.interval(failures: 2) == 120)
        #expect(SyncBackoff.interval(failures: 3) == 240)
        #expect(SyncBackoff.interval(failures: 4) == 480)
    }

    @Test("退避封顶在 8 分钟——再长会让「服务器修好了」迟迟不被发现")
    func cappedAtEightMinutes() {
        for failures in 5...50 {
            #expect(SyncBackoff.interval(failures: failures) == SyncBackoff.maxInterval)
        }
        #expect(SyncBackoff.maxInterval == 480)
    }

    @Test("退避曲线单调不减，且永远不小于基础间隔")
    func monotonicAndNeverFasterThanBase() {
        var previous = SyncBackoff.interval(failures: 0)
        for failures in 1...20 {
            let current = SyncBackoff.interval(failures: failures)
            #expect(current >= previous)
            #expect(current >= SyncBackoff.baseInterval)
            previous = current
        }
    }

    @Test("一轮同步的推送上限存在且有界")
    func pushBatchIsBounded() async {
        // 无上限时，首次全家上云 / SSD 批量导入后的几千条待推会一次性取回内存并逐条推，
        // 整轮几分钟全程占用主线程。上限必须存在，且不能大到失去意义。
        #expect(SyncEngine.pushBatchCap > 0)
        #expect(SyncEngine.pushBatchCap <= 500)
    }
}

// MARK: - 时光轴卡片文案回归测试
/// v2.10.1 及更早：没有标题的记录会把正文顶上去当标题，下面那行摘要又原样再渲染一次，
/// 同一句话在同一张卡上下重复。这里把规则钉死。
struct TimelineCardTextTests {

    @Test("有标题时用标题，正文作为副文案")
    func titleAndNote() {
        #expect(TimelineCardText.headline(title: "第一次站起来", note: "扶着沙发") == "第一次站起来")
        #expect(TimelineCardText.subtitle(title: "第一次站起来", note: "扶着沙发") == "扶着沙发")
    }

    @Test("没有标题时正文顶上去当标题，且不再重复渲染为副文案")
    func noteBecomesHeadlineOnce() {
        #expect(TimelineCardText.headline(title: nil, note: "今天也很可爱") == "今天也很可爱")
        #expect(TimelineCardText.subtitle(title: nil, note: "今天也很可爱") == nil)
        // 空字符串等价于没有标题
        #expect(TimelineCardText.headline(title: "", note: "今天也很可爱") == "今天也很可爱")
        #expect(TimelineCardText.subtitle(title: "", note: "今天也很可爱") == nil)
    }

    @Test("标题与正文逐字相同时不重复显示")
    func identicalTitleAndNote() {
        #expect(TimelineCardText.headline(title: "布布的笑", note: "布布的笑") == "布布的笑")
        #expect(TimelineCardText.subtitle(title: "布布的笑", note: "布布的笑") == nil)
    }

    @Test("既没有标题也没有正文时回落到「记录此刻」，且没有副文案")
    func emptyEntry() {
        #expect(TimelineCardText.headline(title: nil, note: nil) == "记录此刻")
        #expect(TimelineCardText.subtitle(title: nil, note: nil) == nil)
        #expect(TimelineCardText.headline(title: "", note: "") == "记录此刻")
    }
}
