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









}
