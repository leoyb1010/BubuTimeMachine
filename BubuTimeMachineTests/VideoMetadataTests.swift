import Foundation
import AVFoundation
import CoreVideo
import Testing
#if !MEDIA_HELPER_TESTS
@testable import BubuTimeMachine
#endif

@MainActor
struct VideoMetadataTests {
    @Test("来源时间码在有限视频时长内，缺失或非数值不触发跳转")
    func sourceTimecodeStaysInBounds() {
        #expect(VideoStartPosition.seconds(requested: 13.5, duration: 73) == 13.5)
        #expect(VideoStartPosition.seconds(requested: -2, duration: 73) == 0)
        #expect(VideoStartPosition.seconds(requested: 99, duration: 73) == 73)
        #expect(VideoStartPosition.seconds(requested: nil, duration: 73) == nil)
        #expect(VideoStartPosition.seconds(requested: .infinity, duration: 73) == nil)
        #expect(VideoStartPosition.seconds(requested: .nan, duration: 73) == nil)
        #expect(VideoStartPosition.seconds(requested: 10, duration: .nan) == nil)
        #expect(VideoStartPosition.seconds(requested: 10, duration: .infinity) == nil)
    }

    @Test("读取保存的视频时长，并按显示方向解释尺寸", arguments: [false, true])
    func readsStoredVideo(rotated: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Self.makeVideo(at: url, rotated: rotated)
        let metadata = await VideoMetadata.read(from: url)
        #expect(metadata.width == (rotated ? 16 : 32))
        #expect(metadata.height == (rotated ? 32 : 16))
        #expect((metadata.duration ?? 0) >= 1)
    }

    @Test("无法读取的文件保留未知值，不伪造零时长")
    func unreadableMetadataStaysUnknown() async {
        let metadata = await VideoMetadata.read(from: URL(fileURLWithPath: "/missing/\(UUID()).mp4"))
        #expect(metadata.duration == nil)
        #expect(metadata.width == nil)
        #expect(metadata.height == nil)
    }

    static func makeVideo(at url: URL, rotated: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 16
        ])
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 16, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: 32,
                                         kCVPixelBufferHeightKey as String: 16])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 32, 16, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        #expect(status == kCVReturnSuccess)
        let frame = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(frame, [])
        if let base = CVPixelBufferGetBaseAddress(frame) {
            memset(base, 100, CVPixelBufferGetDataSize(frame))
        }
        CVPixelBufferUnlockBaseAddress(frame, [])
        for seconds in [0, 1] {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(input.isReadyForMoreMediaData)
            #expect(adaptor.append(frame, withPresentationTime: CMTime(seconds: Double(seconds), preferredTimescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }
}
