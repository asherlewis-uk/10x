import CryptoKit
import Foundation

/// Imports local legacy 10x projects into 11x without touching the original folder.
actor LegacyTenXProjectImporter {
    static let defaultLegacyRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/TenXApp", isDirectory: true)

    private let database: CockpitDatabase
    private let projectRepository: ProjectRepository
    private let versionRepository: VersionRepository
    private let legacyImportRepository: LegacyImportRepository
    private let profileRepository: ProfileRepository
    private let localStore: LocalProjectStore
    private let assetStorage: LocalAssetStorage
    private let previewService: XcodePreviewService

    private let fileManager = FileManager.default

    init(
        database: CockpitDatabase = CockpitDatabase.shared,
        projectRepository: ProjectRepository? = nil,
        versionRepository: VersionRepository? = nil,
        legacyImportRepository: LegacyImportRepository? = nil,
        profileRepository: ProfileRepository? = nil,
        localStore: LocalProjectStore? = nil,
        assetStorage: LocalAssetStorage? = nil,
        previewService: XcodePreviewService? = nil
    ) {
        self.database = database
        self.projectRepository = projectRepository ?? ProjectRepository(database: database)
        self.versionRepository = versionRepository ?? VersionRepository(database: database)
        self.legacyImportRepository = legacyImportRepository ?? LegacyImportRepository(database: database)
        self.profileRepository = profileRepository ?? ProfileRepository(database: database)
        self.localStore = localStore ?? LocalProjectStore()
        self.assetStorage = assetStorage ?? LocalAssetStorage()
        self.previewService = previewService ?? XcodePreviewService()
    }

    // MARK: - Discovery

    func scanLegacyProjects(at rootURL: URL = defaultLegacyRoot) async -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let candidates = urls.filter { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            return isLegacyProjectCandidate(at: url)
        }

        return candidates.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated func isLegacyProjectCandidate(at url: URL) -> Bool {
        let projectJSON = url.appendingPathComponent(".tenx/project.json")
        let projectYML = url.appendingPathComponent("ios/project.yml")
        return FileManager.default.fileExists(atPath: projectJSON.path)
            || FileManager.default.fileExists(atPath: projectYML.path)
    }

    // MARK: - Import

    func importProject(
        from sourceURL: URL,
        preserveGitHistory: Bool = false
    ) async throws -> LegacyTenXImportReport {
        let source = sourceURL.standardizedFileURL

        guard fileManager.fileExists(atPath: source.path) else {
            throw LegacyTenXImportError.notLegacyProject("The selected folder could not be found.")
        }
        guard isLegacyProjectCandidate(at: source) else {
            throw LegacyTenXImportError.notLegacyProject(
                "The selected folder does not look like a legacy 10x project."
            )
        }

        var report = LegacyTenXImportReport()

        let projectJSON = try? loadJSON(LegacyProjectJSON.self, from: source.appendingPathComponent(".tenx/project.json"))
        let manifestJSON = try? loadJSON(LegacyManifestJSON.self, from: source.appendingPathComponent(".tenx/manifest.json"))
        let sourceManifest = try? loadJSON(LegacySourceManifest.self, from: source.appendingPathComponent("ios/.tenx-source-manifest.json"))

        let legacyProjectId = projectJSON?.projectId
        let manifestId = manifestJSON.flatMap { $0.projectId ?? $0.bundleIdentifier }
        let fingerprint = try contentFingerprint(at: source)

        if let existing = try await legacyImportRepository.findCompletedImport(
            sourcePath: source.path,
            legacyProjectId: legacyProjectId,
            contentFingerprint: fingerprint
        ) {
            let existingProject = try? await projectRepository.getProject(id: existing.projectId)
            report.alreadyImported = true
            report.previousProjectId = existing.projectId
            report.project = existingProject
            report.skipped.append("Already imported from \(source.path)")
            return report
        }

        let projectName = Self.sanitizedProjectName(
            from: projectJSON?.name ?? manifestJSON?.name ?? sourceManifest?.targetName,
            fallback: source.lastPathComponent
        )

        let targetName = sourceManifest?.targetName
            ?? projectJSON?.targetName
            ?? manifestJSON?.scheme
            ?? XcodePreviewService.targetName(from: projectName)

        let xcodeprojName = Self.discoveredXcodeprojName(in: source) ?? "\(targetName).xcodeproj"
        let containerName = xcodeprojName

        guard fileManager.fileExists(atPath: source.appendingPathComponent("ios").path)
            || fileManager.fileExists(atPath: source.appendingPathComponent(".tenx/file_tree.json").path)
            || fileManager.fileExists(atPath: source.appendingPathComponent(".tenx/messages.json").path)
            || fileManager.fileExists(atPath: source.appendingPathComponent("conversation.md").path)
        else {
            throw LegacyTenXImportError.nothingImportable(
                "This legacy project has no importable source files, file tree, messages, or conversation."
            )
        }

        let profile = try await profileRepository.loadOrCreateProfile()
        var project = try await projectRepository.createProject(
            userId: profile.id,
            name: projectName,
            platform: "swiftui"
        )

        let workspaceRootRelativePath = "ios/\(targetName)"
        let xcodeContainerRelativePath = "ios/\(containerName)"
        let bundleIdentifier = projectJSON?.bundleId
            ?? manifestJSON?.bundleIdentifier
            ?? XcodePreviewService.bundleId(from: projectName)

        var settings = ImportedProjectMetadata(
            workspaceRootRelativePath: workspaceRootRelativePath,
            xcodeContainerRelativePath: xcodeContainerRelativePath,
            xcodeContainerKind: .project,
            scheme: sourceManifest?.targetName ?? manifestJSON?.scheme ?? targetName,
            bundleIdentifier: bundleIdentifier
        ).settingsDictionary

        settings["legacy_import_source_path"] = .string(source.path)
        if let legacyProjectId {
            settings["legacy_project_id"] = .string(legacyProjectId)
        }
        if let manifestId {
            settings["legacy_manifest_id"] = .string(manifestId)
        }

        project = try await projectRepository.updateProject(
            id: project.id,
            settings: settings
        )

        let importRecord = try await legacyImportRepository.startImport(
            sourcePath: source.path,
            legacyProjectId: legacyProjectId,
            manifestId: manifestId,
            contentFingerprint: fingerprint,
            projectId: project.id
        )

        let projectRoot = await previewService.projectDir(for: project.name, projectId: project.id)

        do {
            // Copy generated iOS source files.
            let sourceIOS = source.appendingPathComponent("ios", isDirectory: true)
            let destIOS = projectRoot.appendingPathComponent("ios", isDirectory: true)
            if fileManager.fileExists(atPath: sourceIOS.path) {
                let copyResult = try copyDirectoryTree(
                    from: sourceIOS,
                    to: destIOS,
                    skipGit: !preserveGitHistory
                )
                report.copiedSourceFiles = copyResult.copied.sorted()
                for link in copyResult.skippedSymlinks {
                    report.skipped.append("Symlink skipped: \(link)")
                }
            } else {
                report.unavailable.append("ios/ directory")
            }

            // Import file tree into LocalProjectStore and create a version.
            let fileTreeURL = source.appendingPathComponent(".tenx/file_tree.json")
            var fileTree: [String: String] = [:]
            if let data = try? Data(contentsOf: fileTreeURL),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                fileTree = decoded
                await localStore.saveFileTree(fileTree, projectName: project.name, projectId: project.id)
            } else {
                report.unavailable.append(".tenx/file_tree.json")
            }

            // Import messages / chat state.
            let (messages, chat) = try importChatState(
                from: source,
                project: project,
                report: &report
            )
            let chatId = chat.id

            if !messages.isEmpty {
                let chatState = BuilderChatState(
                    messages: messages,
                    plan: nil,
                    tasks: nil,
                    warnings: [],
                    snapshots: [],
                    cachedReadFiles: [:],
                    cachedReadFileOrder: [],
                    contextState: .empty,
                    timeline: messages.map { .message(messageId: $0.id) }
                )
                await localStore.saveChatState(
                    chatState,
                    chat: chat,
                    projectName: project.name,
                    projectId: project.id,
                    projectDir: projectRoot
                )
                await localStore.saveChatIndex(
                    BuilderChatIndex(chats: [chat], activeChatId: chat.id),
                    projectName: project.name,
                    projectId: project.id
                )
                await localStore.saveMessages(
                    messages,
                    projectName: project.name,
                    projectId: project.id,
                    projectDir: projectRoot
                )
                report.importedMessageCount = messages.count
            }

            // Import plan / tasks.
            let planURL = source.appendingPathComponent(".tenx/plan.md")
            let tasksURL = source.appendingPathComponent(".tenx/tasks.md")
            let plan = try? String(contentsOf: planURL, encoding: .utf8)
            let tasks = try? String(contentsOf: tasksURL, encoding: .utf8)
            let status = BuilderProjectStatusState(plan: plan, tasks: tasks)
            await localStore.saveProjectStatus(status, projectName: project.name, projectId: project.id, projectDir: projectRoot)
            report.importedPlan = !(plan?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            report.importedTasks = !(tasks?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            // Create a version if we have a file tree.
            if !fileTree.isEmpty {
                let prompt = messages.first(where: { $0.role == "user" })?.content
                    ?? projectJSON?.name
                    ?? manifestJSON?.name
                    ?? "Imported legacy 10x project"
                _ = try await versionRepository.createVersion(
                    projectId: project.id,
                    conversationId: chatId,
                    fileTree: fileTree,
                    prompt: prompt
                )
            }

            // Copy legacy docs / marketing artifacts as inert assets.
            let docPaths: [(URL, [String])] = [
                (source.appendingPathComponent("README.md"), ["legacy-docs"]),
                (source.appendingPathComponent("PRODUCTION.md"), ["legacy-docs"]),
                (source.appendingPathComponent("conversation.md"), ["legacy-docs"]),
                (source.appendingPathComponent(".tenx/project.json"), ["legacy-docs", "tenx"]),
                (source.appendingPathComponent(".tenx/manifest.json"), ["legacy-docs", "tenx"]),
                (source.appendingPathComponent("ios/.tenx-source-manifest.json"), ["legacy-docs", "tenx"]),
                (source.appendingPathComponent("ios/project.yml"), ["legacy-docs", "tenx"]),
                (source.appendingPathComponent(".tenx/plan.md"), ["legacy-docs", "tenx"]),
                (source.appendingPathComponent(".tenx/tasks.md"), ["legacy-docs", "tenx"]),
                (source.appendingPathComponent(".tenx/messages.json"), ["legacy-docs", "tenx"]),
                (source.appendingPathComponent(".tenx/chats.json"), ["legacy-docs", "tenx"]),
                (source.appendingPathComponent(".tenx/chats"), ["legacy-docs", "tenx", "chats"]),
                (source.appendingPathComponent("idea"), ["legacy-docs", "idea"]),
                (source.appendingPathComponent("release"), ["legacy-docs", "release"]),
                (source.appendingPathComponent("growth/app-store"), ["legacy-docs", "growth", "app-store"]),
            ]

            for (url, subdirectories) in docPaths {
                let copied = try await copyAsAssets(
                    from: url,
                    into: project.id,
                    subdirectories: subdirectories,
                    skipGit: !preserveGitHistory
                )
                report.copiedAssetFiles.append(contentsOf: copied)
                if url.lastPathComponent == "conversation.md", !copied.isEmpty {
                    report.conversationTranscriptAttached = true
                }
                if url.lastPathComponent == "messages.json", !copied.isEmpty {
                    report.rawMessagesPreserved = true
                }
                if url.lastPathComponent == "chats.json", !copied.isEmpty {
                    report.rawChatsPreserved = true
                }
                if url.lastPathComponent == "chats", !copied.isEmpty {
                    report.rawChatStatesPreserved = copied.count
                }
            }

            report.project = project
            report.skipped.append(".git/ directory (default)")

            try await legacyImportRepository.completeImport(id: importRecord.id)
            return report
        } catch {
            try? await legacyImportRepository.failImport(id: importRecord.id, errorMessage: error.localizedDescription)
            // Remove the partial project directory where safe. Keep project/DB row so
            // the failure is visible and retryable via the failed import record.
            try? fileManager.removeItem(at: projectRoot)
            throw error
        }
    }

    // MARK: - Chat import

    private func importChatState(
        from source: URL,
        project: BuilderProject,
        report: inout LegacyTenXImportReport
    ) throws -> ([BuilderMessage], BuilderChat) {
        let messagesURL = source.appendingPathComponent(".tenx/messages.json")
        let chatsURL = source.appendingPathComponent(".tenx/chats.json")
        let chatsDir = source.appendingPathComponent(".tenx/chats", isDirectory: true)

        var legacyMessages: [LegacyMessage] = []
        var messagesParseFailed = false
        if let data = try? Data(contentsOf: messagesURL) {
            if let decoded = try? JSONDecoder().decode([LegacyMessage].self, from: data), !decoded.isEmpty {
                legacyMessages = decoded
                report.rawMessagesPreserved = true
            } else {
                messagesParseFailed = true
                report.unavailable.append(".tenx/messages.json (malformed but will be preserved as raw asset)")
            }
        } else {
            report.unavailable.append(".tenx/messages.json")
        }

        var legacyChatIndex: LegacyChatIndex? = nil
        var chatsParseFailed = false
        if let data = try? Data(contentsOf: chatsURL) {
            if let decoded = try? JSONDecoder().decode(LegacyChatIndex.self, from: data) {
                legacyChatIndex = decoded
                report.rawChatsPreserved = true
            } else {
                chatsParseFailed = true
                report.unavailable.append(".tenx/chats.json (malformed but will be preserved as raw asset)")
            }
        } else {
            report.unavailable.append(".tenx/chats.json")
        }

        if fileManager.fileExists(atPath: chatsDir.path) {
            report.rawChatStatesPreserved = Self.countRegularFiles(at: chatsDir)
        }

        let chatId = legacyChatIndex?.activeChatId
            ?? legacyMessages.first(where: { !$0.conversation_id.isEmpty })?.conversation_id
            ?? UUID().uuidString
        let chatName = legacyChatIndex?.chats.first(where: { $0.id == chatId })?.name
            ?? legacyChatIndex?.chats.first?.name
            ?? "Imported Chat"

        let chat = BuilderChat(
            id: chatId,
            name: chatName,
            isAutoNamed: true
        )

        if messagesParseFailed {
            report.rawMessagesPreserved = true
            report.errors.append("Could not parse .tenx/messages.json as structured chat; preserved raw file instead.")
        }
        if chatsParseFailed {
            report.rawChatsPreserved = true
            report.errors.append("Could not parse .tenx/chats.json as structured chat index; preserved raw file instead.")
        }

        guard !legacyMessages.isEmpty else {
            return ([], chat)
        }

        let messages: [BuilderMessage] = legacyMessages.map { legacy in
            BuilderMessage(
                id: Self.validMessageID(legacy.id, fallbackSeed: "\(chatId)|\(legacy.id)"),
                conversationId: chatId,
                role: legacy.role,
                content: legacy.content,
                attachments: [],
                requiredSkillNames: [],
                action: nil,
                versionId: nil,
                createdAt: Self.isoTimestamp(from: legacy.created_at) ?? Self.isoTimestamp(),
                mode: legacy.mode.flatMap(ProjectMode.init(rawValue:))
            )
        }

        return (messages, chat)
    }

    private static func countRegularFiles(at url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return 0 }
        var count = 0
        while let item = enumerator.nextObject() as? URL {
            let isRegular = (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isRegular { count += 1 }
        }
        return count
    }

    private func makeImportedChat(named: String) -> BuilderChat {
        BuilderChat(id: UUID().uuidString, name: named, isAutoNamed: true)
    }

    // MARK: - File copy helpers

    /// Recursively copies `sourceDir` into `destDir`, preserving relative structure.
    /// Returns the list of relative paths copied.
    private func copyDirectoryTree(
        from sourceDir: URL,
        to destDir: URL,
        skipGit: Bool
    ) throws -> (copied: [String], skippedSymlinks: [String]) {
        let sourceRoot = sourceDir.standardizedFileURL
        let destRoot = destDir.standardizedFileURL

        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (copied: [], skippedSymlinks: [])
        }

        var copied: [String] = []
        var skippedSymlinks: [String] = []

        while let item = enumerator.nextObject() {
            guard let fileURL = item as? URL else { continue }
            let relativePath = Self.relativePath(of: fileURL, relativeTo: sourceRoot)
            let components = relativePath.split(separator: "/").map(String.init)

            if skipGit, components.contains(".git") {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if components.last == ".DS_Store" {
                continue
            }

            let values = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true {
                skippedSymlinks.append(relativePath)
                continue
            }

            guard let destURL = Self.safeDestinationURL(
                root: destRoot,
                relativePath: relativePath
            ) else {
                throw LegacyTenXImportError.invalidPath(
                    "Destination path escapes import root: \(relativePath)"
                )
            }

            let isDirectory = values?.isDirectory == true

            if isDirectory {
                try fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: fileURL, to: destURL)
                copied.append(relativePath)
            }
        }

        return (copied, skippedSymlinks)
    }

    private nonisolated static func safeDestinationURL(root: URL, relativePath: String) -> URL? {
        let normalized = (relativePath as NSString).standardizingPath
        guard !normalized.hasPrefix("/"),
              !normalized.hasPrefix("~"),
              !normalized.contains("/.."),
              !normalized.contains("/../") else {
            return nil
        }
        let destination = root.appendingPathComponent(normalized, isDirectory: false).standardizedFileURL
        let rootPath = root.path
        let destPath = destination.path
        guard destPath.hasPrefix(rootPath + "/") || destPath == rootPath else {
            return nil
        }
        return destination
    }

    /// Copies a single file or all files under a directory into assets storage.
    private func copyAsAssets(
        from sourceURL: URL,
        into projectId: String,
        subdirectories: [String],
        skipGit: Bool
    ) async throws -> [String] {
        var copied: [String] = []

        if !fileManager.fileExists(atPath: sourceURL.path) {
            return copied
        }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
        guard exists else { return copied }

        if isDirectory.boolValue {
            guard let enumerator = fileManager.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return copied }

            while let item = enumerator.nextObject() {
                guard let fileURL = item as? URL else { continue }
                let relativeWithin = Self.relativePath(of: fileURL, relativeTo: sourceURL)
                let components = relativeWithin.split(separator: "/").map(String.init)
                if skipGit, components.contains(".git") {
                    if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if components.last == ".DS_Store" { continue }

                let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }
                guard values?.isDirectory != true else { continue }
                let data = try Data(contentsOf: fileURL)
                let assetRelative = try await writeAsset(
                    projectId: projectId,
                    filename: fileURL.lastPathComponent,
                    subdirectories: subdirectories + components.dropLast(),
                    data: data
                )
                copied.append(assetRelative)
            }
        } else {
            let data = try Data(contentsOf: sourceURL)
            let assetRelative = try await writeAsset(
                projectId: projectId,
                filename: sourceURL.lastPathComponent,
                subdirectories: subdirectories,
                data: data
            )
            copied.append(assetRelative)
        }

        return copied
    }

    private func writeAsset(
        projectId: String,
        filename: String,
        subdirectories: [String],
        data: Data
    ) async throws -> String {
        let mimeType = Self.mimeType(for: filename)
        let asset = try await assetStorage.writeAsset(
            projectId: projectId,
            kind: .generated,
            filename: filename,
            mimeType: mimeType,
            data: data,
            subdirectories: subdirectories
        )
        return asset.relativePath
    }

    // MARK: - Fingerprint

    private func contentFingerprint(at source: URL) throws -> String {
        var hasher = SHA256()
        hasher.update(data: Data(source.standardizedFileURL.path.utf8))
        let files = [
            source.appendingPathComponent(".tenx/project.json"),
            source.appendingPathComponent(".tenx/manifest.json"),
            source.appendingPathComponent("ios/.tenx-source-manifest.json"),
            source.appendingPathComponent("ios/project.yml"),
            source.appendingPathComponent("conversation.md"),
            source.appendingPathComponent("README.md"),
        ]
        for file in files {
            if let data = try? Data(contentsOf: file) {
                hasher.update(data: data)
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - JSON helpers

    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Static helpers

    private static func discoveredXcodeprojName(in source: URL) -> String? {
        let iosDir = source.appendingPathComponent("ios", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: iosDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return urls.first { $0.pathExtension.lowercased() == "xcodeproj" }?.lastPathComponent
    }

    private static func sanitizedProjectName(from preferred: String?, fallback: String) -> String {
        let raw = preferred ?? fallback
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(120))
        return limited.isEmpty ? fallback : limited
    }

    private static func relativePath(of url: URL, relativeTo baseURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath.hasPrefix(basePath + "/") else { return url.lastPathComponent }
        return String(urlPath.dropFirst(basePath.count + 1))
    }

    private static func mimeType(for filename: String) -> String? {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "md": return "text/markdown"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "yml", "yaml": return "application/x-yaml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    private static func validMessageID(_ raw: String, fallbackSeed: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if UUID(uuidString: trimmed) != nil {
            return trimmed
        }
        let digest = SHA256.hash(data: Data(fallbackSeed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let prefix = String(hex.prefix(32))
        var uuidString = prefix
        // Insert UUID separators: 8-4-4-4-12
        if uuidString.count == 32 {
            uuidString.insert("-", at: uuidString.index(uuidString.startIndex, offsetBy: 8))
            uuidString.insert("-", at: uuidString.index(uuidString.startIndex, offsetBy: 13))
            uuidString.insert("-", at: uuidString.index(uuidString.startIndex, offsetBy: 18))
            uuidString.insert("-", at: uuidString.index(uuidString.startIndex, offsetBy: 23))
        }
        return uuidString
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func isoTimestamp(from legacy: String?) -> String? {
        guard let legacy else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: legacy) else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }
}

// MARK: - Legacy JSON models

private struct LegacyProjectJSON: Decodable {
    let projectId: String?
    let name: String?
    let slug: String?
    let bundleId: String?
    let targetName: String?
    let platform: String?
    let ownerId: String?
    let fileCount: Int?
    let lastUpdated: String?
}

private struct LegacyManifestJSON: Decodable {
    let projectId: String?
    let name: String?
    let projectType: String?
    let workspaceRoot: String?
    let xcodeProject: String?
    let xcodeGenSpec: String?
    let scheme: String?
    let bundleIdentifier: String?
    let createdWith: String?
}

private struct LegacySourceManifest: Decodable {
    let targetName: String?
    let files: [String]?
}

private struct LegacyMessage: Decodable {
    let id: String
    let role: String
    let content: String
    let conversation_id: String
    let mode: String?
    let created_at: String?
}

private struct LegacyChatIndex: Decodable {
    let activeChatId: String?
    let chats: [LegacyChat]
}

private struct LegacyChat: Decodable {
    let id: String
    let name: String?
}
