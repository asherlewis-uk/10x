import Foundation

/// Executes builder tools against the real filesystem.
/// Replaces the API's in-memory file_tree execution with real disk I/O.
actor ToolExecutor {
    private let maxReadFileChars = 40_000
    private let maxReadFilesTotalChars = 60_000
    private let blockedWorkspacePathComponents: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "Build",
        "DerivedData",
        "SourcePackages",
        "Pods",
        "node_modules",
        "tenx",
    ]

    /// The editable workspace root for this session.
    let workspaceRoot: URL

    /// The current project name for this generation session.
    private var projectName: String

    /// The target name used by XcodeGen (e.g. "MyApp").
    /// Source files live under ios/{targetName}/.
    let targetName: String

    /// The active builder mode for this generation session.
    let currentMode: ProjectMode

    /// In-memory file tree kept in sync with disk for Claude context.
    /// Keys are relative paths (e.g. "Views/HomeView.swift").
    private(set) var fileTree: [String: String]

    /// Tracks which files changed during this generation session.
    private(set) var filesChanged: Set<String> = []

    /// Closures to execute external research tools via the API (keeps auth/networking out of this actor).
    private let webSearchHandler: (@Sendable (String) async -> String)?
    private let urlScrapeHandler: (@Sendable (String) async -> String)?
    private let projectIdentityHandler: (@Sendable (String, String?) async -> String)?
    private let appStoreReviewHandler: (@Sendable (AppStoreReviewToolInput) async -> String)?
    private let appStoreDetailsUpdateHandler: (@Sendable (AppStoreDetailsUpdateInput) async -> String)?
    private let screenCatalogHandler: (@Sendable () async -> String)?
    private let environmentVariables: [String: String]
    private let environmentVariableMetadata: [ProjectEnvironmentVariable]
    private var projectBackendState: ProjectBackendState
    private var projectSuperwallState: ProjectSuperwallState

    /// Closures for skill tool operations (list, use).
    private let skillsListHandler: (@Sendable () async -> String)?
    private let skillsUseHandler: (@Sendable (String) async -> String)?
    private let supabaseToolHandlers: SupabaseToolHandlers?
    private let backendToolHandlers: BackendToolHandlers?
    private let superwallToolHandlers: SuperwallToolHandlers?
    private var approvedIntegrationScopes: [String: Set<String>] = [:]

    init(
        workspaceRoot: URL,
        projectName: String,
        targetName: String,
        currentMode: ProjectMode,
        fileTree: [String: String] = [:],
        environmentVariables: [String: String] = [:],
        environmentVariableMetadata: [ProjectEnvironmentVariable] = [],
        projectBackendState: ProjectBackendState = .empty,
        projectSuperwallState: ProjectSuperwallState = .empty,
        webSearchHandler: (@Sendable (String) async -> String)? = nil,
        urlScrapeHandler: (@Sendable (String) async -> String)? = nil,
        projectIdentityHandler: (@Sendable (String, String?) async -> String)? = nil,
        appStoreReviewHandler: (@Sendable (AppStoreReviewToolInput) async -> String)? = nil,
        appStoreDetailsUpdateHandler: (@Sendable (AppStoreDetailsUpdateInput) async -> String)? = nil,
        screenCatalogHandler: (@Sendable () async -> String)? = nil,
        skillsListHandler: (@Sendable () async -> String)? = nil,
        skillsUseHandler: (@Sendable (String) async -> String)? = nil,
        supabaseToolHandlers: SupabaseToolHandlers? = nil,
        backendToolHandlers: BackendToolHandlers? = nil,
        superwallToolHandlers: SuperwallToolHandlers? = nil
    ) {
        self.workspaceRoot = workspaceRoot
        self.projectName = projectName
        self.targetName = targetName
        self.currentMode = currentMode
        self.fileTree = fileTree
        self.environmentVariables = environmentVariables
        self.environmentVariableMetadata = environmentVariableMetadata
        self.projectBackendState = projectBackendState
        self.projectSuperwallState = projectSuperwallState
        self.webSearchHandler = webSearchHandler
        self.urlScrapeHandler = urlScrapeHandler
        self.projectIdentityHandler = projectIdentityHandler
        self.appStoreReviewHandler = appStoreReviewHandler
        self.appStoreDetailsUpdateHandler = appStoreDetailsUpdateHandler
        self.screenCatalogHandler = screenCatalogHandler
        self.skillsListHandler = skillsListHandler
        self.skillsUseHandler = skillsUseHandler
        self.supabaseToolHandlers = supabaseToolHandlers
        self.backendToolHandlers = backendToolHandlers
        self.superwallToolHandlers = superwallToolHandlers
    }

    /// The directory where file tools operate.
    private var sourcesDir: URL {
        workspaceRoot
    }

    /// Reset change tracking for a new generation session.
    func resetChanges() {
        filesChanged = []
    }

    /// Execute a tool and return the result text for Claude.
    func execute(toolName: String, input: [String: Any]) async -> ToolResult {
        switch toolName {
        case "write_file":
            return executeWriteFile(input)
        case "edit_file":
            return executeEditFile(input)
        case "read_files":
            return executeReadFiles(input)
        case "delete_file":
            return executeDeleteFile(input)
        case "list_files":
            return executeListFiles(input)
        case "search_files":
            return executeSearchFiles(input)
        case "run_command":
            return await executeRunCommand(input)
        case "update_project_status":
            return ToolResult(text: "Project status saved successfully.", fileEvent: nil)
        case "update_project_dependencies":
            return executeUpdateProjectDependencies(input)
        case "set_project_identity":
            return await executeSetProjectIdentity(input)
        case "update_app_store_assets", "update_app_store_review_assets":
            return await executeAppStoreReviewAssets(input)
        case "list_screens":
            return await executeListScreens()
        case "update_app_store_details":
            return await executeUpdateAppStoreDetails(input)
        case "change_mode":
            return executeChangeMode(input)
        case "web_search":
            return await executeWebSearch(input)
        case "scrape_url":
            return await executeScrapeURL(input)
        case "list_skills":
            return await executeListSkills()
        case "use_skill":
            return await executeUseSkill(input)
        case "supabase_read_tables":
            return await executeSupabaseReadTables(input)
        case "supabase_write_tables":
            return await executeSupabaseWriteTables(input)
        case "supabase_execute_sql":
            return await executeSupabaseExecuteSQL(input)
        case "supabase_manage_settings":
            return await executeSupabaseManageSettings(input)
        case "backend_manage":
            return await executeBackendManage(input)
        case "superwall_manage":
            return ToolResult(text: "Superwall is not available in 11x local cockpit.", fileEvent: nil)
        default:
            return ToolResult(text: "Unknown tool: \(toolName)", fileEvent: nil)
        }
    }

    // MARK: - File Tools

    private func executeUpdateProjectDependencies(_ input: [String: Any]) -> ToolResult {
        guard ProjectDependencyManifest(toolInput: input) != nil else {
            return ToolResult(
                text: "Error: dependency payload must include a valid `dependencies` array.",
                fileEvent: nil
            )
        }

        return ToolResult(text: "Project dependencies saved successfully.", fileEvent: nil)
    }

    private func executeWriteFile(_ input: [String: Any]) -> ToolResult {
        let path = input["path"] as? String ?? ""
        let content = input["content"] as? String ?? ""
        if let validationError = validateWorkspacePath(path) {
            return ToolResult(text: validationError, fileEvent: nil)
        }
        let existed = fileTree[path] != nil

        fileTree[path] = content
        filesChanged.insert(path)
        writeToDisk(path: path, content: content)

        let action = existed ? "update" : "create"
        let verb = existed ? "Updated" : "Created"
        return ToolResult(text: "\(verb) \(path) (\(content.count) chars)", fileEvent: FileEvent(path: path, content: content, action: action))
    }

    private func executeEditFile(_ input: [String: Any]) -> ToolResult {
        let path = input["path"] as? String ?? ""
        let oldString = input["old_string"] as? String ?? ""
        let newString = input["new_string"] as? String ?? ""

        guard !path.isEmpty else {
            return ToolResult(text: "Error: path is required.", fileEvent: nil)
        }
        if let validationError = validateWorkspacePath(path) {
            return ToolResult(text: validationError, fileEvent: nil)
        }
        guard let content = fileTree[path] else {
            let available = fileTree.keys.sorted().joined(separator: ", ")
            return ToolResult(text: "Error: \(path) not found. Available files: \(available.isEmpty ? "(empty project)" : available)", fileEvent: nil)
        }
        guard !oldString.isEmpty else {
            return ToolResult(text: "Error: old_string is required.", fileEvent: nil)
        }
        guard oldString != newString else {
            return ToolResult(text: "Error: new_string must be different from old_string.", fileEvent: nil)
        }

        let count = content.components(separatedBy: oldString).count - 1

        if count == 0 {
            let hint = findSimilarStrings(in: content, target: oldString)
            return ToolResult(
                text: "Error: old_string not found in \(path). The text must match exactly (including whitespace/indentation).\(hint)",
                fileEvent: nil
            )
        }

        if count > 1 {
            return ToolResult(
                text: "Error: old_string matches \(count) locations in \(path). Include more surrounding context in old_string to make it unique.",
                fileEvent: nil
            )
        }

        // Exactly one match — apply the edit
        let newContent = content.replacingOccurrences(of: oldString, with: newString)
        fileTree[path] = newContent
        filesChanged.insert(path)
        writeToDisk(path: path, content: newContent)

        let oldLines = oldString.components(separatedBy: "\n").count
        let newLines = newString.components(separatedBy: "\n").count
        let text = "Edited \(path): replaced \(oldLines) line\(oldLines != 1 ? "s" : "") with \(newLines) line\(newLines != 1 ? "s" : "")"
        return ToolResult(text: text, fileEvent: FileEvent(path: path, content: newContent, action: "update"))
    }

    private func executeReadFiles(_ input: [String: Any]) -> ToolResult {
        let paths = input["paths"] as? [String] ?? []
        guard !paths.isEmpty else {
            return ToolResult(text: "Error: paths array is required and must not be empty.", fileEvent: nil)
        }

        if paths.count == 1 {
            return readSingleFile(paths[0], maxChars: maxReadFileChars)
        }

        var sections: [String] = []
        var remainingChars = maxReadFilesTotalChars
        var remainingFiles = paths.count
        for path in paths {
            let perFileBudget = max(8_000, remainingChars / max(remainingFiles, 1))
            let result = readSingleFile(path, maxChars: min(maxReadFileChars, perFileBudget))
            sections.append("--- \(path) ---\n\(result.text)")
            remainingChars = max(0, remainingChars - result.text.count)
            remainingFiles -= 1
            if remainingChars <= 0 { break }
        }
        return ToolResult(text: sections.joined(separator: "\n\n"), fileEvent: nil)
    }

    private func readSingleFile(_ path: String, maxChars: Int) -> ToolResult {
        if let validationError = validateWorkspacePath(path) {
            return ToolResult(text: validationError, fileEvent: nil)
        }

        if let content = fileTree[path] {
            return ToolResult(text: renderReadResult(path: path, content: content, maxChars: maxChars), fileEvent: nil)
        }

        guard let fileURL = resolvedWorkspaceFileURL(for: path) else {
            return ToolResult(
                text: "Error: \(path) is outside the readable project workspace or points to generated metadata/build artifacts.",
                fileEvent: nil
            )
        }
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            if content.count <= maxReadFileChars {
                fileTree[path] = content
            }
            return ToolResult(text: renderReadResult(path: path, content: content, maxChars: maxChars), fileEvent: nil)
        }

        let available = fileTree.keys.sorted().joined(separator: ", ")
        return ToolResult(text: "Error: \(path) not found. Available files: \(available.isEmpty ? "(empty project)" : available)", fileEvent: nil)
    }

    private func executeDeleteFile(_ input: [String: Any]) -> ToolResult {
        let path = input["path"] as? String ?? ""
        if let validationError = validateWorkspacePath(path) {
            return ToolResult(text: validationError, fileEvent: nil)
        }
        guard fileTree[path] != nil else {
            return ToolResult(text: "Error: \(path) not found.", fileEvent: nil)
        }
        fileTree.removeValue(forKey: path)
        filesChanged.insert(path)
        deleteFromDisk(path: path)
        return ToolResult(text: "Deleted \(path)", fileEvent: FileEvent(path: path, content: "", action: "delete"))
    }

    private func executeListFiles(_ input: [String: Any]) -> ToolResult {
        let pattern = (input["pattern"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let allPaths = fileTree.keys.sorted()

        if allPaths.isEmpty {
            return ToolResult(text: "Project is empty. No files yet.", fileEvent: nil)
        }

        if pattern.isEmpty {
            let text = "Files in project:\n" + allPaths.map { "- \($0)" }.joined(separator: "\n")
            return ToolResult(text: text, fileEvent: nil)
        }

        let matched = allPaths.filter { matchGlob(path: $0, pattern: pattern) }
        if matched.isEmpty {
            let available = allPaths.joined(separator: ", ")
            return ToolResult(text: "No files matching '\(pattern)'. Available: \(available)", fileEvent: nil)
        }
        return ToolResult(text: "Found \(matched.count) file\(matched.count != 1 ? "s" : ""):\n" + matched.map { "- \($0)" }.joined(separator: "\n"), fileEvent: nil)
    }

    private func executeSearchFiles(_ input: [String: Any]) -> ToolResult {
        let pattern = input["pattern"] as? String ?? ""
        let filePattern = input["file_pattern"] as? String
        let caseSensitive = input["case_sensitive"] as? Bool ?? true

        guard !pattern.isEmpty else {
            return ToolResult(text: "Error: pattern is required.", fileEvent: nil)
        }

        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return ToolResult(text: "Error: invalid regex pattern.", fileEvent: nil)
        }

        var matches: [String] = []
        for path in fileTree.keys.sorted() {
            if let fp = filePattern, !matchGlob(path: path, pattern: fp) { continue }
            guard let content = fileTree[path] else { continue }
            let lines = content.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    matches.append("\(path):\(i + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    if matches.count >= 100 { break }
                }
            }
            if matches.count >= 100 { break }
        }

        if matches.isEmpty {
            let scope = filePattern.map { " in files matching '\($0)'" } ?? ""
            return ToolResult(text: "No matches found for '\(pattern)'\(scope).", fileEvent: nil)
        }

        var header = "Found \(matches.count) match\(matches.count != 1 ? "es" : "") for '\(pattern)':"
        if matches.count >= 100 { header += " (truncated at 100)" }
        return ToolResult(text: header + "\n" + matches.joined(separator: "\n"), fileEvent: nil)
    }


    // MARK: - Run Command

    private func executeRunCommand(_ input: [String: Any]) async -> ToolResult {
        let command = input["command"] as? String ?? ""

        // Block dangerous commands
        let blocked = ["rm -rf /", "sudo", "mkfs", "dd if=", ":(){"]
        let cmdLower = command.lowercased()
        for b in blocked {
            if cmdLower.contains(b) {
                return ToolResult(text: "Error: command blocked for safety: \(b)", fileEvent: nil)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = sourcesDir
        process.environment = ProcessInfo.processInfo.environment.merging(environmentVariables) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()

            let deadline = DispatchTime.now() + .seconds(30)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                group.leave()
            }
            if group.wait(timeout: deadline) == .timedOut {
                process.terminate()
                return ToolResult(text: "Error: command timed out after 30 seconds.", fileEvent: nil)
            }

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

            let maxChars = 5000
            var output = ""
            if !stdoutStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output += "stdout:\n\(String(stdoutStr.prefix(maxChars)))\n"
            }
            if !stderrStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output += "stderr:\n\(String(stderrStr.prefix(maxChars)))\n"
            }
            output += "\nexit code: \(process.terminationStatus)"
            return ToolResult(text: output.isEmpty ? "Command completed with exit code \(process.terminationStatus)" : output, fileEvent: nil)
        } catch {
            return ToolResult(text: "Error running command: \(error.localizedDescription)", fileEvent: nil)
        }
    }

    // MARK: - Web Search

    private func executeWebSearch(_ input: [String: Any]) async -> ToolResult {
        let query = input["query"] as? String ?? ""
        guard !query.isEmpty else {
            return ToolResult(text: "Error: query is required.", fileEvent: nil)
        }
        guard let handler = webSearchHandler else {
            return ToolResult(text: "Web search is not configured.", fileEvent: nil)
        }
        let result = await handler(query)
        return ToolResult(text: result, fileEvent: nil)
    }

    private func executeScrapeURL(_ input: [String: Any]) async -> ToolResult {
        let url = input["url"] as? String ?? ""
        guard !url.isEmpty else {
            return ToolResult(text: "Error: url is required.", fileEvent: nil)
        }
        guard let handler = urlScrapeHandler else {
            return ToolResult(text: "URL scraping is not configured.", fileEvent: nil)
        }
        let result = await handler(url)
        return ToolResult(text: result, fileEvent: nil)
    }

    private func executeSetProjectIdentity(_ input: [String: Any]) async -> ToolResult {
        let name = (input["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawImageFilename = (input["image_filename"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let imageFilename = rawImageFilename.isEmpty ? nil : rawImageFilename
        guard !name.isEmpty else {
            return ToolResult(text: "Error: name is required.", fileEvent: nil)
        }
        guard let handler = projectIdentityHandler else {
            return ToolResult(text: "Project identity updates are not configured.", fileEvent: nil)
        }
        let previousName = projectName
        let resultText = await handler(name, imageFilename)
        projectName = name
        let refresh: ToolContextRefresh? = name != previousName
            ? .projectIdentityChange(name: name)
            : nil
        return ToolResult(text: resultText, fileEvent: nil, contextRefresh: refresh)
    }

    private func executeAppStoreReviewAssets(_ input: [String: Any]) async -> ToolResult {
        guard let handler = appStoreReviewHandler else {
            return ToolResult(text: "App Store asset updates are not configured.", fileEvent: nil)
        }
        let screenshotAction = AppStoreReviewScreenshotAction(
            rawValue: ((input["screenshot_action"] as? String) ?? "").lowercased()
        )
        let reviewInput = AppStoreReviewToolInput(
            assets: input["assets"] as? [String] ?? [],
            brief: input["brief"] as? String,
            sourceViewNames: input["source_view_names"] as? [String] ?? [],
            applyIconToProject: input["apply_icon_to_project"] as? Bool ?? true,
            screenshotAction: screenshotAction,
            screenshotPosition: intValue(input["screenshot_position"]),
            moveToPosition: intValue(input["move_to_position"])
        )
        let result = await handler(reviewInput)
        return ToolResult(text: result, fileEvent: nil)
    }

    private func executeListScreens() async -> ToolResult {
        guard let handler = screenCatalogHandler else {
            return ToolResult(text: "Screen listing is not configured.", fileEvent: nil)
        }
        let result = await handler()
        return ToolResult(text: result, fileEvent: nil)
    }

    private func executeUpdateAppStoreDetails(_ input: [String: Any]) async -> ToolResult {
        guard let handler = appStoreDetailsUpdateHandler else {
            return ToolResult(text: "App Store details updates are not configured.", fileEvent: nil)
        }
        guard let update: AppStoreDetailsUpdateInput = decodeToolValue(input) else {
            return ToolResult(text: "Error: the App Store details input must match the schema exactly.", fileEvent: nil)
        }
        let hasDescription = update.description != nil
        let hasScreenshots = !(update.screenshots?.isEmpty ?? true)
        guard hasDescription || hasScreenshots else {
            return ToolResult(text: "Error: provide a description, screenshots, or both.", fileEvent: nil)
        }
        let result = await handler(update)
        return ToolResult(text: result, fileEvent: nil)
    }

    private func executeChangeMode(_ input: [String: Any]) -> ToolResult {
        let requestedMode = ProjectMode(rawValue: input["mode"] as? String ?? "") ?? .build
        guard requestedMode != currentMode else {
            return ToolResult(
                text: "Mode is already '\(requestedMode.rawValue)'. Continue in the current context without restarting.",
                fileEvent: nil
            )
        }

        return ToolResult(
            text: "Mode changed to '\(requestedMode.rawValue)'. The session will restart with the \(requestedMode.rawValue) mode context and updated file tree.",
            fileEvent: nil,
            contextRefresh: .modeChange(mode: requestedMode.rawValue)
        )
    }

    // MARK: - Skills

    private func executeListSkills() async -> ToolResult {
        guard let handler = skillsListHandler else {
            return ToolResult(text: "Skills are not configured.", fileEvent: nil)
        }
        let result = await handler()
        return ToolResult(text: result, fileEvent: nil)
    }

    private func executeUseSkill(_ input: [String: Any]) async -> ToolResult {
        let name = input["name"] as? String ?? ""
        guard !name.isEmpty else {
            return ToolResult(text: "Error: name is required.", fileEvent: nil)
        }
        guard let handler = skillsUseHandler else {
            return ToolResult(text: "Skills are not configured.", fileEvent: nil)
        }
        let result = await handler(name)
        return ToolResult(text: result, fileEvent: nil)
    }

    // MARK: - Integration Tools

    private func executeSupabaseReadTables(_ input: [String: Any]) async -> ToolResult {
        await executeSupabaseTool(input, decodeError: "Error: the Supabase read input must match the schema exactly.") { handlers, request in
            try await handlers.read(request)
        }
    }

    private func executeSupabaseWriteTables(_ input: [String: Any]) async -> ToolResult {
        await executeSupabaseTool(
            input,
            decodeError: "Error: the Supabase write input must match the schema exactly.",
            approvalResult: { [self] request in
                guard !self.hasIntegrationApproval(integration: "supabase", scope: "write") else {
                    return nil
                }
                return self.approvalRequiredResult(
                    integration: "Supabase",
                    scope: "write",
                    action: "change rows in `\(request.table)`"
                )
            }
        ) { handlers, request in
            try await handlers.write(request)
        }
    }

    private func executeSupabaseExecuteSQL(_ input: [String: Any]) async -> ToolResult {
        await executeSupabaseTool(
            input,
            decodeError: "Error: the Supabase SQL input must match the schema exactly.",
            approvalResult: { [self] (_: SupabaseExecuteSQLInput) in
                guard !self.hasIntegrationApproval(integration: "supabase", scope: "write") else {
                    return nil
                }
                return self.approvalRequiredResult(
                    integration: "Supabase",
                    scope: "write",
                    action: "run SQL in the connected Supabase project"
                )
            }
        ) { handlers, request in
            try await handlers.sql(request)
        }
    }

    private func executeSupabaseManageSettings(_ input: [String: Any]) async -> ToolResult {
        await executeSupabaseTool(
            input,
            decodeError: "Error: the Supabase settings input must match the schema exactly.",
            approvalResult: { [self] request in
                guard (request.action ?? .describeAuth) != .describeAuth else {
                    return nil
                }
                guard !self.hasIntegrationApproval(integration: "supabase", scope: "settings") else {
                    return nil
                }
                return self.approvalRequiredResult(
                    integration: "Supabase",
                    scope: "settings",
                    action: "change Supabase auth settings"
                )
            }
        ) { handlers, request in
            try await handlers.settings(request)
        }
    }

    private func executeBackendManage(_ input: [String: Any]) async -> ToolResult {
        guard let handlers = backendToolHandlers else {
            return backendUnavailableResult()
        }
        guard let request: BackendManageInput = decodeToolValue(input) else {
            return ToolResult(text: "Error: the backend input must match the schema exactly.", fileEvent: nil)
        }

        switch request.action {
        case .status:
            do {
                let snapshot = try await handlers.status()
                projectBackendState = projectBackendState
                    .merging(snapshot: snapshot)
                    .markingStatusRefreshed(at: Self.timestamp())
                await handlers.persistState(projectBackendState)
                return ToolResult(text: renderBackendStatus(), fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .linkProvider:
            do {
                let link = try await handlers.linkProvider()
                projectBackendState = projectBackendState.linking(to: link)
                projectBackendState = projectBackendState.appendingLog(
                    .init(timestamp: Self.timestamp(), message: "Linked \(link.providerID.title) backend.", functionName: nil)
                )
                await handlers.persistState(projectBackendState)
                return ToolResult(text: "Linked \(link.providerID.title) backend to project `\(link.projectRef)`.", fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .upsertFunction:
            let functionName = normalizedFunctionName(request.functionName)
            let sourceCode = (request.sourceCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !functionName.isEmpty else {
                return ToolResult(text: "Error: `function_name` is required for `upsert_function`.", fileEvent: nil)
            }
            guard !sourceCode.isEmpty else {
                return ToolResult(text: "Error: `source_code` is required for `upsert_function`.", fileEvent: nil)
            }

            let verifyJWT = request.verifyJWT ?? true
            let sourcePath = "supabase/functions/\(functionName)/index.ts"
            let configPath = "supabase/config.toml"
            let docsPath = "SUPABASE_BACKEND.md"
            let summary = (request.summary ?? "Managed backend endpoint for \(functionName).")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            upsertWorkspaceFile(path: sourcePath, content: sourceCode)
            upsertWorkspaceFile(
                path: configPath,
                content: mergedSupabaseConfig(existing: readWorkspaceFile(path: configPath), functionName: functionName, verifyJWT: verifyJWT)
            )
            upsertWorkspaceFile(path: docsPath, content: backendDocumentation(existing: readWorkspaceFile(path: docsPath)))

            projectBackendState = projectBackendState.upsertingFunction(
                .init(
                    name: functionName,
                    summary: summary.isEmpty ? "Managed backend endpoint." : summary,
                    verifyJWT: verifyJWT,
                    sourcePath: sourcePath,
                    updatedAt: Self.timestamp(),
                    lastDeployedAt: projectBackendState.functions.first(where: { $0.name == functionName })?.lastDeployedAt,
                    lastInvocationSummary: projectBackendState.functions.first(where: { $0.name == functionName })?.lastInvocationSummary
                )
            )
            projectBackendState = projectBackendState.appendingLog(
                .init(timestamp: Self.timestamp(), message: "Updated local function scaffold for \(functionName).", functionName: functionName)
            )
            await handlers.persistState(projectBackendState)
            return ToolResult(
                text: "Upserted local backend function `\(functionName)` at `\(sourcePath)`.",
                fileEvent: nil
            )

        case .deploy:
            let functionName = normalizedFunctionName(request.functionName)
            guard !functionName.isEmpty else {
                return ToolResult(text: "Error: `function_name` is required for `deploy`.", fileEvent: nil)
            }
            guard hasBackendApproval(scope: "deploy") else {
                return approvalRequiredResult(
                    integration: "Supabase Backend",
                    scope: "deploy",
                    action: "deploy backend changes to the linked Supabase project"
                )
            }
            let sourceDirectory = workspaceRoot.appendingPathComponent("supabase/functions/\(functionName)", isDirectory: true)
            do {
                let response = try await handlers.deploy(
                    .init(
                        functionName: functionName,
                        verifyJWT: request.verifyJWT ?? projectBackendState.functions.first(where: { $0.name == functionName })?.verifyJWT ?? true,
                        sourceDirectory: sourceDirectory
                    )
                )
                projectBackendState = projectBackendState.markingFunctionDeployed(named: functionName, at: Self.timestamp())
                projectBackendState = projectBackendState.with(lastDeploySummary: response)
                projectBackendState = projectBackendState.appendingLog(
                    .init(timestamp: Self.timestamp(), message: response, functionName: functionName)
                )
                await handlers.persistState(projectBackendState)
                return ToolResult(text: response, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .invoke:
            let functionName = normalizedFunctionName(request.functionName)
            guard !functionName.isEmpty else {
                return ToolResult(text: "Error: `function_name` is required for `invoke`.", fileEvent: nil)
            }
            do {
                let timestamp = Self.timestamp()
                let response = try await handlers.invoke(
                    .init(
                        functionName: functionName,
                        requestJSON: request.requestJSON,
                        authMode: request.authMode ?? .userJWT
                    )
                )
                projectBackendState = projectBackendState.markingFunctionInvoked(
                    named: functionName,
                    summary: response,
                    at: timestamp
                )
                projectBackendState = projectBackendState.appendingLog(
                    .init(timestamp: timestamp, message: "Invoked \(functionName).", functionName: functionName)
                )
                await handlers.persistState(projectBackendState)
                return ToolResult(text: response, fileEvent: nil)
            } catch {
                let timestamp = Self.timestamp()
                let requestSummary = summarizedRequestJSON(request.requestJSON)
                let errorMessage = error.localizedDescription
                projectBackendState = projectBackendState
                    .recordFailure(
                        functionName: functionName,
                        requestSummary: requestSummary,
                        errorSummary: errorMessage,
                        source: .invoke,
                        at: timestamp
                    )
                    .appendingLog(
                        .init(
                            timestamp: timestamp,
                            message: errorMessage,
                            level: "error",
                            functionName: functionName
                        )
                    )
                await handlers.persistState(projectBackendState)
                return ToolResult(text: "Error: \(errorMessage)", fileEvent: nil)
            }

        case .setSecret:
            let secretName = (request.secretName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let secretValue = request.secretValue ?? ""
            guard !secretName.isEmpty else {
                return ToolResult(text: "Error: `secret_name` is required for `set_secret`.", fileEvent: nil)
            }
            guard !secretValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ToolResult(text: "Error: `secret_value` is required for `set_secret`.", fileEvent: nil)
            }
            guard hasBackendApproval(scope: "secrets") else {
                return approvalRequiredResult(
                    integration: "Supabase Backend",
                    scope: "secrets",
                    action: "create or rotate backend secrets in the linked Supabase project"
                )
            }
            do {
                let response = try await handlers.setSecret(secretName, secretValue)
                let syncedRemotely = !response.localizedCaseInsensitiveContains("remote sync is pending")
                    && !response.localizedCaseInsensitiveContains("remote sync is unavailable")
                    && !response.localizedCaseInsensitiveContains("pending:")
                projectBackendState = projectBackendState.upsertingSecret(
                    .init(
                        name: secretName,
                        updatedAt: Self.timestamp(),
                        lastSyncedAt: syncedRemotely ? Self.timestamp() : nil
                    )
                )
                projectBackendState = projectBackendState.appendingLog(
                    .init(timestamp: Self.timestamp(), message: response, functionName: nil)
                )
                await handlers.persistState(projectBackendState)
                return ToolResult(text: response, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .listLogs:
            do {
                let logs = try await handlers.listLogs(request.functionName, request.tail ?? 10)
                let effectiveLogs = logs.isEmpty ? projectBackendState.recentLogs : logs
                projectBackendState = projectBackendState.with(recentLogs: effectiveLogs)
                await handlers.persistState(projectBackendState)
                let rendered = effectiveLogs.isEmpty
                    ? "No backend logs found."
                    : effectiveLogs.map { "\($0.timestamp) [\($0.level)] \($0.functionName.map { "\($0): " } ?? "")\($0.message)" }.joined(separator: "\n")
                return ToolResult(text: rendered, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }
        }
    }

    private func executeSuperwallManage(_ input: [String: Any]) async -> ToolResult {
        guard let handlers = superwallToolHandlers else {
            return superwallUnavailableResult()
        }
        guard let request: SuperwallManageInput = decodeToolValue(input) else {
            return ToolResult(text: "Error: the Superwall input must match the schema exactly.", fileEvent: nil)
        }

        switch request.action {
        case .status:
            do {
                let response = try await handlers.status(projectSuperwallState)
                return ToolResult(text: response, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .listPaywalls:
            do {
                let paywalls = try await handlers.listPaywalls(projectSuperwallState)
                if paywalls.isEmpty {
                    return ToolResult(text: "No Superwall paywalls found for the linked application.", fileEvent: nil)
                }
                let lines = paywalls.map { paywall in
                    let identifier = (paywall.identifier?.isEmpty == false) ? " `\(paywall.identifier ?? "")`" : ""
                    return "- \(paywall.name) (`\(paywall.id)`)\(identifier)"
                }
                return ToolResult(text: lines.joined(separator: "\n"), fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .listTemplates:
            do {
                let templates = try await handlers.listTemplates(projectSuperwallState)
                if templates.isEmpty {
                    return ToolResult(text: "No Superwall paywall templates found for the linked application.", fileEvent: nil)
                }
                let lines = templates.map { template in
                    let visibility = template.visibility ?? "unknown"
                    if let category = template.category, !category.isEmpty {
                        return "- \(template.name) (`\(template.id)`) [\(visibility), \(category)]"
                    }
                    return "- \(template.name) (`\(template.id)`) [\(visibility)]"
                }
                return ToolResult(text: lines.joined(separator: "\n"), fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .openDashboard:
            do {
                let response = try await handlers.openDashboard(projectSuperwallState)
                return ToolResult(text: response, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .openPaywalls:
            do {
                let response = try await handlers.openPaywalls(projectSuperwallState)
                return ToolResult(text: response, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .openTemplates:
            do {
                let response = try await handlers.openTemplates(projectSuperwallState)
                return ToolResult(text: response, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .bootstrapProject:
            guard hasIntegrationApproval(integration: "superwall", scope: "bootstrap") else {
                return approvalRequiredResult(
                    integration: "Superwall",
                    scope: "bootstrap",
                    action: "create or link the Superwall project and iOS application for this builder project"
                )
            }
            do {
                let response = try await handlers.bootstrapProject(request, projectSuperwallState)
                projectSuperwallState = response.state
                await handlers.persistState(response.state)
                return ToolResult(text: response.summary, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .bootstrapStarterMonetization:
            guard hasIntegrationApproval(integration: "superwall", scope: "campaigns") else {
                return approvalRequiredResult(
                    integration: "Superwall",
                    scope: "campaigns",
                    action: "attach starter Superwall products and the preview campaign to the selected paywall"
                )
            }
            do {
                let response = try await handlers.bootstrapStarterMonetization(request, projectSuperwallState)
                projectSuperwallState = response.state
                await handlers.persistState(response.state)
                return ToolResult(text: response.summary, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }

        case .syncPreviewTestUser:
            guard hasIntegrationApproval(integration: "superwall", scope: "test-mode") else {
                return approvalRequiredResult(
                    integration: "Superwall",
                    scope: "test-mode",
                    action: "mark the preview user as a Superwall test-mode user"
                )
            }
            do {
                let response = try await handlers.syncPreviewTestUser(request, projectSuperwallState)
                projectSuperwallState = response.state
                await handlers.persistState(response.state)
                return ToolResult(text: response.summary, fileEvent: nil)
            } catch {
                return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
            }
        }
    }

    private func executeSupabaseTool<Request: Decodable>(
        _ input: [String: Any],
        decodeError: String,
        approvalResult: ((Request) -> ToolResult?)? = nil,
        operation: (SupabaseToolHandlers, Request) async throws -> String
    ) async -> ToolResult {
        guard let handlers = supabaseToolHandlers else {
            return supabaseUnavailableResult()
        }
        guard let request: Request = decodeToolValue(input) else {
            return ToolResult(text: decodeError, fileEvent: nil)
        }
        if let approvalResult, let result = approvalResult(request) {
            return result
        }

        do {
            let result = try await operation(handlers, request)
            return ToolResult(text: result, fileEvent: nil)
        } catch {
            return ToolResult(text: "Error: \(error.localizedDescription)", fileEvent: nil)
        }
    }

    private func supabaseUnavailableResult() -> ToolResult {
        ToolResult(
            text: "Supabase access is not available. Ask the user to connect Supabase in Integrations and select a project.",
            fileEvent: nil
        )
    }

    private func backendUnavailableResult() -> ToolResult {
        ToolResult(
            text: "Backend access is not available. Ask the user to connect Supabase in Integrations first, then use Backend to link the provider.",
            fileEvent: nil
        )
    }

    private func superwallUnavailableResult() -> ToolResult {
        ToolResult(
            text: "Superwall access is not available. Ask the user to connect Superwall in Integrations first.",
            fileEvent: nil
        )
    }

    private func decodeToolValue<T: Decodable>(_ rawValue: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(rawValue),
              let data = try? JSONSerialization.data(withJSONObject: rawValue, options: []) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func intValue(_ rawValue: Any?) -> Int? {
        if let intValue = rawValue as? Int {
            return intValue
        }
        if let number = rawValue as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func readWorkspaceFile(path: String) -> String? {
        guard validateWorkspacePath(path) == nil else {
            return nil
        }
        if let content = fileTree[path] {
            return content
        }
        guard let fileURL = resolvedWorkspaceFileURL(for: path) else {
            return nil
        }
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            if content.count <= maxReadFileChars {
                fileTree[path] = content
            }
            return content
        }
        return nil
    }

    private func upsertWorkspaceFile(path: String, content: String) {
        guard validateWorkspacePath(path) == nil else {
            return
        }
        fileTree[path] = content
        filesChanged.insert(path)
        writeToDisk(path: path, content: content)
    }

    private func normalizedFunctionName(_ rawValue: String?) -> String {
        let scalars = (rawValue ?? "").unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
        let collapsed = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
            .lowercased()
        return collapsed.replacingOccurrences(of: "--", with: "-")
    }

    private func mergedSupabaseConfig(existing: String?, functionName: String, verifyJWT: Bool) -> String {
        let section = """
        [functions.\(functionName)]
        verify_jwt = \(verifyJWT ? "true" : "false")
        """
        let trimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return section + "\n"
        }
        let pattern = #"(?ms)^\[functions\.\#(functionName)\]\nverify_jwt = (true|false)\n?"#
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return trimmed.replacingOccurrences(of: pattern, with: section, options: .regularExpression) + "\n"
        }
        return trimmed + "\n\n" + section + "\n"
    }

    private func backendDocumentation(existing: String?) -> String {
        let standard = """
        # Supabase Backend

        This project uses the managed Backend workspace for Supabase Edge Functions.

        - `supabase/functions/<name>/index.ts` contains named backend endpoints.
        - Function secrets are stored in 10x and synced to Supabase through Backend.
        - Do not turn this into an open HTTP proxy.
        """
        let trimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? standard + "\n" : trimmed + "\n"
    }

    private func renderBackendStatus() -> String {
        let provider = projectBackendState.providerID?.title ?? "Not linked"
        let projectRef = projectBackendState.linkedProjectRef ?? "none"
        let lastRefresh = projectBackendState.lastStatusRefreshAt ?? "never"
        let functions = projectBackendState.functions
            .map { "- \($0.name) (\($0.verifyJWT ? "auth" : "public"))" }
            .joined(separator: "\n")
        let secrets = projectBackendState.secrets
            .map { "- \($0.name)" }
            .joined(separator: "\n")
        let failures = projectBackendState.openFailures
            .map { "- \($0.functionName): \($0.errorSummary)" }
            .joined(separator: "\n")

        return """
        Backend provider: \(provider)
        Linked project ref: \(projectRef)
        Last status refresh: \(lastRefresh)
        Functions:
        \(functions.isEmpty ? "- none" : functions)
        Secrets:
        \(secrets.isEmpty ? "- none" : secrets)
        Open failures:
        \(failures.isEmpty ? "- none" : failures)
        """
    }

    private func summarizedRequestJSON(_ requestJSON: AnyCodableValue?) -> String? {
        guard let requestJSON else { return nil }
        let object = requestJSON.jsonObject
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              var rendered = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !rendered.isEmpty
        else {
            let fallback = String(describing: object).trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? nil : fallback
        }

        if rendered.count > 280 {
            rendered = String(rendered.prefix(277)) + "..."
        }
        return rendered
    }

    private nonisolated static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Disk I/O

    private func writeToDisk(path: String, content: String) {
        guard let fileURL = resolvedWorkspaceFileURL(for: path) else {
            return
        }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CoordinatedFileWriter.write(content, to: fileURL)
    }

    private func deleteFromDisk(path: String) {
        guard let fileURL = resolvedWorkspaceFileURL(for: path) else {
            return
        }
        CoordinatedFileWriter.delete(fileURL)
    }

    // MARK: - Helpers

    private func validateWorkspacePath(_ path: String) -> String? {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: path is required."
        }
        guard resolvedWorkspaceFileURL(for: path) != nil else {
            return "Error: \(path) is outside the readable project workspace or points to generated metadata/build artifacts."
        }
        return nil
    }

    private func resolvedWorkspaceFileURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = sourcesDir
            .appendingPathComponent(trimmed)
            .standardizedFileURL
        let root = sourcesDir.standardizedFileURL
        let rootPath = root.path
        let candidatePath = candidate.path

        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }

        let relativeComponents = candidate.pathComponents.dropFirst(root.pathComponents.count)
        guard !relativeComponents.contains(where: { blockedWorkspacePathComponents.contains($0) }) else {
            return nil
        }

        return candidate
    }

    private func renderReadResult(path: String, content: String, maxChars: Int) -> String {
        guard content.count > maxChars else {
            return content
        }

        let headChars = max(6_000, Int(Double(maxChars) * 0.7))
        let tailChars = max(2_000, maxChars - headChars)
        let head = String(content.prefix(headChars))
        let tail = String(content.suffix(tailChars))

        return """
        <truncated_file path="\(path)" total_chars="\(content.count)">
        \(head)

        ... [file truncated to stay within the model context budget. Use `search_files` to locate the exact symbol or narrow the path before reading again.]

        \(tail)
        </truncated_file>
        """
    }

    private func matchGlob(path: String, pattern: String) -> Bool {
        // Simple glob matching using fnmatch-style
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        return path.range(of: regexPattern, options: .regularExpression) != nil
    }

    private func findSimilarStrings(in content: String, target: String, maxResults: Int = 3) -> String {
        let targetLines = target.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        guard let firstLine = targetLines.first?.trimmingCharacters(in: .whitespaces), !firstLine.isEmpty else {
            return ""
        }

        let contentLines = content.components(separatedBy: "\n")
        var candidates: [(Double, Int, String)] = []

        for (i, line) in contentLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let similarity = stringSimilarity(trimmed, firstLine)
            if similarity > 0.6 {
                let end = min(contentLines.count, i + targetLines.count)
                let snippet = contentLines[i..<end].joined(separator: "\n")
                candidates.append((similarity, i + 1, snippet))
            }
        }

        guard !candidates.isEmpty else { return "" }
        candidates.sort { $0.0 > $1.0 }

        let hints = candidates.prefix(maxResults).map { (ratio, lineNum, snippet) in
            let truncated = snippet.count > 200 ? String(snippet.prefix(200)) + "..." : snippet
            return "  Line \(lineNum) (\(Int(ratio * 100))% similar):\n    \(truncated)"
        }

        return "\n\nDid you mean one of these?\n" + hints.joined(separator: "\n")
    }

    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty && !b.isEmpty else { return 0 }
        let aChars = Array(a)
        let bChars = Array(b)
        let maxLen = max(aChars.count, bChars.count)
        var matches = 0
        for i in 0..<min(aChars.count, bChars.count) {
            if aChars[i] == bChars[i] { matches += 1 }
        }
        return Double(matches) / Double(maxLen)
    }

    private func hasIntegrationApproval(integration: String, scope: String) -> Bool {
        approvedIntegrationScopes[integration.lowercased(), default: []].contains(scope.lowercased())
    }

    private func hasBackendApproval(scope: String) -> Bool {
        hasIntegrationApproval(integration: "supabase backend", scope: scope)
    }

    func grantIntegrationApproval(_ request: IntegrationApprovalRequest) {
        approvedIntegrationScopes[request.integration, default: []].insert(request.scope)
    }

    private func approvalRequiredResult(
        integration: String,
        scope: String,
        action: String
    ) -> ToolResult {
        ToolResult(
            text: "Approval required before \(action).",
            fileEvent: nil,
            approvalRequest: IntegrationApprovalRequest(
                integration: integration.lowercased(),
                scope: scope.lowercased(),
                integrationName: integration,
                actionDescription: action
            )
        )
    }
}

// MARK: - Types

nonisolated struct IntegrationApprovalRequest: Codable, Equatable, Sendable {
    let integration: String
    let scope: String
    let integrationName: String
    let actionDescription: String

    var prompt: String {
        "Allow 10x to use the connected \(integrationName) project to \(actionDescription) for this builder session?"
    }

    var approveLabel: String { "Allow" }
    var denyLabel: String { "Don't Allow" }
}

nonisolated struct SupabaseToolHandlers: Sendable {
    let read: @Sendable (SupabaseReadTableInput) async throws -> String
    let write: @Sendable (SupabaseWriteTableInput) async throws -> String
    let sql: @Sendable (SupabaseExecuteSQLInput) async throws -> String
    let settings: @Sendable (SupabaseManageSettingsInput) async throws -> String
}

nonisolated enum SuperwallManageAction: String, Decodable, Sendable {
    case status
    case bootstrapProject = "bootstrap_project"
    case bootstrapStarterMonetization = "bootstrap_starter_monetization"
    case syncPreviewTestUser = "sync_preview_test_user"
    case listPaywalls = "list_paywalls"
    case listTemplates = "list_templates"
    case openDashboard = "open_dashboard"
    case openPaywalls = "open_paywalls"
    case openTemplates = "open_templates"
}

nonisolated struct SuperwallManageInput: Decodable, Sendable {
    let action: SuperwallManageAction
    let organizationID: String?
    let projectID: String?
    let applicationID: String?
    let paywallID: String?
    let previewAppUserID: String?
    let placements: [String]?

    enum CodingKeys: String, CodingKey {
        case action
        case organizationID = "organization_id"
        case projectID = "project_id"
        case applicationID = "application_id"
        case paywallID = "paywall_id"
        case previewAppUserID = "preview_app_user_id"
        case placements
    }
}

nonisolated struct SuperwallToolOperationResult: Sendable {
    let state: ProjectSuperwallState
    let summary: String
}

nonisolated struct SuperwallToolHandlers: Sendable {
    let status: @Sendable (ProjectSuperwallState) async throws -> String
    let bootstrapProject: @Sendable (SuperwallManageInput, ProjectSuperwallState) async throws -> SuperwallToolOperationResult
    let bootstrapStarterMonetization: @Sendable (SuperwallManageInput, ProjectSuperwallState) async throws -> SuperwallToolOperationResult
    let syncPreviewTestUser: @Sendable (SuperwallManageInput, ProjectSuperwallState) async throws -> SuperwallToolOperationResult
    let listPaywalls: @Sendable (ProjectSuperwallState) async throws -> [SuperwallManagementPaywall]
    let listTemplates: @Sendable (ProjectSuperwallState) async throws -> [SuperwallManagementTemplate]
    let openDashboard: @Sendable (ProjectSuperwallState) async throws -> String
    let openPaywalls: @Sendable (ProjectSuperwallState) async throws -> String
    let openTemplates: @Sendable (ProjectSuperwallState) async throws -> String
    let persistState: @Sendable (ProjectSuperwallState) async -> Void
}

nonisolated enum BackendManageAction: String, Decodable, Sendable {
    case status
    case linkProvider = "link_provider"
    case upsertFunction = "upsert_function"
    case deploy
    case invoke
    case setSecret = "set_secret"
    case listLogs = "list_logs"
}

nonisolated enum BackendInvokeAuthMode: String, Decodable, Sendable {
    case userJWT = "user_jwt"
    case anon
    case none
}

nonisolated struct BackendManageInput: Decodable, Sendable {
    let action: BackendManageAction
    let providerID: ProjectBackendProviderID?
    let functionName: String?
    let summary: String?
    let verifyJWT: Bool?
    let sourceCode: String?
    let requestJSON: AnyCodableValue?
    let authMode: BackendInvokeAuthMode?
    let secretName: String?
    let secretValue: String?
    let tail: Int?

    enum CodingKeys: String, CodingKey {
        case action
        case providerID = "provider_id"
        case functionName = "function_name"
        case summary
        case verifyJWT = "verify_jwt"
        case sourceCode = "source_code"
        case requestJSON = "request_json"
        case authMode = "auth_mode"
        case secretName = "secret_name"
        case secretValue = "secret_value"
        case tail
    }
}

nonisolated struct BackendStatusSnapshot: Sendable {
    let providerID: ProjectBackendProviderID
    let projectRef: String
    let projectURL: String
    let remoteFunctionNames: [String]
    let remoteSecretNames: [String]
}

nonisolated struct BackendProviderLink: Sendable {
    let providerID: ProjectBackendProviderID
    let projectRef: String
    let projectURL: String
}

nonisolated struct BackendDeployInput: Sendable {
    let functionName: String
    let verifyJWT: Bool
    let sourceDirectory: URL
}

nonisolated struct BackendInvokeInput: Sendable {
    let functionName: String
    let requestJSON: AnyCodableValue?
    let authMode: BackendInvokeAuthMode
}

nonisolated struct BackendToolHandlers: Sendable {
    let status: @Sendable () async throws -> BackendStatusSnapshot
    let linkProvider: @Sendable () async throws -> BackendProviderLink
    let deploy: @Sendable (BackendDeployInput) async throws -> String
    let invoke: @Sendable (BackendInvokeInput) async throws -> String
    let setSecret: @Sendable (String, String) async throws -> String
    let listLogs: @Sendable (String?, Int) async throws -> [ProjectBackendLogEntry]
    let persistState: @Sendable (ProjectBackendState) async -> Void
}

nonisolated struct ToolResult: Sendable {
    let text: String
    let fileEvent: FileEvent?
    let contextRefresh: ToolContextRefresh?
    let approvalRequest: IntegrationApprovalRequest?

    init(
        text: String,
        fileEvent: FileEvent?,
        contextRefresh: ToolContextRefresh? = nil,
        approvalRequest: IntegrationApprovalRequest? = nil
    ) {
        self.text = text
        self.fileEvent = fileEvent
        self.contextRefresh = contextRefresh
        self.approvalRequest = approvalRequest
    }
}

nonisolated struct FileEvent: Sendable {
    let path: String
    let content: String
    let action: String  // "create", "update", "delete"
}

nonisolated enum ToolContextRefresh: Sendable {
    case modeChange(mode: String)
    case projectIdentityChange(name: String)
}
