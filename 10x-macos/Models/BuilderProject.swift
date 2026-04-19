import Foundation

struct BuilderProject: Codable, Identifiable, Sendable {
    let id: String
    let userId: String
    let name: String
    let description: String?
    let slug: String
    let platform: String
    let status: String
    let currentVersionId: String?
    let settings: [String: AnyCodableValue]?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, slug, platform, status, settings
        case userId = "user_id"
        case currentVersionId = "current_version_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension BuilderProject {
    static let dependencyManifestSettingsKey = "project_dependencies"
    static let backendStateSettingsKey = "project_backend"
    static let superwallStateSettingsKey = "project_superwall"

    var dependencyManifest: ProjectDependencyManifest? {
        settings?[Self.dependencyManifestSettingsKey]?.decode(ProjectDependencyManifest.self)
    }

    var backendState: ProjectBackendState? {
        settings?[Self.backendStateSettingsKey]?.decode(ProjectBackendState.self)
    }

    var superwallState: ProjectSuperwallState? {
        settings?[Self.superwallStateSettingsKey]?.decode(ProjectSuperwallState.self)
    }
}

struct BuilderVersion: Codable, Identifiable, Sendable {
    let id: String
    let projectId: String
    let versionNumber: Int
    let fileTree: [String: String]
    let prompt: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, prompt, status
        case projectId = "project_id"
        case versionNumber = "version_number"
        case fileTree = "file_tree"
        case createdAt = "created_at"
    }
}

enum BuilderMessageAttachmentKind: String, Codable, Sendable, Hashable {
    case text
    case pdf
    case image
}

enum BuilderAttachmentPolicy {
    static let maxItemCount = 5
    static let maxTotalBytes = 5 * 1024 * 1024

    static func fileBytes(for attachments: [BuilderMessageAttachment]) -> Int {
        attachments.reduce(0) { $0 + max($1.sizeBytes, 0) }
    }

    static func payloadBytes(for attachments: [BuilderMessageAttachment]) -> Int {
        let blocks = attachments.flatMap { $0.claudeContentBlocks() }
        guard !blocks.isEmpty,
              JSONSerialization.isValidJSONObject(blocks),
              let data = try? JSONSerialization.data(withJSONObject: blocks, options: [.sortedKeys]) else {
            return fileBytes(for: attachments)
        }
        return data.count
    }

    static func validationError(for attachments: [BuilderMessageAttachment]) -> String? {
        if attachments.count > maxItemCount {
            return "You can attach up to \(maxItemCount) files per message."
        }

        if payloadBytes(for: attachments) > maxTotalBytes {
            return "Attachments can total up to 5 MB per message."
        }

        return nil
    }
}

struct BuilderMessageAttachment: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let filename: String
    let kind: BuilderMessageAttachmentKind
    let mediaType: String
    let sizeBytes: Int
    let textContent: String?
    let base64Data: String?
    let storageRelativePath: String?
    let previewViewName: String?

    nonisolated init(
        id: String = UUID().uuidString,
        filename: String,
        kind: BuilderMessageAttachmentKind,
        mediaType: String,
        sizeBytes: Int,
        textContent: String? = nil,
        base64Data: String? = nil,
        storageRelativePath: String? = nil,
        previewViewName: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.kind = kind
        self.mediaType = mediaType
        self.sizeBytes = sizeBytes
        self.textContent = textContent
        self.base64Data = base64Data
        self.storageRelativePath = storageRelativePath
        self.previewViewName = previewViewName
    }

    nonisolated static func previewViewMentionName(from rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredScalars = trimmed.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        let normalized = String(String.UnicodeScalarView(filteredScalars))
        if !normalized.isEmpty {
            return normalized
        }

        return trimmed.isEmpty ? "View" : trimmed
    }

    nonisolated static func normalizedPreviewViewMentionName(_ rawName: String) -> String {
        previewViewMentionName(from: rawName).lowercased()
    }

    nonisolated static func previewViewMentionTag(for rawName: String) -> String {
        "@\(previewViewMentionName(from: rawName))"
    }

    nonisolated var previewViewMentionTag: String? {
        previewViewName.map(Self.previewViewMentionTag(for:))
    }

    nonisolated var displayKind: String {
        if kind == .image, previewViewName != nil {
            return "View"
        }
        switch kind {
        case .text:
            return "Text"
        case .pdf:
            return "PDF"
        case .image:
            return "Image"
        }
    }

    nonisolated var systemImageName: String {
        if kind == .image, previewViewName != nil {
            return "rectangle.on.rectangle.angled"
        }
        switch kind {
        case .text:
            return "doc.text"
        case .pdf:
            return "doc.richtext"
        case .image:
            return "photo"
        }
    }

    nonisolated var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeBytes))
    }

    nonisolated var transcriptSummaryLine: String {
        if let previewViewMentionTag {
            return "\(previewViewMentionTag) (View, \(sizeDescription))"
        }
        return "\(filename) (\(displayKind), \(sizeDescription))"
    }

    nonisolated var queueSummary: String {
        if let previewViewMentionTag {
            return previewViewMentionTag
        }
        return filename.isEmpty ? displayKind : filename
    }

    nonisolated var approximateContextTokens: Int {
        switch kind {
        case .text:
            let count = textContent?.count ?? 0
            return max(1, Int(ceil(Double(count) / 4.0)))
        case .pdf:
            return max(1, Int(ceil(Double(sizeBytes) / 12.0)))
        case .image:
            return max(1, Int(ceil(Double(sizeBytes) / 16.0)))
        }
    }

    nonisolated var imageData: Data? {
        guard kind == .image,
              let base64Data else { return nil }
        return Data(base64Encoded: base64Data)
    }

    nonisolated var isPreviewViewAttachment: Bool {
        previewViewName != nil
    }

    nonisolated var fileData: Data? {
        if let base64Data, let data = Data(base64Encoded: base64Data) {
            return data
        }
        if kind == .text {
            return textContent?.data(using: .utf8)
        }
        return nil
    }

    nonisolated func claudeContentBlocks() -> [[String: Any]] {
        switch kind {
        case .text:
            let text = textContent ?? ""
            return [[
                "type": "text",
                "text": """
                <attached_file>
                name: \(filename)
                media_type: \(mediaType)
                size_bytes: \(sizeBytes)
                content:
                \(text)
                </attached_file>
                """,
            ]]

        case .pdf:
            guard let base64Data else { return [] }
            return [
                [
                    "type": "text",
                    "text": "Attached PDF: \(filename) (\(sizeDescription)).",
                ],
                [
                    "type": "document",
                    "title": filename,
                    "source": [
                        "type": "base64",
                        "media_type": mediaType,
                        "data": base64Data,
                    ],
                ],
            ]

        case .image:
            guard let base64Data else { return [] }
            let summaryText: String
            if let previewViewName {
                summaryText = "Attached app view screenshot: \(previewViewName) (\(sizeDescription))."
            } else {
                summaryText = "Attached image: \(filename) (\(sizeDescription))."
            }
            return [
                [
                    "type": "text",
                    "text": summaryText,
                ],
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": mediaType,
                        "data": base64Data,
                    ],
                ],
            ]
        }
    }

    nonisolated func withStorageRelativePath(_ storageRelativePath: String) -> BuilderMessageAttachment {
        BuilderMessageAttachment(
            id: id,
            filename: filename,
            kind: kind,
            mediaType: mediaType,
            sizeBytes: sizeBytes,
            textContent: textContent,
            base64Data: base64Data,
            storageRelativePath: storageRelativePath,
            previewViewName: previewViewName
        )
    }
}

enum BuilderMessageAction: String, Codable, Sendable {
    case executePlan
}

struct BuilderMessage: Codable, Identifiable, Sendable {
    let id: String
    let conversationId: String
    let role: String
    var content: String
    var attachments: [BuilderMessageAttachment]
    var requiredSkillNames: [String]
    var action: BuilderMessageAction?
    let versionId: String?
    let createdAt: String
    var mode: ProjectMode?

    init(
        id: String,
        conversationId: String,
        role: String,
        content: String,
        attachments: [BuilderMessageAttachment] = [],
        requiredSkillNames: [String] = [],
        action: BuilderMessageAction? = nil,
        versionId: String?,
        createdAt: String,
        mode: ProjectMode? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.attachments = attachments
        self.requiredSkillNames = requiredSkillNames
        self.action = action
        self.versionId = versionId
        self.createdAt = createdAt
        self.mode = mode
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, attachments, requiredSkillNames, action, mode
        case conversationId = "conversation_id"
        case versionId = "version_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([BuilderMessageAttachment].self, forKey: .attachments) ?? []
        requiredSkillNames = try container.decodeIfPresent([String].self, forKey: .requiredSkillNames) ?? []
        action = try container.decodeIfPresent(BuilderMessageAction.self, forKey: .action)
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        mode = try container.decodeIfPresent(ProjectMode.self, forKey: .mode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(requiredSkillNames, forKey: .requiredSkillNames)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(versionId, forKey: .versionId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(mode, forKey: .mode)
    }
}

enum BuilderToolStepStatus: String, Codable, Sendable, Hashable {
    case running
    case success
    case error
}

enum BuilderToolCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case skills
    case projectFiles
    case webResearch
    case commandLine
    case project
    case questions
    case other

    init(toolName: String) {
        switch toolName {
        case "list_skills", "use_skill":
            self = .skills
        case "write_file", "edit_file", "read_files", "delete_file", "list_files", "search_files":
            self = .projectFiles
        case "web_search", "scrape_url":
            self = .webResearch
        case "run_command":
            self = .commandLine
        case "update_project_status", "update_project_dependencies", "set_project_identity", "change_mode", "update_app_store_assets", "update_app_store_review_assets":
            self = .project
        case "backend_manage", "supabase_read_tables", "supabase_write_tables", "supabase_execute_sql", "supabase_manage_settings", "superwall_manage":
            self = .project
        case "ask_user":
            self = .questions
        default:
            self = .other
        }
    }

    var title: String {
        switch self {
        case .skills:
            return "Skills"
        case .projectFiles:
            return "Project Files"
        case .webResearch:
            return "Web Research"
        case .commandLine:
            return "Command Line"
        case .project:
            return "Project"
        case .questions:
            return "Questions"
        case .other:
            return "Other"
        }
    }

    var systemImageName: String {
        switch self {
        case .skills:
            return "sparkles"
        case .projectFiles:
            return "folder"
        case .webResearch:
            return "globe"
        case .commandLine:
            return "terminal"
        case .project:
            return "slider.horizontal.3"
        case .questions:
            return "questionmark.bubble"
        case .other:
            return "wrench.and.screwdriver"
        }
    }

    func summaryLabel(count: Int) -> String {
        switch self {
        case .skills:
            return count == 1 ? "skill" : "skills"
        case .projectFiles:
            return count == 1 ? "file action" : "file actions"
        case .webResearch:
            return count == 1 ? "research step" : "research steps"
        case .commandLine:
            return count == 1 ? "command" : "commands"
        case .project:
            return count == 1 ? "project update" : "project updates"
        case .questions:
            return count == 1 ? "question" : "questions"
        case .other:
            return count == 1 ? "tool" : "tools"
        }
    }
}

enum BuilderToolPresentation {
    nonisolated static func shortLabel(name: String) -> String {
        switch name {
        case "write_file": return "Writing file..."
        case "edit_file": return "Editing file..."
        case "read_files": return "Reading files..."
        case "delete_file": return "Deleting file..."
        case "list_files": return "Listing project files..."
        case "search_files": return "Searching project files..."
        case "web_search": return "Researching on the web..."
        case "scrape_url": return "Reading web page..."
        case "ask_user": return "Asking a question..."
        case "set_project_identity": return "Updating project identity..."
        case "update_project_status": return "Updating project status..."
        case "update_project_dependencies": return "Updating project dependencies..."
        case "update_app_store_assets", "update_app_store_review_assets": return "Updating App Store assets..."
        case "list_screens": return "Reviewing source screens..."
        case "update_app_store_details": return "Updating App Store details..."
        case "run_command": return "Running command..."
        case "change_mode": return "Switching modes..."
        case "list_skills": return "Reviewing skills..."
        case "use_skill": return "Learning skill..."
        case "backend_manage": return "Managing backend..."
        case "supabase_read_tables": return "Reading Supabase..."
        case "supabase_write_tables": return "Writing Supabase..."
        case "supabase_execute_sql": return "Running Supabase SQL..."
        case "supabase_manage_settings": return "Updating Supabase settings..."
        case "superwall_manage": return "Managing Superwall..."
        default: return humanizedToolName(name)
        }
    }

    nonisolated static func groupTitle(name: String) -> String {
        switch name {
        case "write_file": return "Write File"
        case "edit_file": return "Edit File"
        case "read_files": return "Read Files"
        case "delete_file": return "Delete File"
        case "list_files": return "List Files"
        case "search_files": return "Search Files"
        case "web_search": return "Web Search"
        case "scrape_url": return "Read Web Page"
        case "ask_user": return "Ask User"
        case "set_project_identity": return "Set Project Identity"
        case "update_project_status": return "Update Project Status"
        case "update_project_dependencies": return "Update Project Dependencies"
        case "update_app_store_assets", "update_app_store_review_assets": return "Update App Store Assets"
        case "list_screens": return "List Screens"
        case "update_app_store_details": return "Update App Store Details"
        case "run_command": return "Run Command"
        case "change_mode": return "Change Mode"
        case "list_skills": return "List Skills"
        case "use_skill": return "Read Skill"
        case "backend_manage": return "Manage Backend"
        case "supabase_read_tables": return "Read Supabase Tables"
        case "supabase_write_tables": return "Write Supabase Tables"
        case "supabase_execute_sql": return "Execute Supabase SQL"
        case "supabase_manage_settings": return "Manage Supabase Settings"
        case "superwall_manage": return "Manage Superwall"
        default: return humanizedToolName(name)
        }
    }

    nonisolated static func summaryLabel(name: String, count: Int) -> String {
        switch name {
        case "write_file": return count == 1 ? "file creation" : "file creations"
        case "edit_file": return count == 1 ? "file edit" : "file edits"
        case "read_files": return count == 1 ? "file read" : "file reads"
        case "delete_file": return count == 1 ? "file deletion" : "file deletions"
        case "list_files": return count == 1 ? "file listing" : "file listings"
        case "search_files": return count == 1 ? "code search" : "code searches"
        case "web_search": return count == 1 ? "web search" : "web searches"
        case "scrape_url": return count == 1 ? "page read" : "page reads"
        case "ask_user": return count == 1 ? "question" : "questions"
        case "set_project_identity": return count == 1 ? "identity update" : "identity updates"
        case "update_project_status", "update_project_dependencies": return count == 1 ? "project update" : "project updates"
        case "update_app_store_assets", "update_app_store_review_assets": return count == 1 ? "App Store asset update" : "App Store asset updates"
        case "list_screens": return count == 1 ? "screen listing" : "screen listings"
        case "update_app_store_details": return count == 1 ? "App Store update" : "App Store updates"
        case "run_command": return count == 1 ? "command" : "commands"
        case "change_mode": return count == 1 ? "mode switch" : "mode switches"
        case "list_skills": return count == 1 ? "skill listing" : "skill listings"
        case "use_skill": return count == 1 ? "skill read" : "skill reads"
        case "backend_manage": return count == 1 ? "backend action" : "backend actions"
        case "supabase_read_tables": return count == 1 ? "Supabase read" : "Supabase reads"
        case "supabase_write_tables": return count == 1 ? "Supabase write" : "Supabase writes"
        case "supabase_execute_sql": return count == 1 ? "Supabase SQL execution" : "Supabase SQL executions"
        case "supabase_manage_settings": return count == 1 ? "Supabase settings update" : "Supabase settings updates"
        case "superwall_manage": return count == 1 ? "Superwall action" : "Superwall actions"
        default: return count == 1 ? "tool call" : "tool calls"
        }
    }

    nonisolated static func detailedLabel(name: String, input: [String: Any]) -> String {
        let path = compactLine(input["path"] as? String)

        switch name {
        case "write_file":
            return path.isEmpty ? "Writing file" : "Writing \(path)"
        case "edit_file":
            return path.isEmpty ? "Editing file" : "Editing \(path)"
        case "read_files":
            let paths = compactLines(input["paths"] as? [String] ?? [])
            if let onlyPath = paths.only {
                return "Reading \(onlyPath)"
            }
            if !paths.isEmpty {
                return "Reading \(paths.count) files"
            }
            return "Reading files"
        case "delete_file":
            return path.isEmpty ? "Deleting file" : "Deleting \(path)"
        case "list_files":
            let pattern = compactLine(input["pattern"] as? String)
            return pattern.isEmpty ? "Listing project files" : "Listing files matching \(pattern)"
        case "search_files":
            let pattern = compactLine(input["pattern"] as? String)
            return pattern.isEmpty ? "Searching project files" : "Searching code for \(pattern)"
        case "web_search":
            let query = compactLine(input["query"] as? String)
            return query.isEmpty ? "Researching on the web" : "Researching \(query)"
        case "scrape_url":
            let url = compactLine(input["url"] as? String)
            return url.isEmpty ? "Reading web page" : "Reading \(trim(url, limit: 60))"
        case "ask_user":
            let questions = questionTexts(from: input)
            if let question = questions.only {
                return "Asking \(trim(question, limit: 60))"
            }
            if !questions.isEmpty {
                return "Asking \(questions.count) questions"
            }
            return "Asking a question"
        case "set_project_identity":
            let projectName = compactLine(input["name"] as? String)
            return projectName.isEmpty ? "Updating project identity" : "Naming project \(projectName)"
        case "update_project_status":
            let hasPlan = !(compactLine(input["plan"] as? String).isEmpty)
            let hasTasks = !(compactLine(input["tasks"] as? String).isEmpty)
            switch (hasPlan, hasTasks) {
            case (true, true): return "Updating plan and tasks"
            case (true, false): return "Updating plan"
            case (false, true): return "Updating tasks"
            case (false, false): return "Updating project status"
            }
        case "update_project_dependencies":
            let dependencies = input["dependencies"] as? [[String: Any]] ?? []
            if dependencies.isEmpty {
                return "Confirming no setup requirements"
            }
            return dependencies.count == 1
                ? "Updating 1 dependency requirement"
                : "Updating \(dependencies.count) dependency requirements"
        case "update_app_store_assets", "update_app_store_review_assets":
            let assets = compactLines(input["assets"] as? [String] ?? [])
            if let onlyAsset = assets.only {
                return "Updating App Store \(onlyAsset)"
            }
            if !assets.isEmpty {
                return "Updating App Store assets"
            }
            return "Generating App Store assets"
        case "list_screens":
            return "Listing screens"
        case "update_app_store_details":
            let screenshots = input["screenshots"] as? [[String: Any]] ?? []
            let hasDescription = input["description"] != nil
            switch (hasDescription, screenshots.isEmpty) {
            case (true, false):
                return "Updating App Store description and \(screenshots.count) screenshots"
            case (true, true):
                return "Updating App Store description"
            case (false, false):
                return "Updating \(screenshots.count) App Store screenshots"
            case (false, true):
                return "Updating App Store details"
            }
        case "run_command":
            let command = compactLine(input["command"] as? String)
            return command.isEmpty ? "Running command" : "Running \(trim(command, limit: 60))"
        case "change_mode":
            let mode = compactLine(input["mode"] as? String)
            return mode.isEmpty ? "Switching modes" : "Switching to \(mode.capitalized) mode"
        case "list_skills":
            return "Reviewing skill library"
        case "use_skill":
            let skillName = compactLine(input["name"] as? String)
            return skillName.isEmpty ? "Learning skill" : "Learning \(skillName)"
        case "backend_manage":
            let action = compactLine(input["action"] as? String)
            let functionName = compactLine(input["function_name"] as? String)
            switch action {
            case "status":
                return "Reviewing backend status"
            case "link_provider":
                return "Linking Supabase backend"
            case "upsert_function":
                return functionName.isEmpty ? "Updating backend function" : "Updating \(functionName)"
            case "deploy":
                return functionName.isEmpty ? "Deploying backend function" : "Deploying \(functionName)"
            case "invoke":
                return functionName.isEmpty ? "Invoking backend function" : "Invoking \(functionName)"
            case "set_secret":
                let secretName = compactLine(input["secret_name"] as? String)
                return secretName.isEmpty ? "Updating backend secret" : "Updating secret \(secretName)"
            case "list_logs":
                return functionName.isEmpty ? "Reviewing backend logs" : "Reviewing logs for \(functionName)"
            default:
                return "Managing backend"
            }
        case "supabase_read_tables":
            let table = compactLine(input["table"] as? String)
            return table.isEmpty ? "Inspecting Supabase tables" : "Reading \(table)"
        case "supabase_write_tables":
            let operation = compactLine(input["operation"] as? String)
            let table = compactLine(input["table"] as? String)
            if operation.isEmpty && table.isEmpty { return "Writing Supabase data" }
            if table.isEmpty { return "Running Supabase \(operation)" }
            return "\(operation.capitalized) in \(table)"
        case "supabase_execute_sql":
            let sql = compactLine(input["sql"] as? String)
            return sql.isEmpty ? "Running Supabase SQL" : "Running \(trim(sql, limit: 60))"
        case "supabase_manage_settings":
            let action = compactLine(input["action"] as? String)
            return action.isEmpty ? "Managing Supabase settings" : "Running \(action)"
        case "superwall_manage":
            let action = compactLine(input["action"] as? String)
            let projectID = compactLine(input["project_id"] as? String)
            switch action {
            case "status":
                return "Reviewing Superwall status"
            case "bootstrap_project":
                return projectID.isEmpty ? "Linking Superwall project" : "Linking Superwall project \(projectID)"
            case "bootstrap_starter_monetization":
                return "Bootstrapping Superwall starter monetization"
            case "sync_preview_test_user":
                let previewUser = compactLine(input["preview_app_user_id"] as? String)
                return previewUser.isEmpty ? "Syncing Superwall preview user" : "Syncing \(previewUser)"
            case "list_paywalls":
                return "Reviewing Superwall paywalls"
            case "list_templates":
                return "Reviewing Superwall templates"
            case "open_dashboard":
                return "Opening Superwall dashboard"
            case "open_paywalls":
                return "Opening Superwall paywalls"
            case "open_templates":
                return "Opening Superwall templates"
            default:
                return "Managing Superwall"
            }
        default:
            return humanizedToolName(name)
        }
    }

    nonisolated static func generationStatus(
        name: String,
        input: [String: Any] = [:]
    ) -> BuilderGenerationStatus {
        let path = compactLine(input["path"] as? String)

        switch name {
        case "write_file":
            let detail = path.isEmpty
                ? "Applying the next code change."
                : "Applying the next change in \(trim(path, limit: 70))."
            return BuilderGenerationStatus(title: "Updating the project", detail: detail)
        case "edit_file":
            let detail = path.isEmpty
                ? "Making the next code change."
                : "Updating \(trim(path, limit: 70)) with the next change."
            return BuilderGenerationStatus(title: "Updating the project", detail: detail)
        case "delete_file":
            let detail = path.isEmpty
                ? "Removing a file from the project."
                : "Removing \(trim(path, limit: 70)) from the project."
            return BuilderGenerationStatus(title: "Updating the project", detail: detail)
        case "read_files":
            let paths = compactLines(input["paths"] as? [String] ?? [])
            let detail: String
            if let onlyPath = paths.only {
                detail = "Reading \(trim(onlyPath, limit: 70)) before I make changes."
            } else {
                detail = "Reading the relevant files before I make changes."
            }
            return BuilderGenerationStatus(title: "Inspecting the project", detail: detail)
        case "list_files":
            let pattern = compactLine(input["pattern"] as? String)
            let detail = pattern.isEmpty
                ? "Scanning the project structure to find the right files."
                : "Scanning the project for files matching \(trim(pattern, limit: 70))."
            return BuilderGenerationStatus(title: "Inspecting the project", detail: detail)
        case "search_files":
            let pattern = compactLine(input["pattern"] as? String)
            let detail = pattern.isEmpty
                ? "Searching the codebase for the right place to work."
                : "Finding where \(trim(pattern, limit: 70)) appears so I can make a targeted change."
            return BuilderGenerationStatus(title: "Inspecting the project", detail: detail)
        case "web_search":
            let query = compactLine(input["query"] as? String)
            let detail = query.isEmpty
                ? "Looking for the best outside reference before I continue."
                : "Looking up \(trim(query, limit: 72)) before I continue."
            return BuilderGenerationStatus(title: "Researching", detail: detail)
        case "scrape_url":
            let url = compactLine(input["url"] as? String)
            let detail = url.isEmpty
                ? "Pulling out the details I need from a reference page."
                : "Pulling out the details I need from \(trim(url, limit: 72))."
            return BuilderGenerationStatus(title: "Reading reference material", detail: detail)
        case "ask_user":
            return BuilderGenerationStatus(
                title: "Need your input",
                detail: "I have a question before I take the next step."
            )
        case "set_project_identity", "update_project_status", "update_project_dependencies", "change_mode", "update_app_store_assets", "update_app_store_review_assets":
            return BuilderGenerationStatus(
                title: "Updating project setup",
                detail: "Refreshing the plan, project details, or working mode."
            )
        case "list_screens":
            return BuilderGenerationStatus(
                title: "Inspecting screens",
                detail: "Reviewing the captured screens available for App Store assets."
            )
        case "update_app_store_details":
            return BuilderGenerationStatus(
                title: "Updating App Store assets",
                detail: "Saving the App Store description or screenshot set."
            )
        case "run_command":
            let command = compactLine(input["command"] as? String)
            let detail = command.isEmpty
                ? "Running a quick local check to verify the next step."
                : "Running a local check: \(trim(command, limit: 72))."
            return BuilderGenerationStatus(title: "Checking the result", detail: detail)
        case "list_skills", "use_skill":
            return BuilderGenerationStatus(
                title: "Reviewing guidance",
                detail: "Loading the instructions that match this request."
            )
        case "backend_manage":
            let action = compactLine(input["action"] as? String)
            let functionName = compactLine(input["function_name"] as? String)
            let detail: String
            switch action {
            case "status":
                detail = "Reviewing the managed backend setup for this project."
            case "link_provider":
                detail = "Linking the current project to the managed Supabase backend."
            case "upsert_function":
                detail = functionName.isEmpty
                    ? "Updating a named backend function in the workspace."
                    : "Updating the local \(trim(functionName, limit: 72)) backend function."
            case "deploy":
                detail = functionName.isEmpty
                    ? "Deploying backend changes to Supabase."
                    : "Deploying \(trim(functionName, limit: 72)) to Supabase."
            case "invoke":
                detail = functionName.isEmpty
                    ? "Running a backend smoke check."
                    : "Invoking \(trim(functionName, limit: 72)) for a backend smoke check."
            case "set_secret":
                detail = "Saving backend secrets without exposing them in the client app."
            case "list_logs":
                detail = "Reviewing recent backend logs."
            default:
                detail = "Working with the managed backend for this project."
            }
            return BuilderGenerationStatus(title: "Managing backend", detail: detail)
        case "supabase_read_tables":
            return BuilderGenerationStatus(
                title: "Reading Supabase",
                detail: "Inspecting the connected Supabase project."
            )
        case "supabase_write_tables":
            return BuilderGenerationStatus(
                title: "Updating Supabase",
                detail: "Applying a scoped data change in the connected Supabase project."
            )
        case "supabase_execute_sql":
            return BuilderGenerationStatus(
                title: "Running Supabase SQL",
                detail: "Applying schema or policy changes in the connected Supabase project."
            )
        case "supabase_manage_settings":
            return BuilderGenerationStatus(
                title: "Updating Supabase settings",
                detail: "Inspecting or changing the connected Supabase auth settings."
            )
        case "superwall_manage":
            let action = compactLine(input["action"] as? String)
            let detail: String
            switch action {
            case "status":
                detail = "Reviewing the linked Superwall project and runtime state."
            case "bootstrap_project":
                detail = "Creating or linking the Superwall project and iOS application for this builder project."
            case "bootstrap_starter_monetization":
                detail = "Creating starter Superwall products, placements, paywall, and preview-safe campaign rules."
            case "sync_preview_test_user":
                detail = "Marking the preview user for Superwall test mode."
            case "list_templates":
                detail = "Loading public Superwall paywall templates for the linked application."
            case "open_dashboard":
                detail = "Opening the linked Superwall dashboard."
            default:
                detail = "Working with the linked Superwall account."
            }
            return BuilderGenerationStatus(title: "Managing Superwall", detail: detail)
        default:
            return BuilderGenerationStatus(
                title: "Working in the project",
                detail: shortLabel(name: name).replacingOccurrences(of: "...", with: "")
            )
        }
    }

    nonisolated static func inputPreview(name: String, input: [String: Any]) -> String {
        let path = compactLine(input["path"] as? String)

        switch name {
        case "write_file":
            let content = input["content"] as? String ?? ""
            let lines = content.components(separatedBy: "\n").count
            return "path: \(path)\ncontent: (\(lines) lines, \(content.count) chars)"
        case "edit_file":
            let old = compactLine(input["old_string"] as? String)
            let new = compactLine(input["new_string"] as? String)
            return "path: \(path)\nold: \(trim(old, limit: 100))\nnew: \(trim(new, limit: 100))"
        case "read_files":
            let paths = compactLines(input["paths"] as? [String] ?? [])
            return "paths: \(paths.joined(separator: ", "))"
        case "delete_file":
            return "path: \(path)"
        case "list_files":
            let pattern = compactLine(input["pattern"] as? String)
            return pattern.isEmpty ? "scope: all project files" : "pattern: \(pattern)"
        case "search_files":
            var lines: [String] = []
            let pattern = compactLine(input["pattern"] as? String)
            if !pattern.isEmpty { lines.append("pattern: \(pattern)") }
            let filePattern = compactLine(input["file_pattern"] as? String)
            if !filePattern.isEmpty { lines.append("files: \(filePattern)") }
            if let caseSensitive = input["case_sensitive"] as? Bool {
                lines.append("case sensitive: \(caseSensitive ? "yes" : "no")")
            }
            return lines.joined(separator: "\n")
        case "run_command":
            return "command: \(compactLine(input["command"] as? String))"
        case "web_search":
            return "query: \(compactLine(input["query"] as? String))"
        case "scrape_url":
            return "url: \(compactLine(input["url"] as? String))"
        case "update_project_status":
            var parts: [String] = []
            if !compactLine(input["plan"] as? String).isEmpty { parts.append("plan") }
            if !compactLine(input["tasks"] as? String).isEmpty { parts.append("tasks") }
            return parts.isEmpty ? "status: no changes requested" : "updating: \(parts.joined(separator: ", "))"
        case "update_project_dependencies":
            let dependencies = input["dependencies"] as? [[String: Any]] ?? []
            if dependencies.isEmpty {
                return "dependencies: none"
            }
            let titles = dependencies.compactMap { compactLine($0["title"] as? String) }
            if titles.isEmpty {
                return "dependencies: \(dependencies.count)"
            }
            return "dependencies: \(titles.joined(separator: ", "))"
        case "update_app_store_assets", "update_app_store_review_assets":
            let assets = compactLines(input["assets"] as? [String] ?? [])
            var parts: [String] = []
            if !assets.isEmpty { parts.append("assets: \(assets.joined(separator: ", "))") }
            let brief = compactLine(input["brief"] as? String)
            if !brief.isEmpty { parts.append("brief: \(trim(brief, limit: 120))") }
            let sourceViewNames = compactLines(input["source_view_names"] as? [String] ?? [])
            if !sourceViewNames.isEmpty { parts.append("views: \(sourceViewNames.joined(separator: ", "))") }
            return parts.joined(separator: "\n")
        case "list_screens":
            return "scope: available screens"
        case "update_app_store_details":
            var parts: [String] = []
            if let description = input["description"] as? [String: Any] {
                let headline = compactLine(description["headline"] as? String)
                if !headline.isEmpty {
                    parts.append("headline: \(trim(headline, limit: 120))")
                } else {
                    parts.append("description: App Store copy")
                }
            }
            let screenshots = input["screenshots"] as? [[String: Any]] ?? []
            let ids = screenshots.compactMap { compactLine($0["sourceCaptureID"] as? String) }
            if !ids.isEmpty {
                parts.append("capture ids: \(ids.joined(separator: ", "))")
            } else if !screenshots.isEmpty {
                parts.append("screenshots: replacement set")
            }
            return parts.joined(separator: "\n")
        case "set_project_identity":
            var parts: [String] = []
            let projectName = compactLine(input["name"] as? String)
            if !projectName.isEmpty { parts.append("name: \(projectName)") }
            let imageFilename = compactLine(input["image_filename"] as? String)
            if !imageFilename.isEmpty { parts.append("icon: \(imageFilename)") }
            return parts.joined(separator: "\n")
        case "change_mode":
            var parts: [String] = []
            let mode = compactLine(input["mode"] as? String)
            if !mode.isEmpty { parts.append("mode: \(mode)") }
            let reason = compactLine(input["reason"] as? String)
            if !reason.isEmpty { parts.append("reason: \(reason)") }
            return parts.joined(separator: "\n")
        case "ask_user":
            return questionTexts(from: input)
                .enumerated()
                .map { index, question in
                    "\(index + 1). \(question)"
                }
                .joined(separator: "\n")
        case "list_skills":
            return "scope: all skills"
        case "use_skill":
            return "skill: \(compactLine(input["name"] as? String))"
        case "backend_manage":
            var parts: [String] = []
            let action = compactLine(input["action"] as? String)
            if !action.isEmpty { parts.append("action: \(action)") }
            let provider = compactLine(input["provider_id"] as? String)
            if !provider.isEmpty { parts.append("provider: \(provider)") }
            let functionName = compactLine(input["function_name"] as? String)
            if !functionName.isEmpty { parts.append("function: \(functionName)") }
            let secretName = compactLine(input["secret_name"] as? String)
            if !secretName.isEmpty { parts.append("secret: \(secretName)") }
            if input["secret_value"] != nil { parts.append("secret_value: [redacted]") }
            if let tail = input["tail"] {
                parts.append("tail: \(tail)")
            }
            return parts.joined(separator: "\n")
        case "supabase_read_tables":
            var parts: [String] = []
            let schema = compactLine(input["schema"] as? String)
            let table = compactLine(input["table"] as? String)
            if !schema.isEmpty { parts.append("schema: \(schema)") }
            if !table.isEmpty { parts.append("table: \(table)") }
            let columns = compactLines(input["columns"] as? [String] ?? [])
            if !columns.isEmpty { parts.append("columns: \(columns.joined(separator: ", "))") }
            if let limit = input["limit"] {
                parts.append("limit: \(limit)")
            }
            return parts.joined(separator: "\n")
        case "supabase_write_tables":
            var parts: [String] = []
            let schema = compactLine(input["schema"] as? String)
            if !schema.isEmpty { parts.append("schema: \(schema)") }
            parts.append("table: \(compactLine(input["table"] as? String))")
            parts.append("operation: \(compactLine(input["operation"] as? String))")
            return parts.joined(separator: "\n")
        case "supabase_execute_sql":
            return "sql: \(trim(compactLine(input["sql"] as? String), limit: 160))"
        case "supabase_manage_settings":
            return "action: \(compactLine(input["action"] as? String))"
        case "superwall_manage":
            var parts: [String] = []
            let action = compactLine(input["action"] as? String)
            if !action.isEmpty { parts.append("action: \(action)") }
            let organizationID = compactLine(input["organization_id"] as? String)
            if !organizationID.isEmpty { parts.append("organization: \(organizationID)") }
            let projectID = compactLine(input["project_id"] as? String)
            if !projectID.isEmpty { parts.append("project: \(projectID)") }
            let applicationID = compactLine(input["application_id"] as? String)
            if !applicationID.isEmpty { parts.append("application: \(applicationID)") }
            let paywallID = compactLine(input["paywall_id"] as? String)
            if !paywallID.isEmpty { parts.append("paywall: \(paywallID)") }
            let previewAppUserID = compactLine(input["preview_app_user_id"] as? String)
            if !previewAppUserID.isEmpty { parts.append("preview user: \(previewAppUserID)") }
            let placements = compactLines(input["placements"] as? [String] ?? [])
            if !placements.isEmpty { parts.append("placements: \(placements.joined(separator: ", "))") }
            return parts.joined(separator: "\n")
        default:
            return ""
        }
    }

    private nonisolated static func questionTexts(from input: [String: Any]) -> [String] {
        let questions = input["questions"] as? [[String: Any]] ?? []
        return questions.map { compactLine($0["question"] as? String) }.filter { !$0.isEmpty }
    }

    private nonisolated static func compactLines(_ values: [String]) -> [String] {
        values.map { compactLine($0) }.filter { !$0.isEmpty }
    }

    private nonisolated static func compactLine(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func trim(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(limit - 3, 0))) + "..."
    }

    private nonisolated static func humanizedToolName(_ name: String) -> String {
        name
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

struct BuilderToolStep: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let toolUseId: String?
    let name: String
    var label: String
    var status: BuilderToolStepStatus
    var durationMs: Int?
    var inputPreview: String?
    var outputPreview: String?

    init(
        id: UUID = UUID(),
        toolUseId: String? = nil,
        name: String,
        label: String,
        status: BuilderToolStepStatus,
        durationMs: Int? = nil,
        inputPreview: String? = nil,
        outputPreview: String? = nil
    ) {
        self.id = id
        self.toolUseId = toolUseId
        self.name = name
        self.label = label
        self.status = status
        self.durationMs = durationMs
        self.inputPreview = inputPreview
        self.outputPreview = outputPreview
    }

    var category: BuilderToolCategory {
        BuilderToolCategory(toolName: name)
    }
}

struct BuilderToolStepGroup: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let steps: [BuilderToolStep]

    init(steps: [BuilderToolStep]) {
        self.id = steps.first?.id ?? UUID()
        self.name = steps.first?.name ?? ""
        self.steps = steps
    }
}

extension Array where Element == BuilderToolStep {
    nonisolated var contiguousToolGroups: [BuilderToolStepGroup] {
        guard let first else { return [] }

        var groups: [BuilderToolStepGroup] = []
        var currentSteps: [BuilderToolStep] = [first]

        for step in dropFirst() {
            if step.name == currentSteps.last?.name {
                currentSteps.append(step)
            } else {
                groups.append(BuilderToolStepGroup(steps: currentSteps))
                currentSteps = [step]
            }
        }

        groups.append(BuilderToolStepGroup(steps: currentSteps))
        return groups
    }
}

private extension Array {
    nonisolated var only: Element? {
        count == 1 ? first : nil
    }
}

extension BuilderMessage {
    private nonisolated static let modeSwitchRestartPrefix = "[Mode switched to "
    private nonisolated static let modeSwitchRestartSuffix = ". Continue with the current plan and files. Do not re-ask questions or switch modes.]"
    private nonisolated static let projectRenameRestartPrefix = "[Project renamed to "
    private nonisolated static let projectRenameRestartSuffix = ". Continue with the current plan and files. Do not rename it again unless asked.]"

    nonisolated var restartNoteSystemEvent: BuilderSystemEvent? {
        guard role == "user" else { return nil }

        if content.hasPrefix(Self.modeSwitchRestartPrefix), content.hasSuffix(Self.modeSwitchRestartSuffix) {
            let start = content.index(content.startIndex, offsetBy: Self.modeSwitchRestartPrefix.count)
            let end = content.index(content.endIndex, offsetBy: -Self.modeSwitchRestartSuffix.count)
            let modeLabel = String(content[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modeLabel.isEmpty else { return nil }
            return BuilderSystemEvent(
                id: id,
                kind: .modeChange,
                title: "Mode switched to \(modeLabel)",
                detail: "Continuing with refreshed project context."
            )
        }

        if content.hasPrefix(Self.projectRenameRestartPrefix), content.hasSuffix(Self.projectRenameRestartSuffix) {
            let start = content.index(content.startIndex, offsetBy: Self.projectRenameRestartPrefix.count)
            let end = content.index(content.endIndex, offsetBy: -Self.projectRenameRestartSuffix.count)
            let name = String(content[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return BuilderSystemEvent(
                id: id,
                kind: .projectRename,
                title: "Project renamed to \(name)",
                detail: "Continuing with refreshed project context."
            )
        }

        return nil
    }

    nonisolated var isInternalRestartNote: Bool {
        restartNoteSystemEvent != nil
    }

    /// Returns content safe for display by stripping internal <tool_history> blocks
    /// and trimming surrounding whitespace. Centralized so chat views can reuse it.
    nonisolated var displayableContent: String {
        content.replacingOccurrences(
            of: #"(?:^|\n)\s*<tool_history>[\s\S]*?</tool_history>"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var hasVisibleContent: Bool {
        !displayableContent.isEmpty || !attachments.isEmpty
    }

    nonisolated var attachmentSummaryText: String? {
        guard !attachments.isEmpty else { return nil }
        if attachments.count == 1, let first = attachments.first {
            return "Attached \(first.displayKind.lowercased()): \(first.filename)"
        }
        let names = attachments.prefix(3).map(\.filename).joined(separator: ", ")
        let suffix = attachments.count > 3 ? ", +\(attachments.count - 3) more" : ""
        return "Attached \(attachments.count) files: \(names)\(suffix)"
    }

    nonisolated var requiredSkillTags: [String] {
        requiredSkillNames.map { "/\($0)" }
    }

    nonisolated var requiredSkillsSummaryText: String? {
        guard !requiredSkillTags.isEmpty else { return nil }
        return "Required skills: \(requiredSkillTags.joined(separator: ", "))"
    }

    nonisolated var previewText: String? {
        let normalized = displayableContent
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            return normalized
        }
        return requiredSkillsSummaryText ?? attachmentSummaryText
    }

    nonisolated var titleInputText: String? {
        previewText
    }

    nonisolated private var contentWithAttachmentSummary: String {
        var sections: [String] = []

        let text = displayableContent
        if !text.isEmpty {
            sections.append(text)
        }

        if let requiredSkillsSummaryText {
            sections.append(requiredSkillsSummaryText)
        }

        if !attachments.isEmpty {
            sections.append("Attachments:\n\(attachments.map { "- \($0.transcriptSummaryLine)" }.joined(separator: "\n"))")
        }

        return sections.joined(separator: "\n\n")
    }

    nonisolated var copyableContent: String { contentWithAttachmentSummary }

    nonisolated var transcriptContent: String { contentWithAttachmentSummary }

    nonisolated func claudeMessageContent() -> Any {
        guard role == "user" else {
            return content
        }

        let skillDirective = requiredSkillsPromptDirective
        let messageText = displayableContent
        let combinedText: String
        if let skillDirective, !messageText.isEmpty {
            combinedText = "\(skillDirective)\n\n\(messageText)"
        } else if let skillDirective {
            combinedText = skillDirective
        } else {
            combinedText = messageText
        }

        guard !attachments.isEmpty else {
            return combinedText
        }

        var blocks: [[String: Any]] = []
        if !combinedText.isEmpty {
            blocks.append([
                "type": "text",
                "text": combinedText,
            ])
        } else {
            blocks.append([
                "type": "text",
                "text": "The user attached file(s) with no additional text.",
            ])
        }

        for attachment in attachments {
            blocks.append(contentsOf: attachment.claudeContentBlocks())
        }

        return blocks
    }

    nonisolated private var requiredSkillsPromptDirective: String? {
        guard role == "user", !requiredSkillTags.isEmpty else { return nil }
        return "User explicitly tagged required skills for this request: \(requiredSkillTags.joined(separator: ", ")). Apply those skills as mandatory guidance."
    }
}
