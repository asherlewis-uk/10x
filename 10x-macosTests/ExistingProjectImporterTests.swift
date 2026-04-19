import XCTest
@testable import TenXAppCore

final class ExistingProjectImporterTests: XCTestCase {
    func testResolveSelectionFindsProjectInsideDirectory() async throws {
        let rootURL = try makeTempDirectory()
        let projectURL = rootURL.appendingPathComponent("SampleApp", isDirectory: true)
        let xcodeprojURL = projectURL.appendingPathComponent("SampleApp.xcodeproj", isDirectory: true)

        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "import SwiftUI\n".write(
            to: projectURL.appendingPathComponent("SampleAppApp.swift"),
            atomically: true,
            encoding: .utf8
        )

        let importer = ExistingProjectImporter()
        let selection = try await importer.resolveSelection(at: projectURL)

        XCTAssertEqual(selection.rootURL.standardizedFileURL, projectURL.standardizedFileURL)
        XCTAssertEqual(selection.containerURL.standardizedFileURL, xcodeprojURL.standardizedFileURL)
        XCTAssertEqual(selection.containerKind, .project)
        XCTAssertEqual(selection.displayName, "SampleApp")
    }

    func testLoadTextFileTreeSkipsBinaryAndBuildArtifacts() async throws {
        let rootURL = try makeTempDirectory()
        let xcodeprojURL = rootURL.appendingPathComponent("SampleApp.xcodeproj", isDirectory: true)
        let assetsURL = rootURL
            .appendingPathComponent("Assets.xcassets", isDirectory: true)
            .appendingPathComponent("AppIcon.appiconset", isDirectory: true)

        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("DerivedData", isDirectory: true),
            withIntermediateDirectories: true
        )

        try """
        import SwiftUI

        @main
        struct SampleAppApp: App {
            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }
        """.write(
            to: rootURL.appendingPathComponent("SampleAppApp.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct ContentView: View { var body: some View { Text(\"Hi\") } }".write(
            to: rootURL.appendingPathComponent("ContentView.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "// !$*UTF8*$!\n".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true,
            encoding: .utf8
        )
        try "{ \"images\": [], \"info\": { \"version\": 1, \"author\": \"xcode\" } }".write(
            to: assetsURL.appendingPathComponent("Contents.json"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored".write(
            to: rootURL.appendingPathComponent("DerivedData/Ignore.swift"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0x89, 0x50, 0x4E, 0x47]).write(
            to: rootURL.appendingPathComponent("Preview.png")
        )

        let importer = ExistingProjectImporter()
        let fileTree = try await importer.loadTextFileTree(from: rootURL)

        XCTAssertNotNil(fileTree["SampleAppApp.swift"])
        XCTAssertNotNil(fileTree["ContentView.swift"])
        XCTAssertNotNil(fileTree["SampleApp.xcodeproj/project.pbxproj"])
        XCTAssertNotNil(fileTree["Assets.xcassets/AppIcon.appiconset/Contents.json"])
        XCTAssertNil(fileTree["Preview.png"])
        XCTAssertNil(fileTree["DerivedData/Ignore.swift"])
    }

    func testImportedWorkspaceDescriptorReadsStoredSettings() {
        let metadata = ImportedProjectMetadata(
            workspaceRootRelativePath: "imported/SampleApp",
            xcodeContainerRelativePath: "imported/SampleApp/SampleApp.xcodeproj",
            xcodeContainerKind: .project,
            scheme: "SampleApp",
            bundleIdentifier: "com.example.sample"
        )
        let project = BuilderProject(
            id: UUID().uuidString,
            userId: UUID().uuidString,
            name: "Imported App",
            description: nil,
            slug: "imported-app",
            platform: "swiftui",
            status: "active",
            currentVersionId: nil,
            settings: metadata.settingsDictionary,
            createdAt: "2026-04-14T00:00:00Z",
            updatedAt: "2026-04-14T00:00:00Z"
        )

        let descriptor = project.workspaceDescriptor

        XCTAssertTrue(descriptor.isImported)
        XCTAssertEqual(descriptor.workspaceRootRelativePath, metadata.workspaceRootRelativePath)
        XCTAssertEqual(descriptor.xcodeContainerRelativePath, metadata.xcodeContainerRelativePath)
        XCTAssertEqual(descriptor.xcodeContainerKind, .project)
        XCTAssertEqual(descriptor.scheme, "SampleApp")
        XCTAssertEqual(descriptor.bundleIdentifier, "com.example.sample")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TenXAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
