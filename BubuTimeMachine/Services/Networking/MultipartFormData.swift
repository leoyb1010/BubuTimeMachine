import Foundation

/// multipart 头部只允许单行、安全的文件名。正文内容不改，服务器仍能收到原文件字节。
nonisolated enum MultipartFormData {
    static func safeFilename(_ raw: String, fallback: String = "upload.bin") -> String {
        let forbidden = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "\"\\/"))
        let cleaned = raw.unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? "_" : String(scalar)
        }.joined()
        let bounded = String(cleaned.prefix(180))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.isEmpty ? fallback : bounded
    }
}
