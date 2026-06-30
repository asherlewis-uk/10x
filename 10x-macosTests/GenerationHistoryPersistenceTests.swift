import Foundation
import XCTest
@testable import TenXAppCore

final class GenerationHistoryPersistenceTests: XCTestCase {
    private var database: CockpitDatabase!
    private var profileId: String!
    private var projectId: String!
    private var conversationId: String!

    override func setUp() async throws {
        try await super.setUp()
        database = try CockpitDatabase(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("cockpit.sqlite")
        )
        let profile = try await ProfileRepository(database: database).loadOrCreateProfile()
        profileId = profile.id
        let project = try await ProjectRepository(database: database).createProject(
            userId: profileId,
            name: "History Test Project"
        )
        projectId = project.id
        conversationId = UUID().uuidString
    }

    // MARK: - Version history

    func testVersionHistoryPersistsAfterReload() async throws {
        let versions = VersionRepository(database: database)
        let firstTree = ["App.swift": "// first"]
        let first = try await versions.createVersion(
            projectId: projectId,
            conversationId: conversationId,
            fileTree: firstTree,
            prompt: "Initial generation"
        )
        XCTAssertEqual(first.versionNumber, 1)

        let secondTree = ["App.swift": "// second", "HomeView.swift": "// home"]
        let second = try await versions.createVersion(
            projectId: projectId,
            conversationId: conversationId,
            fileTree: secondTree,
            prompt: "Add home view"
        )
        XCTAssertEqual(second.versionNumber, 2)

        // Simulate a fresh repository reading the same database
        let reloaded = VersionRepository(database: database)
        let fetched = try await reloaded.fetchVersions(projectId: projectId)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.map(\.versionNumber), [2, 1])
        XCTAssertEqual(fetched.first?.fileTree, secondTree)
    }

    func testCurrentVersionIdUpdatesWithEachGeneration() async throws {
        let versions = VersionRepository(database: database)
        let projects = ProjectRepository(database: database)

        let first = try await versions.createVersion(
            projectId: projectId,
            conversationId: conversationId,
            fileTree: ["App.swift": "// v1"],
            prompt: "v1"
        )
        let projectAfterFirst = try await projects.getProject(id: projectId)
        XCTAssertEqual(projectAfterFirst?.currentVersionId, first.id)

        let second = try await versions.createVersion(
            projectId: projectId,
            conversationId: conversationId,
            fileTree: ["App.swift": "// v2"],
            prompt: "v2"
        )
        let projectAfterSecond = try await projects.getProject(id: projectId)
        XCTAssertEqual(projectAfterSecond?.currentVersionId, second.id)
    }

    // MARK: - Message history

    func testMessageHistoryPersistsAfterReload() async throws {
        let messages = MessageRepository(database: database)
        let now = ISO8601DateFormatter().string(from: Date())

        let userMessage = BuilderMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: "user",
            content: "Generate a SwiftUI app",
            versionId: nil,
            createdAt: now
        )
        let assistantMessage = BuilderMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: "assistant",
            content: "Started generation",
            versionId: nil,
            createdAt: now
        )

        try await messages.addMessage(userMessage, projectId: projectId)
        try await messages.addMessage(assistantMessage, projectId: projectId)

        let reloaded = MessageRepository(database: database)
        let fetched = try await reloaded.fetchMessages(
            projectId: projectId,
            conversationId: conversationId
        )
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.map(\.role), ["user", "assistant"])
        XCTAssertEqual(fetched.map(\.content), ["Generate a SwiftUI app", "Started generation"])
    }

    // MARK: - End-to-end generation history

    func testGenerationHistorySurvivesRepositoryRecreation() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("recreated.sqlite")
        database = try CockpitDatabase(url: dbURL)
        let profile = try await ProfileRepository(database: database).loadOrCreateProfile()
        profileId = profile.id
        let project = try await ProjectRepository(database: database).createProject(
            userId: profileId,
            name: "Recreate Project"
        )
        projectId = project.id

        let versions = VersionRepository(database: database)
        let messages = MessageRepository(database: database)
        let now = ISO8601DateFormatter().string(from: Date())

        let version = try await versions.createVersion(
            projectId: projectId,
            conversationId: conversationId,
            fileTree: ["App.swift": "// generated"],
            prompt: "Generate app"
        )
        try await messages.addMessage(BuilderMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: "assistant",
            content: "Done",
            versionId: version.id,
            createdAt: now
        ), projectId: projectId)

        // Simulate a full app restart by reconnecting to the same file.
        let restartedDB = try CockpitDatabase(url: dbURL)
        let restartedVersions = VersionRepository(database: restartedDB)
        let restartedMessages = MessageRepository(database: restartedDB)

        let fetchedVersion = try await restartedVersions.getVersion(
            projectId: projectId,
            versionId: version.id
        )
        XCTAssertNotNil(fetchedVersion)
        XCTAssertEqual(fetchedVersion?.fileTree["App.swift"], "// generated")

        let fetchedMessages = try await restartedMessages.fetchMessages(
            projectId: projectId,
            conversationId: conversationId
        )
        XCTAssertEqual(fetchedMessages.count, 1)
        XCTAssertEqual(fetchedMessages.first?.versionId, version.id)
    }
}
