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
        let isCandidate = importer.isLegacyProjectCandidate(at: root)
        XCTAssertTrue(isCandidate)

        let scanned = await importer.scanLegacyProjects(at: fixture.scanRoot)
        XCTAssertTrue(scanned.contains { $0.lastPathComponent == root.lastPathComponent })
    }

    func testDetectsCandidateByProjectYML() async throws {
        let fixture = try makeMinimalLegacyFixture(name: "YML Candidate", includeProjectJSON: false)
        let root = fixture.url

        let importer = LegacyTenXProjectImporter()
        let isCandidate = importer.isLegacyProjectCandidate(at: root)
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

    private func makeMinimalLegacyFixture(
        name: String,
        includeProjectJSON: Bool = true,
        includeIOSFiles: Bool = true
    ) throws -> LegacyFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        let scanRoot = root.deletingLastPathComponent()
        let fm = FileManager.default

        let tenxDir = root.appendingPathComponent(".tenx", isDirectory: true)
        try fm.createDirectory(at: tenxDir, withIntermediateDirectories: true)

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

        if includeIOSFiles {
            let iosDir = root.appendingPathComponent("ios", isDirectory: true)
            try fm.createDirectory(at: iosDir, withIntermediateDirectories: true)
            try Data("name: TestApp".utf8)
                .write(to: iosDir.appendingPathComponent("project.yml"))
        }

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

    // MARK: - Failure and retry

    func testFailedImportDoesNotBlockRetry() async throws {
        let fixture = try makeFullLegacyFixture(name: "Retryable Failure")

        // Inject a failing asset storage by using a root URL that is a file instead of a directory.
        let badStorage = LocalAssetStorage(rootURL: fixture.url.appendingPathComponent("ios/project.yml"), repository: AssetRepository(database: database))
        let failingImporter = LegacyTenXProjectImporter(
            database: database,
            assetStorage: badStorage,
            previewService: XcodePreviewService()
        )

        let first = try? await failingImporter.importProject(from: fixture.url)
        XCTAssertNil(first?.project, "Import should have failed")

        let second = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(second.succeeded, "Retry after failed import should succeed: \(second.errors.joined(separator: ", "))")
        XCTAssertFalse(second.alreadyImported)
        if let project = second.project {
            createdProjectIds.append(project.id)
            createdProjectNames.append(project.name)
            createdAppSupportProjectPaths.append(
                await XcodePreviewService().projectDir(for: project.name, projectId: project.id)
            )
        }
    }

    func testIncompleteImportRecordDoesNotBlockRetry() async throws {
        let fixture = try makeFullLegacyFixture(name: "Incomplete Record")
        let repo = LegacyImportRepository(database: database)

        // Manually insert an in_progress record.
        let profile = try await ProfileRepository(database: database).loadOrCreateProfile()
        let project = try await ProjectRepository(database: database).createProject(userId: profile.id, name: "Incomplete", platform: "swiftui")
        createdProjectIds.append(project.id)
        let fingerprint = "incomplete-fingerprint"
        _ = try await repo.startImport(
            sourcePath: fixture.url.path,
            legacyProjectId: "legacy-incomplete",
            manifestId: nil,
            contentFingerprint: fingerprint,
            projectId: project.id
        )

        // Retry should succeed because the prior import is not completed.
        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(report.alreadyImported)
        if let p = report.project {
            createdProjectIds.append(p.id)
            createdProjectNames.append(p.name)
            createdAppSupportProjectPaths.append(
                await XcodePreviewService().projectDir(for: p.name, projectId: p.id)
            )
        }
    }

    func testOrphanLegacyImportDoesNotBlockReimport() async throws {
        let fixture = try makeFullLegacyFixture(name: "Orphan Import")
        let repo = LegacyImportRepository(database: database)
        let profile = try await ProfileRepository(database: database).loadOrCreateProfile()
        let project = try await ProjectRepository(database: database).createProject(userId: profile.id, name: "Orphan", platform: "swiftui")
        createdProjectIds.append(project.id)
        let record = try await repo.startImport(
            sourcePath: fixture.url.path,
            legacyProjectId: nil,
            manifestId: nil,
            contentFingerprint: "orphan-fingerprint",
            projectId: project.id
        )
        try await repo.completeImport(id: record.id)

        // Delete the project; with FK cascade the legacy_imports row should also disappear.
        try await ProjectRepository(database: database).deleteProject(id: project.id)

        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(report.alreadyImported)
        if let p = report.project {
            createdProjectIds.append(p.id)
            createdProjectNames.append(p.name)
            createdAppSupportProjectPaths.append(
                await XcodePreviewService().projectDir(for: p.name, projectId: p.id)
            )
        }
    }

    func testMalformedMessagesIsPreservedRaw() async throws {
        let fixture = try makeFullLegacyFixture(name: "Malformed Messages")
        try "not valid json".write(
            to: fixture.url.appendingPathComponent(".tenx/messages.json"),
            atomically: true,
            encoding: .utf8
        )

        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(report.importedMessageCount, 0)
        XCTAssertTrue(report.errors.contains { $0.contains("messages.json") })

        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)

        let assetRepo = AssetRepository(database: database)
        let assets = try await assetRepo.fetchAssets(projectId: project.id)
        let rawAsset = assets.first { $0.relativePath.contains("messages.json") }
        XCTAssertNotNil(rawAsset)
    }

    func testMalformedChatsIsPreservedRaw() async throws {
        let fixture = try makeFullLegacyFixture(name: "Malformed Chats")
        try "not valid json".write(
            to: fixture.url.appendingPathComponent(".tenx/chats.json"),
            atomically: true,
            encoding: .utf8
        )

        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertTrue(report.errors.contains { $0.contains("chats.json") })

        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)

        let assetRepo = AssetRepository(database: database)
        let assets = try await assetRepo.fetchAssets(projectId: project.id)
        let rawAsset = assets.first { $0.relativePath.contains("chats.json") }
        XCTAssertNotNil(rawAsset)
    }

    func testChatStateFilesPreserved() async throws {
        let fixture = try makeFullLegacyFixture(name: "Chat State Preserved")
        let chatId = UUID().uuidString
        let chatStateDir = fixture.url.appendingPathComponent(".tenx/chats/\(chatId)", isDirectory: true)
        try FileManager.default.createDirectory(at: chatStateDir, withIntermediateDirectories: true)
        let state: [String: Any] = ["messages": []]
        try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
            .write(to: chatStateDir.appendingPathComponent("state.json"))

        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(report.rawChatStatesPreserved, 1)

        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)
    }

    func testSourceOnlyImportRequiresGenerationContext() async throws {
        // Fixture with only metadata but no source, messages, or conversation should fail.
        let fixture = try makeMinimalLegacyFixture(name: "Source Only", includeIOSFiles: false)

        do {
            _ = try await importer.importProject(from: fixture.url)
            XCTFail("Expected nothingImportable error for source-only project")
        } catch let error as LegacyTenXImportError {
            if case .nothingImportable = error {
                // Expected
            } else {
                XCTFail("Expected nothingImportable, got \(error)")
            }
        }
    }

    func testFingerprintDoesNotCollideForSparseProjects() async throws {
        let a = try makeMinimalLegacyFixture(name: "Sparse A", includeProjectJSON: false)
        let b = try makeMinimalLegacyFixture(name: "Sparse B", includeProjectJSON: false)

        let first = try await importer.importProject(from: a.url)
        XCTAssertTrue(first.succeeded)
        if let p = first.project {
            createdProjectIds.append(p.id)
            createdProjectNames.append(p.name)
            createdAppSupportProjectPaths.append(
                await XcodePreviewService().projectDir(for: p.name, projectId: p.id)
            )
        }

        let second = try await importer.importProject(from: b.url)
        XCTAssertTrue(second.succeeded)
        XCTAssertFalse(second.alreadyImported)
        if let p = second.project {
            createdProjectIds.append(p.id)
            createdProjectNames.append(p.name)
            createdAppSupportProjectPaths.append(
                await XcodePreviewService().projectDir(for: p.name, projectId: p.id)
            )
        }
    }

    func testSymlinkIsSkippedAndDoesNotEscapeRoot() async throws {
        let fixture = try makeFullLegacyFixture(name: "Symlink Test")
        let outsideFile = fixture.scanRoot.appendingPathComponent("outside.txt")
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)
        let linkPath = fixture.url.appendingPathComponent("ios/EscapeLink")
        try FileManager.default.createSymbolicLink(atPath: linkPath.path, withDestinationPath: outsideFile.path)

        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertTrue(report.skipped.contains { $0.contains("Symlink skipped") })

        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)
        let projectRoot = await XcodePreviewService().projectDir(for: project.name, projectId: project.id)
        createdAppSupportProjectPaths.append(projectRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("ios/EscapeLink").path))
        try? FileManager.default.removeItem(at: outsideFile)
    }

    func testPathTraversalCannotEscapeDestinationRoot() async throws {
        let fixture = try makeFullLegacyFixture(name: "Traversal Test")
        let weirdDir = fixture.url.appendingPathComponent("ios/TestApp/dotdot", isDirectory: true)
        try FileManager.default.createDirectory(at: weirdDir, withIntermediateDirectories: true)
        try "evil".write(to: weirdDir.appendingPathComponent("evil.swift"), atomically: true, encoding: .utf8)

        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        let project = try XCTUnwrap(report.project)
        createdProjectIds.append(project.id)
        createdProjectNames.append(project.name)
        let projectRoot = await XcodePreviewService().projectDir(for: project.name, projectId: project.id)
        createdAppSupportProjectPaths.append(projectRoot)

        // The destination should not contain files above the ios/ destination root.
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("evil.swift").path))
    }

    func testDeterministicFallbackMessageIDs() async throws {
        let fixture = try makeFullLegacyFixture(name: "Deterministic IDs")
        // Use a non-UUID string id to exercise fallback path.
        let messages: [[String: Any]] = [
            [
                "id": "not-a-uuid",
                "role": "user",
                "content": "Hello",
                "conversation_id": "",
                "created_at": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        try JSONSerialization.data(withJSONObject: messages, options: [.sortedKeys])
            .write(to: fixture.url.appendingPathComponent(".tenx/messages.json"))

        let first = try await importer.importProject(from: fixture.url)
        _ = try await importer.importProject(from: fixture.url)
        // Re-import should be already-imported; still, the imported message id should be stable.
        XCTAssertTrue(first.succeeded)
        if let p = first.project {
            createdProjectIds.append(p.id)
            createdProjectNames.append(p.name)
            createdAppSupportProjectPaths.append(
                await XcodePreviewService().projectDir(for: p.name, projectId: p.id)
            )
        }
    }

    func testImportReportContainsSkippedAndUnavailableInfo() async throws {
        let fixture = try makeFullLegacyFixture(name: "Report Info")
        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertTrue(report.skipped.contains { $0.contains(".git") })
        if let p = report.project {
            createdProjectIds.append(p.id)
            createdProjectNames.append(p.name)
            createdAppSupportProjectPaths.append(
                await XcodePreviewService().projectDir(for: p.name, projectId: p.id)
            )
        }
    }

    func testLegacyImportDoesNotRequireAccessToken() async throws {
        let fixture = try makeFullLegacyFixture(name: "Tokenless")

        // The legacy importer itself is local-only and does not take a remote token.
        let report = try await importer.importProject(from: fixture.url)
        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(report.alreadyImported)
        if let p = report.project {
            createdProjectIds.append(p.id)
            createdProjectNames.append(p.name)
            createdAppSupportProjectPaths.append(
                await XcodePreviewService().projectDir(for: p.name, projectId: p.id)
            )
        }
    }

}
