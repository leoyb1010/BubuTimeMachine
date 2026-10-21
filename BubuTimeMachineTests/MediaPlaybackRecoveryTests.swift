import Foundation
import Testing
#if !MEDIA_HELPER_TESTS
@testable import BubuTimeMachine
#endif

@MainActor
struct MediaPlaybackRecoveryTests {
    @Test("媒体请求失败后放弃旧签名，重试可获取新地址")
    func failedMediaRenewsSignature() async {
        let state = RemoteVideoPlayback()
        let first = URL(string: "https://example.invalid/video.mp4?token=expired")!
        let next = URL(string: "https://example.invalid/video.mp4?token=new")!
        await state.resolve { first }
        state.playbackFailed(for: first)
        #expect(state.failed)
        #expect(state.playableURL == nil)
        var requests = 0
        await state.resolve { requests += 1; return next }
        #expect(requests == 1)
        #expect(state.playableURL == next)
        #expect(!state.failed)
    }

    @Test("重新进入缓存的相邻视频页也重新签名")
    func returningToCachedPageRenewsSignature() async {
        let state = RemoteVideoPlayback()
        let first = URL(string: "https://example.invalid/old")!
        let next = URL(string: "https://example.invalid/new")!
        await state.resolve { first }
        await state.resolve { next }
        #expect(state.playableURL == next)
        state.playbackFailed(for: first)
        #expect(!state.failed)
        #expect(state.playableURL == next)
    }

    @Test("页面退出后的签名响应不能重新挂回旧播放器")
    func lateSignatureIsDiscarded() async {
        let state = RemoteVideoPlayback()
        await state.resolve {
            state.cancel()
            return URL(string: "https://example.invalid/stale")!
        }
        #expect(state.playableURL == nil)
        #expect(!state.isLoading)
    }

    @Test("签名服务失败仍可重试")
    func signingFailureCanRetry() async {
        let state = RemoteVideoPlayback()
        await state.resolve { throw URLError(.notConnectedToInternet) }
        #expect(state.failed)
        #expect(!state.isLoading)
        await state.resolve { URL(string: "https://example.invalid/recovered")! }
        #expect(state.playableURL != nil)
        #expect(!state.failed)
    }
}

struct MediaFileAvailabilityTests {
    @Test("数据库还记着文件名，但丢失的照片必须回退远端")
    func staleFilenameDoesNotSelectLocalPhoto() {
        let url = MediaFileAvailability.localURL(fileName: "lost.jpg",
            resolve: { URL(fileURLWithPath: "/missing/" + $0) }, exists: { _ in false })
        #expect(url == nil)
    }

    @Test("存在的本地原件仍优先离线显示")
    func existingOriginalStaysLocal() {
        let expected = URL(fileURLWithPath: "/local/photo.jpg")
        #expect(MediaFileAvailability.localURL(fileName: "photo.jpg", resolve: { _ in expected },
            exists: { $0 == expected }) == expected)
    }

    @Test("恢复后缺文件的已同步记录进入补下载")
    func restoreMissingOriginal() {
        #expect(MediaFileAvailability.needsDownload(fileName: "lost.jpg",
            remoteURL: "https://example.invalid/photo.jpg", isSynced: true, exists: { _ in false }))
    }

    @Test("不覆盖待上传的本地素材，也不重下已有原件")
    func preservePendingAndAvailableOriginals() {
        #expect(!MediaFileAvailability.needsDownload(fileName: "new.jpg",
            remoteURL: "https://example.invalid/old.jpg", isSynced: false, exists: { _ in false }))
        #expect(!MediaFileAvailability.needsDownload(fileName: "ok.jpg",
            remoteURL: "https://example.invalid/ok.jpg", isSynced: true, exists: { _ in true }))
        #expect(!MediaFileAvailability.needsDownload(fileName: nil,
            remoteURL: nil, isSynced: true, exists: { _ in false }))
    }
}
