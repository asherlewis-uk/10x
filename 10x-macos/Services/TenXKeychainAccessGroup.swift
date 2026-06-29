import Foundation
import Security

enum TenXKeychainAccessGroup {
    private nonisolated static let entitlementKey = "keychain-access-groups"
    private nonisolated static let sharedGroupSuffix = AppIdentity.keychainAccessGroupSuffix
    private nonisolated static let accessGroup = resolveCurrentAccessGroup()

    nonisolated static func queryVariants(for query: [String: Any]) -> [[String: Any]] {
        guard let accessGroup else { return [query] }

        var sharedQuery = query
        sharedQuery[kSecUseDataProtectionKeychain as String] = true
        sharedQuery[kSecAttrAccessGroup as String] = accessGroup
        return [sharedQuery, query]
    }

    private nonisolated static func resolveCurrentAccessGroup() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        guard let value = SecTaskCopyValueForEntitlement(task, entitlementKey as CFString, nil) else {
            return nil
        }
        guard let groups = value as? [String], !groups.isEmpty else {
            return nil
        }

        if let sharedGroup = groups.first(where: { $0.hasSuffix(sharedGroupSuffix) }) {
            return sharedGroup
        }

        return groups.first
    }
}
