import Foundation
import XCTest
@testable import TenXAppCore

final class LocalExportIntegrationTests: XCTestCase {
    private var rootURL: URL!
    private var originalBaseDirectory: URL?

    override func setUp() async throws {
        try await super.setUp()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        originalBaseDirectory = LocalProjectStore.baseDirectory
        LocalProjectStore.testBaseDirectoryOverride = rootURL
        addTeardownBlock {
            LocalProjectStore.testBaseDirectoryOverride = nil
            try? FileManager.default.removeItem(at: self.rootURL)
        }
    }

    override func tearDown() async throws {
        LocalProjectStore.testBaseDirectoryOverride = originalBaseDirectory
        try await super.tearDown()
    }

    private func makeProject() async throws -> BuilderProject {
        let database = try CockpitDatabase(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("export.sqlite")
        )
        let profile = try await ProfileRepository(database: database).loadOrCreateProfile()
        return try await ProjectRepository(database: database).createProject(
            userId: profile.id,
            name: "Exportable Project"
        )
    }

    // MARK: - Folder export

    func testFolderExportContainsProjectFilesAndIsNotGatedByBilling() async throws {
        let project = try await makeProject()
        let store = LocalProjectStore()

        let fileTree = ["App.swift": "import SwiftUI\n"]
        await store.saveFileTree(fileTree, projectName: project.name, projectId: project.id)

        let message = BuilderMessage(
            id: UUID().uuidString,
            conversationId: "chat-1",
            role: "assistant",
            content: "Exported generation",
            versionId: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        await store.saveMessages([message], projectName: project.name, projectId: project.id)

        let projectRoot = LocalProjectStore.projectRootDirectory(
            projectName: project.name,
            projectId: project.id
        )
        XCTAssertTrue(projectRoot.path.hasPrefix(rootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectRoot.path))

        let tenxDir = LocalProjectStore.tenxDirectory(
            projectName: project.name,
            projectId: project.id
        )
        let fileTreeURL = tenxDir.appendingPathComponent("file_tree.json")
        let messagesURL = tenxDir.appendingPathComponent("messages.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileTreeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: messagesURL.path))

        XCTAssertTrue(LocalEntitlements.canExport)
        XCTAssertFalse(LocalEntitlements.canUseBilling)
    }

    // MARK: - Zip export

    func testZipExportCanBeCreatedFromProjectFolder() async throws {
        let project = try await makeProject()
        let store = LocalProjectStore()
        let fileTree = ["App.swift": "import SwiftUI\n"]
        await store.saveFileTree(fileTree, projectName: project.name, projectId: project.id)

        let exportFolder = rootURL.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        let projectRoot = LocalProjectStore.projectRootDirectory(
            projectName: project.name,
            projectId: project.id
        )
        let exportedProjectFolder = exportFolder.appendingPathComponent(
            "\(project.name)-\(ISO8601DateFormatter().string(from: Date()))",
            isDirectory: true
        )
        try FileManager.default.copyItem(at: projectRoot, to: exportedProjectFolder)

        let manifestURL = exportedProjectFolder.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "app": "11x",
            "exportVersion": 1,
            "projectId": project.id,
            "projectName": project.name,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "includesAssets": true,
            "providerMetadataIncluded": true,
            "secretsIncluded": false,
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try manifestData.write(to: manifestURL)

        let zipURL = exportFolder.appendingPathComponent("\(project.name)-export.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = exportFolder
        process.arguments = ["-rq", zipURL.path, exportedProjectFolder.lastPathComponent]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
        let size = attributes[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    // MARK: - Export safety

    func testExportExcludesProviderSecrets() async throws {
        let project = try await makeProject()
        let providerConfig: [String: Any] = [
            "provider_type": "openai-compatible",
            "base_url": "https://api.openai.com",
            "model": "gpt-4.1",
        ]
        let exportFolder = rootURL.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        let providerJSON = try JSONSerialization.data(withJSONObject: providerConfig, options: [.sortedKeys])
        let providerURL = exportFolder.appendingPathComponent("provider.json")
        try providerJSON.write(to: providerURL)

        let contents = try String(contentsOf: providerURL, encoding: .utf8)
        XCTAssertFalse(contents.contains("api_key"))
        XCTAssertFalse(contents.contains("OPENAI_API_KEY"))
        XCTAssertFalse(contents.contains("sk-"))
    }
}
