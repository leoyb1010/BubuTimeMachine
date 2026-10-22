import Foundation
import Security

// MARK: - Keychain 简单封装
/// 用于保存家庭服务器密码等敏感配置。读失败返回 nil（离线照常可用）；
/// **写失败不再静默**：返回 OSStatus，调用方据此提示「需要重新登录」（D9-09）。
///
/// 本机条目统一走 data protection keychain（kSecUseDataProtectionKeychain）：iOS 上本就如此，
/// Mac Catalyst 上系统忽略该键（TN3137）。读取时若新查询找不到，回退旧查询并原样迁移，
/// 保证已经登录的人升级后不会被登出。
nonisolated enum KeychainStore {
    private static let service = "com.bubu.timemachine"

    static func string(for key: String) -> String? {
        if let value = read(baseQuery(key)) { return value }
        // 旧版本写入时未带 data protection 标记：找到就迁移过去（写失败也照样返回旧值，不登出）。
        guard let legacy = read(legacyQuery(key)) else { return nil }
        if set(legacy, for: key) == errSecSuccess {
            SecItemDelete(legacyQuery(key) as CFDictionary)
        }
        return legacy
    }

    private static func read(_ base: [String: Any]) -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// 写入并返回结果；`errSecSuccess` 之外都表示没存住（锁屏首解前、签名/权限异常 -34018 等）。
    @discardableResult
    static func set(_ value: String, for key: String) -> OSStatus {
        let data = Data(value.utf8)
        let query = baseQuery(key)
        let attrs: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }

    /// 写入后读回核对：只有读得回同一个值才算真的存住。
    static func setVerified(_ value: String, for key: String) -> Bool {
        set(value, for: key) == errSecSuccess && string(for: key) == value
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        SecItemDelete(legacyQuery(key) as CFDictionary)
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
        var query = legacyQuery(key)
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    private static func legacyQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
