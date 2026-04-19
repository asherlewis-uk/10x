import Foundation

enum ExistingProjectImportError: LocalizedError {
    case invalidSelection(String)
    case unsupportedProject(String)
    case copyFailed(String)
    case emptyFileTree

    var errorDescription: String? {
        switch self {
        case .invalidSelection(let message):
            return message
        case .unsupportedProject(let message):
            return message
        case .copyFailed(let message):
            return message
        case .emptyFileTree:
            return "The selected project did not contain any importable text files."
        }
    }
}

struct ResolvedProjectSelection: Sendable {
    let rootURL: URL
    let containerURL: URL
    let containerKind: XcodeContainerKind
    let displayName: String
}

struct ExistingProjectImportResult: Sendable {
    let fileTree: [String: String]
    let metadata: ImportedProjectMetadata
}

actor ExistingProjectImporter {
    private static let maxImportedTextFileBytes = 512 * 1024
    private let developerDir: String = {
        let xcodeApp = "/Applications/Xcode.app/Contents/Developer"
        if FileManager.default.fileExists(atPath: xcodeApp) {
            return xcodeApp
        }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? xcodeApp)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    func resolveSelection(at selectionURL: URL) throws -> ResolvedProjectSelection {
        let fileManager = FileManager.default
        let normalized = selectionURL.standardizedFileURL

        guard fileManager.fileExists(atPath: normalized.path) else {
            throw ExistingProjectImportError.invalidSelection("The selected project could not be found.")
        }

        if let containerKind = XcodeContainerKind(pathExtension: normalized.pathExtension) {
            let displayName = normalized.deletingPathExtension().lastPathComponent
            return ResolvedProjectSelection(
                rootURL: normalized.deletingLastPathComponent(),
                containerURL: normalized,
                containerKind: containerKind,
                displayName: displayName
            )
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExistingProjectImportError.invalidSelection(
                "Choose a SwiftUI project folder, `.xcodeproj`, or `.xcworkspace`."
            )
        }

        guard let containerURL = discoveredContainers(in: normalized).first,
              let containerKind = XcodeContainerKind(pathExtension: containerURL.pathExtension) else {
            throw ExistingProjectImportError.invalidSelection(
                "No `.xcodeproj` or `.xcworkspace` was found in that folder."
            )
        }

        return ResolvedProjectSelection(
            rootURL: normalized,
            containerURL: containerURL,
            containerKind: containerKind,
            displayName: containerURL.deletingPathExtension().lastPathComponent
        )
    }

    func validateSwiftUISources(at rootURL: URL) throws {
        guard containsSwiftUISource(at: rootURL) else {
            throw ExistingProjectImportError.unsupportedProject(
                "The selected project does not look like a SwiftUI app yet."
            )
        }
    }

    func importProject(from selection: ResolvedProjectSelection, into projectRoot: URL) async throws -> ExistingProjectImportResult {
        try validateSwiftUISources(at: selection.rootURL)

        let importedParent = projectRoot.appendingPathComponent("imported", isDirectory: true)
        try FileManager.default.createDirectory(at: importedParent, withIntermediateDirectories: true)

        let importedRoot = importedParent.appendingPathComponent(selection.rootURL.lastPathComponent, isDirectory: true)
        if FileManager.default.fileExists(atPath: importedRoot.path) {
            try FileManager.default.removeItem(at: importedRoot)
        }
        try FileManager.default.createDirectory(at: importedRoot, withIntermediateDirectories: true)

        do {
            try copyProjectTree(from: selection.rootURL, to: importedRoot)
        } catch {
            throw ExistingProjectImportError.copyFailed(
                "Failed to copy the selected project into the 10x workspace: \(error.localizedDescription)"
            )
        }

        let copiedContainerRelativePath = try relativePath(
            of: selection.containerURL,
            relativeTo: selection.rootURL
        )
        let copiedContainerURL = importedRoot.appendingPathComponent(copiedContainerRelativePath)

        let scheme = await preferredScheme(
            for: copiedContainerURL,
            kind: selection.containerKind,
            fallback: selection.displayName
        )
        let bundleIdentifier = await preferredBundleIdentifier(
            for: copiedContainerURL,
            kind: selection.containerKind,
            scheme: scheme
        )

        let fileTree = try loadTextFileTree(from: importedRoot)
        guard !fileTree.isEmpty else {
            throw ExistingProjectImportError.emptyFileTree
        }
        guard Self.containsSwiftUISource(in: fileTree) else {
            throw ExistingProjectImportError.unsupportedProject(
                "The imported files did not include any SwiftUI source yet."
            )
        }

        return ExistingProjectImportResult(
            fileTree: fileTree,
            metadata: ImportedProjectMetadata(
                workspaceRootRelativePath: try relativePath(of: importedRoot, relativeTo: projectRoot),
                xcodeContainerRelativePath: try relativePath(of: copiedContainerURL, relativeTo: projectRoot),
                xcodeContainerKind: selection.containerKind,
                scheme: scheme,
                bundleIdentifier: bundleIdentifier
            )
        )
    }

    func loadTextFileTree(from rootURL: URL) throws -> [String: String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var fileTree: [String: String] = [:]

        for case let fileURL as URL in enumerator {
            let relativePath = try relativePath(of: fileURL, relativeTo: rootURL)
            let pathComponents = relativePath.split(separator: "/").map(String.init)
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])

            if shouldSkip(relativePathComponents: pathComponents, isDirectory: values.isDirectory == true) {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isDirectory != true else { continue }
            guard let size = values.fileSize, size <= Self.maxImportedTextFileBytes else { continue }

            let data = try Data(contentsOf: fileURL)
            guard let text = Self.decodeText(data) else { continue }

            fileTree[relativePath] = text
        }

        return fileTree
    }

    func containsSwiftUISource(at rootURL: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            let relativeComponents = fileURL.path
                .replacingOccurrences(of: rootURL.path + "/", with: "")
                .split(separator: "/")
                .map(String.init)
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])

            if shouldSkip(relativePathComponents: relativeComponents, isDirectory: values?.isDirectory == true) {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard fileURL.pathExtension == "swift",
                  let data = try? Data(contentsOf: fileURL),
                  let content = Self.decodeText(data)
            else {
                continue
            }

            if content.contains("import SwiftUI") {
                return true
            }
        }

        return false
    }

    private func discoveredContainers(in rootURL: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var containers: [URL] = []
        let baseDepth = rootURL.pathComponents.count

        for case let fileURL as URL in enumerator {
            let depth = fileURL.pathComponents.count - baseDepth
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])

            if depth > 2 {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let components = fileURL.path
                .replacingOccurrences(of: rootURL.path + "/", with: "")
                .split(separator: "/")
                .map(String.init)
            if shouldSkip(relativePathComponents: components, isDirectory: values?.isDirectory == true) {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard XcodeContainerKind(pathExtension: fileURL.pathExtension) != nil else {
                continue
            }

            containers.append(fileURL)
            if values?.isDirectory == true {
                enumerator.skipDescendants()
            }
        }

        return containers.sorted { lhs, rhs in
            let lhsKind = XcodeContainerKind(pathExtension: lhs.pathExtension)
            let rhsKind = XcodeContainerKind(pathExtension: rhs.pathExtension)
            let lhsRank = lhsKind == .workspace ? 0 : 1
            let rhsRank = rhsKind == .workspace ? 0 : 1
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let lhsDepth = lhs.pathComponents.count
            let rhsDepth = rhs.pathComponents.count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }

            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    private func copyProjectTree(from sourceRoot: URL, to destinationRoot: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let sourceURL as URL in enumerator {
            let relativePath = try relativePath(of: sourceURL, relativeTo: sourceRoot)
            let components = relativePath.split(separator: "/").map(String.init)
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])

            if shouldSkip(relativePathComponents: components, isDirectory: values.isDirectory == true) {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let destinationURL = destinationRoot.appendingPathComponent(relativePath)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }
    }

    private func shouldSkip(relativePathComponents components: [String], isDirectory: Bool) -> Bool {
        let skippedNames: Set<String> = [
            "DerivedData",
            "build",
            ".build",
            "Pods",
            "Carthage",
            "xcuserdata",
            ".swiftpm",
        ]

        if components.contains(where: { skippedNames.contains($0) }) {
            return true
        }

        if components.last == ".DS_Store" {
            return true
        }

        if isDirectory, components.last == "Build" && components.dropLast().last == "Carthage" {
            return true
        }

        return false
    }

    private func relativePath(of url: URL, relativeTo baseURL: URL) throws -> String {
        let basePath = baseURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath == basePath || urlPath.hasPrefix(basePath + "/") else {
            throw ExistingProjectImportError.invalidSelection("The selected project layout could not be resolved.")
        }

        if urlPath == basePath {
            return ""
        }

        return String(urlPath.dropFirst(basePath.count + 1))
    }

    private func preferredScheme(
        for containerURL: URL,
        kind: XcodeContainerKind,
        fallback: String
    ) async -> String {
        guard let output = await xcodebuildOutput(
            arguments: containerArguments(for: containerURL, kind: kind) + ["-list", "-json"],
            currentDirectoryURL: containerURL.deletingLastPathComponent()
        ),
        let data = jsonPayloadData(from: output),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return fallback
        }

        let rawSchemes =
            (json["project"] as? [String: Any])?["schemes"] as? [String]
            ?? (json["workspace"] as? [String: Any])?["schemes"] as? [String]
            ?? []

        let preferred = rawSchemes.first {
            $0.compare(fallback, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if let preferred {
            return preferred
        }

        if let appScheme = rawSchemes.first(where: { !Self.looksLikeTestScheme($0) }) {
            return appScheme
        }

        return rawSchemes.first ?? fallback
    }

    private func preferredBundleIdentifier(
        for containerURL: URL,
        kind: XcodeContainerKind,
        scheme: String
    ) async -> String? {
        guard let output = await xcodebuildOutput(
            arguments: containerArguments(for: containerURL, kind: kind)
                + ["-showBuildSettings", "-json", "-scheme", scheme],
            currentDirectoryURL: containerURL.deletingLastPathComponent()
        ),
        let data = jsonPayloadData(from: output),
        let rawEntries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }

        let applicationEntry = rawEntries.first { entry in
            guard let buildSettings = entry["buildSettings"] as? [String: Any] else {
                return false
            }
            let wrapperExtension = (buildSettings["WRAPPER_EXTENSION"] as? String)?.lowercased()
            let productType = (buildSettings["PRODUCT_TYPE"] as? String)?.lowercased()
            return wrapperExtension == "app" || (productType?.contains("application") == true)
        }

        let selectedEntry = applicationEntry ?? rawEntries.first
        guard let buildSettings = selectedEntry?["buildSettings"] as? [String: Any] else {
            return nil
        }

        let bundleIdentifier = (buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil
    }

    private func containerArguments(for containerURL: URL, kind: XcodeContainerKind) -> [String] {
        switch kind {
        case .project:
            return ["-project", containerURL.path]
        case .workspace:
            return ["-workspace", containerURL.path]
        }
    }

    private func xcodebuildOutput(arguments: [String], currentDirectoryURL: URL) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["xcodebuild"] + arguments
                process.currentDirectoryURL = currentDirectoryURL
                process.environment = ProcessInfo.processInfo.environment.merging(
                    ["DEVELOPER_DIR": self.developerDir]
                ) { _, new in new }

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                var outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                outputData.append(stderr.fileHandleForReading.readDataToEndOfFile())
                let output = String(data: outputData, encoding: .utf8)
                continuation.resume(returning: output)
            }
        }
    }

    private static func looksLikeTestScheme(_ scheme: String) -> Bool {
        let lower = scheme.lowercased()
        return lower.hasSuffix("tests")
            || lower.hasSuffix("uitests")
            || lower.contains("snapshot")
    }

    private func jsonPayloadData(from output: String) -> Data? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directData = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: directData)) != nil {
            return directData
        }

        for delimiters in [("{", "}"), ("[", "]")] {
            guard let start = trimmed.firstIndex(of: Character(delimiters.0)),
                  let end = trimmed.lastIndex(of: Character(delimiters.1)),
                  start <= end
            else {
                continue
            }

            let slice = String(trimmed[start...end])
            guard let data = slice.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                continue
            }
            return data
        }

        return nil
    }

    private static func decodeText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        let looksLikeUTF16 =
            data.starts(with: [0xFF, 0xFE])
            || data.starts(with: [0xFE, 0xFF])
            || data.contains(0x00)
        guard looksLikeUTF16 else {
            return nil
        }

        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        if let utf16LittleEndian = String(data: data, encoding: .utf16LittleEndian) {
            return utf16LittleEndian
        }
        return nil
    }

    private static func containsSwiftUISource(in fileTree: [String: String]) -> Bool {
        fileTree.contains { path, content in
            path.hasSuffix(".swift") && content.contains("import SwiftUI")
        }
    }
}
