import Foundation
import Security

/// OS-keychain storage for provider secrets. Never serialized into UI state or exports.
enum ProviderKeychainStore {
    private static let defaultService = "\(AppIdentity.keychainServiceNamespace).provider"

    /// Test hook to isolate keychain writes. Do not use in production.
    static var testServiceOverride: String?

    private static var service: String {
        testServiceOverride ?? defaultService
    }

    static func value(for key: String) -> String? {
        guard !key.isEmpty else { return nil }
        for (_, query) in queryVariants(for: key).enumerated() {
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                guard let data = result as? Data else { return nil }
                return String(data: data, encoding: .utf8)
            case errSecItemNotFound:
                continue
            default:
                logFailure("load", status: status, key: key)
                return nil
            }
        }
        return nil
    }

    static func set(_ value: String?, for key: String) {
        guard !key.isEmpty else { return }
        if let value, !value.isEmpty {
            upsert(value, for: key)
        } else {
            remove(for: key)
        }
    }

    static func remove(for key: String) {
        guard !key.isEmpty else { return }
        for query in queryVariants(for: key) {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                logFailure("delete", status: status, key: key)
                return
            }
            if status == errSecSuccess { return }
        }
    }

    private static func upsert(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let variants = queryVariants(for: key)
        let base = variants[0]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            logFailure("update", status: updateStatus, key: key)
            return
        }

        var addQuery = base
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logFailure("add", status: addStatus, key: key)
        } else {
        }
    }

    private static func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
    }

    private static func queryVariants(for key: String) -> [[String: Any]] {
        TenXKeychainAccessGroup.queryVariants(for: query(for: key))
    }

    private static func logFailure(_ operation: String, status: OSStatus, key: String) {
    }
}
