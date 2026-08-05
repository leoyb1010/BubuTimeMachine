import Foundation
import Testing
@testable import BubuTimeMachine

@MainActor
struct SemanticSearchTests {
    @Test("服务端语义响应解码并忽略不下发给 UI 的文件地址")
    func responseDecoding() throws {
        let json = """
        {
          "query": "在公园荡秋千",
          "model_version": "mobileclip-s0",
          "hits": [{
            "asset_id": "media-1",
            "entry_local_id": "76F8E681-77A6-4382-921C-51DF311F7192",
            "media_record_id": "record-1",
            "file_url": "https://private.example/protected.jpg",
            "captured_at": "2026-08-05T12:00:00Z",
            "caption": "第一次玩秋千",
            "tags": ["公园"],
            "score": 0.91,
            "reason": "画面语义接近‘荡秋千’"
          }]
        }
        """
        let response = try JSONDecoder().decode(SemanticSearchResponse.self, from: Data(json.utf8))

        #expect(response.query == "在公园荡秋千")
        #expect(response.hits.first?.mediaRecordId == "record-1")
        #expect(response.hits.first?.reason.contains("秋千") == true)
    }

    @Test("每条本地记录只保留最高分来源，远端孤儿结果不会出现在时光轴")
    func resolverKeepsBestLocalHit() {
        let localID = UUID(uuidString: "76F8E681-77A6-4382-921C-51DF311F7192")!
        let missingID = UUID(uuidString: "6BC5E2EF-2859-4D74-A31D-EFC637326337")!
        let low = hit(entryID: localID, asset: "low", score: 0.4)
        let high = hit(entryID: localID, asset: "high", score: 0.9)
        let orphan = hit(entryID: missingID, asset: "orphan", score: 1.0)

        let result = TimelineSemanticSearchResolver.bestHits(
            [low, orphan, high],
            availableEntryIDs: [localID]
        )

        #expect(result.count == 1)
        #expect(result[localID]?.assetId == "high")
    }

    private func hit(entryID: UUID, asset: String, score: Double) -> SemanticSearchHit {
        SemanticSearchHit(
            assetId: asset,
            entryLocalId: entryID.uuidString,
            mediaRecordId: "record-\(asset)",
            capturedAt: "2026-08-05T12:00:00Z",
            score: score,
            reason: "画面语义匹配"
        )
    }
}
