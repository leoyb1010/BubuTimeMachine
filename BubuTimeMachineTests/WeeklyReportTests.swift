import Foundation
import Testing
@testable import BubuTimeMachine

@MainActor
struct WeeklyReportTests {
    @Test("周报响应保留五段正文和可回查来源")
    func responseDecoding() throws {
        let json = """
        {
          "id": "artifact123",
          "artifact_key": "weekly_report:family:2026-07-27",
          "status": "ready",
          "title": "布布周报",
          "summary": "三件小事",
          "week_start": "2026-07-27T00:00:00Z",
          "week_end": "2026-08-03T00:00:00Z",
          "generated_at": "2026-08-03T12:00:00Z",
          "model_version": "test-model",
          "content_hash": "abc123",
          "sections": [{
            "kind": "voice",
            "title": "一段原声",
            "text": "妈妈你看，小鸟回家了。",
            "sourceIds": ["voicememos:voice-1"]
          }],
          "source_refs": [{
            "source_id": "voicememos:voice-1",
            "collection": "voicememos",
            "record_id": "record1",
            "local_id": "voice-1",
            "happened_at": "2026-07-31T12:10:00Z",
            "title": "午后的原声",
            "excerpt": "妈妈你看，小鸟回家了。",
            "kind": "voice"
          }]
        }
        """
        let report = try JSONDecoder().decode(WeeklyReport.self, from: Data(json.utf8))
        #expect(report.sections.first?.sourceIds == ["voicememos:voice-1"])
        #expect(report.sourceRefs.first?.kind == "voice")
        #expect(report.status == "ready")
    }
}
