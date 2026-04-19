import AppKit
import Foundation

extension BuilderViewModel {
    func loadProjects(accessToken: String) async {
        isLoadingProjects = true
        defer {
            isLoadingProjects = false
            hasLoadedProjects = true
        }
        do {
            let userId = Self.userIdFromJWT(accessToken)
            guard let userId else {
                print("Failed to load projects: no user ID in token")
                return
            }
            projects = try await supabase.fetchProjects(userId: userId)
            archivedProjects = try await supabase.fetchArchivedProjects(userId: userId)
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    func loadAvailableSkills(accessToken: String) async {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            availableSkills = []
            isLoadingSkills = false
            return
        }

        if !availableSkills.isEmpty || isLoadingSkills {
            return
        }

        isLoadingSkills = true
        let skills = await skillsManager.fetchRegistry(accessToken: accessToken)
        availableSkills = skills
        isLoadingSkills = false
    }

    func archiveProject(_ project: BuilderProject) async {
        do {
            let archivedProject = try await supabase.archiveProject(id: project.id)
            projects.removeAll { $0.id == project.id }
            upsertProject(archivedProject, in: &archivedProjects)
            if activeProject?.id == archivedProject.id {
                activeProject = archivedProject
            }
        } catch {
            print("Failed to archive project: \(error)")
        }
    }

    func unarchiveProject(_ project: BuilderProject) async {
        do {
            let restoredProject = try await supabase.unarchiveProject(id: project.id)
            archivedProjects.removeAll { $0.id == project.id }
            upsertProject(restoredProject, in: &projects)
            if activeProject?.id == restoredProject.id {
                activeProject = restoredProject
            }
        } catch {
            print("Failed to unarchive project: \(error)")
        }
    }

    func deleteProject(_ project: BuilderProject) async {
        do {
            try await supabase.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
            archivedProjects.removeAll { $0.id == project.id }
            if activeProject?.id == project.id {
                activeProject = nil
                localProjectPath = nil
                previewScreenshot = nil
                lastPreviewedFileTreeRevision = nil
                projectWarnings = []
                productionChecklistState = .empty
                appStoreReviewState = .empty
                appStoreReviewStatus = nil
                appStoreReviewError = nil
                appStoreSubmissionDraft = .empty
                appStoreSubmissionStatus = nil
                appStoreSubmissionError = nil
                isGeneratingAppStoreSubmission = false
                isPublishingAppStoreSubmission = false
                reviewAssetImageCache = [:]
            }
            await localStore.deleteProjectData(projectName: project.name, projectId: project.id)
        } catch {
            print("Failed to permanently delete project: \(error)")
        }
    }

    func renameProject(_ project: BuilderProject, newName: String) async {
        let existingIcon = if activeProject?.id == project.id {
            projectIcon
        } else {
            await localStore.loadCustomIcon(projectName: project.name, projectId: project.id)
        }

        await updateProjectDetails(project, newName: newName, customIcon: existingIcon)
    }

    func updateProjectDetails(_ project: BuilderProject, newName: String, customIcon: NSImage?) async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        do {
            let finalProject: BuilderProject
            if trimmedName != project.name {
                finalProject = try await supabase.updateProject(id: project.id, data: UpdateProjectData(name: trimmedName))
            } else {
                finalProject = project
            }

            let projectDir = if trimmedName != project.name {
                try await previewService.moveProjectDirectory(
                    oldProjectName: project.name,
                    newProjectName: trimmedName,
                    projectId: project.id
                )
            } else {
                await previewService.projectDir(for: trimmedName, projectId: project.id)
            }

            if trimmedName != project.name {
                await localStore.moveProjectData(
                    oldProjectName: project.name,
                    newProjectName: trimmedName,
                    projectId: project.id
                )
            }

            if let customIcon {
                await localStore.saveCustomIcon(customIcon, projectName: trimmedName, projectId: project.id)
            } else {
                await localStore.deleteCustomIcon(projectName: trimmedName, projectId: project.id)
            }

            replaceProject(finalProject)

            if activeProject?.id == project.id {
                projectIcon = customIcon
                let workspaceDescriptor = finalProject.workspaceDescriptor
                if !workspaceDescriptor.isImported,
                   FileManager.default.fileExists(atPath: projectDir.path),
                   !fileTree.isEmpty {
                    do {
                        localProjectPath = try await previewService.writeProjectToDisk(
                            fileTree: fileTree,
                            projectName: trimmedName,
                            projectId: project.id,
                            customIcon: customIcon,
                            environmentVariables: environmentVariables
                        )
                        fileWatcher?.updateBaseline(fileTree: fileTree)
                    } catch {
                        print("Failed to rewrite renamed project to disk: \(error)")
                        localProjectPath = projectDir
                    }
                } else {
                    localProjectPath = FileManager.default.fileExists(atPath: projectDir.path) ? projectDir : nil
                }

                await saveLocally(touchChat: false)
            }
        } catch {
            print("Failed to update project details: \(error)")
        }
    }

    func createProject(name: String, accessToken: String) async {
        do {
            let userId = Self.userIdFromJWT(accessToken)
            guard let userId else {
                print("[10x] Failed to create project: no user ID in token")
                return
            }
            print("[10x] Creating project: \(name)")
            let project = try await supabase.createProject(userId: userId, name: name)
            print("[10x] Project created: \(project.id)")
            projects.insert(project, at: 0)
            selectProject(project, accessToken: accessToken)
        } catch {
            print("[10x] Failed to create project: \(error)")
        }
    }

    func importExistingProject(from selectionURL: URL, accessToken: String) async throws -> BuilderProject {
        guard let userId = Self.userIdFromJWT(accessToken) else {
            throw ExistingProjectImportError.invalidSelection("You need a valid session before importing a project.")
        }

        let selection = try await projectImporter.resolveSelection(at: selectionURL)
        try await projectImporter.validateSwiftUISources(at: selection.rootURL)

        let createdProject = try await supabase.createProject(
            userId: userId,
            name: selection.displayName
        )
        let projectRoot = try await previewService.scaffoldProjectDirectory(
            projectName: createdProject.name,
            projectId: createdProject.id
        )

        do {
            let importResult = try await projectImporter.importProject(
                from: selection,
                into: projectRoot
            )
            let importedProject = try await supabase.updateProject(
                id: createdProject.id,
                data: UpdateProjectData(settings: importResult.metadata.settingsDictionary)
            )

            await localStore.saveFileTree(
                importResult.fileTree,
                projectName: importedProject.name,
                projectId: importedProject.id
            )

            let conversation = try await supabase.fetchConversation(projectId: importedProject.id)
            if let conversationId = conversation.conversationId {
                _ = try? await supabase.createVersion(
                    projectId: importedProject.id,
                    conversationId: conversationId,
                    fileTree: importResult.fileTree,
                    prompt: "Imported existing SwiftUI project: \(selection.displayName)"
                )
            }

            upsertProject(importedProject, in: &projects)
            return importedProject
        } catch {
            try? await supabase.deleteProject(id: createdProject.id)
            try? FileManager.default.removeItem(at: projectRoot)
            throw error
        }
    }

    func selectProject(_ project: BuilderProject, accessToken: String) {
        rememberAccessToken(accessToken)
        cancelPreviewWork()
        fileWatcher?.stop()
        fileWatcher = nil
        activeProject = project
        chats = []
        activeChat = nil
        messages = []
        chatItems = []
        fileTree = [:]
        environmentVariables = []
        versions = []
        activeSteps = []
        pendingAssistantContent = ""
        buildError = nil
        localProjectPath = nil
        previewScreenshot = nil
        livePreviewScreenshot = nil
        projectIcon = nil
        developmentPreviewMode = .saved
        viewMode = .canvas
        mode = project.currentVersionId == nil ? .plan : .build
        showChatSidebar = false
        projectPlan = nil
        projectTasks = nil
        projectWarnings = []
        projectDependencyManifest = nil
        projectBackendState = .empty
        projectSuperwallState = .empty
        productionChecklistState = .empty
        questionQueue = nil
        integrationApproval = nil
        messageQueue = []
        showResumePrompt = false
        lastFailedRequest = nil
        isAutoFixingBuild = false
        consecutiveAutomaticBuildFixFailures = 0
        lastPreviewCompileError = nil
        latestBuildFixError = nil
        suppressIntermediateAssistantText = false
        pendingRequiredSkillPrefill = nil
        pendingMessageActionPrefill = nil
        pendingAttachmentPrefill = nil
        pendingAttachmentAppend = nil
        pendingEnvironmentIntegrationFocus = nil
        pendingBackendFocus = false
        generationSnapshots = []
        contextState = .empty
        cachedReadFiles = [:]
        cachedReadFileOrder = []
        titleRequestsInFlight = []
        previewScreenLibrary = []
        capturedScreenLibrary = []
        selectedPreviewScreenID = nil
        selectedCapturedScreenID = nil
        previewScreenImageCache = [:]
        reviewAssetImageCache = [:]
        pendingInitialPreviewImage = nil
        lastPreviewedFileTreeRevision = nil
        appStoreReviewState = .empty
        appStoreReviewStatus = nil
        appStoreReviewError = nil
        isGeneratingAppStoreReviewAssets = false
        appStoreSubmissionDraft = .empty
        appStoreSubmissionStatus = nil
        appStoreSubmissionError = nil
        isGeneratingAppStoreSubmission = false
        isPublishingAppStoreSubmission = false

        Task {
            await loadProjectData(projectId: project.id)
        }
    }

    func selectVersion(_ version: BuilderVersion) {
        activeVersion = version
        fileTree = version.fileTree
        fileTreeRevision += 1
    }

    var environmentValuesByKey: [String: String] {
        ProjectEnvironmentSecurity.runtimeEnvironment(from: environmentVariables)
    }

    var clientEnvironmentValuesByKey: [String: String] {
        ProjectEnvironmentSecurity.clientRuntimeEnvironment(from: environmentVariables)
    }

    var toolEnvironmentValuesByKey: [String: String] {
        ProjectEnvironmentSecurity.toolEnvironment(from: environmentVariables)
    }

    var integrationToolAvailability: BuilderIntegrationToolAvailability {
        let projectRef = SupabaseManagementService.projectRef(from: environmentValuesByKey["SUPABASE_URL"])
        let hasSupabaseAccess = projectRef != nil && SupabaseManagementOAuthService.shared.hasUsableSession()
        let hasSuperwallAccess = SuperwallManagementTokenStore().hasAPIKey()
        return BuilderIntegrationToolAvailability(
            hasSupabaseAccess: hasSupabaseAccess,
            hasSuperwallAccess: hasSuperwallAccess
        )
    }

    func saveEnvironmentVariables(_ variables: [ProjectEnvironmentVariable]) async throws {
        guard let project = activeProject else { return }

        let normalized = Self.normalizedEnvironmentVariables(variables)
        let nextBackendState = try await syncedBackendState(for: normalized)
        environmentVariables = normalized

        await localStore.saveEnvironmentVariables(
            normalized,
            projectName: project.name,
            projectId: project.id
        )

        if localProjectPath != nil,
           !fileTree.isEmpty,
           !project.workspaceDescriptor.isImported {
            do {
                try await previewService.regenerateXcodeProject(
                    projectName: project.name,
                    projectId: project.id,
                    fileTree: fileTree,
                    customIcon: projectIcon,
                    environmentVariables: normalized
                )
                fileWatcher?.updateBaseline(fileTree: fileTree)
            } catch {
                print("Failed to refresh Xcode project after environment update: \(error)")
            }
        }

        if let nextBackendState {
            await saveProjectBackendState(nextBackendState)
        } else {
            await saveLocally(touchChat: false)
        }
    }

    func setProjectIdentity(name: String, imageFilename: String?) async -> String {
        guard let project = activeProject else { return "Error: no active project." }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Error: name is required." }
        let nameChanged = name != project.name
        if !nameChanged && (imageFilename == nil || imageFilename?.isEmpty == true) {
            return "Project identity already matches '\(name)'. No rename was needed."
        }
        let renderedIcon: NSImage?
        if let imageFilename, !imageFilename.isEmpty {
            guard let uploadedIcon = uploadedImage(named: imageFilename) else {
                return "Error: uploaded image '\(imageFilename)' not found."
            }
            renderedIcon = uploadedIcon
        } else {
            renderedIcon = projectIcon
        }
        await updateProjectDetails(project, newName: name, customIcon: renderedIcon)
        if let imageFilename, !imageFilename.isEmpty, nameChanged {
            return "Set project name to '\(name)' with uploaded image '\(imageFilename)'."
        } else if let imageFilename, !imageFilename.isEmpty {
            return "Updated the project icon while keeping the name '\(name)'."
        }
        return "Set project name to '\(name)'."
    }

    private func loadProjectData(projectId: String) async {
        guard let projectName = activeProject?.name else { return }

        projectIcon = await localStore.loadCustomIcon(projectName: projectName, projectId: projectId)
        let projectDir = await previewService.projectDir(for: projectName, projectId: projectId)
        let projectDirExists = FileManager.default.fileExists(atPath: projectDir.path)
        var hasLocalTree = false

        let projectStatus = BuilderProjectStatusState.merged(
            projectStatus: await localStore.loadProjectStatus(projectName: projectName, projectId: projectId),
            projectDependencyManifest: activeProject?.dependencyManifest
        )
        projectBackendState = activeProject?.backendState ?? .empty
        projectSuperwallState = activeProject?.superwallState ?? .empty
        let hadLocalChats = await initializeChats(
            projectName: projectName,
            projectId: projectId,
            projectStatus: projectStatus
        )
        environmentVariables = await localStore.loadEnvironmentVariables(projectName: projectName, projectId: projectId)
        productionChecklistState = await localStore.loadProductionChecklist(
            projectName: projectName,
            projectId: projectId
        )
        appStoreSubmissionDraft = activeProject?.appStoreSubmissionDraft?.normalized(projectName: projectName) ?? .empty
        if let localTree = await localStore.loadFileTree(projectName: projectName, projectId: projectId) {
            hasLocalTree = true
            fileTree = localTree
        }
        appStoreReviewState = await localStore.loadReviewState(projectName: projectName, projectId: projectId)
        previewScreenLibrary = await localStore.loadPreviewScreens(projectName: projectName, projectId: projectId)
        capturedScreenLibrary = await localStore.loadCapturedScreens(projectName: projectName, projectId: projectId)
        await sanitizePreviewScreenLibrary()
        selectedPreviewScreenID = previewScreenLibrary.first?.id
        selectedCapturedScreenID = previewScreenLibrary.isEmpty ? capturedScreenLibrary.first?.id : nil
        localProjectPath = projectDirExists && !fileTree.isEmpty ? projectDir : nil

        let hadLocalTree = hasLocalTree

        async let messagesTask: [BuilderMessage] = {
            do {
                let (msgs, _) = try await supabase.fetchConversation(projectId: projectId)
                return msgs
            } catch {
                print("Failed to load messages: \(error)")
                return []
            }
        }()

        async let versionsTask: [BuilderVersion] = {
            do {
                return try await supabase.fetchVersions(projectId: projectId)
            } catch {
                print("Failed to load versions: \(error)")
                return []
            }
        }()

        let (fetchedMessages, fetchedVersions) = await (messagesTask, versionsTask)

        guard activeProject?.id == projectId else { return }

        versions = fetchedVersions

        if !hadLocalChats {
            if !fetchedMessages.isEmpty {
                let importedState = BuilderChatState(
                    messages: fetchedMessages,
                    plan: nil,
                    tasks: nil,
                    snapshots: [],
                    contextState: .empty
                )
                applyChatState(importedState, projectStatus: projectStatusState)
            }
            await saveLocally(touchChat: false)
        }

        if projectStatus == nil, projectStatusState.hasContent, let project = activeProject {
            await localStore.saveProjectStatus(
                projectStatusState,
                projectName: project.name,
                projectId: project.id,
                projectDir: localProjectPath
            )
        }

        if !hadLocalTree, let latest = fetchedVersions.first {
            activeVersion = latest
            fileTree = latest.fileTree
            await localStore.saveFileTree(latest.fileTree, projectName: projectName, projectId: projectId)
        }

        mode = (!fileTree.isEmpty || !fetchedVersions.isEmpty || hadLocalTree) ? .build : .plan

        await sanitizePreviewScreenLibrary()
        selectedPreviewScreenID = previewScreenLibrary.first?.id
        selectedCapturedScreenID = previewScreenLibrary.isEmpty ? capturedScreenLibrary.first?.id : nil

        lastPreviewedFileTreeRevision = previewScreenLibrary.isEmpty ? nil : fileTreeRevision

        localProjectPath = projectDirExists && !fileTree.isEmpty ? projectDir : nil
        if !fileTree.isEmpty {
            await previewService.writeProductionGuideIfNeeded(
                projectName: projectName,
                projectId: projectId,
                fileTree: fileTree,
                environmentVariables: environmentVariables
            )
        }
        startFileWatcherIfNeeded()
        scheduleGeneratedChatTitleIfNeeded()
    }

    private func startFileWatcherIfNeeded() {
        guard activeProject != nil,
              let workspaceRoot = workspaceRootURL()
        else {
            return
        }

        let watcher = FileSystemWatcher(sourcesDir: workspaceRoot) { [weak self] changes in
            Task { @MainActor [weak self] in
                self?.applyExternalFileChanges(changes)
            }
        }
        watcher.start(currentFileTree: fileTree)
        fileWatcher = watcher
    }

    private func applyExternalFileChanges(_ changes: FileSystemWatcher.Changes) {
        guard !isGenerating, !isReverting else { return }

        var didChange = false

        for (path, content) in changes.created {
            fileTree[path] = content
            didChange = true
        }
        for (path, content) in changes.modified {
            fileTree[path] = content
            didChange = true
        }
        for path in changes.deleted {
            fileTree.removeValue(forKey: path)
            didChange = true
        }

        if didChange {
            fileTreeRevision += 1
            print("[10x] Applied external file changes — created: \(changes.created.count), modified: \(changes.modified.count), deleted: \(changes.deleted.count)")

            if let project = activeProject {
                Task {
                    await localStore.saveFileTree(fileTree, projectName: project.name, projectId: project.id)
                }
            }
        }
    }

    private func uploadedImage(named filename: String) -> NSImage? {
        for message in messages.reversed() where message.role == "user" {
            for attachment in message.attachments.reversed()
            where attachment.kind == .image && attachment.filename == filename {
                if let data = attachment.imageData {
                    return NSImage(data: data)
                }
            }
        }
        return nil
    }

    private func replaceProject(_ updated: BuilderProject) {
        if let idx = projects.firstIndex(where: { $0.id == updated.id }) {
            projects[idx] = updated
        }
        if let idx = archivedProjects.firstIndex(where: { $0.id == updated.id }) {
            archivedProjects[idx] = updated
        }
        if activeProject?.id == updated.id {
            activeProject = updated
        }
    }

    private func upsertProject(_ updated: BuilderProject, in list: inout [BuilderProject]) {
        list.removeAll { $0.id == updated.id }
        list.insert(updated, at: 0)
    }

    func focusEnvironmentIntegration(_ integrationID: ProjectIntegrationID?) {
        pendingEnvironmentIntegrationFocus = integrationID
        viewMode = .environment
    }

    func focusBackend() {
        pendingBackendFocus = true
        viewMode = .backend
    }

    func saveProjectDependencyManifest(_ manifest: ProjectDependencyManifest?) async {
        guard let project = activeProject else { return }

        projectDependencyManifest = manifest

        var mergedSettings = project.settings ?? [:]
        if let manifest, let encoded = AnyCodableValue.encode(manifest) {
            mergedSettings[BuilderProject.dependencyManifestSettingsKey] = encoded
        } else {
            mergedSettings.removeValue(forKey: BuilderProject.dependencyManifestSettingsKey)
        }

        do {
            let updatedProject = try await supabase.updateProject(
                id: project.id,
                data: UpdateProjectData(settings: mergedSettings.isEmpty ? nil : mergedSettings)
            )
            replaceProject(updatedProject)
        } catch {
            print("Failed to save dependency manifest: \(error)")
        }

        await saveLocally(touchChat: false)
    }

    func saveProjectBackendState(_ state: ProjectBackendState) async {
        guard let project = activeProject else { return }

        projectBackendState = state

        var mergedSettings = project.settings ?? [:]
        if let encoded = AnyCodableValue.encode(state) {
            mergedSettings[BuilderProject.backendStateSettingsKey] = encoded
        } else {
            mergedSettings.removeValue(forKey: BuilderProject.backendStateSettingsKey)
        }

        do {
            let updatedProject = try await supabase.updateProject(
                id: project.id,
                data: UpdateProjectData(settings: mergedSettings.isEmpty ? nil : mergedSettings)
            )
            replaceProject(updatedProject)
        } catch {
            print("Failed to save backend state: \(error)")
        }

        await saveLocally(touchChat: false)
    }

    func saveProjectSuperwallState(_ state: ProjectSuperwallState) async {
        guard let project = activeProject else { return }

        projectSuperwallState = state

        var mergedSettings = project.settings ?? [:]
        if state != .empty, let encoded = AnyCodableValue.encode(state) {
            mergedSettings[BuilderProject.superwallStateSettingsKey] = encoded
        } else {
            mergedSettings.removeValue(forKey: BuilderProject.superwallStateSettingsKey)
        }

        do {
            let updatedProject = try await supabase.updateProject(
                id: project.id,
                data: UpdateProjectData(settings: mergedSettings.isEmpty ? nil : mergedSettings)
            )
            replaceProject(updatedProject)
        } catch {
            print("Failed to save Superwall state: \(error)")
        }

        await saveLocally(touchChat: false)
    }

    private static func userIdFromJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder > 0 { payload += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else { return nil }
        return sub
    }

    private static func normalizedEnvironmentVariables(
        _ variables: [ProjectEnvironmentVariable]
    ) -> [ProjectEnvironmentVariable] {
        variables.compactMap { variable in
            let trimmedKey = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = variable.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = variable.value
            guard !trimmedKey.isEmpty else { return nil }

            return ProjectEnvironmentVariable(
                id: variable.id,
                key: trimmedKey,
                description: trimmedDescription,
                value: value,
                scope: variable.scope
            )
        }
    }

    private func syncedBackendState(for variables: [ProjectEnvironmentVariable]) async throws -> ProjectBackendState? {
        let hostedSecrets = variables.compactMap { variable -> (name: String, value: String)? in
            guard variable.scope == .hosted else { return nil }
            let name = variable.normalizedKey
            let value = variable.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            return (name, value)
        }
        guard !hostedSecrets.isEmpty else { return nil }

        let valuesByKey = Dictionary(uniqueKeysWithValues: variables.map { ($0.normalizedKey, $0.value) })
        guard let projectURL = valuesByKey["SUPABASE_URL"],
              let projectRef = SupabaseManagementService.projectRef(from: projectURL) else {
            throw SupabaseManagementServiceError.invalidInput(
                "Connect Supabase in Integrations before saving hosted keys."
            )
        }
        guard let appAccessToken = sessionAccessToken else {
            throw SupabaseManagementOAuthError.missingAppSession
        }

        let accessToken = try await SupabaseManagementOAuthService.shared.validAccessToken(
            appAccessToken: appAccessToken,
            requiredScopes: SupabaseManagementOAuthService.edgeFunctionSecretWriteScopes
        )
        try Self.syncSupabaseSecrets(
            projectRef: projectRef,
            secrets: hostedSecrets,
            accessToken: accessToken
        )

        let timestamp = ISO8601DateFormatter().string(from: Date())
        var nextState = projectBackendState.linking(
            to: .init(providerID: .supabase, projectRef: projectRef, projectURL: projectURL)
        )
        for secret in hostedSecrets {
            nextState = nextState.upsertingSecret(
                .init(
                    name: secret.name,
                    updatedAt: timestamp,
                    lastSyncedAt: timestamp
                )
            )
        }
        return nextState
    }
}
