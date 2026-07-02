import Foundation
import XCTest
@testable import TenXAppCore

final class LegacyTenXProjectImporterTests: XCTestCase {
    private var database: CockpitDatabase!
    private var assetRoot: URL!
    private var testProjectRootOverride: URL!
    private var importer: LegacyTenXProjectImporter!
    private var createdProjectIds: [String] = []
    private var createdProjectNames: [String] = []
    private var createdAppSupportProjectPaths: [URL] = []

    override func setUp() {
        super.setUp()
        do {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

            let dbURL = base.appendingPathComponent("cockpit.sqlite")
            database = try CockpitDatabase(url: dbURL)

            assetRoot = base.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: assetRoot, withIntermediateDirectories: true)

            testProjectRootOverride = base.appendingPathComponent("projects", isDirectory: true)
            try FileManager.default.createDirectory(at: testProjectRootOverride, withIntermediateDirectories: true)
            LocalProjectStore.testBaseDirectoryOverride = testProjectRootOverride

            importer = LegacyTenXProjectImporter(
                database: database,
                assetStorage: LocalAssetStorage(rootURL: assetRoot, repository: AssetRepository(database: database)),
                previewService: XcodePreviewService()
            )
        } catch {
            XCTFail("Failed to set up test database: \(error)")
        }
    }

    override func tearDown() {
        LocalProjectStore.testBaseDirectoryOverride = nil

        // Clean up any app-support project directories created by XcodePreviewService.
        for url in createdAppSupportProjectPaths {
            try? FileManager.default.removeItem(at: url)
        }

        // Clean up any assets written to the real asset root for created project ids.
        let realAssetRoot = LocalAssetStorage.defaultAssetRootURL()
        for projectId in createdProjectIds {
            let projectAssetDir = realAssetRoot
                .appendingPathComponent("projects", isDirectory: true)
                .appendingPathComponent(projectId, isDirectory: true)
            try? FileManager.default.removeItem(at: projectAssetDir)
        }

        super.tearDown()
    }

    // MARK: - Detection

    func testDetectsCandidateByProjectJSON() async throws {
        let fixture = try makeMinimalLegacyFixture(name: "JSON Candidate")
        let root = fixture.url

        let importer = LegacyTenXProjectImporter()
        let isCandidate = await importer.isLegacyProjectCandidate(at: root)
        XCTAssertTrue(isCandidate)

        let scanned = await importer.scanLegacyProjects(at: fixture.scanRoot)
        XCTAssertTrue(scanned.contains { $0.lastPathComponent == root.lastPathComponent })
    }

    func testDetectsCandidateByProjectYML() async throws {
        let fixture = try makeMinimalLegacyFixture(name: "YML Candidate", includeProjectJSON: false)
        let root = fixture.url

        let importer = LegacyTenXProjectImporter()
        let isCandidate = await importer.isLegacyProjectCandidate(at: root)
        XCTAssertTrue(isCandidate)

        let scanned = await importer.scanLegacyProjects(at: fixture.scanRoot)
        XCTAssertTrue(scanned.contains { $0.lastPathComponent == root.lastPathComponent })
    }

    // MARK: - Import success

    func testImportsProjectWithoutRemoteLogin() async throws {
        let fixture = try makeFullLegacyFixture(name: "Remote Free")

        let report = try await importer.importProject(from: fixture.url)

        XCTAssertTrue(report.succeeded, "Import failed: \(report.errors.joined(separator: ", "))")
        XCTAssertNotNil(report.project)
        XCTAssertFalse(report.alreadyImported)

        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)
        createdAppSupportProjectPaths.append(
            await XcodePreviewService().projectDir(for: project.name, projectId: project.id)
        )

        let repo = ProjectRepository(database: database)
        let loaded = try await repo.getProject(id: project.id)
        XCTAssertEqual(loaded?.id, project.id)
        XCTAssertEqual(loaded?.name, project.name)
    }

    func testCopyDoesNotMoveOrMutateLegacyFolder() async throws {
        let fixture = try makeFullLegacyFixture(name: "Copy Safe")
        let before = try listFiles(at: fixture.url)

        _ = try await importer.importProject(from: fixture.url)

        let after = try listFiles(at: fixture.url)
        XCTAssertEqual(before.sorted(), after.sorted(), "Legacy folder contents changed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent(".git").path))
    }

    func testSkipsGitByDefault() async throws {
        let fixture = try makeFullLegacyFixture(name: "Git Skip")

        let report = try await importer.importProject(from: fixture.url)
        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)
        let projectRoot = await XcodePreviewService().projectDir(for: project.name, projectId: project.id)
        createdAppSupportProjectPaths.append(projectRoot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent(".git").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent(".git").path))
    }

    func testImportsGeneratedIOSFiles() async throws {
        let fixture = try makeFullLegacyFixture(name: "Generated Source")

        let report = try await importer.importProject(from: fixture.url)
        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)
        let projectRoot = await XcodePreviewService().projectDir(for: project.name, projectId: project.id)
        createdAppSupportProjectPaths.append(projectRoot)

        let copiedIOS = projectRoot.appendingPathComponent("ios", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedIOS.path))
        XCTAssertTrue(report.copiedSourceFiles.contains { $0.hasSuffix("App.swift") })
    }

    func testImportsMessagesAndHistory() async throws {
        let fixture = try makeFullLegacyFixture(name: "Chat History")

        let report = try await importer.importProject(from: fixture.url)
        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)

        let localStore = LocalProjectStore()
        let messages = await localStore.loadMessages(projectName: project.name, projectId: project.id)
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(report.importedMessageCount, 2)

        let index = await localStore.loadChatIndex(projectName: project.name, projectId: project.id)
        XCTAssertNotNil(index)
        XCTAssertEqual(index?.chats.count, 1)
    }

    func testImportsPlanAndTasks() async throws {
        let fixture = try makeFullLegacyFixture(name: "Plan Tasks")

        let report = try await importer.importProject(from: fixture.url)
        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)

        let localStore = LocalProjectStore()
        XCTAssertEqual(report.importedPlan, true)
        XCTAssertEqual(report.importedTasks, true)

        let plan = await localStore.loadPlan(projectName: project.name, projectId: project.id)
        let tasks = await localStore.loadTasks(projectName: project.name, projectId: project.id)
        XCTAssertEqual(plan?.trimmingCharacters(in: .whitespacesAndNewlines), "# Plan")
        XCTAssertEqual(tasks?.trimmingCharacters(in: .whitespacesAndNewlines), "- [ ] Task")
    }

    func testImportsGrowthAppStoreAsInertAssets() async throws {
        let fixture = try makeFullLegacyFixture(name: "App Store Growth")

        let report = try await importer.importProject(from: fixture.url)
        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)

        let assetRepo = AssetRepository(database: database)
        let assets = try await assetRepo.fetchAssets(projectId: project.id)
        let growthAsset = assets.first { $0.relativePath.contains("growth/app-store") }
        XCTAssertNotNil(growthAsset)

        // Ensure no active App Store review/submission state was created.
        let localStore = LocalProjectStore()
        let reviewState = await localStore.loadReviewState(projectName: project.name, projectId: project.id)
        XCTAssertFalse(reviewState.hasContent)
    }

    func testHandlesMissingPartialMetadata() async throws {
        let fixture = try makeMinimalLegacyFixture(name: "Partial", includeProjectJSON: true)

        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertTrue(report.unavailable.contains { $0.contains("messages.json") })
        XCTAssertTrue(report.unavailable.contains { $0.contains("file_tree.json") })
    }

    func testDuplicateImportIsPrevented() async throws {
        let fixture = try makeFullLegacyFixture(name: "Duplicate")

        let first = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(first.succeeded)
        let project = try XCTUnwrap(first.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)
        createdAppSupportProjectPaths.append(
            await XcodePreviewService().projectDir(for: project.name, projectId: project.id)
        )

        let second = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(second.alreadyImported)
        XCTAssertNotNil(second.previousProjectId)
        XCTAssertEqual(second.previousProjectId, first.project?.id)
    }

    // MARK: - Fixture helpers

    private struct LegacyFixture {
        let url: URL
        let scanRoot: URL
    }

    private func makeMinimalLegacyFixture(name: String, includeProjectJSON: Bool = true) throws -> LegacyFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        let scanRoot = root.deletingLastPathComponent()
        let fm = FileManager.default

        let tenxDir = root.appendingPathComponent(".tenx", isDirectory: true)
        let iosDir = root.appendingPathComponent("ios", isDirectory: true)
        try fm.createDirectory(at: tenxDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: iosDir, withIntermediateDirectories: true)

        if includeProjectJSON {
            let projectJSON: [String: Any] = [
                "projectId": UUID().uuidString,
                "name": name,
                "slug": LegacyTenXProjectImporterTests.slugify(name),
                "bundleId": "com.test.\(LegacyTenXProjectImporterTests.slugify(name))",
                "targetName": "TestApp",
                "platform": "ios"
            ]
            try JSONSerialization.data(withJSONObject: projectJSON, options: [.sortedKeys])
                .write(to: tenxDir.appendingPathComponent("project.json"))
        }

        try Data("name: TestApp".utf8)
            .write(to: iosDir.appendingPathComponent("project.yml"))

        // Add a small .git marker so skip-git tests have something to skip.
        let gitDir = root.appendingPathComponent(".git", isDirectory: true)
        try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8)
            .write(to: gitDir.appendingPathComponent("HEAD"))

        return LegacyFixture(url: root, scanRoot: scanRoot)
    }

    private func makeFullLegacyFixture(name: String) throws -> LegacyFixture {
        let fixture = try makeMinimalLegacyFixture(name: name)
        let root = fixture.url
        let fm = FileManager.default
        let tenxDir = root.appendingPathComponent(".tenx")
        let iosDir = root.appendingPathComponent("ios")

        // File tree
        let fileTree: [String: String] = [
            "App.swift": "import SwiftUI\n@main struct TestApp: App { var body: some Scene { WindowGroup { Text(\"Hi\") } } }",
            "ContentView.swift": "struct ContentView: View { var body: some View { Text(\"Hello\") } }"
        ]
        try JSONEncoder().encode(fileTree)
            .write(to: tenxDir.appendingPathComponent("file_tree.json"))

        // Messages
        let messages: [[String: Any]] = [
            [
                "id": UUID().uuidString,
                "role": "user",
                "content": "Build a hello world app",
                "conversation_id": "",
                "created_at": ISO8601DateFormatter().string(from: Date())
            ],
            [
                "id": UUID().uuidString,
                "role": "assistant",
                "content": "Sure, here is the source.",
                "conversation_id": "",
                "created_at": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        try JSONSerialization.data(withJSONObject: messages, options: [.sortedKeys])
            .write(to: tenxDir.appendingPathComponent("messages.json"))

        // Plan / tasks
        try "# Plan\n".write(to: tenxDir.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        try "- [ ] Task\n".write(to: tenxDir.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)

        // Root docs
        try "# Readme\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        // iOS source files and project bundle
        let targetDir = iosDir.appendingPathComponent("TestApp", isDirectory: true)
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try fileTree["App.swift"]!.write(to: targetDir.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try fileTree["ContentView.swift"]!.write(to: targetDir.appendingPathComponent("ContentView.swift"), atomically: true, encoding: .utf8)

        let xcodeproj = iosDir.appendingPathComponent("TestApp.xcodeproj", isDirectory: true)
        try fm.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        try "// project".write(to: xcodeproj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

        let sourceManifest: [String: Any] = [
            "targetName": "TestApp",
            "files": ["App.swift", "ContentView.swift"]
        ]
        try JSONSerialization.data(withJSONObject: sourceManifest, options: [.sortedKeys])
            .write(to: iosDir.appendingPathComponent(".tenx-source-manifest.json"))

        // Growth / app-store marketing docs
        let growthDir = root.appendingPathComponent("growth/app-store", isDirectory: true)
        try fm.createDirectory(at: growthDir, withIntermediateDirectories: true)
        try "Keywords".write(to: growthDir.appendingPathComponent("keywords.txt"), atomically: true, encoding: .utf8)

        return fixture
    }

    private func listFiles(at url: URL) throws -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var paths: [String] = []
        while let item = enumerator.nextObject() as? URL {
            paths.append(Self.relativePath(of: item, relativeTo: url))
        }
        return paths
    }

    private static func relativePath(of url: URL, relativeTo baseURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath.hasPrefix(basePath + "/") else { return url.lastPathComponent }
        return String(urlPath.dropFirst(basePath.count + 1))
    }

    private static func slugify(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
    }
}
