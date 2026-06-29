import Foundation
import XCTest
@testable import TenXAppCore

final class AuthKeychainStoreTests: XCTestCase {
    func testAuthTokenStoreMigratesLegacyDefaultsIntoKeychain() {
        let key = "tenx_access_token"
        let suiteName = "AuthTokenStoreMigratesLegacyDefaultsIntoKeychain"
        let service = "app.kasey.11x.tests.auth.tokens.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("legacy-token", forKey: key)

        defer {
            AuthKeychainStore.removeValue(for: key, service: service)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AuthTokenStore(service: service, userDefaultsSuiteName: suiteName)

        XCTAssertEqual(store.string(for: key), "legacy-token")
        XCTAssertNil(defaults.string(forKey: key))
        XCTAssertEqual(AuthKeychainStore.string(for: key, service: service), "legacy-token")
    }

    func testAuthTokenStoreRemovesKeychainValue() {
        let key = "tenx_refresh_token"
        let service = "app.kasey.11x.tests.auth.tokens.\(UUID().uuidString)"
        let store = AuthTokenStore(service: service)

        defer {
            AuthKeychainStore.removeValue(for: key, service: service)
        }

        store.set("refresh-value", for: key)
        XCTAssertEqual(AuthKeychainStore.string(for: key, service: service), "refresh-value")

        store.remove(key)
        XCTAssertNil(AuthKeychainStore.string(for: key, service: service))
    }

    func testAuthTokenStoreHasValueWithoutReadingSecret() {
        let key = "tenx_access_token"
        let service = "app.kasey.11x.tests.auth.tokens.\(UUID().uuidString)"
        let store = AuthTokenStore(service: service)

        defer {
            AuthKeychainStore.removeValue(for: key, service: service)
        }

        XCTAssertFalse(store.hasValue(for: key, allowUserInteraction: false))

        store.set("stored-token", for: key)

        XCTAssertTrue(store.hasValue(for: key, allowUserInteraction: false))
    }

    func testKeychainAuthLocalStorageMigratesLegacyUserDefaultsData() throws {
        let key = "supabase.session"
        let suiteName = "KeychainAuthLocalStorageMigratesLegacyUserDefaultsData"
        let service = "app.kasey.11x.tests.auth.supabase.\(UUID().uuidString)"
        let storage = KeychainAuthLocalStorage(
            service: service,
            legacyKeyPrefix: "tenx.supabase.auth",
            userDefaultsSuiteName: suiteName
        )
        let defaults = UserDefaults(suiteName: suiteName)!
        let legacyKey = "tenx.supabase.auth.\(key)"
        let legacyData = Data("legacy-session".utf8)
        defaults.set(legacyData, forKey: legacyKey)

        defer {
            AuthKeychainStore.removeValue(for: key, service: service)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let migrated = try storage.retrieve(key: key)

        XCTAssertEqual(migrated, legacyData)
        XCTAssertNil(defaults.data(forKey: legacyKey))
        XCTAssertEqual(AuthKeychainStore.data(for: key, service: service), legacyData)
    }

    func testSupabaseManagementTokenStoreUsesKeychain() {
        let service = "app.kasey.11x.tests.integrations.supabase-management.\(UUID().uuidString)"
        let store = SupabaseManagementTokenStore(service: service)

        defer {
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.accessTokenKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.refreshTokenKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.expiresAtKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.tokenTypeKey, service: service)
        }

        store.setToken(" sbp_test_token ")

        XCTAssertEqual(store.token(), "sbp_test_token")
        XCTAssertEqual(
            AuthKeychainStore.string(for: SupabaseManagementTokenStore.accessTokenKey, service: service),
            "sbp_test_token"
        )

        store.clear()
        XCTAssertNil(store.token())
        XCTAssertNil(AuthKeychainStore.string(for: SupabaseManagementTokenStore.accessTokenKey, service: service))
    }

    func testSupabaseManagementTokenStoreHasStoredSessionWithoutInteractiveRead() {
        let service = "app.kasey.11x.tests.integrations.supabase-management.\(UUID().uuidString)"
        let store = SupabaseManagementTokenStore(service: service)

        defer {
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.accessTokenKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.refreshTokenKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.expiresAtKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.tokenTypeKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.scopeKey, service: service)
        }

        XCTAssertFalse(store.hasStoredSession(allowUserInteraction: false))

        store.saveOAuthSession(
            accessToken: "oauth-access",
            refreshToken: "oauth-refresh",
            expiresIn: 3600,
            tokenType: "bearer",
            scope: "edge_functions_write"
        )

        XCTAssertTrue(store.hasStoredSession(allowUserInteraction: false))
    }

    func testSupabaseManagementTokenStorePersistsOAuthSession() {
        let service = "app.kasey.11x.tests.integrations.supabase-management.oauth.\(UUID().uuidString)"
        let store = SupabaseManagementTokenStore(service: service)

        defer {
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.accessTokenKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.refreshTokenKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.expiresAtKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.tokenTypeKey, service: service)
            AuthKeychainStore.removeValue(for: SupabaseManagementTokenStore.scopeKey, service: service)
        }

        store.saveOAuthSession(
            accessToken: "oauth-access",
            refreshToken: "oauth-refresh",
            expiresIn: 3600,
            tokenType: "bearer",
            scope: "edge_functions_write edge_functions_secrets_write"
        )

        let session = store.session()
        XCTAssertEqual(session?.accessToken, "oauth-access")
        XCTAssertEqual(session?.refreshToken, "oauth-refresh")
        XCTAssertEqual(session?.tokenType, "bearer")
        XCTAssertEqual(session?.scope, "edge_functions_write edge_functions_secrets_write")
        XCTAssertNotNil(session?.expiresAt)
        XCTAssertFalse(session?.needsRefresh ?? true)
        XCTAssertTrue(session?.hasScopes(["edge_functions_write"]) == true)
        XCTAssertFalse(session?.hasScopes(["edge_functions_secrets_read"]) == true)
    }

    func testSuperwallManagementTokenStoreUsesKeychain() {
        let service = "app.kasey.11x.tests.integrations.superwall-management.\(UUID().uuidString)"
        let store = SuperwallManagementTokenStore(service: service)

        defer {
            AuthKeychainStore.removeValue(for: SuperwallManagementTokenStore.apiKeyKey, service: service)
        }

        store.setAPIKey(" sw_live_test_123 ")

        XCTAssertEqual(store.apiKey(), "sw_live_test_123")
        XCTAssertTrue(store.hasAPIKey(allowUserInteraction: false))
        XCTAssertEqual(
            AuthKeychainStore.string(for: SuperwallManagementTokenStore.apiKeyKey, service: service),
            "sw_live_test_123"
        )

        store.clear()
        XCTAssertNil(store.apiKey())
        XCTAssertNil(AuthKeychainStore.string(for: SuperwallManagementTokenStore.apiKeyKey, service: service))
    }
}
