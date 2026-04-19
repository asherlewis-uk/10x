import Foundation
import LocalAuthentication
import Security
import Supabase

enum AuthKeychainStore {
    nonisolated static let defaultService = "app.10x.macos.auth"

    nonisolated static func data(
        for key: String,
        service: String = defaultService,
        allowUserInteraction: Bool = true
    ) -> Data? {
        guard !key.isEmpty else { return nil }

        for (index, base) in queryVariants(key: key, service: service).enumerated() {
            var query = base
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            applyInteractionPolicy(&query, allowUserInteraction: allowUserInteraction)

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                guard let data = result as? Data else { return nil }
                if index > 0 {
                    set(data, for: key, service: service)
                }
                return data
            case errSecItemNotFound:
                continue
            case errSecInteractionNotAllowed:
                return nil
            default:
                logFailure("load", status: status, service: service, key: key)
                return nil
            }
        }

        return nil
    }

    nonisolated static func string(
        for key: String,
        service: String = defaultService,
        allowUserInteraction: Bool = true
    ) -> String? {
        guard let stored = data(
            for: key,
            service: service,
            allowUserInteraction: allowUserInteraction
        ) else { return nil }
        return String(data: stored, encoding: .utf8)
    }

    nonisolated static func containsValue(
        for key: String,
        service: String = defaultService,
        allowUserInteraction: Bool = true
    ) -> Bool {
        guard !key.isEmpty else { return false }

        for base in queryVariants(key: key, service: service) {
            var query = base
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            applyInteractionPolicy(&query, allowUserInteraction: allowUserInteraction)

            let status = SecItemCopyMatching(query as CFDictionary, nil)
            switch status {
            case errSecSuccess:
                return true
            case errSecItemNotFound:
                continue
            case errSecInteractionNotAllowed:
                return false
            default:
                logFailure("contains", status: status, service: service, key: key)
                return false
            }
        }

        return false
    }

    nonisolated static func set(_ value: Data, for key: String, service: String = defaultService) {
        guard !key.isEmpty else { return }

        let query = queryVariants(key: key, service: service)[0]
        let attributes: [String: Any] = [
            kSecAttrLabel as String: "10x \(key)",
            kSecValueData as String: value,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            logFailure("update", status: updateStatus, service: service, key: key)
            return
        }

        var addQuery = query
        addQuery[kSecAttrLabel as String] = "10x \(key)"
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        addQuery[kSecValueData as String] = value

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logFailure("add", status: addStatus, service: service, key: key)
        }
    }

    nonisolated static func set(_ value: String, for key: String, service: String = defaultService) {
        guard let data = value.data(using: .utf8) else { return }
        set(data, for: key, service: service)
    }

    nonisolated static func removeValue(for key: String, service: String = defaultService) {
        guard !key.isEmpty else { return }

        let status = SecItemDelete(queryVariants(key: key, service: service)[0] as CFDictionary)
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        logFailure("delete", status: status, service: service, key: key)
    }

    private nonisolated static func baseQuery(key: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private nonisolated static func queryVariants(key: String, service: String) -> [[String: Any]] {
        TenXKeychainAccessGroup.queryVariants(for: baseQuery(key: key, service: service))
    }

    private nonisolated static func applyInteractionPolicy(
        _ query: inout [String: Any],
        allowUserInteraction: Bool
    ) {
        guard !allowUserInteraction else { return }
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
    }

    private nonisolated static func logFailure(_ operation: String, status: OSStatus, service: String, key: String) {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
        print("[10x] Auth Keychain \(operation) failed for service \(service), key \(key): \(message) (\(status))")
    }

}

struct AuthTokenStore: Sendable {
    let service: String
    let userDefaultsSuiteName: String?

    nonisolated init(
        service: String = "\(AuthKeychainStore.defaultService).tokens",
        userDefaultsSuiteName: String? = nil
    ) {
        self.service = service
        self.userDefaultsSuiteName = userDefaultsSuiteName
    }

    nonisolated func string(for key: String, allowUserInteraction: Bool = true) -> String? {
        if let stored = AuthKeychainStore.string(
            for: key,
            service: service,
            allowUserInteraction: allowUserInteraction
        ), !stored.isEmpty {
            defaults.removeObject(forKey: key)
            return stored
        }

        guard let legacy = defaults.string(forKey: key), !legacy.isEmpty else {
            return nil
        }

        AuthKeychainStore.set(legacy, for: key, service: service)
        defaults.removeObject(forKey: key)
        return legacy
    }

    nonisolated func hasValue(for key: String, allowUserInteraction: Bool = true) -> Bool {
        if AuthKeychainStore.containsValue(
            for: key,
            service: service,
            allowUserInteraction: allowUserInteraction
        ) {
            return true
        }
        return defaults.string(forKey: key)?.isEmpty == false
    }

    nonisolated func set(_ value: String?, for key: String) {
        if let value, !value.isEmpty {
            AuthKeychainStore.set(value, for: key, service: service)
        } else {
            AuthKeychainStore.removeValue(for: key, service: service)
        }
        defaults.removeObject(forKey: key)
    }

    nonisolated func remove(_ key: String) {
        AuthKeychainStore.removeValue(for: key, service: service)
        defaults.removeObject(forKey: key)
    }

    private nonisolated var defaults: UserDefaults {
        guard let userDefaultsSuiteName else {
            return .standard
        }
        return UserDefaults(suiteName: userDefaultsSuiteName) ?? .standard
    }
}

struct KeychainAuthLocalStorage: AuthLocalStorage, Sendable {
    let service: String
    let legacyKeyPrefix: String
    let userDefaultsSuiteName: String?

    nonisolated init(
        service: String = "\(AuthKeychainStore.defaultService).supabase",
        legacyKeyPrefix: String = "tenx.supabase.auth",
        userDefaultsSuiteName: String? = nil
    ) {
        self.service = service
        self.legacyKeyPrefix = legacyKeyPrefix
        self.userDefaultsSuiteName = userDefaultsSuiteName
    }

    nonisolated func store(key: String, value: Data) throws {
        AuthKeychainStore.set(value, for: key, service: service)
        defaults.removeObject(forKey: namespacedKey(for: key))
    }

    nonisolated func retrieve(key: String) throws -> Data? {
        if let stored = AuthKeychainStore.data(for: key, service: service) {
            defaults.removeObject(forKey: namespacedKey(for: key))
            return stored
        }

        guard let legacy = defaults.data(forKey: namespacedKey(for: key)) else {
            return nil
        }

        AuthKeychainStore.set(legacy, for: key, service: service)
        defaults.removeObject(forKey: namespacedKey(for: key))
        return legacy
    }

    nonisolated func remove(key: String) throws {
        AuthKeychainStore.removeValue(for: key, service: service)
        defaults.removeObject(forKey: namespacedKey(for: key))
    }

    private nonisolated func namespacedKey(for key: String) -> String {
        "\(legacyKeyPrefix).\(key)"
    }

    private nonisolated var defaults: UserDefaults {
        guard let userDefaultsSuiteName else {
            return .standard
        }
        return UserDefaults(suiteName: userDefaultsSuiteName) ?? .standard
    }
}
