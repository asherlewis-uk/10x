import Foundation
import XCTest
@testable import TenXAppCore

@MainActor
final class HostedVendorRemovalTests: XCTestCase {
    func testConfigApiBaseURLIsEmptyByDefault() {
        XCTAssertTrue(Config.apiBaseURL.isEmpty)
    }

    func testConfigHostedAppsBaseURLIsEmptyByDefault() {
        XCTAssertTrue(Config.hostedAppsBaseURL.isEmpty)
        XCTAssertTrue(Config.hostedAppsDisplayHost.isEmpty)
    }

    func testConfigSparkleFeedURLIsEmptyByDefault() {
        XCTAssertTrue(Config.sparkleFeedURL.isEmpty)
    }

    func testPublishAppStoreSubmissionIsBlockedWithLocalModeMessage() async {
        let viewModel = BuilderViewModel()
        viewModel.activeProject = BuilderProject(
            id: "project-1",
            userId: "user-1",
            name: "Atlas",
            description: nil,
            slug: "atlas",
            platform: "swiftui",
            status: "active",
            currentVersionId: nil,
            settings: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )

        await viewModel.publishAppStoreSubmission()

        XCTAssertEqual(
            viewModel.appStoreSubmissionError,
            "Hosted publishing is not available in 11x. Use local export instead."
        )
    }

    func testUnpublishAppStoreSubmissionIsBlockedWithLocalModeMessage() async {
        let viewModel = BuilderViewModel()
        viewModel.activeProject = BuilderProject(
            id: "project-1",
            userId: "user-1",
            name: "Atlas",
            description: nil,
            slug: "atlas",
            platform: "swiftui",
            status: "active",
            currentVersionId: nil,
            settings: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )

        await viewModel.unpublishAppStoreSubmission()

        XCTAssertEqual(
            viewModel.appStoreSubmissionError,
            "Hosted publishing is not available in 11x. Use local export instead."
        )
    }

    func testRequestAppStoreReviewGenerationIsBlocked() {
        let viewModel = BuilderViewModel()
        viewModel.requestAppStoreReviewGeneration()
        XCTAssertEqual(
            viewModel.appStoreReviewError,
            "Marketing asset generation is not available in 11x. Use local export instead."
        )
    }

    func testGenerateAppStoreSubmissionDraftsIsBlocked() async {
        let viewModel = BuilderViewModel()
        viewModel.activeProject = BuilderProject(
            id: "project-1",
            userId: "user-1",
            name: "Atlas",
            description: nil,
            slug: "atlas",
            platform: "swiftui",
            status: "active",
            currentVersionId: nil,
            settings: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )

        await viewModel.generateAppStoreSubmissionDrafts()

        XCTAssertEqual(
            viewModel.appStoreSubmissionError,
            "App Store submission generation is not available in 11x. Use local export instead."
        )
    }

    func testChatCreditAndUpgradeDetectionAlwaysReturnsFalse() {
        // The source scans below prove the legacy credit/upgrade keyword branches were removed.
        let chatInputSource = try? rootText("10x-macos/Views/Chat/ChatInputView.swift")
        let chatPanelSource = try? rootText("10x-macos/Views/Chat/ChatPanelView.swift")
        XCTAssertNotNil(chatInputSource)
        XCTAssertNotNil(chatPanelSource)
        XCTAssertFalse(chatInputSource?.contains("Plans & Packs") ?? true)
        XCTAssertFalse(chatPanelSource?.contains("Plans & Packs") ?? true)
        XCTAssertFalse((chatInputSource?.contains("openPlansAndPacks()") ?? false) && !(chatInputSource?.contains("// Billing catalog is disabled") ?? false))
        XCTAssertFalse((chatPanelSource?.contains("openPlansAndPacks()") ?? false) && !(chatPanelSource?.contains("// Billing catalog is disabled") ?? false))
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func rootText(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
