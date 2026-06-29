import Foundation
import AppKit

struct CompileResult: Sendable {
    let success: Bool
    let errors: [String]
    let output: String
}

/// Writes generated SwiftUI files to disk as a standard Xcode iOS project and opens it.
actor XcodePreviewService {
    private let baseDir: URL

    init() {
        baseDir = AppIdentity.appSupportDirectory
    }

    // MARK: - Project Directory Layout
    //
    // ~/Library/Application Support/11x/{project-slug}/
    // ├── ios/                          # Xcode project
    // │   ├── {TargetName}/             # Swift source files
    // │   ├── {TargetName}.xcodeproj/
    // │   └── DerivedData/              # Build cache
    // ├── planning/                     # Specs, briefs, notes
    // │   └── brief.md
    // ├── assets/                       # Design assets, screenshots
    // └── tenx/
    //     └── project.json              # Metadata

    /// Resolve the root project directory for a given project.
    /// Uses projectId to ensure uniqueness when names collide.
    func projectDir(for projectName: String, projectId: String? = nil) -> URL {
        let safeName = Self.safeName(from: projectName)
        let dirName = if let projectId, !projectId.isEmpty {
            "\(safeName)-\(projectId.prefix(8))"
        } else {
            safeName
        }
        return baseDir.appendingPathComponent(dirName, isDirectory: true)
    }

    /// The ios/ subdirectory where the Xcode project lives.
    func iosDir(for projectName: String, projectId: String? = nil) -> URL {
        projectDir(for: projectName, projectId: projectId).appendingPathComponent("ios", isDirectory: true)
    }

    func writeProductionGuideIfNeeded(
        projectName: String,
        projectId: String,
        fileTree: [String: String],
        environmentVariables: [ProjectEnvironmentVariable]
    ) {
        let rootDir = projectDir(for: projectName, projectId: projectId)
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        ensureProductionGuide(
            in: rootDir,
            projectName: projectName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )
    }

    func moveProjectDirectory(oldProjectName: String, newProjectName: String, projectId: String) throws -> URL {
        let oldDir = projectDir(for: oldProjectName, projectId: projectId)
        let newDir = projectDir(for: newProjectName, projectId: projectId)

        guard oldDir.path != newDir.path else { return newDir }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: oldDir.path), !fileManager.fileExists(atPath: newDir.path) {
            try fileManager.moveItem(at: oldDir, to: newDir)
        }

        if fileManager.fileExists(atPath: newDir.path) {
            try renameGeneratedProjectArtifactsIfNeeded(
                in: newDir,
                oldProjectName: oldProjectName,
                newProjectName: newProjectName
            )
            try writeProjectMetadata(
                in: newDir,
                projectName: newProjectName,
                projectId: projectId,
                fileCount: nil
            )
        }

        return newDir
    }

    // MARK: - Naming Helpers

    static func safeName(from projectName: String) -> String {
        projectName
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
    }

    static func targetName(from projectName: String) -> String {
        let sanitized = projectName
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .map {
                guard let first = $0.first else { return "" }
                return first.uppercased() + $0.dropFirst()
            }
            .joined()

        let fallback = sanitized.isEmpty ? "GeneratedApp" : sanitized
        if let first = fallback.first, first.isNumber {
            return "App\(fallback)"
        }
        return fallback
    }

    static func bundleId(from projectName: String) -> String {
        "com.10x.generated.\(safeName(from: projectName))"
    }

    // MARK: - Clean Project Sources

    /// Remove source files, .xcodeproj, and DerivedData from a project's ios directory.
    /// Called when reverting to an empty state so leftover files don't contaminate
    /// the next generation (avoids "Multiple commands produce .stringsdata" errors).
    func cleanProjectSources(projectName: String, projectId: String? = nil) {
        let targetName = Self.targetName(from: projectName)
        let rootDir = projectDir(for: projectName, projectId: projectId)
        let iosDir = rootDir.appendingPathComponent("ios", isDirectory: true)
        let fm = FileManager.default

        let sourcesDir = iosDir.appendingPathComponent(targetName, isDirectory: true)
        if fm.fileExists(atPath: sourcesDir.path) {
            try? fm.removeItem(at: sourcesDir)
        }

        let xcodeprojDir = iosDir.appendingPathComponent("\(targetName).xcodeproj", isDirectory: true)
        if fm.fileExists(atPath: xcodeprojDir.path) {
            try? fm.removeItem(at: xcodeprojDir)
        }

        let localDerivedData = iosDir.appendingPathComponent("DerivedData", isDirectory: true)
        if fm.fileExists(atPath: localDerivedData.path) {
            try? fm.removeItem(at: localDerivedData)
        }

        let projectYml = iosDir.appendingPathComponent("project.yml")
        if fm.fileExists(atPath: projectYml.path) {
            try? fm.removeItem(at: projectYml)
        }

        let manifest = sourceManifestURL(in: iosDir)
        if fm.fileExists(atPath: manifest.path) {
            try? fm.removeItem(at: manifest)
        }

        Self.cleanSystemDerivedData(targetName: targetName)
    }

    // MARK: - Scaffold Empty Directory

    /// Create the project folder structure without writing any source files.
    /// Returns the root project directory URL.
    func scaffoldProjectDirectory(projectName: String, projectId: String? = nil) throws -> URL {
        let rootDir = projectDir(for: projectName, projectId: projectId)
        let iosDir = rootDir.appendingPathComponent("ios", isDirectory: true)
        let planningDir = rootDir.appendingPathComponent("planning", isDirectory: true)
        let assetsDir = rootDir.appendingPathComponent("assets", isDirectory: true)
        let tenxDir = rootDir.appendingPathComponent("tenx", isDirectory: true)

        for dir in [iosDir, planningDir, assetsDir, tenxDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return rootDir
    }

    // MARK: - Write Project to Disk

    /// Scaffold the full project directory and write the iOS project files.
    /// Returns the root project directory URL.
    func writeProjectToDisk(
        fileTree: [String: String],
        projectName: String,
        projectId: String? = nil,
        prompt: String? = nil,
        customIcon: NSImage? = nil,
        environmentVariables: [ProjectEnvironmentVariable] = []
    ) async throws -> URL {
        let targetName = Self.targetName(from: projectName)
        let bundleId = Self.bundleId(from: projectName)
        let rootDir = projectDir(for: projectName, projectId: projectId)
        let iosDir = rootDir.appendingPathComponent("ios", isDirectory: true)
        let planningDir = rootDir.appendingPathComponent("planning", isDirectory: true)
        let assetsOutputDir = rootDir.appendingPathComponent("assets", isDirectory: true)
        let tenxDir = rootDir.appendingPathComponent("tenx", isDirectory: true)

        // Create directory structure
        for dir in [iosDir, planningDir, assetsOutputDir, tenxDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try cleanupStaleProjectArtifacts(in: iosDir, keepingTargetName: targetName)

        // --- iOS project ---

        // Clean source files and DerivedData to avoid stale build conflicts
        let sourcesDir = iosDir.appendingPathComponent(targetName, isDirectory: true)
        if FileManager.default.fileExists(atPath: sourcesDir.path) {
            try FileManager.default.removeItem(at: sourcesDir)
        }
        // Clean local DerivedData (used by our project.yml options.derivedDataPath)
        let localDerivedData = iosDir.appendingPathComponent("DerivedData", isDirectory: true)
        if FileManager.default.fileExists(atPath: localDerivedData.path) {
            try? FileManager.default.removeItem(at: localDerivedData)
        }
        // Also clean system-level DerivedData for this target to prevent
        // "Multiple commands produce .app" from stale Xcode build plans
        Self.cleanSystemDerivedData(targetName: targetName)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        // Write Swift source files (coordinated so Xcode auto-reloads without prompting)
        for (path, content) in fileTree {
            let fileURL = sourcesDir.appendingPathComponent(path)
            let parentDir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            CoordinatedFileWriter.write(content, to: fileURL)
        }

        try injectTenXSupport(in: sourcesDir)

        try ensureAppAssets(
            in: sourcesDir,
            fileTree: fileTree,
            customIcon: customIcon
        )

        // Generate .xcodeproj via XcodeGen
        try generateXcodeProject(
            iosDir: iosDir,
            targetName: targetName,
            bundleId: bundleId,
            displayName: projectName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )

        // --- Planning ---

        let briefPath = planningDir.appendingPathComponent("brief.md")
        if !FileManager.default.fileExists(atPath: briefPath.path) {
            let brief = """
            # \(projectName)

            **Platform:** iOS 26 (SwiftUI + Liquid Glass)
            **Bundle ID:** \(bundleId)
            **Generated:** \(ISO8601DateFormatter().string(from: Date()))

            ## Description

            \(prompt ?? "AI-generated iOS app.")

            ## Files

            \(fileTree.keys.sorted().map { "- \($0)" }.joined(separator: "\n"))
            """
            CoordinatedFileWriter.write(brief, to: briefPath)
        }

        ensureProductionGuide(
            in: rootDir,
            projectName: projectName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )

        // --- Metadata ---

        try writeProjectMetadata(
            in: rootDir,
            projectName: projectName,
            projectId: projectId,
            fileCount: fileTree.count
        )

        return rootDir
    }

    // MARK: - Open in Xcode

    /// Write the file tree to disk and open the project in Xcode.
    func openInXcode(
        fileTree: [String: String],
        projectName: String,
        projectId: String? = nil,
        customIcon: NSImage? = nil,
        environmentVariables: [ProjectEnvironmentVariable] = []
    ) async throws {
        _ = try await writeProjectToDisk(
            fileTree: fileTree,
            projectName: projectName,
            projectId: projectId,
            customIcon: customIcon,
            environmentVariables: environmentVariables
        )

        let targetName = Self.targetName(from: projectName)
        let xcodeprojDir = iosDir(for: projectName, projectId: projectId)
            .appendingPathComponent("\(targetName).xcodeproj", isDirectory: true)

        await MainActor.run {
            NSWorkspace.shared.open(
                [xcodeprojDir],
                withApplicationAt: URL(fileURLWithPath: "/Applications/Xcode.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    // MARK: - Compile Check

    /// Compile the file tree against iOS SDK and return any errors.
    func compile(fileTree: [String: String], projectName: String) async throws -> CompileResult {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ElevenX-compile-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Use a Swift Package for compile checks (faster than full xcodebuild)
        let packageSwift = Self.compileCheckPackageContents(
            requiredPackages: Self.requiredPackageDependencies(for: fileTree)
        )
        try packageSwift.write(
            to: tempDir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let sourcesDir = tempDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        for (path, content) in fileTree {
            let fileURL = sourcesDir.appendingPathComponent(path)
            let parentDir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [
            "build",
            "--package-path", tempDir.path,
            "--sdk", "iphonesimulator"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return CompileResult(success: true, errors: [], output: output)
        }

        let errors = output
            .components(separatedBy: "\n")
            .filter { $0.contains("error:") }

        return CompileResult(success: false, errors: errors, output: output)
    }

    // MARK: - DerivedData Cleanup

    /// Remove system-level DerivedData folders matching this target name.
    /// Prevents "Multiple commands produce .app" when XcodeGen regenerates the project.
    private static func cleanSystemDerivedData(targetName: String) {
        let systemDerivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: systemDerivedData,
            includingPropertiesForKeys: nil
        ) else { return }

        for dir in contents where dir.lastPathComponent.hasPrefix(targetName + "-") {
            try? FileManager.default.removeItem(at: dir)
            print("[10x] Cleaned system DerivedData: \(dir.lastPathComponent)")
        }
    }

    // MARK: - Xcode Project Generation (via XcodeGen)

    /// Prepare preview support files after ToolExecutor has already written source files.
    /// Regenerates the .xcodeproj when either the project config changed or the
    /// set of source/resource files changed, so newly created files are actually
    /// added to the Xcode target while normal content-only edits still reuse build cache.
    func regenerateXcodeProject(
        projectName: String,
        projectId: String? = nil,
        fileTree: [String: String],
        customIcon: NSImage? = nil,
        environmentVariables: [ProjectEnvironmentVariable] = []
    ) throws {
        let targetName = Self.targetName(from: projectName)
        let bundleId = Self.bundleId(from: projectName)
        let iosDir = self.iosDir(for: projectName, projectId: projectId)
        let sourcesDir = iosDir.appendingPathComponent(targetName, isDirectory: true)

        removeOrphanedSourceFiles(in: sourcesDir, fileTree: fileTree)

        try injectTenXSupport(in: sourcesDir)

        try ensureAppAssets(
            in: sourcesDir,
            fileTree: fileTree,
            customIcon: customIcon
        )

        if needsProjectRegeneration(
            iosDir: iosDir,
            targetName: targetName,
            bundleId: bundleId,
            displayName: projectName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        ) {
            try cleanupStaleProjectArtifacts(in: iosDir, keepingTargetName: targetName)

            // A real project regeneration can invalidate Xcode's build plan, so clear
            // both local and system DerivedData only in that case.
            let localDerivedData = iosDir.appendingPathComponent("DerivedData", isDirectory: true)
            if FileManager.default.fileExists(atPath: localDerivedData.path) {
                try? FileManager.default.removeItem(at: localDerivedData)
            }
            Self.cleanSystemDerivedData(targetName: targetName)

            try generateXcodeProject(
                iosDir: iosDir,
                targetName: targetName,
                bundleId: bundleId,
                displayName: projectName,
                fileTree: fileTree,
                environmentVariables: environmentVariables
            )
        }

        ensureProductionGuide(
            in: projectDir(for: projectName, projectId: projectId),
            projectName: projectName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )

        try writeProjectMetadata(
            in: projectDir(for: projectName, projectId: projectId),
            projectName: projectName,
            projectId: projectId,
            fileCount: fileTree.count
        )
    }

    private func renameGeneratedProjectArtifactsIfNeeded(
        in rootDir: URL,
        oldProjectName: String,
        newProjectName: String
    ) throws {
        let oldTargetName = Self.targetName(from: oldProjectName)
        let newTargetName = Self.targetName(from: newProjectName)
        guard oldTargetName != newTargetName else { return }

        let iosDir = rootDir.appendingPathComponent("ios", isDirectory: true)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: iosDir.path) else { return }

        let oldSourcesDir = iosDir.appendingPathComponent(oldTargetName, isDirectory: true)
        let newSourcesDir = iosDir.appendingPathComponent(newTargetName, isDirectory: true)
        if fileManager.fileExists(atPath: oldSourcesDir.path),
           !fileManager.fileExists(atPath: newSourcesDir.path) {
            try fileManager.moveItem(at: oldSourcesDir, to: newSourcesDir)
        }

        let oldXcodeprojDir = iosDir.appendingPathComponent("\(oldTargetName).xcodeproj", isDirectory: true)
        let newXcodeprojDir = iosDir.appendingPathComponent("\(newTargetName).xcodeproj", isDirectory: true)
        if fileManager.fileExists(atPath: oldXcodeprojDir.path),
           !fileManager.fileExists(atPath: newXcodeprojDir.path) {
            try fileManager.moveItem(at: oldXcodeprojDir, to: newXcodeprojDir)
        }
    }

    private func cleanupStaleProjectArtifacts(in iosDir: URL, keepingTargetName targetName: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: iosDir.path) else { return }

        let allowedNames: Set<String> = [
            "DerivedData",
            "project.yml",
            targetName,
            "\(targetName).xcodeproj"
        ]
        let contents = try fileManager.contentsOfDirectory(
            at: iosDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let name = item.lastPathComponent
            guard !allowedNames.contains(name) else { continue }

            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            if name.hasSuffix(".xcodeproj") || isLikelyGeneratedTargetDirectory(item) {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private func isLikelyGeneratedTargetDirectory(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        if contents.contains(where: { $0.lastPathComponent == "Assets.xcassets" || $0.pathExtension == "swift" }) {
            return true
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let child as URL in enumerator where child.pathExtension == "swift" {
            return true
        }

        return false
    }

    /// Remove Swift files from sourcesDir that are not present in the in-memory fileTree
    /// and were not injected by TenX preview support. This prevents stale files left
    /// over from a previous generation from being picked up by XcodeGen, which can cause
    /// "Multiple commands produce .stringsdata" when two files share the same base name.
    private func removeOrphanedSourceFiles(in sourcesDir: URL, fileTree: [String: String]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcesDir.path),
              let enumerator = fm.enumerator(
                at: sourcesDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else { return }

        let injectedFilenames: Set<String> = Set(Self.allTenXSupportFilenames)
        var assetsPrefix: String { "Assets.xcassets" }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }

            let relativePath = fileURL.path
                .replacingOccurrences(of: sourcesDir.path + "/", with: "")

            if relativePath.hasPrefix(assetsPrefix) { continue }
            if injectedFilenames.contains(fileURL.lastPathComponent) { continue }

            if fileTree[relativePath] == nil {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    private func writeProjectMetadata(
        in rootDir: URL,
        projectName: String,
        projectId: String?,
        fileCount: Int?
    ) throws {
        let tenxDir = rootDir.appendingPathComponent("tenx", isDirectory: true)
        try FileManager.default.createDirectory(at: tenxDir, withIntermediateDirectories: true)

        let metadataPath = tenxDir.appendingPathComponent("project.json")

        let existingMetadata: [String: Any]
        if let data = try? Data(contentsOf: metadataPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existingMetadata = json
        } else {
            existingMetadata = [:]
        }

        var metadata = existingMetadata
        metadata["name"] = projectName
        metadata["slug"] = Self.safeName(from: projectName)
        metadata["targetName"] = Self.targetName(from: projectName)
        metadata["bundleId"] = Self.bundleId(from: projectName)
        metadata["projectId"] = projectId ?? (existingMetadata["projectId"] as? String) ?? ""
        metadata["platform"] = (existingMetadata["platform"] as? String) ?? "ios"
        metadata["lastUpdated"] = ISO8601DateFormatter().string(from: Date())
        metadata["fileCount"] = fileCount ?? (existingMetadata["fileCount"] as? Int) ?? 0

        let jsonData = try JSONSerialization.data(
            withJSONObject: metadata,
            options: [.prettyPrinted, .sortedKeys]
        )
        CoordinatedFileWriter.writeData(jsonData, to: metadataPath)
    }

    private func ensureProductionGuide(
        in rootDir: URL,
        projectName: String,
        fileTree: [String: String],
        environmentVariables: [ProjectEnvironmentVariable]
    ) {
        let guideURL = rootDir.appendingPathComponent("PRODUCTION.md")
        if let existing = try? String(contentsOf: guideURL, encoding: .utf8),
           !existing.isEmpty,
           !existing.contains(ProductionGuideBuilder.generatedMarker) {
            return
        }

        let guide = ProductionGuideBuilder.build(
            projectName: projectName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )
        CoordinatedFileWriter.write(guide.markdown, to: guideURL)
    }

    /// Generate a proper .xcodeproj using the bundled XcodeGen binary.
    private func generateXcodeProject(
        iosDir: URL,
        targetName: String,
        bundleId: String,
        displayName: String,
        fileTree: [String: String],
        environmentVariables: [ProjectEnvironmentVariable]
    ) throws {
        let projectYml = Self.projectYmlContents(
            targetName: targetName,
            bundleId: bundleId,
            displayName: displayName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )
        CoordinatedFileWriter.write(projectYml, to: iosDir.appendingPathComponent("project.yml"))

        let xcodeprojDir = iosDir.appendingPathComponent("\(targetName).xcodeproj", isDirectory: true)

        // Use bundled xcodegen binary (it overwrites the .xcodeproj in place)
        #if SWIFT_PACKAGE
        let resourceBundle = Bundle.module
        #else
        let resourceBundle = Bundle.main
        #endif

        guard let xcodegen = resourceBundle.url(forResource: "xcodegen", withExtension: nil) else {
            throw XcodeGenError.binaryNotFound
        }

        let process = Process()
        process.executableURL = xcodegen
        process.arguments = ["generate", "--spec", "project.yml", "--no-env"]
        process.currentDirectoryURL = iosDir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw XcodeGenError.generationFailed(output)
        }

        // XcodeGen's derivedDataPath option doesn't reliably create WorkspaceSettings.
        // Write it ourselves so Xcode IDE uses local DerivedData instead of the system location,
        // preventing stale build plans from causing "Multiple commands produce .app" errors.
        let sharedDataDir = xcodeprojDir
            .appendingPathComponent("project.xcworkspace", isDirectory: true)
            .appendingPathComponent("xcshareddata", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedDataDir, withIntermediateDirectories: true)

        let workspaceSettings = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>BuildLocationStyle</key>
            <string>UseAppPreferences</string>
            <key>DerivedDataLocationStyle</key>
            <string>WorkspaceRelativePath</string>
            <key>DerivedDataCustomLocation</key>
            <string>DerivedData</string>
        </dict>
        </plist>
        """
        CoordinatedFileWriter.write(workspaceSettings, to: sharedDataDir.appendingPathComponent("WorkspaceSettings.xcsettings"))

        try writeSourceManifest(in: iosDir, targetName: targetName)
    }

    private func writeSourceManifest(in iosDir: URL, targetName: String) throws {
        let sourcesDir = iosDir.appendingPathComponent(targetName, isDirectory: true)
        let entries = sourceManifestEntries(in: sourcesDir) ?? []
        let payload: [String: Any] = [
            "targetName": targetName,
            "files": entries,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        CoordinatedFileWriter.writeData(data, to: sourceManifestURL(in: iosDir))
    }

    private func storedSourceManifestEntries(in iosDir: URL) -> [String]? {
        let manifestURL = sourceManifestURL(in: iosDir)
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [String]
        else {
            return nil
        }

        return files.sorted()
    }

    private func sourceManifestEntries(in sourcesDir: URL) -> [String]? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourcesDir.path),
              let enumerator = fileManager.enumerator(
                at: sourcesDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return nil
        }

        var entries: [String] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(of: sourcesDir.path + "/", with: "")
            entries.append(relativePath)
        }

        return entries.sorted()
    }

    private func sourceManifestURL(in iosDir: URL) -> URL {
        iosDir.appendingPathComponent(".tenx-source-manifest.json")
    }

    /// Writes the merged TenX support helper into the sources directory,
    /// removes legacy helper files, and injects view tracking into screen-level views.
    func injectTenXSupport(in sourcesDir: URL) throws {
        for legacyFilename in Self.legacyTenXSupportFilenames {
            let legacyURL = sourcesDir.appendingPathComponent(legacyFilename)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try? FileManager.default.removeItem(at: legacyURL)
            }
        }

        let helperURL = sourcesDir.appendingPathComponent(Self.tenXSupportFilename)
        CoordinatedFileWriter.write(
            Self.tenXSupportSource(),
            to: helperURL
        )

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sourcesDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift",
                  !Self.allTenXSupportFilenames.contains(fileURL.lastPathComponent)
            else { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let relativePath = fileURL.path
                .replacingOccurrences(of: sourcesDir.path + "/", with: "")
            guard Self.isScreenLevelViewFile(path: relativePath, content: content) else { continue }

            if let modified = Self.withInjectedViewTracking(
                content: content,
                preferredViewNames: Self.preferredTrackedViewNames(for: relativePath)
            ) {
                CoordinatedFileWriter.write(modified, to: fileURL)
            }
        }
    }

    // MARK: - Programmatic View Tracking Injection

    /// Determines if a file is a screen-level view that should get tracking.
    static func isScreenLevelViewFile(path: String, content: String) -> Bool {
        guard content.range(of: #":\s*.*\bView\b"#, options: .regularExpression) != nil else {
            return false
        }
        let lower = path.lowercased()
        if lower.hasPrefix("components/") { return false }
        if lower.hasPrefix("models/") || lower.hasPrefix("viewmodels/") || lower.hasPrefix("services/") { return false }
        if lower.hasSuffix("app.swift") { return false }

        return lower == "contentview.swift"
            || lower.hasPrefix("views/")
            || lower.hasSuffix("view.swift")
    }

    /// Injects `.trackView("StructName")` onto a transparent `Group` wrapping the body
    /// of the screen view that best matches the file name, so captured screens keep the
    /// actual SwiftUI view type instead of a helper view declared in the same file.
    static func withInjectedViewTracking(content: String, preferredViewNames: [String]) -> String? {
        let normalizedContent = removingLegacyInjectedViewTracking(from: content)
        if normalizedContent.contains(".trackView(") {
            return normalizedContent == content ? nil : normalizedContent
        }

        let viewStructs = topLevelTrackedViewStructs(in: normalizedContent)
        guard !viewStructs.isEmpty else { return nil }

        let targetStruct = preferredViewNames.lazy.compactMap { preferredName in
            viewStructs.first(where: { $0.name == preferredName })
        }.first ?? (viewStructs.count == 1 ? viewStructs[0] : nil)

        guard let targetStruct,
              let injectionTarget = bodyInjectionTarget(in: normalizedContent, viewStruct: targetStruct)
        else {
            return nil
        }

        var result = normalizedContent
        let originalBody = String(result[injectionTarget.bodyRange])
        let wrappedBody = wrappedTrackedBody(
            originalBody,
            bodyIndentation: injectionTarget.bodyIndentation,
            viewName: injectionTarget.viewName
        )
        result.replaceSubrange(injectionTarget.bodyRange, with: wrappedBody)

        guard result != content else { return nil }
        return result
    }

    /// Resolves the top-level SwiftUI view name that TenX tracks for a source file.
    /// Runtime preview capture uses this to reject stale logged names that do not
    /// exist in the current project anymore.
    static func trackedViewName(for path: String, content: String) -> String? {
        guard isScreenLevelViewFile(path: path, content: content) else {
            return nil
        }

        let viewStructs = topLevelTrackedViewStructs(in: content)
        guard !viewStructs.isEmpty else { return nil }

        return preferredTrackedViewNames(for: path).lazy.compactMap { preferredName in
            viewStructs.first(where: { $0.name == preferredName })?.name
        }.first ?? (viewStructs.count == 1 ? viewStructs[0].name : nil)
    }

    static func trackedViewNames(in fileTree: [String: String]) -> Set<String> {
        let trackedEntries = fileTree.compactMap { path, content -> (path: String, viewName: String)? in
            guard let viewName = trackedViewName(for: path, content: content) else {
                return nil
            }
            return (path: path, viewName: viewName)
        }
        // Keep root ContentView names in the validation set. Some projects launch
        // directly into ContentView even when they also define other screen files,
        // and excluding it drops the true initial screen from preview capture.
        return Set(trackedEntries.map(\.viewName))
    }

    private struct TrackedViewStruct {
        let name: String
        let bodyRange: Range<String.Index>
    }

    private struct ViewBodyInjectionTarget {
        let viewName: String
        let bodyRange: Range<String.Index>
        let bodyIndentation: String
    }

    private static func preferredTrackedViewNames(for path: String) -> [String] {
        let baseName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard !baseName.isEmpty else { return [] }

        var ordered: [String] = []
        func append(_ name: String) {
            guard !name.isEmpty, !ordered.contains(name) else { return }
            ordered.append(name)
        }

        append(baseName)
        if !baseName.hasSuffix("View") {
            append(baseName + "View")
        }
        if !baseName.hasSuffix("Screen") {
            append(baseName + "Screen")
        }

        return ordered
    }

    private static func topLevelTrackedViewStructs(in content: String) -> [TrackedViewStruct] {
        guard let regex = try? NSRegularExpression(
            pattern: #"struct\s+([A-Za-z_][A-Za-z0-9_]*)\b(?:\s*<[^>{}]+>)?\s*:\s*[^{]*\bView\b[^{]*\{"#
        ) else {
            return []
        }

        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)

        return regex.matches(in: content, range: nsRange).compactMap { match in
            guard let declarationRange = Range(match.range, in: content),
                  let nameRange = Range(match.range(at: 1), in: content),
                  braceDepth(in: content, upTo: declarationRange.lowerBound) == 0
            else {
                return nil
            }

            let declaration = content[declarationRange]
            guard let openingBraceIndex = declaration.lastIndex(of: "{"),
                  let closingBraceIndex = matchingBraceIndex(in: content, openingBraceIndex: openingBraceIndex)
            else {
                return nil
            }

            let bodyStart = content.index(after: openingBraceIndex)
            guard bodyStart <= closingBraceIndex else { return nil }

            return TrackedViewStruct(
                name: String(content[nameRange]),
                bodyRange: bodyStart..<closingBraceIndex
            )
        }
    }

    private static func bodyInjectionTarget(
        in content: String,
        viewStruct: TrackedViewStruct
    ) -> ViewBodyInjectionTarget? {
        guard let regex = try? NSRegularExpression(
            pattern: #"var\s+body\s*:\s*some\s+View\s*\{"#
        ) else {
            return nil
        }

        let nsRange = NSRange(viewStruct.bodyRange, in: content)
        for match in regex.matches(in: content, range: nsRange) {
            guard let declarationRange = Range(match.range, in: content),
                  braceDepth(in: content[viewStruct.bodyRange], upTo: declarationRange.lowerBound) == 0
            else {
                continue
            }

            let declaration = content[declarationRange]
            guard let openingBraceIndex = declaration.lastIndex(of: "{") else { continue }
            guard let closingBraceIndex = matchingBraceIndex(in: content, openingBraceIndex: openingBraceIndex) else {
                continue
            }

            let bodyContentStart = content.index(after: openingBraceIndex)
            return ViewBodyInjectionTarget(
                viewName: viewStruct.name,
                bodyRange: bodyContentStart..<closingBraceIndex,
                bodyIndentation: lineIndentation(in: content, at: declarationRange.lowerBound)
            )
        }

        return nil
    }

    private static func removingLegacyInjectedViewTracking(from content: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\n([ \t]*)\.onAppear\s*\{\s*(?:TenXInject|TenXViewTracker)\.track\([^)]*\)\s*\}[ \t]*"#,
            options: []
        ) else {
            return content
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
    }

    private static func wrappedTrackedBody(
        _ originalBody: String,
        bodyIndentation: String,
        viewName: String
    ) -> String {
        let contentIndentation = bodyIndentation + "    "
        let groupIndentation = contentIndentation + "    "
        let trimmedBody = trimmingOuterBlankLines(from: originalBody)
        let indentedBody = reindentingBodyContent(
            trimmedBody,
            removing: contentIndentation,
            adding: groupIndentation
        )

        return [
            "",
            "\(contentIndentation)Group {",
            indentedBody,
            "\(contentIndentation)}",
            "\(contentIndentation).trackView(\(swiftStringLiteral(viewName)))",
            bodyIndentation,
        ].joined(separator: "\n")
    }

    private static func swiftStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func trimmingOuterBlankLines(from content: String) -> String {
        var lines = content.components(separatedBy: "\n")

        while let first = lines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
        }

        while let last = lines.last,
              last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }

        return lines.joined(separator: "\n")
    }

    private static func reindentingBodyContent(
        _ content: String,
        removing currentIndentation: String,
        adding targetIndentation: String
    ) -> String {
        content
            .components(separatedBy: "\n")
            .map { line in
                guard !line.isEmpty else { return targetIndentation }

                var adjustedLine = line
                if adjustedLine.hasPrefix(currentIndentation) {
                    adjustedLine.removeFirst(currentIndentation.count)
                }
                return targetIndentation + adjustedLine
            }
            .joined(separator: "\n")
    }

    private static func matchingBraceIndex(
        in content: String,
        openingBraceIndex: String.Index
    ) -> String.Index? {
        var braceCount = 1
        var cursor = content.index(after: openingBraceIndex)

        while cursor < content.endIndex {
            switch content[cursor] {
            case "{":
                braceCount += 1
            case "}":
                braceCount -= 1
                if braceCount == 0 {
                    return cursor
                }
            default:
                break
            }
            cursor = content.index(after: cursor)
        }

        return nil
    }

    private static func braceDepth<S: StringProtocol>(in content: S, upTo limit: S.Index) -> Int {
        var depth = 0
        var cursor = content.startIndex

        while cursor < limit {
            switch content[cursor] {
            case "{":
                depth += 1
            case "}":
                depth = max(0, depth - 1)
            default:
                break
            }
            cursor = content.index(after: cursor)
        }

        return depth
    }

    private static func lineIndentation(in content: String, at index: String.Index) -> String {
        let lineStart = content[..<index].lastIndex(of: "\n").map { content.index(after: $0) } ?? content.startIndex
        let indentation = content[lineStart..<index].prefix { $0 == " " || $0 == "\t" }
        return String(indentation)
    }

    private static func tenXSupportSource() -> String {
        return """
        import Foundation
        import SwiftUI

        /// Shared TenX preview hooks injected into generated projects.
        enum TenXPreviewSupport {
            /// The file used by preview capture to discover the currently visible screen.
            private static let viewLogURL: URL = {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                return docs.appendingPathComponent("tenx-view-log.json")
            }()

            /// Records the visible screen for TenX preview capture.
            static func track(_ viewName: String) {
                let entry: [String: Any] = [
                    "view": viewName,
                    "timestamp": Date().timeIntervalSince1970
                ]

                if let data = try? JSONSerialization.data(withJSONObject: entry) {
                    try? data.write(to: viewLogURL, options: .atomic)
                }
            }
        }

        /// Backward-compatible tracking shim for older generated screen code.
        enum TenXViewTracker {
            static func track(_ viewName: String) {
                TenXPreviewSupport.track(viewName)
            }
        }

        struct TenXPreviewTrackerModifier: ViewModifier {
            let viewName: String

            func body(content: Content) -> some View {
                content
                    .task(id: viewName) {
                        TenXPreviewSupport.track(viewName)
                    }
                    .onAppear {
                        TenXPreviewSupport.track(viewName)
                    }
            }
        }

        extension View {
            /// Manual opt-in hook if generated code wants to track a view explicitly.
            func trackView(_ name: String) -> some View {
                modifier(TenXPreviewTrackerModifier(viewName: name))
            }
        }
        """
    }

    private func ensureAppAssets(
        in sourcesDir: URL,
        fileTree: [String: String],
        customIcon: NSImage?
    ) throws {
        let xcassetsDir = sourcesDir.appendingPathComponent("Assets.xcassets", isDirectory: true)
        let hasAssets = fileTree.keys.contains { $0.hasPrefix("Assets.xcassets") }

        if !FileManager.default.fileExists(atPath: xcassetsDir.path) {
            try FileManager.default.createDirectory(at: xcassetsDir, withIntermediateDirectories: true)
        }

        let contentsURL = xcassetsDir.appendingPathComponent("Contents.json")
        if !FileManager.default.fileExists(atPath: contentsURL.path) || !hasAssets {
            CoordinatedFileWriter.write(
                """
                { "info": { "version": 1, "author": "xcode" } }
                """,
                to: contentsURL
            )
        }

        if let customIcon {
            try writeAppIconSet(from: customIcon, to: xcassetsDir)
        } else if !hasAssets {
            let appIconDir = xcassetsDir.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
            if !FileManager.default.fileExists(atPath: appIconDir.path) {
                try FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)
                CoordinatedFileWriter.write(
                    """
                    { "images": [{ "idiom": "universal", "platform": "ios", "size": "1024x1024" }],
                      "info": { "version": 1, "author": "xcode" } }
                    """,
                    to: appIconDir.appendingPathComponent("Contents.json")
                )
            }
        }
    }

    private func writeAppIconSet(from image: NSImage, to xcassetsDir: URL) throws {
        let appIconDir = xcassetsDir.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        if FileManager.default.fileExists(atPath: appIconDir.path) {
            try FileManager.default.removeItem(at: appIconDir)
        }
        try FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)

        let specs = Self.appIconSpecs
        for spec in specs {
            let outputURL = appIconDir.appendingPathComponent(spec.filename)
            guard let png = Self.pngData(for: image, pixelSize: spec.pixelSize) else { continue }
            CoordinatedFileWriter.writeData(png, to: outputURL)
        }

        let images = specs.map { spec in
            """
                {
                  "filename" : "\(spec.filename)",
                  "idiom" : "\(spec.idiom)",
                  "scale" : "\(spec.scale)x",
                  "size" : "\(spec.pointSize)"\(spec.platform.map { ",\n                  \"platform\" : \"\($0)\"" } ?? "")
                }
            """
        }.joined(separator: ",\n")

        let contents = """
        {
          "images" : [
        \(images)
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        CoordinatedFileWriter.write(contents, to: appIconDir.appendingPathComponent("Contents.json"))
    }

    private func needsProjectRegeneration(
        iosDir: URL,
        targetName: String,
        bundleId: String,
        displayName: String,
        fileTree: [String: String],
        environmentVariables: [ProjectEnvironmentVariable]
    ) -> Bool {
        let projectYmlURL = iosDir.appendingPathComponent("project.yml")
        let xcodeprojDir = iosDir.appendingPathComponent("\(targetName).xcodeproj", isDirectory: true)

        guard FileManager.default.fileExists(atPath: projectYmlURL.path),
              FileManager.default.fileExists(atPath: xcodeprojDir.path),
              let existingProjectYml = try? String(contentsOf: projectYmlURL, encoding: .utf8)
        else {
            return true
        }

        let expectedProjectYml = Self.projectYmlContents(
            targetName: targetName,
            bundleId: bundleId,
            displayName: displayName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )
        guard existingProjectYml == expectedProjectYml else {
            return true
        }

        let sourcesDir = iosDir.appendingPathComponent(targetName, isDirectory: true)
        guard let currentSourceManifest = sourceManifestEntries(in: sourcesDir),
              let storedSourceManifest = storedSourceManifestEntries(in: iosDir)
        else {
            return true
        }

        return currentSourceManifest != storedSourceManifest
    }

    private nonisolated static func projectYmlContents(
        targetName: String,
        bundleId: String,
        displayName: String,
        fileTree: [String: String],
        environmentVariables: [ProjectEnvironmentVariable]
    ) -> String {
        let escapedDisplayName = Self.yamlSingleQuoted(displayName)
        let normalizedEnvironment = ProjectEnvironmentSecurity.clientRuntimeEnvironment(from: environmentVariables)
        let requiredPackages = Self.requiredPackageDependencies(for: fileTree)
        let environmentSection: String
        if normalizedEnvironment.isEmpty {
            environmentSection = ""
        } else {
            let environmentLines = normalizedEnvironment.keys.sorted().map { key in
                "        \(Self.yamlSingleQuoted(key)): \(Self.yamlSingleQuoted(normalizedEnvironment[key] ?? ""))"
            }.joined(separator: "\n")
            environmentSection = """
                scheme:
                  environmentVariables:
            \(environmentLines)
            """
        }

        let packageSection: String
        if requiredPackages.isEmpty {
            packageSection = ""
        } else {
            let packageLines = requiredPackages.map { dependency in
                """
                  \(dependency.yamlKey):
                    url: \(Self.yamlSingleQuoted(dependency.repositoryURL))
                    from: \(Self.yamlSingleQuoted(dependency.minimumVersion))
                """
            }.joined(separator: "\n")
            packageSection = "packages:\n\(packageLines)\n"
        }

        let targetDependencySection: String
        if requiredPackages.isEmpty {
            targetDependencySection = ""
        } else {
            let dependencyLines = requiredPackages.map { dependency in
                """
                          - package: \(dependency.yamlKey)
                            product: \(dependency.productName)
                """
            }.joined(separator: "\n")
            targetDependencySection = """
                dependencies:
            \(dependencyLines)
            """
        }

        return """
        name: \(targetName)
        \(packageSection)targets:
          \(targetName):
            type: application
            platform: iOS
            deploymentTarget: "26.0"
            sources:
              - path: \(targetName)
        \(targetDependencySection)
            settings:
              base:
                PRODUCT_NAME: \(targetName)
                PRODUCT_BUNDLE_IDENTIFIER: \(bundleId)
                GENERATE_INFOPLIST_FILE: YES
                INFOPLIST_KEY_CFBundleDisplayName: \(escapedDisplayName)
                INFOPLIST_KEY_CFBundleName: \(escapedDisplayName)
                INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
                INFOPLIST_KEY_UILaunchScreen_Generation: YES
                INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES
                MARKETING_VERSION: "1.0"
                CURRENT_PROJECT_VERSION: 1
                CODE_SIGN_STYLE: Automatic
                SWIFT_EMIT_LOC_STRINGS: NO
                ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
                ALWAYS_SEARCH_USER_PATHS: NO
                TARGETED_DEVICE_FAMILY: "1,2"
                SWIFT_VERSION: "5.0"
              configs:
                Debug:
                  ONLY_ACTIVE_ARCH: YES
        \(environmentSection)
        """
    }

    nonisolated static func testingProjectYmlContents(
        targetName: String,
        bundleId: String,
        displayName: String,
        fileTree: [String: String],
        environmentVariables: [ProjectEnvironmentVariable] = []
    ) -> String {
        projectYmlContents(
            targetName: targetName,
            bundleId: bundleId,
            displayName: displayName,
            fileTree: fileTree,
            environmentVariables: environmentVariables
        )
    }

    nonisolated static func testingCompileCheckPackageContents(
        fileTree: [String: String]
    ) -> String {
        compileCheckPackageContents(
            requiredPackages: requiredPackageDependencies(for: fileTree)
        )
    }

    private static func pngData(for image: NSImage, pixelSize: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: pixelSize, height: pixelSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()

        let imageSize = image.size
        let scale = max(CGFloat(pixelSize) / max(imageSize.width, 1), CGFloat(pixelSize) / max(imageSize.height, 1))
        let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = NSRect(
            x: (CGFloat(pixelSize) - drawSize.width) / 2,
            y: (CGFloat(pixelSize) - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    private static func yamlSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private nonisolated static func requiredPackageDependencies(
        for fileTree: [String: String]
    ) -> [SwiftPackageDependency] {
        var dependencies: [SwiftPackageDependency] = []
        if fileTree.values.contains(where: { importsModule("Supabase", in: $0) }) {
            dependencies.append(.supabase)
        }
        if fileTree.values.contains(where: { importsModule("SuperwallKit", in: $0) }) {
            dependencies.append(.superwall)
        }
        return dependencies
    }

    private nonisolated static func importsModule(_ moduleName: String, in content: String) -> Bool {
        let pattern = #"(?m)^\s*(?:@_exported\s+)?import\s+\#(moduleName)\b"#
        return content.range(of: pattern, options: .regularExpression) != nil
    }

    private nonisolated static func compileCheckPackageContents(
        requiredPackages: [SwiftPackageDependency]
    ) -> String {
        let dependencySection: String
        if requiredPackages.isEmpty {
            dependencySection = ""
        } else {
            let dependencyLines = requiredPackages.map { dependency in
                "        .package(url: \"\(dependency.repositoryURL)\", from: \"\(dependency.minimumVersion)\")"
            }.joined(separator: ",\n")
            dependencySection = """
                dependencies: [
            \(dependencyLines)
                ],
            """
        }

        let targetDependencySection: String
        if requiredPackages.isEmpty {
            targetDependencySection = ""
        } else {
            let dependencyLines = requiredPackages.map { dependency in
                "                .product(name: \"\(dependency.productName)\", package: \"\(dependency.packageIdentity)\")"
            }.joined(separator: ",\n")
            targetDependencySection = """
                        dependencies: [
            \(dependencyLines)
                        ],
            """
        }

        return """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(
            name: "CompileCheck",
            platforms: [.iOS(.v17)],
        \(dependencySection)
            targets: [
                .executableTarget(
                    name: "CompileCheck",
        \(targetDependencySection)            path: "Sources"
                )
            ]
        )
        """
    }

    private static let tenXSupportFilename = "TenXPreviewSupport.swift"
    private static let legacyTenXSupportFilenames = ["TenXInject.swift", "TenXEnvironment.swift", "TenXViewTracker.swift"]
    private static let allTenXSupportFilenames = [tenXSupportFilename] + legacyTenXSupportFilenames

    private static let appIconSpecs: [AppIconSpec] = [
        .init(pointSize: "20x20", scale: 2, idiom: "iphone"),
        .init(pointSize: "20x20", scale: 3, idiom: "iphone"),
        .init(pointSize: "29x29", scale: 2, idiom: "iphone"),
        .init(pointSize: "29x29", scale: 3, idiom: "iphone"),
        .init(pointSize: "40x40", scale: 2, idiom: "iphone"),
        .init(pointSize: "40x40", scale: 3, idiom: "iphone"),
        .init(pointSize: "60x60", scale: 2, idiom: "iphone"),
        .init(pointSize: "60x60", scale: 3, idiom: "iphone"),
        .init(pointSize: "20x20", scale: 1, idiom: "ipad"),
        .init(pointSize: "20x20", scale: 2, idiom: "ipad"),
        .init(pointSize: "29x29", scale: 1, idiom: "ipad"),
        .init(pointSize: "29x29", scale: 2, idiom: "ipad"),
        .init(pointSize: "40x40", scale: 1, idiom: "ipad"),
        .init(pointSize: "40x40", scale: 2, idiom: "ipad"),
        .init(pointSize: "76x76", scale: 1, idiom: "ipad"),
        .init(pointSize: "76x76", scale: 2, idiom: "ipad"),
        .init(pointSize: "83.5x83.5", scale: 2, idiom: "ipad"),
        .init(pointSize: "1024x1024", scale: 1, idiom: "ios-marketing")
    ]
}

private struct AppIconSpec {
    let pointSize: String
    let scale: Int
    let idiom: String
    let platform: String?
    let filename: String
    let pixelSize: Int

    nonisolated init(pointSize: String, scale: Int, idiom: String) {
        self.pointSize = pointSize
        self.scale = scale
        self.idiom = idiom
        self.platform = idiom == "ios-marketing" ? "ios" : nil
        self.filename = "icon-\(idiom)-\(pointSize.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "x", with: "-"))@\(scale)x.png"
        let base = Double(pointSize.components(separatedBy: "x").first ?? "0") ?? 0
        self.pixelSize = Int(round(base * Double(scale)))
    }
}

private struct SwiftPackageDependency {
    let yamlKey: String
    let repositoryURL: String
    let minimumVersion: String
    let packageIdentity: String
    let productName: String

    nonisolated init(
        yamlKey: String,
        repositoryURL: String,
        minimumVersion: String,
        packageIdentity: String,
        productName: String
    ) {
        self.yamlKey = yamlKey
        self.repositoryURL = repositoryURL
        self.minimumVersion = minimumVersion
        self.packageIdentity = packageIdentity
        self.productName = productName
    }

    nonisolated static let superwall = SwiftPackageDependency(
        yamlKey: "Superwall",
        repositoryURL: "https://github.com/superwall/Superwall-iOS",
        minimumVersion: "4.0.0",
        packageIdentity: "Superwall-iOS",
        productName: "SuperwallKit"
    )

    nonisolated static let supabase = SwiftPackageDependency(
        yamlKey: "Supabase",
        repositoryURL: "https://github.com/supabase/supabase-swift",
        minimumVersion: "2.0.0",
        packageIdentity: "supabase-swift",
        productName: "Supabase"
    )
}

enum XcodeGenError: LocalizedError {
    case binaryNotFound
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Bundled xcodegen binary not found in app bundle"
        case .generationFailed(let output):
            return "XcodeGen failed: \(output)"
        }
    }
}
