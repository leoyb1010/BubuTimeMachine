import Testing
import Foundation
@testable import BubuTimeMachine

@Suite("声音年轮契约")
struct SoundRingTests {
    @Test("服务端 snake_case 契约完整解码且不启用声音克隆")
    func decodesSoundRing() throws {
        let json = #"""
        {
          "id":"artifact123",
          "artifact_key":"sound_ring:family:hash",
          "status":"ready",
          "title":"布布的声音年轮 · 0—2岁",
          "summary":"3 段真实原声 · 3分20秒",
          "generated_at":"2026-08-06T08:00:00Z",
          "model_version":"sound-ring-v1-original-first",
          "original_duration_seconds":200,
          "rendered_duration_seconds":214,
          "attempts":1,
          "error":"",
          "narrator":"Apple 系统中性旁白",
          "voice_cloning":false,
          "has_audio":true,
          "clips":[{
            "source_id":"voicememos:voice-local",
            "photo_source_id":"entries:entry-local",
            "age_years":1,
            "kind":"childVoice",
            "title":"布布的声音",
            "recorded_at":"2025-08-06T08:00:00Z",
            "transcript":"小鸟回家啦。",
            "duration_seconds":70,
            "start_seconds":4,
            "end_seconds":74
          }],
          "source_refs":[{
            "source_id":"voicememos:voice-local",
            "collection":"voicememos",
            "record_id":"record1",
            "local_id":"voice-local",
            "happened_at":"2025-08-06T08:00:00Z",
            "title":"布布的声音",
            "excerpt":"小鸟回家啦。",
            "kind":"voice"
          }],
          "content_hash":"abc123"
        }
        """#.data(using: .utf8)!

        let ring = try JSONDecoder().decode(SoundRing.self, from: json)
        #expect(ring.status == "ready")
        #expect(ring.voiceCloning == false)
        #expect(ring.hasAudio)
        #expect(ring.clips.first?.sourceId == "voicememos:voice-local")
        #expect(ring.clips.first?.photoSourceId == "entries:entry-local")
        #expect(ring.sourceRefs.first?.localId == "voice-local")
    }

    @Test("片段标识稳定使用事实来源")
    func clipIdentityUsesSource() {
        let clip = SoundRingClip(
            sourceId: "voicememos:one", photoSourceId: "", ageYears: 0,
            kind: "childVoice", title: "布布的声音", recordedAt: "",
            transcript: "", durationSeconds: 60, startSeconds: 2, endSeconds: 62)
        #expect(clip.id == "voicememos:one")
        #expect(clip.endSeconds - clip.startSeconds == 60)
    }
}
