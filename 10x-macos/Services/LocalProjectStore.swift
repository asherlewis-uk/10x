import AppKit
import Foundation

/// A file-tree and project-status snapshot captured before each generation, used to restore state on revert.
struct ProjectSnapshot: Codable, Sendable {
    let messageCountBefore: Int
    let fileTree: [String: String]
    let plan: String?
    let tasks: String?
    let warnings: [BuilderProjectWarning]?
    let cachedReadFiles: [String: String]?
    let cachedReadFileOrder: [String]?
    let contextState: BuilderContextState?
    let includesPlanState: Bool
    let includesProjectStatusState: Bool

    init(
        messageCountBefore: Int,
        fileTree: [String: String],
        plan: String?,
        tasks: String?,
        warnings: [BuilderProjectWarning],
        cachedReadFiles: [String: String],
        cachedReadFileOrder: [String],
        contextState: BuilderContextState
    ) {
        self.messageCountBefore = messageCountBefore
        self.fileTree = fileTree
        self.plan = plan
        self.tasks = tasks
        self.warnings = warnings
        self.cachedReadFiles = cachedReadFiles
        self.cachedReadFileOrder = cachedReadFileOrder
        self.contextState = contextState
        self.includesPlanState = true
        self.includesProjectStatusState = true
    }

    private enum CodingKeys: String, CodingKey {
        case messageCountBefore
        case fileTree
        case plan
        case tasks
        case warnings
        case cachedReadFiles
        case cachedReadFileOrder
        case contextState
        case includesPlanState
        case includesProjectStatusState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageCountBefore = try container.decode(Int.self, forKey: .messageCountBefore)
        fileTree = try container.decode([String: String].self, forKey: .fileTree)

        if container.contains(.plan) {
            plan = try container.decodeIfPresent(String.self, forKey: .plan)
            includesPlanState = try container.decodeIfPresent(Bool.self, forKey: .includesPlanState) ?? true
        } else {
            // Older snapshots only captured the file tree, so keep the previous
            // behavior for those sessions instead of force-clearing the plan.
            plan = nil
            includesPlanState = false
        }
        tasks = try container.decodeIfPresent(String.self, forKey: .tasks)
        warnings = try container.decodeIfPresent([BuilderProjectWarning].self, forKey: .warnings)
        cachedReadFiles = try container.decodeIfPresent([String: String].self, forKey: .cachedReadFiles)
        cachedReadFileOrder = try container.decodeIfPresent([String].self, forKey: .cachedReadFileOrder)
        contextState = try container.decodeIfPresent(BuilderContextState.self, forKey: .contextState)
        includesProjectStatusState =
            try container.decodeIfPresent(Bool.self, forKey: .includesProjectStatusState)
            ?? (container.contains(.tasks) || container.contains(.warnings))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageCountBefore, forKey: .messageCountBefore)
        try container.encode(fileTree, forKey: .fileTree)
        try container.encode(plan, forKey: .plan)
        try container.encodeIfPresent(tasks, forKey: .tasks)
        try container.encodeIfPresent(warnings, forKey: .warnings)
        try container.encodeIfPresent(cachedReadFiles, forKey: .cachedReadFiles)
        try container.encodeIfPresent(cachedReadFileOrder, forKey: .cachedReadFileOrder)
        try container.encodeIfPresent(contextState, forKey: .contextState)
        try container.encode(includesPlanState, forKey: .includesPlanState)
        try container.encode(includesProjectStatusState, forKey: .includesProjectStatusState)
    }
}

/// Persists project conversation data locally for instant loading.
/// Stores data in the project's tenx/ directory alongside the generated code.
actor LocalProjectStore {
    private let assetStorage = LocalAssetStorage()

    nonisolated static var baseDirectory: URL {
        AppIdentity.appSupportDirectory
    }

    // MARK: - Directory helpers

    private func tenxDir(projectName: String, projectId: String) -> URL {
        Self.tenxDirectory(projectName: projectName, projectId: projectId)
    }

    private func chatsDir(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("chats", isDirectory: true)
    }

    private func chatDir(projectName: String, projectId: String, chatId: String) -> URL {
        chatsDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent(chatId, isDirectory: true)
    }

    private func chatIndexURL(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("chats.json")
    }

    private func projectStatusURL(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("project-status.json")
    }

    private func productionChecklistURL(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("publishing-checklist.json")
    }

    private func projectRootDir(projectName: String, projectId: String) -> URL {
        Self.projectRootDirectory(projectName: projectName, projectId: projectId)
    }

    nonisolated static func projectRootDirectory(projectName: String, projectId: String) -> URL {
        let safeName = XcodePreviewService.safeName(from: projectName)
        let dirName = "\(safeName)-\(projectId.prefix(8))"
        return baseDirectory.appendingPathComponent(dirName, isDirectory: true)
    }

    nonisolated static func tenxDirectory(projectName: String, projectId: String) -> URL {
        projectRootDirectory(projectName: projectName, projectId: projectId)
            .appendingPathComponent("tenx", isDirectory: true)
    }

    nonisolated static func previewScreenImageURL(
        projectName: String,
        projectId: String,
        relativePath: String
    ) -> URL {
        assetURLOrLegacyTenxURL(
            projectName: projectName,
            projectId: projectId,
            relativePath: relativePath
        )
    }

    private func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func removeIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func safeAttachmentFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let sanitized = filename
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "attachment" : sanitized
    }

    private func normalizedAttachmentRelativePath(_ relativePath: String) -> String? {
        let normalized = NSString(string: relativePath).standardizingPath
        guard normalized.hasPrefix("attachments/"),
              !normalized.hasPrefix("/"),
              !normalized.contains("/../")
        else {
            return nil
        }
        return normalized
    }

    private func relativeAttachmentPath(
        for attachment: BuilderMessageAttachment,
        messageId: String,
        projectId: String,
        chatId: String
    ) -> String {
        LocalAssetStorage.relativePath(
            projectId: projectId,
            kind: .upload,
            filename: "\(attachment.id)-\(safeAttachmentFilename(attachment.filename))",
            subdirectories: [chatId, messageId]
        )
    }

    private func relativePath(of url: URL, relativeTo baseURL: URL) -> String? {
        let basePath = baseURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath.hasPrefix(basePath + "/") else { return nil }
        return String(urlPath.dropFirst(basePath.count + 1))
    }

    private func previewScreensIndexURL(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("preview-screens.json")
    }

    private func previewScreensDir(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("preview-screens", isDirectory: true)
    }

    private func capturedScreensIndexURL(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("captured-screens.json")
    }

    private func capturedScreensDir(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("captured-screens", isDirectory: true)
    }

    private func reviewStateURL(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("app-store-review.json")
    }

    private func reviewAssetsDir(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("app-store-review", isDirectory: true)
    }

    nonisolated static func reviewAssetImageURL(
        projectName: String,
        projectId: String,
        relativePath: String
    ) -> URL {
        assetURLOrLegacyTenxURL(
            projectName: projectName,
            projectId: projectId,
            relativePath: relativePath
        )
    }

    private func environmentVariablesURL(projectName: String, projectId: String) -> URL {
        tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("environment.json")
    }

    private func dotEnvURL(projectName: String, projectId: String) -> URL {
        projectRootDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent(".env.local")
    }

    private nonisolated static func assetURLOrLegacyTenxURL(
        projectName: String,
        projectId: String,
        relativePath: String
    ) -> URL {
        if LocalAssetStorage.isPortableAssetPath(relativePath),
           let url = try? LocalAssetStorage.resolvedAssetURL(relativePath: relativePath) {
            return url
        }

        return legacyTenxAssetURL(
            projectName: projectName,
            projectId: projectId,
            relativePath: relativePath
        )
    }

    private nonisolated static func legacyTenxAssetURL(
        projectName: String,
        projectId: String,
        relativePath: String
    ) -> URL {
        let safeRelativePath = (try? LocalAssetStorage.normalizedRelativePath(relativePath))
            ?? "__invalid_asset_path__"
        return tenxDirectory(projectName: projectName, projectId: projectId)
            .appendingPathComponent(safeRelativePath)
    }

    private nonisolated static func thumbnailRelativePath(projectId: String) -> String {
        LocalAssetStorage.relativePath(
            projectId: projectId,
            kind: .preview,
            filename: "thumbnail.png",
            subdirectories: ["thumbnails"]
        )
    }

    private nonisolated static func customIconRelativePath(projectId: String) -> String {
        LocalAssetStorage.relativePath(
            projectId: projectId,
            kind: .generated,
            filename: "custom-icon.png",
            subdirectories: ["project-icons"]
        )
    }

    @MainActor
    private static func pngData(from image: NSImage) -> Data? {
        image.pngData
    }

    private func normalizedEnvironmentVariable(
        _ variable: ProjectEnvironmentVariable
    ) -> ProjectEnvironmentVariable? {
        let trimmedKey = ProjectEnvironmentSecurity.normalizedKey(variable.key)
        let trimmedDescription = ProjectEnvironmentSecurity.normalizedDescription(variable.description)
        guard !trimmedKey.isEmpty else { return nil }

        return ProjectEnvironmentVariable(
            id: variable.id,
            key: trimmedKey,
            description: trimmedDescription,
            value: variable.value,
            scope: variable.scope
        )
    }

    private func parseDotEnvVariables(from contents: String) -> [ProjectEnvironmentVariable] {
        var variables: [ProjectEnvironmentVariable] = []
        var pendingDescriptionLines: [String] = []
        var pendingScope: ProjectEnvironmentScope?

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                pendingDescriptionLines = []
                pendingScope = nil
                continue
            }

            if trimmed.hasPrefix("#") {
                let comment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                if comment.lowercased().hasPrefix("scope:") {
                    let rawScope = String(comment.dropFirst("scope:".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    pendingScope = ProjectEnvironmentScope(rawValue: rawScope)
                    continue
                }
                let normalizedComment: String
                if comment.lowercased().hasPrefix("description:") {
                    normalizedComment = String(comment.dropFirst("description:".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    normalizedComment = comment
                }

                if !normalizedComment.isEmpty {
                    pendingDescriptionLines.append(normalizedComment)
                }
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                pendingDescriptionLines = []
                continue
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                pendingDescriptionLines = []
                continue
            }

            var value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
                value = value
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }

            variables.append(
                ProjectEnvironmentVariable(
                    key: key,
                    description: pendingDescriptionLines.joined(separator: " "),
                    value: value,
                    scope: pendingScope
                )
            )
            pendingDescriptionLines = []
            pendingScope = nil
        }

        return variables
    }

    private func decodeStoredEnvironmentVariables(from data: Data) -> [ProjectEnvironmentVariable]? {
        try? JSONDecoder().decode([ProjectEnvironmentVariable].self, from: data)
    }

    private func storedEnvironmentMetadata(projectName: String, projectId: String) -> [ProjectEnvironmentVariable] {
        let environmentURL = environmentVariablesURL(projectName: projectName, projectId: projectId)
        let dotEnvURL = dotEnvURL(projectName: projectName, projectId: projectId)

        if let data = try? Data(contentsOf: environmentURL),
           let metadata = decodeStoredEnvironmentVariables(from: data) {
            return metadata.compactMap(normalizedEnvironmentVariable)
        }

        if let contents = try? String(contentsOf: dotEnvURL, encoding: .utf8) {
            return parseDotEnvVariables(from: contents).compactMap(normalizedEnvironmentVariable)
        }

        return []
    }

    private func mergedEnvironmentVariables(
        metadataVariables: [ProjectEnvironmentVariable],
        projectFileVariables: [ProjectEnvironmentVariable]
    ) -> [ProjectEnvironmentVariable] {
        var merged = metadataVariables

        for projectVariable in projectFileVariables {
            let key = projectVariable.normalizedKey
            guard !key.isEmpty else { continue }

            if let index = merged.firstIndex(where: { $0.normalizedKey == key }) {
                let existing = merged[index]
                merged[index] = ProjectEnvironmentVariable(
                    id: existing.id,
                    key: key,
                    description: existing.description.isEmpty ? projectVariable.description : existing.description,
                    value: existing.value.isEmpty ? projectVariable.value : existing.value,
                    scope: existing.scope
                )
            } else {
                merged.append(projectVariable)
            }
        }

        return merged
    }

    private func canonicalEnvironmentVariables(
        _ variables: [ProjectEnvironmentVariable]
    ) -> [CanonicalEnvironmentVariable] {
        variables
            .compactMap(normalizedEnvironmentVariable)
            .map {
                CanonicalEnvironmentVariable(
                    key: $0.normalizedKey,
                    description: $0.description,
                    value: $0.value,
                    scope: $0.scope
                )
            }
            .sorted()
    }

    private func withSupabaseClientAliases(
        _ variables: [ProjectEnvironmentVariable]
    ) -> [ProjectEnvironmentVariable] {
        var merged = variables
        let existingByKey = Dictionary(uniqueKeysWithValues: merged.map { ($0.normalizedKey, $0) })
        let anonValue = existingByKey["SUPABASE_ANON_KEY"]?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publishableValue = existingByKey["SUPABASE_PUBLISHABLE_KEY"]?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedValue = !anonValue.isEmpty ? anonValue : publishableValue

        guard !resolvedValue.isEmpty else { return merged }

        let aliases: [(String, String)] = [
            (
                "SUPABASE_ANON_KEY",
                ProjectIntegrations.field(envKey: "SUPABASE_ANON_KEY")?.description
                    ?? "Client-side Supabase anon key saved in the project's `.env.local`."
            ),
            (
                "SUPABASE_PUBLISHABLE_KEY",
                ProjectIntegrations.field(envKey: "SUPABASE_PUBLISHABLE_KEY")?.description
                    ?? "Client-side Supabase publishable key alias saved in the project's `.env.local` for compatibility."
            ),
        ]

        for (key, description) in aliases {
            if let index = merged.firstIndex(where: { $0.normalizedKey == key }) {
                let existing = merged[index]
                merged[index] = ProjectEnvironmentVariable(
                    id: existing.id,
                    key: key,
                    description: existing.description.isEmpty ? description : existing.description,
                    value: existing.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? resolvedValue : existing.value,
                    scope: .client
                )
            } else {
                merged.append(
                    ProjectEnvironmentVariable(
                        key: key,
                        description: description,
                        value: resolvedValue,
                        scope: .client
                    )
                )
            }
        }

        return merged
    }

    private func withHostedValuesFromKeychain(
        _ variables: [ProjectEnvironmentVariable],
        projectId: String
    ) -> [ProjectEnvironmentVariable] {
        variables.map { variable in
            guard variable.scope == .hosted,
                  variable.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let storedValue = ProjectKeychainStore.value(projectId: projectId, key: variable.normalizedKey) else {
                return variable
            }

            return ProjectEnvironmentVariable(
                id: variable.id,
                key: variable.normalizedKey,
                description: variable.description,
                value: storedValue,
                scope: variable.scope
            )
        }
    }

    private func serializeDotEnvVariables(_ variables: [ProjectEnvironmentVariable]) -> String {
        variables.map { variable in
            var lines: [String] = ["# scope: \(variable.scope.rawValue)"]

            let description = ProjectEnvironmentSecurity.normalizedDescription(variable.description)
            if !description.isEmpty {
                for line in description.components(separatedBy: .newlines) where !line.isEmpty {
                    lines.append("# description: \(line)")
                }
            }

            lines.append("\(variable.normalizedKey)=\(dotEnvLiteral(for: variable.value))")
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n") + (variables.isEmpty ? "" : "\n")
    }

    private func dotEnvLiteral(for value: String) -> String {
        guard !value.isEmpty else { return "\"\"" }
        if value.range(of: #"^[A-Za-z0-9_./:@%-]+$"#, options: .regularExpression) != nil {
            return value
        }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private struct CanonicalEnvironmentVariable: Comparable {
        let key: String
        let description: String
        let value: String
        let scope: ProjectEnvironmentScope

        static func < (lhs: CanonicalEnvironmentVariable, rhs: CanonicalEnvironmentVariable) -> Bool {
            if lhs.key != rhs.key {
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            if lhs.scope != rhs.scope {
                return lhs.scope.rawValue.localizedCaseInsensitiveCompare(rhs.scope.rawValue) == .orderedAscending
            }
            if lhs.description != rhs.description {
                return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
            }
            return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
        }
    }

    private func persistEnvironmentVariablesToDisk(
        _ variables: [ProjectEnvironmentVariable],
        projectName: String,
        projectId: String
    ) throws {
        let environmentURL = environmentVariablesURL(projectName: projectName, projectId: projectId)
        let dotEnvURL = dotEnvURL(projectName: projectName, projectId: projectId)
        let clientVariables = variables.filter { $0.scope == .client }
        let metadataVariables = variables.map(ProjectEnvironmentSecurity.sanitizedForDisk)

        if metadataVariables.isEmpty {
            try removeIfExists(environmentURL)
            try removeIfExists(dotEnvURL)
            return
        }

        let tenxDirectory = tenxDir(projectName: projectName, projectId: projectId)
        try ensureDir(tenxDirectory)

        let projectDirectory = projectRootDir(projectName: projectName, projectId: projectId)
        try ensureDir(projectDirectory)

        if clientVariables.isEmpty {
            try removeIfExists(dotEnvURL)
        } else {
            CoordinatedFileWriter.write(serializeDotEnvVariables(clientVariables), to: dotEnvURL)
        }

        let data = try JSONEncoder().encode(metadataVariables)
        try data.write(to: environmentURL, options: .atomic)
    }

    private func prunePreviewScreenImages(
        in directory: URL,
        keeping relativePaths: Set<String>,
        projectName: String,
        projectId: String
    ) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        if relativePaths.isEmpty {
            try removeIfExists(directory)
            return
        }

        let baseDirectory = tenxDir(projectName: projectName, projectId: projectId)
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let next = enumerator?.nextObject() as? URL {
            let isDirectory = (try? next.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                continue
            }
            guard let relativePath = relativePath(of: next, relativeTo: baseDirectory) else { continue }
            if !relativePaths.contains(relativePath) {
                try removeIfExists(next)
            }
        }
    }

    private func materializeAttachment(
        _ attachment: BuilderMessageAttachment,
        messageId: String,
        chatDirectory: URL,
        projectId: String,
        chatId: String
    ) async throws -> (attachment: BuilderMessageAttachment, url: URL)? {
        let storedRelativePath = attachment.storageRelativePath ?? ""
        let legacyRelativePath = normalizedAttachmentRelativePath(storedRelativePath)
        let relativePath = LocalAssetStorage.isPortableAssetPath(storedRelativePath)
            ? try LocalAssetStorage.normalizedRelativePath(storedRelativePath)
            : relativeAttachmentPath(
                for: attachment,
                messageId: messageId,
                projectId: projectId,
                chatId: chatId
            )
        let fileURL = try LocalAssetStorage.resolvedAssetURL(relativePath: relativePath)
        let updatedAttachment = attachment.storageRelativePath == relativePath
            ? attachment
            : attachment.withStorageRelativePath(relativePath)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return (updatedAttachment, fileURL)
        }

        let legacyData = legacyRelativePath.flatMap { relativePath -> Data? in
            let legacyURL = chatDirectory.appendingPathComponent(relativePath)
            return try? Data(contentsOf: legacyURL)
        }
        guard let data = legacyData ?? attachment.fileData else { return nil }

        _ = try await assetStorage.writeAsset(
            projectId: projectId,
            kind: .upload,
            relativePath: relativePath,
            mimeType: attachment.mediaType,
            data: data
        )

        return (updatedAttachment, fileURL)
    }

    private func pruneAttachments(in chatDirectory: URL, keeping relativePaths: Set<String>) throws {
        let root = chatDirectory.appendingPathComponent("attachments", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        if relativePaths.isEmpty {
            try removeIfExists(root)
            return
        }

        let keys: [URLResourceKey] = [.isDirectoryKey]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var directories: [URL] = []
        while let next = enumerator?.nextObject() as? URL {
            let isDirectory = (try? next.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
            if isDirectory {
                directories.append(next)
                continue
            }

            guard let relativePath = relativePath(of: next, relativeTo: chatDirectory) else { continue }
            if !relativePaths.contains(relativePath) {
                try removeIfExists(next)
            }
        }

        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            if contents.isEmpty {
                try removeIfExists(directory)
            }
        }
    }

    private func writeConversationLog(
        _ messages: [BuilderMessage],
        projectName: String,
        chatName: String,
        projectDir: URL
    ) throws {
        let log = messages.compactMap { msg -> String? in
            if let event = msg.restartNoteSystemEvent {
                let body = [event.title, event.detail]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                return "### System\n\n\(body)\n"
            }

            let role = msg.role == "user" ? "You" : "10x"
            let body = msg.transcriptContent.trimmingCharacters(in: .whitespacesAndNewlines)
            return "### \(role)\n\n\(body)\n"
        }.joined(separator: "\n---\n\n")
        let header = "# \(projectName) — \(chatName)\n\n"
        try (header + log).write(
            to: projectDir.appendingPathComponent("conversation.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writePlanningFiles(
        plan: String?,
        tasks: String?,
        projectName: String,
        projectId: String,
        projectDir: URL?
    ) throws {
        let dir = tenxDir(projectName: projectName, projectId: projectId)
        try ensureDir(dir)

        let internalPlanURL = dir.appendingPathComponent("plan.md")
        let internalTasksURL = dir.appendingPathComponent("tasks.md")
        let rootDir = projectDir ?? projectRootDir(projectName: projectName, projectId: projectId)
        let planningDir = rootDir.appendingPathComponent("planning", isDirectory: true)
        let projectPlanURL = planningDir.appendingPathComponent("plan.md")
        let projectTasksURL = planningDir.appendingPathComponent("tasks.md")

        let normalizedPlan = plan?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedPlan, !normalizedPlan.isEmpty {
            try normalizedPlan.write(to: internalPlanURL, atomically: true, encoding: .utf8)
            try ensureDir(planningDir)
            try normalizedPlan.write(to: projectPlanURL, atomically: true, encoding: .utf8)
        } else {
            try removeIfExists(internalPlanURL)
            try removeIfExists(projectPlanURL)
        }

        let normalizedTasks = tasks?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedTasks, !normalizedTasks.isEmpty {
            try normalizedTasks.write(to: internalTasksURL, atomically: true, encoding: .utf8)
            try ensureDir(planningDir)
            try normalizedTasks.write(to: projectTasksURL, atomically: true, encoding: .utf8)
        } else {
            try removeIfExists(internalTasksURL)
            try removeIfExists(projectTasksURL)
        }
    }

    // MARK: - Chats

    func persistAttachments(
        in messages: [BuilderMessage],
        projectName: String,
        projectId: String,
        chatId: String
    ) async -> [BuilderMessage] {
        let chatDirectory = chatDir(projectName: projectName, projectId: projectId, chatId: chatId)
        let attachmentsDirectory = chatDirectory.appendingPathComponent("attachments", isDirectory: true)

        do {
            guard messages.contains(where: { !$0.attachments.isEmpty }) else {
                try removeIfExists(attachmentsDirectory)
                return messages
            }

            try ensureDir(attachmentsDirectory)

            var referencedRelativePaths: Set<String> = []
            var updatedMessages: [BuilderMessage] = []
            for message in messages {
                var updatedMessage = message
                var updatedAttachments: [BuilderMessageAttachment] = []
                for attachment in message.attachments {
                    guard let materialized = try await materializeAttachment(
                        attachment,
                        messageId: message.id,
                        chatDirectory: chatDirectory,
                        projectId: projectId,
                        chatId: chatId
                    ) else {
                        updatedAttachments.append(attachment)
                        continue
                    }
                    if let relativePath = materialized.attachment.storageRelativePath {
                        referencedRelativePaths.insert(relativePath)
                    }
                    updatedAttachments.append(materialized.attachment)
                }
                updatedMessage.attachments = updatedAttachments
                updatedMessages.append(updatedMessage)
            }

            try pruneAttachments(in: chatDirectory, keeping: referencedRelativePaths)
            return updatedMessages
        } catch {
            print("Failed to persist attachments locally: \(error)")
            return messages
        }
    }

    func resolveAttachmentFile(
        for attachment: BuilderMessageAttachment,
        messageId: String,
        projectName: String,
        projectId: String,
        chatId: String
    ) async -> (attachment: BuilderMessageAttachment, url: URL)? {
        let chatDirectory = chatDir(projectName: projectName, projectId: projectId, chatId: chatId)

        do {
            return try await materializeAttachment(
                attachment,
                messageId: messageId,
                chatDirectory: chatDirectory,
                projectId: projectId,
                chatId: chatId
            )
        } catch {
            print("Failed to resolve attachment file: \(error)")
            return nil
        }
    }

    func saveChatIndex(_ index: BuilderChatIndex, projectName: String, projectId: String) {
        do {
            let dir = tenxDir(projectName: projectName, projectId: projectId)
            try ensureDir(dir)
            let data = try JSONEncoder().encode(index)
            try data.write(to: chatIndexURL(projectName: projectName, projectId: projectId))
        } catch {
            print("Failed to save chat index locally: \(error)")
        }
    }

    func loadChatIndex(projectName: String, projectId: String) -> BuilderChatIndex? {
        let file = chatIndexURL(projectName: projectName, projectId: projectId)
        guard let data = try? Data(contentsOf: file),
              let index = try? JSONDecoder().decode(BuilderChatIndex.self, from: data) else {
            return nil
        }
        return index
    }

    func saveChatState(
        _ state: BuilderChatState,
        chat: BuilderChat,
        projectName: String,
        projectId: String,
        projectDir: URL? = nil
    ) {
        do {
            let dir = chatDir(projectName: projectName, projectId: projectId, chatId: chat.id)
            try ensureDir(dir)
            let data = try JSONEncoder().encode(state)
            try data.write(to: dir.appendingPathComponent("state.json"))

            if let projectDir {
                try writeConversationLog(state.messages, projectName: projectName, chatName: chat.name, projectDir: projectDir)
            }
        } catch {
            print("Failed to save chat state locally: \(error)")
        }
    }

    func loadChatState(projectName: String, projectId: String, chatId: String) -> BuilderChatState? {
        let file = chatDir(projectName: projectName, projectId: projectId, chatId: chatId)
            .appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: file),
              let state = try? JSONDecoder().decode(BuilderChatState.self, from: data) else {
            return nil
        }
        return state
    }

    func deleteChatState(projectName: String, projectId: String, chatId: String) {
        do {
            try removeIfExists(chatDir(projectName: projectName, projectId: projectId, chatId: chatId))
        } catch {
            print("Failed to delete chat state locally: \(error)")
        }
    }

    // MARK: - Messages

    func saveMessages(_ messages: [BuilderMessage], projectName: String, projectId: String, projectDir: URL? = nil) {
        do {
            // Save structured JSON to tenx/ for app loading
            let dir = tenxDir(projectName: projectName, projectId: projectId)
            try ensureDir(dir)
            let data = try JSONEncoder().encode(messages)
            try data.write(to: dir.appendingPathComponent("messages.json"))

            // Save human-readable conversation log to project root
            if let projectDir {
                try writeConversationLog(messages, projectName: projectName, chatName: "Conversation", projectDir: projectDir)
            }
        } catch {
            print("Failed to save messages locally: \(error)")
        }
    }

    func loadMessages(projectName: String, projectId: String) -> [BuilderMessage]? {
        let file = tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("messages.json")
        guard let data = try? Data(contentsOf: file),
              let messages = try? JSONDecoder().decode([BuilderMessage].self, from: data) else {
            return nil
        }
        return messages
    }

    // MARK: - File Tree

    func saveFileTree(_ fileTree: [String: String], projectName: String, projectId: String) {
        do {
            let dir = tenxDir(projectName: projectName, projectId: projectId)
            try ensureDir(dir)
            let data = try JSONEncoder().encode(fileTree)
            try data.write(to: dir.appendingPathComponent("file_tree.json"))
        } catch {
            print("Failed to save file tree locally: \(error)")
        }
    }

    func loadFileTree(projectName: String, projectId: String) -> [String: String]? {
        let file = tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("file_tree.json")
        guard let data = try? Data(contentsOf: file),
              let tree = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return tree
    }

    func loadPlan(projectName: String, projectId: String) -> String? {
        let file = tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("plan.md")
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func loadTasks(projectName: String, projectId: String) -> String? {
        let file = tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("tasks.md")
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func saveProjectStatus(
        _ status: BuilderProjectStatusState,
        projectName: String,
        projectId: String,
        projectDir: URL? = nil
    ) {
        do {
            let dir = tenxDir(projectName: projectName, projectId: projectId)
            try ensureDir(dir)

            let statusURL = projectStatusURL(projectName: projectName, projectId: projectId)
            if status.hasContent {
                let data = try JSONEncoder().encode(status)
                try data.write(to: statusURL, options: .atomic)
            } else {
                try removeIfExists(statusURL)
            }

            try writePlanningFiles(
                plan: status.plan,
                tasks: status.tasks,
                projectName: projectName,
                projectId: projectId,
                projectDir: projectDir
            )
        } catch {
            print("Failed to save project status locally: \(error)")
        }
    }

    func loadProjectStatus(projectName: String, projectId: String) -> BuilderProjectStatusState? {
        let statusURL = projectStatusURL(projectName: projectName, projectId: projectId)
        if let data = try? Data(contentsOf: statusURL),
           let status = try? JSONDecoder().decode(BuilderProjectStatusState.self, from: data) {
            return status
        }

        let legacyStatus = BuilderProjectStatusState(
            plan: loadPlan(projectName: projectName, projectId: projectId),
            tasks: loadTasks(projectName: projectName, projectId: projectId),
            warnings: []
        )
        return legacyStatus.hasContent ? legacyStatus : nil
    }

    func saveProductionChecklist(
        _ checklist: ProductionChecklistState,
        projectName: String,
        projectId: String
    ) {
        do {
            let dir = tenxDir(projectName: projectName, projectId: projectId)
            try ensureDir(dir)

            let url = productionChecklistURL(projectName: projectName, projectId: projectId)
            if checklist.checkedItemIDs.isEmpty {
                try removeIfExists(url)
                return
            }

            let data = try JSONEncoder().encode(checklist)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save production checklist locally: \(error)")
        }
    }

    func loadProductionChecklist(projectName: String, projectId: String) -> ProductionChecklistState {
        let url = productionChecklistURL(projectName: projectName, projectId: projectId)
        guard let data = try? Data(contentsOf: url),
              let checklist = try? JSONDecoder().decode(ProductionChecklistState.self, from: data) else {
            return .empty
        }
        return checklist
    }

    // MARK: - Environment Variables

    func saveEnvironmentVariables(
        _ variables: [ProjectEnvironmentVariable],
        projectName: String,
        projectId: String
    ) {
        do {
            let normalized = withSupabaseClientAliases(variables.compactMap(normalizedEnvironmentVariable))
            try persistEnvironmentVariablesToDisk(
                normalized,
                projectName: projectName,
                projectId: projectId
            )
            ProjectKeychainStore.syncStoredValues(projectId: projectId, variables: normalized)
        } catch {
            print("Failed to save environment variables locally: \(error)")
        }
    }

    func loadEnvironmentVariables(projectName: String, projectId: String) -> [ProjectEnvironmentVariable] {
        let environmentURL = environmentVariablesURL(projectName: projectName, projectId: projectId)
        let dotEnvURL = dotEnvURL(projectName: projectName, projectId: projectId)

        let metadataVariables = ((try? Data(contentsOf: environmentURL))
            .flatMap { decodeStoredEnvironmentVariables(from: $0) } ?? [])
            .compactMap(normalizedEnvironmentVariable)
        let projectFileVariables = ((try? String(contentsOf: dotEnvURL, encoding: .utf8))
            .map { parseDotEnvVariables(from: $0) } ?? [])
            .compactMap(normalizedEnvironmentVariable)

        let sourceVariables: [ProjectEnvironmentVariable]
        let shouldRewriteDisk: Bool
        if !metadataVariables.isEmpty {
            sourceVariables = mergedEnvironmentVariables(
                metadataVariables: metadataVariables,
                projectFileVariables: projectFileVariables
            )
            let sourceClientVariables = sourceVariables.filter { $0.scope == .client }
            let projectFileClientVariables = projectFileVariables.filter { $0.scope == .client }
            shouldRewriteDisk =
                projectFileVariables.contains { $0.scope == .hosted }
                || canonicalEnvironmentVariables(sourceClientVariables)
                    != canonicalEnvironmentVariables(projectFileClientVariables)
        } else if !projectFileVariables.isEmpty {
            sourceVariables = projectFileVariables
            shouldRewriteDisk = true
        } else {
            sourceVariables = []
            shouldRewriteDisk = false
        }

        guard !sourceVariables.isEmpty else { return [] }

        let normalized = withSupabaseClientAliases(sourceVariables.compactMap(normalizedEnvironmentVariable))
        let hydrated = withHostedValuesFromKeychain(normalized, projectId: projectId)
        let sanitized = hydrated.map(ProjectEnvironmentSecurity.sanitizedForDisk)
        let needsLegacySecretMigration = normalized.contains {
            $0.scope == .hosted
                && (!$0.value.isEmpty || ProjectKeychainStore.value(projectId: projectId, key: $0.normalizedKey) != nil)
        }

        if shouldRewriteDisk || needsLegacySecretMigration {
            do {
                try persistEnvironmentVariablesToDisk(
                    sanitized,
                    projectName: projectName,
                    projectId: projectId
                )
                ProjectKeychainStore.syncStoredValues(projectId: projectId, variables: hydrated)
            } catch {
                print("Failed to migrate environment variables locally: \(error)")
            }
        }

        return hydrated
    }

    // MARK: - Preview Screens

    func savePreviewScreenImage(
        _ image: NSImage,
        capture: PreviewScreenCapture,
        projectName: String,
        projectId: String
    ) async {
        do {
            guard let png = await Self.pngData(from: image) else { return }
            if LocalAssetStorage.isPortableAssetPath(capture.relativeImagePath) {
                _ = try await assetStorage.writeAsset(
                    projectId: projectId,
                    kind: .preview,
                    relativePath: capture.relativeImagePath,
                    mimeType: "image/png",
                    data: png
                )
            } else {
                let imageURL = Self.previewScreenImageURL(
                    projectName: projectName,
                    projectId: projectId,
                    relativePath: capture.relativeImagePath
                )
                try ensureDir(imageURL.deletingLastPathComponent())
                try png.write(to: imageURL, options: .atomic)
            }
        } catch {
            print("Failed to save preview screen image: \(error)")
        }
    }

    func savePreviewScreens(
        _ captures: [PreviewScreenCapture],
        projectName: String,
        projectId: String
    ) {
        saveScreenCaptures(
            captures,
            indexURL: previewScreensIndexURL(projectName: projectName, projectId: projectId),
            directory: previewScreensDir(projectName: projectName, projectId: projectId),
            projectName: projectName,
            projectId: projectId,
            label: "preview screens"
        )
    }

    func loadPreviewScreens(projectName: String, projectId: String) -> [PreviewScreenCapture] {
        loadScreenCaptures(indexURL: previewScreensIndexURL(projectName: projectName, projectId: projectId))
    }

    func saveCapturedScreens(
        _ captures: [PreviewScreenCapture],
        projectName: String,
        projectId: String
    ) {
        saveScreenCaptures(
            captures,
            indexURL: capturedScreensIndexURL(projectName: projectName, projectId: projectId),
            directory: capturedScreensDir(projectName: projectName, projectId: projectId),
            projectName: projectName,
            projectId: projectId,
            label: "captured screens"
        )
    }

    func loadCapturedScreens(projectName: String, projectId: String) -> [PreviewScreenCapture] {
        loadScreenCaptures(indexURL: capturedScreensIndexURL(projectName: projectName, projectId: projectId))
    }

    private func saveScreenCaptures(
        _ captures: [PreviewScreenCapture],
        indexURL: URL,
        directory: URL,
        projectName: String,
        projectId: String,
        label: String
    ) {
        do {
            let tenxDirectory = tenxDir(projectName: projectName, projectId: projectId)
            try ensureDir(tenxDirectory)

            let data = try JSONEncoder().encode(captures)
            try data.write(to: indexURL, options: .atomic)

            let relativePaths = Set(captures.map(\.relativeImagePath))
            try prunePreviewScreenImages(
                in: directory,
                keeping: relativePaths,
                projectName: projectName,
                projectId: projectId
            )
        } catch {
            print("Failed to save \(label): \(error)")
        }
    }

    private func loadScreenCaptures(indexURL: URL) -> [PreviewScreenCapture] {
        guard let data = try? Data(contentsOf: indexURL) else {
            return []
        }

        if let captures = try? JSONDecoder().decode([PreviewScreenCapture].self, from: data) {
            return captures
        }

        return []
    }

    // MARK: - App Store Review Assets

    func saveReviewAssetImage(
        _ image: NSImage,
        relativePath: String,
        projectName: String,
        projectId: String
    ) async {
        do {
            guard let png = await Self.pngData(from: image) else { return }
            if LocalAssetStorage.isPortableAssetPath(relativePath) {
                _ = try await assetStorage.writeAsset(
                    projectId: projectId,
                    kind: .export,
                    relativePath: relativePath,
                    mimeType: "image/png",
                    data: png
                )
            } else {
                let imageURL = Self.reviewAssetImageURL(
                    projectName: projectName,
                    projectId: projectId,
                    relativePath: relativePath
                )
                try ensureDir(imageURL.deletingLastPathComponent())
                try png.write(to: imageURL, options: .atomic)
            }
        } catch {
            print("Failed to save review asset image: \(error)")
        }
    }

    func saveReviewState(
        _ state: AppStoreReviewState,
        projectName: String,
        projectId: String
    ) {
        do {
            let tenxDirectory = tenxDir(projectName: projectName, projectId: projectId)
            try ensureDir(tenxDirectory)

            let stateURL = reviewStateURL(projectName: projectName, projectId: projectId)
            if state.hasContent {
                let data = try JSONEncoder().encode(state)
                try data.write(to: stateURL, options: .atomic)
            } else {
                try removeIfExists(stateURL)
            }

            try prunePreviewScreenImages(
                in: reviewAssetsDir(projectName: projectName, projectId: projectId),
                keeping: state.referencedImagePaths,
                projectName: projectName,
                projectId: projectId
            )
        } catch {
            print("Failed to save app store review state: \(error)")
        }
    }

    func loadReviewState(projectName: String, projectId: String) -> AppStoreReviewState {
        let stateURL = reviewStateURL(projectName: projectName, projectId: projectId)
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(AppStoreReviewState.self, from: data) else {
            return .empty
        }
        return state
    }

    // MARK: - Onboarding Draft

    func saveOnboardingDraft(_ draft: OnboardingDraft, projectName: String, projectId: String) {
        do {
            let dir = tenxDir(projectName: projectName, projectId: projectId)
            try ensureDir(dir)
            let data = try JSONEncoder().encode(draft)
            try data.write(to: dir.appendingPathComponent("onboarding-draft.json"))
        } catch {
            print("Failed to save onboarding draft: \(error)")
        }
    }

    nonisolated func loadOnboardingDraft(projectName: String, projectId: String) -> OnboardingDraft? {
        let file = Self.tenxDirectory(projectName: projectName, projectId: projectId)
            .appendingPathComponent("onboarding-draft.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    func deleteOnboardingDraft(projectName: String, projectId: String) {
        let file = tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("onboarding-draft.json")
        try? removeIfExists(file)
    }

    // MARK: - Thumbnail

    func saveThumbnail(_ image: NSImage, projectName: String, projectId: String) async {
        do {
            guard let png = await Self.pngData(from: image) else { return }
            _ = try await assetStorage.writeAsset(
                projectId: projectId,
                kind: .preview,
                relativePath: Self.thumbnailRelativePath(projectId: projectId),
                mimeType: "image/png",
                data: png
            )
        } catch {
            print("Failed to save thumbnail: \(error)")
        }
    }

    nonisolated func loadThumbnail(projectName: String, projectId: String) -> NSImage? {
        if let assetURL = try? LocalAssetStorage.resolvedAssetURL(
            relativePath: Self.thumbnailRelativePath(projectId: projectId)
        ),
           let image = NSImage(contentsOf: assetURL) {
            return image
        }

        let legacyFile = Self.tenxDirectory(projectName: projectName, projectId: projectId)
            .appendingPathComponent("thumbnail.png")
        return NSImage(contentsOf: legacyFile)
    }

    // MARK: - Custom Project Icon

    func saveCustomIcon(_ image: NSImage, projectName: String, projectId: String) async {
        do {
            guard let png = await Self.pngData(from: image) else { return }
            _ = try await assetStorage.writeAsset(
                projectId: projectId,
                kind: .generated,
                relativePath: Self.customIconRelativePath(projectId: projectId),
                mimeType: "image/png",
                data: png
            )
        } catch {
            print("Failed to save custom icon: \(error)")
        }
    }

    func loadCustomIcon(projectName: String, projectId: String) -> NSImage? {
        if let assetURL = try? LocalAssetStorage.resolvedAssetURL(
            relativePath: Self.customIconRelativePath(projectId: projectId)
        ),
           let image = NSImage(contentsOf: assetURL) {
            return image
        }

        let legacyFile = tenxDir(projectName: projectName, projectId: projectId)
            .appendingPathComponent("custom-icon.png")
        return NSImage(contentsOf: legacyFile)
    }

    func deleteCustomIcon(projectName: String, projectId: String) {
        do {
            if let assetURL = try? LocalAssetStorage.resolvedAssetURL(
                relativePath: Self.customIconRelativePath(projectId: projectId)
            ) {
                try removeIfExists(assetURL)
            }
            let legacyFile = tenxDir(projectName: projectName, projectId: projectId)
                .appendingPathComponent("custom-icon.png")
            try removeIfExists(legacyFile)
        } catch {
            print("Failed to delete custom icon: \(error)")
        }
    }

    func moveProjectData(oldProjectName: String, newProjectName: String, projectId: String) {
        let oldDir = projectRootDir(projectName: oldProjectName, projectId: projectId)
        let newDir = projectRootDir(projectName: newProjectName, projectId: projectId)

        guard oldDir.path != newDir.path else { return }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: oldDir.path), !fileManager.fileExists(atPath: newDir.path) {
                try fileManager.moveItem(at: oldDir, to: newDir)
            }
        } catch {
            print("Failed to move local project data: \(error)")
        }
    }

    // MARK: - Delete all local data

    func deleteProjectData(projectName: String, projectId: String) {
        let projectDir = projectRootDir(projectName: projectName, projectId: projectId)

        try? FileManager.default.removeItem(at: projectDir)
    }
}
