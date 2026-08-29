import Testing
@testable import BubuTimeMachine

struct MultipartFormDataTests {
    @Test("multipart 文件名不能注入换行、引号或路径")
    func sanitizesHeaderFilename() {
        let safe = MultipartFormData.safeFilename("../布布\"\r\nX-Evil: yes\\photo.jpg")
        #expect(!safe.contains("\r"))
        #expect(!safe.contains("\n"))
        #expect(!safe.contains("\""))
        #expect(!safe.contains("/"))
        #expect(!safe.contains("\\"))
        #expect(safe.hasSuffix("photo.jpg"))
    }

    @Test("空文件名使用安全兜底且超长名被限制")
    func boundsAndFallsBack() {
        #expect(MultipartFormData.safeFilename("   ") == "upload.bin")
        #expect(MultipartFormData.safeFilename(String(repeating: "a", count: 500)).count == 180)
    }
}
