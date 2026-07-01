import Foundation
import XCTest
@testable import TenXAppCore

/// UI Pass 09 regression coverage: copy boundaries and key 11x product assertions.
/// These tests read the current SwiftUI view source to prove that the visible product
/// surface no longer uses 10x/SaaS/debug vocabulary and that the local-first model is
/// clearly surfaced.
final class UIReassertionCopyTests: XCTestCase {

    // MARK: - Helpers

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func rootText(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Extracts quoted Swift string literals (both single-line and triple-quoted)
    /// so tests inspect visible copy, not code symbols or comments.
    private func visibleStrings(in source: String) -> [String] {
        var results: [String] = []
        let nsRange = NSRange(source.startIndex..., in: source)

        let single = try! NSRegularExpression(
            pattern: #""([^"\\]|\\.)*""#,
            options: []
        )
        for match in single.matches(in: source, options: [], range: nsRange) {
            if let range = Range(match.range, in: source) {
                results.append(String(source[range]))
            }
        }

        let triple = try! NSRegularExpression(
            pattern: #""{3}([\s\S]*?)"{3}"#,
            options: []
        )
        for match in triple.matches(in: source, options: [], range: nsRange) {
            if let range = Range(match.range, in: source) {
                results.append(String(source[range]))
            }
        }

        return results
    }

    private func visibleCopy(_ relativePath: String) throws -> String {
        let source = try rootText(relativePath)
        return visibleStrings(in: source).joined(separator: "\n").lowercased()
    }

    /// True if `copy` contains `phrase` as a whole-word/phrase boundary, not as
    /// a substring of another word (e.g. "design inspiration" should not match "sign in").
    private func containsPhrase(_ phrase: String, in copy: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"\b\#(escaped)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return copy.contains(phrase)
        }
        let range = NSRange(copy.startIndex..., in: copy)
        return regex.firstMatch(in: copy, options: [], range: range) != nil
    }

    /// Primary product surfaces that a user sees during normal building.
    /// Diagnostics, legacy allow-listed integration views, and the onboarding
    /// local-mode bullet list are handled separately.
    private var primaryProductSurfaces: [String] {
        [
            "10x-macos/ContentView.swift",
            "10x-macos/Views/HomeView.swift",
            "10x-macos/Views/BuilderView.swift",
            "10x-macos/Views/Chat/ChatPanelView.swift",
            "10x-macos/Views/Chat/ChatInputView.swift",
            "10x-macos/Views/Preview/PreviewPanelView.swift",
            "10x-macos/Views/Settings/SettingsView.swift",
            "10x-macos/Views/Settings/GeneralSettingsView.swift",
            "10x-macos/Views/Settings/ProviderSettingsView.swift",
            "10x-macos/Views/Settings/StorageSettingsView.swift",
            "10x-macos/Views/Settings/AboutSettingsView.swift",
            "10x-macos/Views/Auth/LoginView.swift",
        ]
    }

    // MARK: - Billing / monetization vocabulary

    func testPrimaryProductSurfacesDoNotShowBillingOrMonetizationVocabulary() throws {
        let banned = [
            "billing",
            "credits",
            "paywall",
            "upgrade",
            "checkout",
            "subscription",
            "purchase",
            "receipt",
            "plans & packs",
        ]

        for path in primaryProductSurfaces {
            let copy = try visibleCopy(path)
            for word in banned {
                XCTAssertFalse(
                    containsPhrase(word, in: copy),
                    "\(path) visible copy must not contain monetization vocabulary: \(word)"
                )
            }
        }
    }

    // MARK: - Account / sign-out language

    func testPrimaryProductSurfacesDoNotUseAccountOrSignOutLanguage() throws {
        let banned = [
            "account",
            "sign out",
            "sign in",
        ]

        for path in primaryProductSurfaces {
            let copy = try visibleCopy(path)
            for phrase in banned {
                XCTAssertFalse(
                    containsPhrase(phrase, in: copy),
                    "\(path) visible copy must not use account/sign-in language: \(phrase)"
                )
            }
        }
    }

    // MARK: - Hosted deploy / publishing CTAs

    func testNoHostedDeployCTAInPrimaryProductSurfaces() throws {
        let banned = [
            "hosted deploy",
            "hosted pages",
            "publish app",
            "deploy app",
            "deploy to",
            "publish",
            "deploy",
        ]

        for path in primaryProductSurfaces {
            let copy = try visibleCopy(path)
            for phrase in banned {
                XCTAssertFalse(
                    containsPhrase(phrase, in: copy),
                    "\(path) visible copy must not contain hosted-deploy CTA language: \(phrase)"
                )
            }
        }
    }

    // MARK: - App Store submission CTAs

    func testNoAppStoreSubmissionCTAInPrimaryProductSurfaces() throws {
        let banned = [
            "app store submission",
            "submit to app store",
            "app store review generation",
        ]

        for path in primaryProductSurfaces {
            let copy = try visibleCopy(path)
            for phrase in banned {
                XCTAssertFalse(
                    containsPhrase(phrase, in: copy),
                    "\(path) visible copy must not contain App Store submission CTA language: \(phrase)"
                )
            }
        }
    }

    // MARK: - Provider settings hide raw key

    func testProviderSettingsUsesSecureFieldAndDoesNotRevealKey() throws {
        let source = try rootText("10x-macos/Views/Settings/ProviderSettingsView.swift")

        XCTAssertTrue(
            source.contains("SecureField"),
            "Provider settings must use SecureField for the API key"
        )

        // The raw key state must never be rendered as visible Text.
        let keyLiteralOccurrences = source.components(separatedBy: "Text(apiKey)").count - 1
        XCTAssertEqual(
            keyLiteralOccurrences, 0,
            "Provider settings must not render the raw apiKey state in a Text view"
        )

        // Visible copy may contain the placeholder "sk-...", but must not show a
        // real-looking key prefix.
        let visible = visibleStrings(in: source).joined(separator: "\n").lowercased()
        let keyPattern = #"\bsk-[a-z0-9]"#
        let regex = try! NSRegularExpression(pattern: keyPattern, options: [])
        let range = NSRange(visible.startIndex..., in: visible)
        let matches = regex.matches(in: visible, options: [], range: range)
        XCTAssertEqual(
            matches.count, 0,
            "Provider settings visible copy must not show a real key prefix (sk-...)"
        )
    }

    // MARK: - Storage settings surfaces paths and actions

    func testStorageSettingsSurfacesDatabaseAssetsExportPathsWithActions() throws {
        let source = try rootText("10x-macos/Views/Settings/StorageSettingsView.swift")
        let visible = visibleStrings(in: source).joined(separator: "\n")

        XCTAssertTrue(visible.contains("Database"), "Storage settings must show the database path")
        XCTAssertTrue(visible.contains("Assets"), "Storage settings must show the assets path")
        XCTAssertTrue(visible.contains("Exports"), "Storage settings must show the exports path")
        XCTAssertTrue(visible.contains("Copy"), "Storage settings must offer Copy Path")
        XCTAssertTrue(visible.contains("Reveal"), "Storage settings must offer Reveal in Finder")

        // Runtime paths are under the 11x Application Support directory.
        XCTAssertTrue(
            CockpitDatabase.defaultDatabaseURL().path.contains("Application Support/11x"),
            "Database path should live under 11x Application Support"
        )
        XCTAssertTrue(
            LocalAssetStorage.defaultAssetRootURL().path.contains("Application Support/11x"),
            "Asset storage path should live under 11x Application Support"
        )
    }

    // MARK: - Export affordance is visible

    func testExportAffordanceIsVisibleInBuilderAndReview() throws {
        let reviewSource = try rootText("10x-macos/Views/Preview/ReviewView.swift")
        let previewSource = try rootText("10x-macos/Views/Preview/PreviewPanelView.swift")
        let reviewVisible = visibleStrings(in: reviewSource).joined(separator: "\n").lowercased()
        let previewVisible = visibleStrings(in: previewSource).joined(separator: "\n").lowercased()

        XCTAssertTrue(
            reviewSource.contains("exportAppStoreSubmissionPacket()"),
            "ReviewView must call exportAppStoreSubmissionPacket()"
        )
        XCTAssertTrue(
            reviewSource.contains("exportAppStoreReviewAssetsZip()"),
            "ReviewView must call exportAppStoreReviewAssetsZip()"
        )
        XCTAssertTrue(
            reviewVisible.contains("export packet"),
            "ReviewView must expose an Export Packet action"
        )
        XCTAssertTrue(
            reviewVisible.contains("export zip") || reviewVisible.contains("open folder"),
            "ReviewView must expose export ZIP or open-folder actions"
        )
        XCTAssertTrue(
            previewVisible.contains("open in finder") && previewVisible.contains("open in xcode"),
            "Preview panel must surface local export actions: Open in Finder and Open in Xcode"
        )
    }

    // MARK: - Local status visible but not over-repeated

    func testLocalModeNotesAreVisibleButNotOverRepeatedInPrimarySurfaces() throws {
        let surfaces = primaryProductSurfaces + [
            "10x-macos/Views/Onboarding/OnboardingView.swift",
        ]

        let noteCount = try surfaces.reduce(0) { count, path in
            let source = try rootText(path)
            let realMatches = source.components(separatedBy: "LocalModeNote(").count - 1
            return count + realMatches
        }

        // Diagnostics is intentionally allowed to be more detailed; this test covers
        // primary product surfaces where one calm note per card is enough.
        XCTAssertLessThanOrEqual(
            noteCount, 6,
            "Primary product surfaces should not repeat LocalModeNote more than a few times: found \(noteCount)"
        )
        XCTAssertGreaterThan(
            noteCount, 0,
            "At least one LocalModeNote should be visible in primary product surfaces"
        )
    }

    func testHomeAndSettingsSurfaceLocalCockpitStatus() throws {
        let homeCopy = try visibleCopy("10x-macos/Views/HomeView.swift")
        let generalCopy = try visibleCopy("10x-macos/Views/Settings/GeneralSettingsView.swift")
        let aboutCopy = try visibleCopy("10x-macos/Views/Settings/AboutSettingsView.swift")

        XCTAssertTrue(
            homeCopy.contains("build an ios app locally") || homeCopy.contains("saved on this mac"),
            "Home should surface the local-first cockpit identity"
        )
        XCTAssertTrue(
            generalCopy.contains("local cockpit") || generalCopy.contains("saved on this mac"),
            "General settings should summarize the local cockpit"
        )
        XCTAssertTrue(
            aboutCopy.contains("unlimited single-user local cockpit"),
            "About settings should describe 11x as an unlimited single-user local cockpit"
        )
    }

    // MARK: - App identity

    func testAppIdentityRemains11x() {
        XCTAssertEqual(AppIdentity.displayName, "11x")
        XCTAssertEqual(AppIdentity.bundleIdentifier, "app.kasey.11x")
        XCTAssertEqual(AppIdentity.urlScheme, "elevenx")
        XCTAssertEqual(AppIdentity.appSupportDirectoryName, "11x")
        XCTAssertTrue(AppIdentity.appSupportDirectory.path.contains("Application Support/11x"))
    }

    // MARK: - Onboarding is project-first, not account-first

    func testOnboardingExplainsLocalCockpitWithoutAccountLanguage() throws {
        let copy = try visibleCopy("10x-macos/Views/Onboarding/OnboardingView.swift")

        XCTAssertTrue(copy.contains("welcome to 11x"), "Onboarding should welcome the user to 11x")
        XCTAssertTrue(
            copy.contains("unlimited single-user local cockpit"),
            "Onboarding should describe the product as a local cockpit"
        )
        XCTAssertTrue(copy.contains("no login required"), "Onboarding should say no login is required")
        XCTAssertTrue(
            copy.contains("local profile lives on your mac"),
            "Onboarding should explain the local profile"
        )
    }

    // MARK: - Settings IA is local-cockpit only

    func testSettingsSectionsExcludeBillingAccountHosted() {
        let sections = SettingsSection.allCases.map(\.rawValue)
        XCTAssertEqual(Set(sections), ["General", "Provider", "Storage", "Diagnostics", "About"])

        XCTAssertFalse(sections.contains("Billing"))
        XCTAssertFalse(sections.contains("Account"))
        XCTAssertFalse(sections.contains("Subscription"))
        XCTAssertFalse(sections.contains("Plans"))
        XCTAssertFalse(sections.contains("Hosted"))
    }

    func testAppTabKindIsSettingsNotAccount() {
        let settingsTab = AppTab.settings()
        XCTAssertEqual(settingsTab.kind, .settings)
        XCTAssertEqual(settingsTab.label, "Settings")
        XCTAssertEqual(settingsTab.icon, "gearshape")
    }
}
