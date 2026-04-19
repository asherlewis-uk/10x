import Foundation
import Security

/// Local secure storage for project-scoped hosted secret values.
enum ProjectKeychainStore {
    private static let servicePrefix = "com.tenx.project-environment"

    static func value(projectId: String, key: String) -> String? {
        let normalizedKey = ProjectEnvironmentSecurity.normalizedKey(key)
        guard !normalizedKey.isEmpty else { return nil }

        var query = baseQuery(projectId: projectId, key: normalizedKey)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            logFailure("load", status: status, projectId: projectId, key: normalizedKey)
            return nil
        }
    }

    static func syncStoredValues(projectId: String, variables: [ProjectEnvironmentVariable]) {
        let hostedValuesByKey = Dictionary(
            uniqueKeysWithValues: variables.compactMap { variable -> (String, String)? in
                guard variable.scope == .hosted else { return nil }
                let key = variable.normalizedKey
                let value = variable.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else { return nil }
                return (key, value)
            }
        )

        let existingKeys = Set(storedKeys(projectId: projectId))
        let desiredKeys = Set(hostedValuesByKey.keys)

        for key in existingKeys.subtracting(desiredKeys) {
            delete(projectId: projectId, key: key)
        }

        for (key, value) in hostedValuesByKey {
            upsert(projectId: projectId, key: key, value: value)
        }
    }

    static func removeStoredValues(projectId: String) {
        for key in storedKeys(projectId: projectId) {
            delete(projectId: projectId, key: key)
        }
    }

    private static func service(projectId: String) -> String {
        "\(servicePrefix).\(projectId)"
    }

    private static func baseQuery(projectId: String, key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(projectId: projectId),
            kSecAttrAccount as String: key,
        ]
    }

    private static func upsert(projectId: String, key: String, value: String) {
        let normalizedKey = ProjectEnvironmentSecurity.normalizedKey(key)
        guard !normalizedKey.isEmpty, let data = value.data(using: .utf8) else { return }

        let query = baseQuery(projectId: projectId, key: normalizedKey)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let addQuery = query.merging(attributes) { _, newValue in newValue }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                logFailure("update", status: updateStatus, projectId: projectId, key: normalizedKey)
                return
            }
        default:
            logFailure("save", status: addStatus, projectId: projectId, key: normalizedKey)
        }
    }

    private static func delete(projectId: String, key: String) {
        let normalizedKey = ProjectEnvironmentSecurity.normalizedKey(key)
        guard !normalizedKey.isEmpty else { return }

        let status = SecItemDelete(baseQuery(projectId: projectId, key: normalizedKey) as CFDictionary)
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        logFailure("delete", status: status, projectId: projectId, key: normalizedKey)
    }

    private static func storedKeys(projectId: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(projectId: projectId),
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let items = result as? [[String: Any]] {
                return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
            }
            if let item = result as? [String: Any],
               let account = item[kSecAttrAccount as String] as? String {
                return [account]
            }
            return []
        case errSecItemNotFound:
            return []
        default:
            logFailure("list", status: status, projectId: projectId, key: nil)
            return []
        }
    }

    private static func logFailure(_ operation: String, status: OSStatus, projectId: String, key: String?) {
        let resolvedKey = key ?? "*"
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
        print("[10x] Keychain \(operation) failed for project \(projectId), key \(resolvedKey): \(message) (\(status))")
    }
}
