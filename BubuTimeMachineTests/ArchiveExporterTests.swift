import Foundation
import Testing
@testable import BubuTimeMachine

@MainActor
struct ArchiveExporterTests {
    @Test("开放档案包含成长疫苗胶囊、不完整报告与 SHA 清单")
    func openArchiveIsCompleteAndHonest() throws {
        let date = Date(timeIntervalSince1970: 1_786_000_000)
        let capsuleID = UUID()
        let input = ArchiveExporter.ExportInput(
            childName: "布布",
            birthday: Date(timeIntervalSince1970: 1_716_307_200),
            entries: [],
            milestones: [],
            voiceMemos: [],
            healthRecords: [],
            growthMeasurements: [
                .init(measuredAt: date, heightCm: 88.2, weightKg: 12.4,
                      headCircumferenceCm: 48.0, note: "体检", source: "checkup")
            ],
            vaccines: [
                .init(vaccineName: "麻腮风", doseLabel: "第1剂", injectedAt: date,
                      hospital: "社区医院", injectionSite: nil, reaction: "无", note: nil)
            ],
            firstTimes: [],
            timeCapsules: [
                .init(id: capsuleID, title: "十八岁", fromRole: "爸爸", unlockAt: date,
                      isLocked: true, coverEmoji: "💌", encryptedBlobFileName: nil)
            ],
            unavailableReferences: ["time-capsule:test-id"])

        let result = try ArchiveExporter(mediaStore: MediaStore()).export(input)
        defer { try? FileManager.default.removeItem(at: result.root) }

        #expect(result.incompleteReferences == ["time-capsule:test-id"])
        let data = try Data(contentsOf: result.root.appendingPathComponent("data.json"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["archiveVersion"] as? Int == 3)
        #expect((json["growthMeasurements"] as? [[String: Any]])?.count == 1)
        #expect((json["vaccines"] as? [[String: Any]])?.count == 1)
        #expect((json["timeCapsules"] as? [[String: Any]])?.count == 1)
        #expect((json["timeCapsules"] as? [[String: Any]])?.first?["id"] as? String
                == capsuleID.uuidString)

        let readme = try String(
            contentsOf: result.root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("本次档案不完整"))
        #expect(readme.contains("time-capsule:test-id"))

        let manifest = try String(
            contentsOf: result.root.appendingPathComponent("manifest.sha256"), encoding: .utf8)
        #expect(manifest.contains("  data.json"))
        #expect(manifest.contains("  index.html"))
        #expect(manifest.contains("  README.md"))
    }
}
