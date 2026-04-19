import Foundation
import XCTest
@testable import TenXAppCore

final class AppUpdateChannelTests: XCTestCase {
    func testResolvedPrefersStoredChannelOverBuildDefault() {
        XCTAssertEqual(
            AppUpdateChannel.resolved(preferenceRawValue: "beta", defaultRawValue: "stable"),
            .beta
        )
    }

    func testResolvedFallsBackToBuildDefaultThenStable() {
        XCTAssertEqual(
            AppUpdateChannel.resolved(preferenceRawValue: nil, defaultRawValue: "beta"),
            .beta
        )
        XCTAssertEqual(
            AppUpdateChannel.resolved(preferenceRawValue: nil, defaultRawValue: "unknown"),
            .stable
        )
    }

    func testPersistStoresPreferredChannelInUserDefaults() {
        let suiteName = "AppUpdateChannelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AppUpdateChannel.beta.persist(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppUpdateChannel.userDefaultsKey), AppUpdateChannel.beta.rawValue)
        XCTAssertEqual(
            AppUpdateChannel.preferredChannel(defaults: defaults, bundle: Bundle(for: Self.self)),
            .beta
        )
    }

    func testBrowserReleaseNotesURLDropsHtmlExtensionForChannelReleaseNotes() {
        let betaURL = URL(string: "https://downloads.example.invalid/beta/release-notes/1.0.0-beta.22.html")
        let stableURL = URL(string: "https://downloads.example.invalid/stable/release-notes/1.0.0.html")

        XCTAssertEqual(
            AppUpdateChannel.browserReleaseNotesURL(from: betaURL)?.absoluteString,
            "https://downloads.example.invalid/beta/release-notes/1.0.0-beta.22"
        )
        XCTAssertEqual(
            AppUpdateChannel.browserReleaseNotesURL(from: stableURL)?.absoluteString,
            "https://downloads.example.invalid/stable/release-notes/1.0.0"
        )
    }

    func testBrowserReleaseNotesURLLeavesUnrelatedURLsUnchanged() {
        let unrelatedURL = URL(string: "https://downloads.example.invalid/changelog/latest.html")

        XCTAssertEqual(
            AppUpdateChannel.browserReleaseNotesURL(from: unrelatedURL)?.absoluteString,
            unrelatedURL?.absoluteString
        )
    }
}
