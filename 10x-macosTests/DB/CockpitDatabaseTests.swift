import XCTest
@testable import TenXAppCore

final class CockpitDatabaseTests: XCTestCase {
    private func makeTestDatabase() throws -> CockpitDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("cockpit.sqlite")
        return try CockpitDatabase(url: url)
    }

    func testMigrationsApplyOnEmptyDatabase() async throws {
        let db = try makeTestDatabase()
        let rows = try await db.query("SELECT version FROM schema_migrations ORDER BY version;")
        let versions = rows.compactMap { $0["version"] }
        XCTAssertTrue(versions.contains("001_schema_migrations"))
        XCTAssertTrue(versions.contains("003_projects"))
        XCTAssertTrue(versions.contains("004_versions"))
    }

    func testProjectCRUD() async throws {
        let db = try makeTestDatabase()
        let projects = ProjectRepository(database: db)
        let profile = try await ProfileRepository(database: db).loadOrCreateProfile()

        let project = try await projects.createProject(userId: profile.id, name: "Test Project")
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.userId, profile.id)

        let loaded = try await projects.getProject(id: project.id)
        XCTAssertEqual(loaded?.id, project.id)

        let updated = try await projects.updateProject(id: project.id, name: "Renamed Project")
        XCTAssertEqual(updated.name, "Renamed Project")

        let archived = try await projects.archiveProject(id: project.id)
        XCTAssertEqual(archived.status, "archived")

        try await projects.deleteProject(id: project.id)
        let gone = try await projects.getProject(id: project.id)
        XCTAssertNil(gone)
    }

    func testVersionPersistence() async throws {
        let db = try makeTestDatabase()
        let projects = ProjectRepository(database: db)
        let versions = VersionRepository(database: db)
        let profile = try await ProfileRepository(database: db).loadOrCreateProfile()

        let project = try await projects.createProject(userId: profile.id, name: "Versioned Project")
        let tree = ["App.swift": "// hello"]
        let version = try await versions.createVersion(
            projectId: project.id,
            conversationId: UUID().uuidString,
            fileTree: tree,
            prompt: "Initial generation"
        )

        XCTAssertEqual(version.projectId, project.id)
        XCTAssertEqual(version.fileTree, tree)
        XCTAssertEqual(version.versionNumber, 1)

        let fetched = try await versions.fetchVersions(projectId: project.id)
        XCTAssertEqual(fetched.count, 1)
    }

    func testSettingsPersistence() async throws {
        let db = try makeTestDatabase()
        let settings = AppSettingsRepository(database: db)
        try await settings.set("elevenx", forKey: "provider.model")
        let value = try await settings.string(forKey: "provider.model")
        XCTAssertEqual(value, "elevenx")
    }

    func testUsageLogDoesNotGate() async throws {
        let db = try makeTestDatabase()
        let logs = UsageLogRepository(database: db)
        let profile = try await ProfileRepository(database: db).loadOrCreateProfile()
        try await logs.addLog(kind: "generation", payload: ["model": .string("gpt-5")])
        let fetched = try await logs.fetchLogs(limit: 10)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.kind, "generation")
        XCTAssertFalse(LocalEntitlements.usageTrackingGatesFeatures)
    }
}
