import Foundation
import Security

// MARK: - Keychain 简单封装
/// 用于保存家庭服务器密码等敏感配置。失败时静默降级为空，避免影响离线使用。
nonisolated enum KeychainStore {
    private static let service = "com.bubu.timemachine"

    static func string(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query = baseQuery(key)
        let attrs: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    // MARK: iCloud 同步 Keychain（kSecAttrSynchronizable）
    /// 用于时间胶囊 v3 的恢复码：随 iCloud 钥匙串同步到家庭同一 Apple ID 的设备。
    /// 与本机条目命名空间隔离（account 加 `.icloud` 后缀），避免与 device-only 条目冲突。

    static func icloudString(for key: String) -> String? {
        var query = baseQuery(key + ".icloud")
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func setICloud(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query = baseQuery(key + ".icloud")
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(key + ".icloud")
            add[kSecAttrSynchronizable as String] = true
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
