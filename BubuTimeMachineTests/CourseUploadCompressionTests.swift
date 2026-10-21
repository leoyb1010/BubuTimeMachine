import Testing
import Foundation
import AVFoundation
@testable import BubuTimeMachine

/// 大视频在上传前压缩到 720p，确保单个请求低于家庭服务前置代理的上限，且保留老师声音。
struct CourseUploadCompressionTests {
    @Test func largeClassroomVideoShrinksBelowRequestLimitAndKeepsAudio() async throws {
        let source = URL(fileURLWithPath: "/private/tmp/bubu-uitest/large-1080p.mp4")
        try #require(FileManager.default.fileExists(atPath: source.path), "需要本机测试视频")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("large-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: source, to: copy)
        let input = LearningUploadFile(url: copy, fileName: "课堂.mp4", mimeType: "video/mp4")
        #expect(CourseUploadSheet.size(of: copy) > CourseUploadSheet.compressAboveBytes)
        let output = try await CourseUploadSheet.compress(input)
        #expect(output.url != copy && output.mimeType == "video/mp4" && output.fileName == "课堂.mp4")
        #expect(CourseUploadSheet.size(of: output.url) < CourseUploadSheet.maxRequestBytes)
        let asset = AVURLAsset(url: output.url)
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty)
        let original = try await AVURLAsset(url: copy).load(.duration).seconds
        let compressed = try await asset.load(.duration).seconds
        #expect(abs(original - compressed) < 1)
    }
}
