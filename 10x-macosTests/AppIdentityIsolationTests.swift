import Foundation
import XCTest
@testable import TenXAppCore

final class AppIdentityIsolationTests: XCTestCase {
    func testRuntimeIdentityConstantsUse11xNamespace() {
        XCTAssertEqual(AppIdentity.displayName, "11x")
        XCTAssertEqual(AppIdentity.bundleIdentifier, "app.kasey.11x")
        XCTAssertEqual(AppIdentity.urlScheme, "elevenx")
        XCTAssertEqual(AppIdentity.preferencesNamespace, "app.kasey.11x")
        XCTAssertEqual(AppIdentity.keychainServiceNamespace, "app.kasey.11x")
        XCTAssertEqual(AuthKeychainStore.defaultService, "app.kasey.11x")
        XCTAssertEqual(AppUpdateChannel.userDefaultsKey, "app.kasey.11x.preferredUpdateChannel")
        XCTAssertEqual(LocalProjectStore.baseDirectory.lastPathComponent, "11x")
        XCTAssertTrue(LocalProjectStore.baseDirectory.path.contains("Application Support"))
    }

    func testInfoPlistUses11xIdentityAndElevenXURLScheme() throws {
        let plist = try rootPlist("AppInfo.plist")

        XCTAssertEqual(plist["CFBundleName"] as? String, "11x")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "11x")

        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertEqual(schemes, ["elevenx"])
        XCTAssertFalse(schemes.contains("app.10x.macos"))
        XCTAssertFalse(schemes.contains(AppIdentity.ownedDomain))
    }

    func testProjectBuildSettingsProduceSeparateAppBundle() throws {
        let project = try rootText("10x-macos.xcodeproj/project.pbxproj")

        XCTAssertTrue(project.contains("path = 11x.app;"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = app.kasey.11x;"))
        XCTAssertTrue(project.contains("PRODUCT_NAME = 11x;"))
        XCTAssertFalse(project.contains("path = 10x.app;"))
        XCTAssertFalse(project.contains("PRODUCT_BUNDLE_IDENTIFIER = app.10x.macos;"))
    }

    func testEntitlementsUse11xKeychainGroup() throws {
        let plist = try rootPlist("10x-macos/10x_macos.entitlements")
        let groups = try XCTUnwrap(plist["keychain-access-groups"] as? [String])

        XCTAssertEqual(groups, ["$(AppIdentifierPrefix)app.kasey.11x.shared"])
        XCTAssertFalse(groups.contains { $0.contains("app.10x.shared") })
    }

    func testUpdaterFeedIsDisabledForIdentityIsolation() throws {
        let plist = try rootPlist("AppInfo.plist")
        let project = try rootText("10x-macos.xcodeproj/project.pbxproj")

        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, false)
        XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(plist["SUFeedURL"] as? String, "")
        XCTAssertEqual(plist["SUPublicEDKey"] as? String, "")
        XCTAssertFalse(project.contains("downloads.example.invalid/appcast.xml"))
    }

    func testLocalModeBadgeCopyExistsInAppShell() throws {
        let appSource = try rootText("10x-macos/TenXAppApp.swift")

        XCTAssertTrue(appSource.contains("LocalModeBadge"))
        XCTAssertEqual(AppIdentity.localBadgeTitle, "11x")
        XCTAssertTrue(AppIdentity.localBadgeDetails.contains("Single-user cockpit"))
        XCTAssertTrue(AppIdentity.localBadgeDetails.contains("Local backend"))
        XCTAssertTrue(AppIdentity.localBadgeDetails.contains("No billing"))
    }

    private func rootPlist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent(relativePath))
        return try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func rootText(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
