import Foundation
import CryptoKit
import WebKit

/// Stable browser storage for one configured family account, independent of token rotation and page lifetime.
nonisolated enum LearningWebsiteDataStore {
    static func identifier(serviceURL: URL, account: String) -> UUID {
        var components = URLComponents(url: serviceURL.standardized, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.user = nil; components.password = nil
        components.query = nil; components.fragment = nil
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) { components.port = nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }

        // Length prefixes keep component boundaries unambiguous. This namespace is a storage format: do not bump it per release.
        let parts = ["com.bubu.learning-web-store.v1", components.string ?? "", account]
        var material = Data()
        for part in parts {
            let bytes = Data(part.utf8)
            material.append(Data("\(bytes.count):".utf8))
            material.append(bytes)
        }
        var bytes = Array(SHA256.hash(data: material).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80 // UUID v8: application-defined SHA-256 derivation.
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    @MainActor
    static func make(serviceURL: URL, account: String) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: identifier(serviceURL: serviceURL, account: account))
    }
}
