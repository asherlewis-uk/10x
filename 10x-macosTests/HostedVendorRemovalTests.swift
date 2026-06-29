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
}
