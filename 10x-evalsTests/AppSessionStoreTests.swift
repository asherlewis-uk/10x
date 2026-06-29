import XCTest
@testable import TenXEvals

final class AppSessionStoreTests: XCTestCase {
    func testPrefersSupabaseStoredSessionBlobWhenPresent() throws {
        let suiteName = "app.kasey.11x.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("stale-access", forKey: "tenx_access_token")
        defaults.set("stale-refresh", forKey: "tenx_refresh_token")

        let payload = """
        {
          "accessToken": "fresh-access",
          "refreshToken": "fresh-refresh",
          "user": {
            "id": "blob-user-id",
            "email": "blob@example.com"
          }
        }
        """
        defaults.set(Data(payload.utf8), forKey: "tenx.supabase.auth.sb-test-auth-token")

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let session = try AppSessionStore(suiteName: suiteName).load()
        XCTAssertEqual(session.accessToken, "fresh-access")
        XCTAssertEqual(session.refreshToken, "fresh-refresh")
        XCTAssertEqual(session.userId, "blob-user-id")
        XCTAssertEqual(session.userEmail, "blob@example.com")
    }

    func testLoadsSessionFromExplicitSuite() throws {
        let suiteName = "app.kasey.11x.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("access", forKey: "tenx_access_token")
        defaults.set("refresh", forKey: "tenx_refresh_token")
        defaults.set("user-id", forKey: "tenx_user_id")
        defaults.set("person@example.com", forKey: "tenx_user_email")

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let session = try AppSessionStore(suiteName: suiteName).load()
        XCTAssertEqual(session.accessToken, "access")
        XCTAssertEqual(session.refreshToken, "refresh")
        XCTAssertEqual(session.userId, "user-id")
        XCTAssertEqual(session.userEmail, "person@example.com")
    }

    func testMissingAccessTokenThrowsHelpfulError() throws {
        let suiteName = "app.kasey.11x.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("refresh", forKey: "tenx_refresh_token")

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertThrowsError(try AppSessionStore(suiteName: suiteName).load()) { error in
            XCTAssertEqual(error as? AppSessionStoreError, .missingAccessToken(suiteName))
        }
    }
}
