import Foundation
import SwiftUI

enum BuilderGenerationTimeoutError: LocalizedError {
    case timedOut(operation: String, seconds: Int)

    var errorDescription: String? {
        switch self {
        case .timedOut(let operation, let seconds):
            return "Timed out after \(seconds) seconds while \(operation)."
        }
    }
}

private struct SupabaseMultipartFile {
    let fieldName: String
    let filename: String
    let data: Data
}

private struct SupabaseFunctionUpload {
    let functionName: String
    let entrypointPath: String
    let importMapPath: String?
    let files: [SupabaseMultipartFile]

    nonisolated func metadata(verifyJWT: Bool) -> [String: Any] {
        var value: [String: Any] = [
            "name": functionName,
            "entrypoint_path": entrypointPath,
            "verify_jwt": verifyJWT,
        ]
        if let importMapPath {
            value["import_map_path"] = importMapPath
        }
        return value
    }
}

extension BuilderViewModel {
    func validateDraft(text: String, attachments: [BuilderMessageAttachment]) -> String? {
        BuilderGenerationRequestPlanner.validateDraft(
            text: text,
            attachments: attachments,
            maxInlineTextAttachmentTokens: Self.maxInlineTextAttachmentTokens
        )
    }

    private func currentSessionAccessToken(fallback accessToken: String) -> String {
        let trimmed = sessionAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? accessToken : trimmed
    }

    func retryLastMessage(accessToken: String) {
        guard let failedRequest = lastFailedRequest else { return }
        lastFailedRequest = nil
        buildError = nil
        lastPreviewCompileError = nil
        latestBuildFixError = nil
        lastAutomaticBuildFixSignature = nil
        lastAutomaticBuildFixRevision = nil
        chatItems.removeAll { if case .error = $0 { return true }; return false }
        if let error = validateDraft(text: failedRequest.text, attachments: failedRequest.attachments) {
            chatItems.append(.error(id: UUID().uuidString, message: error))
            return
        }
        mode = failedRequest.mode
        startGeneration(
            failedRequest.text,
            attachments: failedRequest.attachments,
            accessToken: accessToken,
            appendUserMessage: false,
            requiredSkillNames: failedRequest.requiredSkillNames,
            messageAction: failedRequest.action
        )
    }

    @discardableResult
    func sendMessage(
        _ text: String,
        attachments: [BuilderMessageAttachment] = [],
        accessToken: String,
        requiredSkillNames: [String] = [],
        action: BuilderMessageAction? = nil
    ) -> String? {
        if let error = validateDraft(text: text, attachments: attachments) {
            return error
        }

        consecutiveAutomaticBuildFixFailures = 0
        lastAutomaticBuildFixSignature = nil
        lastAutomaticBuildFixRevision = nil
        if isGenerating || hasPendingUserResponse {
            messageQueue.append(
                QueuedMessage(
                    text: text,
                    attachments: attachments,
                    requiredSkillNames: requiredSkillNames,
                    action: action,
                    mode: mode
                )
            )
            return nil
        }
        startGeneration(
            text,
            attachments: attachments,
            accessToken: accessToken,
            appendUserMessage: true,
            requiredSkillNames: requiredSkillNames,
            messageAction: action
        )
        return nil
    }

    func moveQueuedMessages(from source: IndexSet, to destination: Int) {
        messageQueue.move(fromOffsets: source, toOffset: destination)
    }

    func removeQueuedMessage(at index: Int) {
        guard index < messageQueue.count else { return }
        messageQueue.remove(at: index)
    }

    func fixBuildError(accessToken: String) {
        guard let error = buildError else { return }
        latestBuildFixError = error
        let buildFixMessageId = appendBuildFixMessage(error: error)

        Task { await saveLocally() }
        let prompt = "The project failed to compile. Fix these errors:\n\n\(error)\n\nFix all errors and make sure the project compiles. Do not add any new features."
        startGeneration(
            prompt,
            accessToken: accessToken,
            appendUserMessage: false,
            isBuildFix: true,
            buildFixMessageId: buildFixMessageId
        )
    }

    func refreshBackendStatus(accessToken: String) async -> String {
        rememberAccessToken(accessToken)
        guard let project = activeProject else {
            return "Open a project first."
        }

        let workspaceRoot: URL
        if let localProjectPath {
            workspaceRoot = project.workspaceDescriptor.workspaceRootURL(projectRoot: localProjectPath)
        } else {
            workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("tenx-backend-\(project.id)", isDirectory: true)
        }

        guard let handlers = makeBackendToolHandlers(
            appAccessToken: accessToken,
            workspaceRoot: workspaceRoot
        ) else {
            return "Connect Supabase in Integrations first."
        }

        do {
            let snapshot = try await handlers.status()
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let nextState = projectBackendState
                .merging(snapshot: snapshot)
                .markingStatusRefreshed(at: timestamp)
            await handlers.persistState(nextState)
            return "Backend status refreshed."
        } catch {
            return "Failed to refresh backend status: \(error.localizedDescription)"
        }
    }

    func fixBackendFailure(_ failure: ProjectBackendFailureRecord, accessToken: String) {
        guard !isGenerating else { return }
        rememberAccessToken(accessToken)

        let function = projectBackendState.functions.first {
            $0.name.caseInsensitiveCompare(failure.functionName) == .orderedSame
        }
        let sourcePath = function?.sourcePath ?? "supabase/functions/\(failure.functionName)/index.ts"
        let relevantLogs = projectBackendState.recentLogs
            .filter {
                $0.functionName?.caseInsensitiveCompare(failure.functionName) == .orderedSame
                    || failure.relatedLogIDs.contains($0.id)
            }
            .prefix(6)
        let renderedLogs = relevantLogs.isEmpty
            ? "- none"
            : relevantLogs.map { log in
                "- [\(log.level.uppercased())] \(log.timestamp): \(log.message)"
            }.joined(separator: "\n")

        let prompt = """
        Fix the managed Supabase backend failure for the function `\(failure.functionName)`.

        Failure context:
        - Function: `\(failure.functionName)`
        - Source path: `\(sourcePath)`
        - Failure source: `\(failure.source.rawValue)`
        - Failure timestamp: \(failure.timestamp)
        - Request summary: \(failure.requestSummary ?? "none")
        - Error summary: \(failure.errorSummary)
        - Last deploy summary: \(projectBackendState.lastDeploySummary ?? "none")
        - Last deployed at: \(function?.lastDeployedAt ?? "never")
        - Last invocation summary: \(function?.lastInvocationSummary ?? "none")

        Relevant logs:
        \(renderedLogs)

        Requirements:
        - Fix the backend issue only.
        - Use the managed Supabase Backend path.
        - Keep secrets server-side.
        - Do not add unrelated features.
        """

        startGeneration(
            prompt,
            accessToken: accessToken,
            appendUserMessage: false,
            requiredSkillNames: ["backend"],
            previewRefreshOnCompletionOverride: false
        )
    }

    func prefillBackendPrompt(_ text: String) {
        pendingInputPrefill = text
        pendingAttachmentPrefill = []
        pendingRequiredSkillPrefill = ["backend"]
        pendingMessageActionPrefill = nil
    }

    func focusSourceFile(_ relativePath: String) {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedFile = trimmed
        viewMode = .development
    }

    func answerCurrentQuestion(_ answer: String, accessToken: String) {
        rememberAccessToken(accessToken)
        if let error = ProjectEnvironmentSecurity.secretPasteWarning(in: answer) {
            chatItems.append(.error(id: UUID().uuidString, message: error))
            return
        }
        guard var queue = questionQueue, let current = queue.currentQuestion else { return }
        queue.answers[current.question] = answer
        queue.currentIndex += 1

        if queue.isComplete {
            questionQueue = nil
            let answerText: String
            if queue.answers.count == 1, let only = queue.answers.values.first {
                answerText = only
            } else {
                answerText = queue.questions
                    .compactMap { q in
                        guard let a = queue.answers[q.question] else { return nil }
                        return "**\(q.question)**: \(a)"
                    }
                    .joined(separator: "\n\n")
            }

            if !activeSteps.isEmpty {
                let answeredSteps = finalizeAnsweredQuestionSteps(activeSteps)
                if answeredSteps != activeSteps {
                    flushToolStepsToChatIfNeeded(answeredSteps)
                    activeSteps = []
                } else {
                    activeSteps = answeredSteps
                }
            }

            let answerMsg = BuilderMessage(
                id: UUID().uuidString,
                conversationId: "",
                role: "user",
                content: answerText,
                versionId: nil,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                mode: mode
            )
            messages.append(answerMsg)
            chatItems.append(.message(answerMsg))
            scheduleGeneratedChatTitleIfNeeded()

            isGenerating = true
            generationStatus = .pickingBackUp
            Task {
                await saveLocally()
                await generationService.provideAskUserAnswer(answerText)
            }
        } else {
            questionQueue = queue
            Task { await saveLocally(touchChat: false) }
        }
    }

    func skipCurrentQuestion(accessToken: String) {
        answerCurrentQuestion("Skip — use your best judgment.", accessToken: accessToken)
    }

    func respondToIntegrationApproval(_ isApproved: Bool, accessToken: String) {
        rememberAccessToken(accessToken)
        guard integrationApproval != nil else { return }

        integrationApproval = nil
        isGenerating = true
        generationStatus = .pickingBackUp

        let response = isApproved ? "Allow" : "Don't Allow"
        Task {
            await saveLocally()
            await generationService.provideAskUserAnswer(response)
        }
    }

    func goToPreviousQuestion() {
        guard var queue = questionQueue, queue.currentIndex > 0 else { return }
        queue.currentIndex -= 1
        questionQueue = queue
        Task { await saveLocally(touchChat: false) }
    }

    func stopGeneration() {
        activeGenerationRunID = UUID()
        cancelPreviewWork()
        streamTask?.cancel()
        streamTask = nil
        Task { await generationService.cancelAskUser() }

        if !activeSteps.isEmpty {
            flushToolStepsToChatIfNeeded(
                finalizeUnfinishedToolSteps(
                    activeSteps,
                    fallbackOutput: "Generation was stopped before this tool call completed."
                )
            )
        }
        if !pendingAssistantContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let partialMsg = BuilderMessage(
                id: UUID().uuidString,
                conversationId: "",
                role: "assistant",
                content: pendingAssistantContent,
                versionId: nil,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                mode: mode
            )
            withAnimation(.none) {
                messages.append(partialMsg)
                chatItems.append(.message(partialMsg))
            }
            anchorDependencyChecklistIfNeeded(afterAssistantMessageId: partialMsg.id)
        }
        finalizePendingDependencyChecklistAnchorIfNeeded()

        activeSteps = []
        questionQueue = nil
        integrationApproval = nil
        isGenerating = false
        isAutoFixingBuild = false
        generationStatus = nil
        pendingAssistantContent = ""
        suppressIntermediateAssistantText = false

        Task { await saveLocally() }
    }

    func revertToMessage(_ id: String) async {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let msg = messages[idx]
        guard Self.isUserAuthoredMessage(msg) else { return }

        if isGenerating { stopGeneration() }

        let restoredSnapshot = generationSnapshots.last(where: { $0.messageCountBefore <= idx })
        var restoredTree = restoredSnapshot?.fileTree
        let restoredPlan = if let restoredSnapshot, restoredSnapshot.includesPlanState {
            restoredSnapshot.plan
        } else {
            projectPlan
        }
        let restoredTasks = if let restoredSnapshot, restoredSnapshot.includesProjectStatusState {
            restoredSnapshot.tasks
        } else {
            projectTasks
        }
        let restoredWarnings = if let restoredSnapshot, restoredSnapshot.includesProjectStatusState {
            restoredSnapshot.warnings ?? []
        } else {
            projectWarnings
        }
        var restoredCachedReadFiles = restoredSnapshot?.cachedReadFiles
        var restoredCachedReadFileOrder = restoredSnapshot?.cachedReadFileOrder
        let restoredContextState = restoredSnapshot?.contextState ?? .empty

        if restoredTree == nil {
            restoredTree = legacyRestoreTree(beforeMessageAt: idx)
            restoredCachedReadFiles = [:]
            restoredCachedReadFileOrder = []
        }

        if restoredTree == nil {
            let userMessagesBefore = messages.prefix(idx).filter(Self.isUserAuthoredMessage).count
            if userMessagesBefore == 0 {
                restoredTree = [:]
                restoredCachedReadFiles = [:]
                restoredCachedReadFileOrder = []
            } else if !versions.isEmpty {
                let targetIndex = versions.count - userMessagesBefore
                restoredTree = versions[max(0, targetIndex)].fileTree
                restoredCachedReadFiles = [:]
                restoredCachedReadFileOrder = []
            }
        }

        if let tree = restoredTree {
            fileTree = tree
        }
        projectPlan = restoredPlan
        projectTasks = restoredTasks
        projectWarnings = restoredWarnings
        cachedReadFiles = restoredCachedReadFiles ?? [:]
        cachedReadFileOrder = (restoredCachedReadFileOrder ?? []).filter { cachedReadFiles[$0] != nil }
        contextState = restoredContextState
        if cachedReadFileOrder.isEmpty, !cachedReadFiles.isEmpty {
            cachedReadFileOrder = cachedReadFiles.keys.sorted()
        }
        if !hasProjectStatusContent, viewMode == .roadmap {
            viewMode = .canvas
        }

        let restoredChatItems: [ChatItem]
        if chatItems.contains(where: { $0.id == id }) {
            restoredChatItems = Array(chatItems.prefix { $0.id != id })
        } else {
            restoredChatItems = messages.prefix(idx).compactMap { message in
                guard shouldRenderMessageInChat(message) else { return nil }
                return chatItem(from: message)
            }
        }

        messages = Array(messages.prefix(idx))
        chatItems = restoredChatItems
        ensureDependencyChecklistAnchorIfNeeded()
        pendingInputPrefill = msg.content
        pendingAttachmentPrefill = msg.attachments
        pendingRequiredSkillPrefill = msg.requiredSkillNames
        pendingMessageActionPrefill = msg.action

        buildError = nil
        pendingAssistantContent = ""
        activeSteps = []
        questionQueue = nil
        integrationApproval = nil
        generationStatus = nil
        showResumePrompt = false
        lastFailedRequest = nil
        isAutoFixingBuild = false
        consecutiveAutomaticBuildFixFailures = 0
        lastPreviewCompileError = nil
        latestBuildFixError = nil
        lastAutomaticBuildFixSignature = nil
        lastAutomaticBuildFixRevision = nil
        let shouldPreservePreviewDuringRevert = !(restoredTree?.isEmpty ?? true)
        if !shouldPreservePreviewDuringRevert {
            previewScreenshot = nil
        }
        cancelPreviewWork()

        generationSnapshots.removeAll(where: { $0.messageCountBefore >= idx })

        if let tree = restoredTree, let project = activeProject {
            if tree.isEmpty {
                await previewService.cleanProjectSources(
                    projectName: project.name,
                    projectId: project.id
                )
                localProjectPath = nil
                fileTreeRevision += 1
            } else {
                isReverting = true
                do {
                    let rootDir = try await previewService.writeProjectToDisk(
                        fileTree: tree,
                        projectName: project.name,
                        projectId: project.id,
                        customIcon: projectIcon,
                        environmentVariables: environmentVariables
                    )
                    localProjectPath = rootDir
                    fileWatcher?.updateBaseline(fileTree: tree)
                } catch {
                    print("[10x] Revert failed to write project to disk: \(error)")
                }
                isReverting = false
                fileTreeRevision += 1

                await runSimulatorPreview()
            }
        }

        await saveLocally()
    }

    func persistToSupabase(projectId: String) async {
        do {
            let (_, conversationId) = try await Self.withTimeout(
                seconds: 5,
                operation: "fetching the Supabase conversation"
            ) {
                try await self.supabase.fetchConversation(projectId: projectId)
            }
            guard let conversationId else { return }

            if !fileTree.isEmpty {
                let prompt = Self.lastUserAuthoredMessage(in: messages)?.previewText ?? ""
                _ = try await Self.withTimeout(
                    seconds: 8,
                    operation: "persisting the generated version to Supabase"
                ) {
                    try await self.supabase.createVersion(
                        projectId: projectId,
                        conversationId: conversationId,
                        fileTree: self.fileTree,
                        prompt: prompt
                    )
                }
            }
        } catch {
            print("[10x] Failed to persist to Supabase: \(error)")
        }
    }

    func firstNonEmpty(_ candidates: [String?]) -> String? {
        candidates.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    nonisolated static func shouldRunPreviewRefreshAfterGeneration(
        shouldRefreshPreviewOnCompletion: Bool,
        hasChanges: Bool,
        isBuildFix: Bool,
        hasFiles: Bool,
        fileTreeRevision: Int,
        lastPreviewedFileTreeRevision: Int?
    ) -> Bool {
        guard shouldRefreshPreviewOnCompletion else { return false }
        if hasChanges || isBuildFix { return true }
        guard hasFiles else { return false }
        guard let lastPreviewedFileTreeRevision else { return true }
        return fileTreeRevision > lastPreviewedFileTreeRevision
    }

    nonisolated static func shouldRequestPreviewRefreshOnCompletion(
        previewRefreshOnCompletionOverride: Bool?,
        isBuildFix: Bool,
        requestType: BuilderGenerationRequestType,
        currentMode: ProjectMode
    ) -> Bool {
        if let previewRefreshOnCompletionOverride {
            return previewRefreshOnCompletionOverride
        }
        if isBuildFix { return true }
        if requestType == .build { return true }
        return currentMode == .build
    }

    nonisolated static func previewRefreshOverrideForRestart(
        shouldRefreshPreviewOnCompletion: Bool
    ) -> Bool? {
        shouldRefreshPreviewOnCompletion ? true : nil
    }

    nonisolated static func withTimeout<T: Sendable>(
        seconds: Int,
        operation: String,
        task: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await task()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw BuilderGenerationTimeoutError.timedOut(operation: operation, seconds: seconds)
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    func continueAutomaticBuildFixIfPossible() {
        guard let error = lastPreviewCompileError else { return }
        print(
            "[provider] builder.auto_build_fix.check billingGroupId=\(currentBillingGroupId ?? "nil") failureCount=\(consecutiveAutomaticBuildFixFailures) hasError=true"
        )

        let normalizedErrorSignature = BuilderBuildFixSupport.normalizedSignature(for: error)
        if lastAutomaticBuildFixSignature == normalizedErrorSignature,
           lastAutomaticBuildFixRevision == fileTreeRevision {
            print("[10x] Skipping automatic build-fix retry because the same compiler error returned without any file changes.")
            appendAssistantMessage(
                "The latest build check is still returning the same compiler error without any source changes, so I stopped the automatic retry loop to avoid repeating the same fix attempt."
            )
            return
        }

        if consecutiveAutomaticBuildFixFailures >= Self.automaticBuildFixFailureLimit {
            print(
                "[10x] Automatic build-fix limit reached (\(Self.automaticBuildFixFailureLimit)). Returning latest build errors to the user."
            )
            appendAssistantMessage(
                "I’m still hitting compile errors after \(Self.automaticBuildFixFailureLimit) automatic repair attempts. Tell me what should happen or how you want me to fix it, and I’ll continue from the latest build errors above."
            )
            return
        }

        guard let accessToken = sessionAccessToken else {
            print("[10x] Cannot start automatic build-fix because no session access token is available.")
            return
        }
        print(
            "[10x] Automatically sending preview/build error to agent (attempt \(consecutiveAutomaticBuildFixFailures + 1) of \(Self.automaticBuildFixFailureLimit))."
        )
        print(
            "[provider] builder.auto_build_fix.start billingGroupId=\(currentBillingGroupId ?? "nil") attempt=\(consecutiveAutomaticBuildFixFailures + 1)"
        )
        lastAutomaticBuildFixSignature = normalizedErrorSignature
        lastAutomaticBuildFixRevision = fileTreeRevision
        buildError = error
        fixBuildError(accessToken: accessToken)
    }

    func appendAssistantMessage(_ content: String) {
        guard messages.last?.role != "assistant" || messages.last?.content != content else { return }

        let assistantMsg = BuilderMessage(
            id: UUID().uuidString,
            conversationId: "",
            role: "assistant",
            content: content,
            versionId: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            mode: mode
        )
        messages.append(assistantMsg)
        chatItems.append(.message(assistantMsg))
        anchorDependencyChecklistIfNeeded(afterAssistantMessageId: assistantMsg.id)
        Task { await saveLocally() }
    }

    func finalizeLatestBuildFix(messageId: String?) async {
        guard let messageId else { return }
        let latestCompileError = latestBuildFixError ?? lastPreviewCompileError
        let succeeded = latestCompileError == nil

        if let latestCompileError {
            updateBuildFixState(messageId: messageId, error: latestCompileError, resolved: false)
        } else {
            updateBuildFixState(messageId: messageId, error: nil, resolved: true)
        }

        if succeeded {
            consecutiveAutomaticBuildFixFailures = 0
            latestBuildFixError = nil
            lastAutomaticBuildFixSignature = nil
            lastAutomaticBuildFixRevision = nil
        } else {
            consecutiveAutomaticBuildFixFailures += 1
        }

        await saveLocally()
    }

    func appendBuildFixMessage(error: String) -> String {
        let fixContent = BuildFixContent(error: error, resolved: false)
        let contentJSON = (try? String(data: JSONEncoder().encode(fixContent), encoding: .utf8)) ?? error
        let fixMessage = BuilderMessage(
            id: UUID().uuidString,
            conversationId: "",
            role: "build_fix",
            content: contentJSON,
            versionId: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        messages.append(fixMessage)
        chatItems.append(.buildFix(id: fixMessage.id, error: error, resolved: false))
        return fixMessage.id
    }

    func updateBuildFixState(messageId: String, error: String?, resolved: Bool) {
        guard let msgIdx = messages.firstIndex(where: { $0.id == messageId && $0.role == "build_fix" }) else { return }

        let existingFix = messages[msgIdx].content.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode(BuildFixContent.self, from: $0) }
        let nextError = error ?? existingFix?.error ?? buildError ?? "Build fix in progress."
        let nextFix = BuildFixContent(error: nextError, resolved: resolved)

        if let newContent = try? String(data: JSONEncoder().encode(nextFix), encoding: .utf8) {
            messages[msgIdx].content = newContent
        }

        if let chatIdx = chatItems.lastIndex(where: {
            if case .buildFix(let id, _, _) = $0 {
                return id == messageId
            }
            return false
        }) {
            chatItems[chatIdx] = .buildFix(id: messageId, error: nextError, resolved: resolved)
        } else {
            chatItems.append(.buildFix(id: messageId, error: nextError, resolved: resolved))
        }
    }

    func startGeneration(
        _ text: String,
        attachments: [BuilderMessageAttachment] = [],
        accessToken: String,
        appendUserMessage: Bool,
        requiredSkillNames: [String] = [],
        messageAction: BuilderMessageAction? = nil,
        isBuildFix: Bool = false,
        restartContextNote: String? = nil,
        buildFixMessageId: String? = nil,
        previewRefreshOnCompletionOverride: Bool? = nil
    ) {
        rememberAccessToken(accessToken)
        guard let project = activeProject, !isGenerating else {
            print("[10x] startGeneration BLOCKED — activeProject: \(activeProject?.id ?? "nil"), isGenerating: \(isGenerating)")
            return
        }

        print("[10x] startGeneration — projectId: \(project.id), mode: \(mode.rawValue), appendUser: \(appendUserMessage)")
        let generationRunID = UUID()
        activeGenerationRunID = generationRunID
        generationSnapshots.append(
            ProjectSnapshot(
                messageCountBefore: messages.count,
                fileTree: fileTree,
                plan: projectPlan,
                tasks: projectTasks,
                warnings: activeRoadmapWarnings,
                cachedReadFiles: cachedReadFiles,
                cachedReadFileOrder: cachedReadFileOrder,
                contextState: contextState
            )
        )
        isGenerating = true
        isAutoFixingBuild = isBuildFix

        showResumePrompt = false
        pendingAssistantContent = ""
        activeSteps = []
        questionQueue = nil
        integrationApproval = nil
        generationStatus = .gettingReady
        buildError = nil
        lastPreviewCompileError = nil
        if !isBuildFix {
            latestBuildFixError = nil
        }
        lastFailedRequest = nil
        let effectiveRequiredSkillNames = resolvedRequiredSkillNames(
            explicit: requiredSkillNames,
            text: text,
            attachments: attachments,
            action: messageAction
        )

        if appendUserMessage {
            let tempMsg = BuilderMessage(
                id: UUID().uuidString,
                conversationId: "",
                role: "user",
                content: text,
                attachments: attachments,
                requiredSkillNames: effectiveRequiredSkillNames,
                action: messageAction,
                versionId: nil,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                mode: mode
            )
            messages.append(tempMsg)
            chatItems.append(.message(tempMsg))
            scheduleGeneratedChatTitleIfNeeded()

            Task { await saveLocally() }
        }

        let previewFromText = BuilderGenerationRequestPlanner.billingMessagePreview(from: text)
        if appendUserMessage {
            currentBillingGroupId = UUID().uuidString
            currentBillingMessagePreview = previewFromText
        } else if currentBillingGroupId == nil {
            currentBillingGroupId = UUID().uuidString
            currentBillingMessagePreview = previewFromText ?? Self.lastUserAuthoredMessage(in: messages)?.previewText
        } else if currentBillingMessagePreview == nil {
            currentBillingMessagePreview = previewFromText ?? Self.lastUserAuthoredMessage(in: messages)?.previewText
        }
        let billingGroupId = currentBillingGroupId ?? UUID().uuidString
        currentBillingGroupId = billingGroupId
        print(
            "[provider] builder.start_generation projectId=\(project.id) sessionId=\(activeChat?.id ?? "nil") appendUser=\(appendUserMessage) isBuildFix=\(isBuildFix) mode=\(mode.rawValue) billingGroupId=\(billingGroupId) preview=\(currentBillingMessagePreview ?? "")"
        )

        var restartContinuation: RestartContinuation?
        var currentSegmentContent = ""
        if let modeSwitch = BuilderGenerationRequestPlanner.explicitModeSwitch(
            for: messageAction,
            currentMode: mode
        ) {
            mode = modeSwitch.mode
            appendSystemEventToChat(BuilderSystemEvent(
                kind: .modeChange,
                title: "Mode switched to \(modeSwitch.mode.label)",
                detail: modeSwitch.detail
            ))
        }
        let requestType = BuilderGenerationRequestPlanner.classifyGenerationRequest(
            requestText: text,
            isBuildFix: isBuildFix,
            messageAction: messageAction
        )
        let activeIntegrationToolAvailability = self.integrationToolAvailability
        let requestOptions = BuilderGenerationRequestPlanner.requestOptionsForGeneration(requestType: requestType)
        let generationTools = BuilderGenerationRequestPlanner.toolsForGeneration(
            requestType: requestType,
            mode: mode,
            integrationAvailability: activeIntegrationToolAvailability
        )
        let shouldRefreshPreviewOnCompletion = Self.shouldRequestPreviewRefreshOnCompletion(
            previewRefreshOnCompletionOverride: previewRefreshOnCompletionOverride,
            isBuildFix: isBuildFix,
            requestType: requestType,
            currentMode: mode
        )
        suppressIntermediateAssistantText = BuilderGenerationRequestPlanner.shouldSuppressIntermediateAssistantText(
            requestType: requestType,
            mode: mode,
            hasFileTree: !fileTree.isEmpty
        )
        persistCurrentRunToolSteps = true

        streamTask = Task {
            let projectDir: URL
            if let existing = localProjectPath {
                projectDir = existing
            } else {
                do {
                    projectDir = try await previewService.scaffoldProjectDirectory(
                        projectName: project.name,
                        projectId: project.id
                    )
                    guard generationRunID == activeGenerationRunID else { return }
                    localProjectPath = projectDir
                } catch {
                    guard generationRunID == activeGenerationRunID else { return }
                    buildError = "Failed to create project directory: \(error.localizedDescription)"
                    isGenerating = false
                    return
                }
            }
            let workspaceDescriptor = project.workspaceDescriptor
            let workspaceRoot = workspaceDescriptor.workspaceRootURL(projectRoot: projectDir)

            let api = APIClient()
            let initialAccessToken = accessToken
            let targetName = XcodePreviewService.targetName(from: project.name)
            let skills = skillsManager
            let currentAccessToken: @Sendable () async -> String = { [weak self] in
                guard let self else { return initialAccessToken }
                return await self.currentSessionAccessToken(fallback: initialAccessToken)
            }
            let supabaseToolHandlers = activeIntegrationToolAvailability.hasSupabaseAccess
                ? makeSupabaseToolHandlers(appAccessToken: initialAccessToken)
                : nil
            let backendToolHandlers = activeIntegrationToolAvailability.hasSupabaseAccess
                ? makeBackendToolHandlers(
                    appAccessToken: initialAccessToken,
                    workspaceRoot: workspaceRoot
                )
                : nil
            // Superwall removed in 11x local cockpit
            let toolExecutor = ToolExecutor(
                workspaceRoot: workspaceRoot,
                projectName: project.name,
                targetName: targetName,
                currentMode: mode,
                fileTree: fileTree,
                environmentVariables: toolEnvironmentValuesByKey,
                environmentVariableMetadata: environmentVariables,
                projectBackendState: projectBackendState,
                projectSuperwallState: projectSuperwallState,
                webSearchHandler: { query in
                    do {
                        let accessToken = await currentAccessToken()
                        let response: [String: String] = try await api.post(
                            APIClient.builder("web-search"),
                            json: ["query": query],
                            accessToken: accessToken
                        )
                        return response["result"] ?? "No results found."
                    } catch {
                        return "Web search failed: \(error.localizedDescription)"
                    }
                },
                urlScrapeHandler: { url in
                    do {
                        let accessToken = await currentAccessToken()
                        let response: [String: String] = try await api.post(
                            APIClient.builder("scrape-url"),
                            json: ["url": url],
                            accessToken: accessToken
                        )
                        return response["result"] ?? "No page contents found."
                    } catch {
                        return "URL scrape failed: \(error.localizedDescription)"
                    }
                },
                projectIdentityHandler: { [weak self] name, imageFilename in
                    guard let self else { return "Error: project identity update failed." }
                    return await self.setProjectIdentity(name: name, imageFilename: imageFilename)
                },
                appStoreReviewHandler: { [weak self] input in
                    guard let self else { return "Error: App Store review update failed." }
                    return await self.handleAppStoreReviewTool(input)
                },
                skillsListHandler: {
                    await skills.listSkills(accessToken: await currentAccessToken())
                },
                skillsUseHandler: { name in
                    await skills.useSkill(name: name, accessToken: await currentAccessToken())
                },
                supabaseToolHandlers: supabaseToolHandlers,
                backendToolHandlers: backendToolHandlers,
            )

            let promptAccessToken = await currentAccessToken()
            let skillsCatalogSection = await skillsManager.catalogSection(accessToken: promptAccessToken)

            let systemPrompt = BuilderPrompts.systemPrompt(mode: mode)
            let promptContext = BuilderPrompts.messageContext(
                mode: mode,
                projectName: project.name,
                currentFileTree: fileTree,
                plan: projectPlan,
                tasks: projectTasks,
                warnings: activeRoadmapWarnings,
                dependencyManifest: projectDependencyManifest,
                backendState: projectBackendState,
                designStyle: designStyle,
                environmentVariables: environmentVariables,
                hasCustomProjectIcon: projectIcon != nil,
                skillsCatalogSection: skillsCatalogSection
            )
            let preparedConversationContext = await contextManager.prepareConversationContext(
                system: systemPrompt,
                messages: messages,
                timeline: persistedTimelineSnapshot(),
                cachedReadFiles: cachedReadFiles,
                cachedReadFileOrder: cachedReadFileOrder,
                projectPlan: projectPlan,
                projectTasks: projectTasks,
                prefixMessages: promptContext.prefixMessages,
                preUserMessages: promptContext.preUserMessages,
                tools: generationTools,
                requestOptions: requestOptions,
                maxTokens: 64_000,
                accessToken: promptAccessToken
            )
            guard generationRunID == activeGenerationRunID else { return }
            contextState = preparedConversationContext.contextState
            var claudeMessages = preparedConversationContext.messages
            if let restartContextNote, !restartContextNote.isEmpty {
                claudeMessages.append(["role": "user", "content": restartContextNote])
            }
            if isBuildFix && !text.isEmpty {
                claudeMessages.append(["role": "user", "content": text])
            }
            print(
                "[10x] Assembled turn context: approx=\(preparedConversationContext.approximateInputTokens) exact=\(preparedConversationContext.exactInputTokens.map(String.init) ?? "n/a") raw_kept=\(preparedConversationContext.includedRawMessageCount) raw_omitted=\(preparedConversationContext.omittedRawMessageCount) working_files=\(preparedConversationContext.includedWorkingFileCount) used_memory=\(preparedConversationContext.usedContextMemory ? "yes" : "no")"
            )

            print("[10x] Starting client-side generation for project \(project.id)...")

            let generationOutcome = await generationService.runGeneration(
                systemPrompt: systemPrompt,
                claudeMessages: claudeMessages,
                tools: generationTools,
                requestOptions: requestOptions,
                toolExecutor: toolExecutor,
                accessToken: initialAccessToken,
                accessTokenProvider: { await currentAccessToken() },
                projectId: project.id,
                sessionId: activeChat?.id,
                billingGroupId: billingGroupId,
                billingMessagePreview: currentBillingMessagePreview,
                onClaudeCallFinished: { [weak self] in
                    // Billing refresh disabled in 11x local cockpit
                }
            ) { [weak self] event in
                guard let self else { return }
                self.handleGenerationEvent(
                    event,
                    text: text,
                    attachments: attachments,
                    requiredSkillNames: effectiveRequiredSkillNames,
                    generationRunID: generationRunID,
                    messageAction: messageAction,
                    accessToken: accessToken,
                    buildFixMessageId: buildFixMessageId,
                    currentSegmentContent: &currentSegmentContent,
                    restartContinuation: &restartContinuation
                )
            }

            guard generationRunID == activeGenerationRunID else { return }
            let updatedTree = await toolExecutor.fileTree
            fileTree = updatedTree

            let hasChanges = await toolExecutor.filesChanged.count > 0
            if hasChanges, !fileTree.isEmpty, !workspaceDescriptor.isImported {
                do {
                    try await previewService.regenerateXcodeProject(
                        projectName: project.name,
                        projectId: project.id,
                        fileTree: fileTree,
                        customIcon: projectIcon,
                        environmentVariables: environmentVariables
                    )
                } catch {
                    print("Failed to regenerate Xcode project: \(error)")
                }
            }

            print("[10x] Generation finished. isGenerating -> false")

            isGenerating = false
            generationStatus = nil
            pendingAssistantContent = ""
            suppressIntermediateAssistantText = false

            await saveLocally()

            let generationFailed: Bool
            switch generationOutcome {
            case .completed:
                generationFailed = false
            case .failed:
                generationFailed = true
            }

            guard generationRunID == activeGenerationRunID else { return }

            if let restartContinuation, !generationFailed {
                print("[10x] Restarting generation with refreshed project context.")
                print(
                    "[provider] builder.restart_generation reason=restart_note billingGroupId=\(billingGroupId) note=\(restartContinuation.note)"
                )
                appendSystemEventToChat(restartContinuation.event)
                await saveLocally()
                let nextAccessToken = await currentAccessToken()
                startGeneration(
                    "",
                    accessToken: nextAccessToken,
                    appendUserMessage: false,
                    requiredSkillNames: effectiveRequiredSkillNames,
                    messageAction: messageAction,
                    restartContextNote: restartContinuation.note,
                    previewRefreshOnCompletionOverride: Self.previewRefreshOverrideForRestart(
                        shouldRefreshPreviewOnCompletion: shouldRefreshPreviewOnCompletion
                    )
                )
                return
            }

            if generationFailed {
                if isBuildFix {
                    await finalizeLatestBuildFix(messageId: buildFixMessageId)
                }
                return
            }

            if !messageQueue.isEmpty {
                let next = messageQueue.removeFirst()
                if let error = validateDraft(text: next.text, attachments: next.attachments) {
                    chatItems.append(.error(id: UUID().uuidString, message: error))
                } else {
                    mode = next.mode
                    print(
                        "[provider] builder.dequeue_generation previousBillingGroupId=\(billingGroupId) nextMode=\(next.mode.rawValue)"
                    )
                    let nextAccessToken = await currentAccessToken()
                    startGeneration(
                        next.text,
                        attachments: next.attachments,
                        accessToken: nextAccessToken,
                        appendUserMessage: true,
                        requiredSkillNames: next.requiredSkillNames,
                        messageAction: next.action
                    )
                    return
                }
            }

            isAutoFixingBuild = false

            if Self.shouldRunPreviewRefreshAfterGeneration(
                shouldRefreshPreviewOnCompletion: shouldRefreshPreviewOnCompletion,
                hasChanges: hasChanges,
                isBuildFix: isBuildFix,
                hasFiles: !fileTree.isEmpty,
                fileTreeRevision: fileTreeRevision,
                lastPreviewedFileTreeRevision: lastPreviewedFileTreeRevision
            ) {
                print("[provider] builder.preview_refresh billingGroupId=\(billingGroupId)")
                await runSimulatorPreview(
                    autoFixIfNeeded: true,
                    buildFixMessageId: buildFixMessageId
                )
                guard generationRunID == activeGenerationRunID else { return }
                if isGenerating {
                    return
                }
            }

            guard generationRunID == activeGenerationRunID else { return }
            await persistToSupabase(projectId: project.id)

            if isBuildFix {
                await finalizeLatestBuildFix(messageId: buildFixMessageId)
            } else {
                consecutiveAutomaticBuildFixFailures = 0
            }
        }
    }

    func handleGenerationEvent(
        _ event: GenerationEvent,
        text: String,
        attachments: [BuilderMessageAttachment],
        requiredSkillNames: [String],
        generationRunID: UUID,
        messageAction: BuilderMessageAction?,
        accessToken: String,
        buildFixMessageId: String?,
        currentSegmentContent: inout String,
        restartContinuation: inout RestartContinuation?
    ) {
        guard generationRunID == activeGenerationRunID else { return }
        switch event {
        case .content(let delta):
            if !activeSteps.isEmpty && activeSteps.allSatisfy({ $0.status != .running }) {
                flushToolStepsToChatIfNeeded(activeSteps)
                activeSteps = []
            }

            currentSegmentContent += delta
            if suppressIntermediateAssistantText {
                pendingAssistantContent = ""
            } else {
                pendingAssistantContent = currentSegmentContent
            }
            if !delta.isEmpty {
                generationStatus = nil
            }

        case .status(let status):
            generationStatus = status

        case .toolCallStart(let toolUseId, let name):
            if !currentSegmentContent.isEmpty {
                if !suppressIntermediateAssistantText || name == "ask_user" {
                    appendAssistantSegmentMessage(currentSegmentContent)
                }
                currentSegmentContent = ""
                pendingAssistantContent = ""
            }

            let label = BuilderToolPresentation.shortLabel(name: name)
            activeSteps.append(BuilderToolStep(
                toolUseId: toolUseId,
                name: name,
                label: label,
                status: .running
            ))

        case .toolCallUpdate(let toolUseId, let label, let inputPreview):
            if let idx = activeSteps.lastIndex(where: { $0.toolUseId == toolUseId && $0.status == .running }) {
                activeSteps[idx].label = label
                if !inputPreview.isEmpty {
                    activeSteps[idx].inputPreview = inputPreview
                }
                Task { await saveLocally(touchChat: false) }
            }

        case .toolCallEnd(let toolUseId, let name, let durationMs, let status, let inputPreview, let outputPreview):
            if let idx = activeSteps.lastIndex(where: {
                $0.toolUseId == toolUseId
            }) ?? activeSteps.lastIndex(where: {
                $0.toolUseId == nil && $0.name == name && $0.status == .running
            }) {
                activeSteps[idx].status = status == "success" ? .success : .error
                activeSteps[idx].durationMs = durationMs
                if !inputPreview.isEmpty { activeSteps[idx].inputPreview = inputPreview }
                if !outputPreview.isEmpty { activeSteps[idx].outputPreview = outputPreview }
                Task { await saveLocally(touchChat: false) }
            }

            if isAutoFixingBuild,
               name == "run_command",
               BuilderBuildFixSupport.isBuildCheckCommand(inputPreview),
               let latestCompilerError = BuilderBuildFixSupport.extractCompilerDiagnostics(from: outputPreview) {
                latestBuildFixError = latestCompilerError
                if let buildFixMessageId {
                    updateBuildFixState(messageId: buildFixMessageId, error: latestCompilerError, resolved: false)
                }
            } else if isAutoFixingBuild,
                      name == "run_command",
                      BuilderBuildFixSupport.isBuildCheckCommand(inputPreview),
                      status == "success" {
                latestBuildFixError = nil
            }

        case .readFile(let path, let content):
            cacheFileSnapshot(path: path, content: content)
            if let idx = activeSteps.lastIndex(where: {
                $0.name == "read_files" && $0.status == .running
            }) {
                activeSteps[idx].label = "Reading \(path)"
            }

        case .fileChanged(let path, let content, let action):
            if action == "delete" {
                fileTree.removeValue(forKey: path)
                removeCachedFileSnapshot(path: path)
            } else {
                fileTree[path] = content
                // Persist writes and edits into the same snapshot cache used for prior reads
                // so follow-up turns can reuse the last known file contents without re-reading.
                cacheFileSnapshot(path: path, content: content)
            }
            fileTreeRevision += 1
            if let idx = activeSteps.lastIndex(where: {
                ["write_file", "edit_file", "delete_file"].contains($0.name)
                && $0.status == .running
            }) {
                let verb = action == "delete" ? "Deleting" : (action == "update" ? "Updating" : "Creating")
                activeSteps[idx].label = "\(verb) \(path)"
            }

        case .planUpdate(let plan):
            projectPlan = plan

        case .tasksUpdate(let tasks):
            projectTasks = tasks

        case .warningsUpdate(let warnings):
            projectWarnings = warnings

        case .dependenciesUpdate(let manifest):
            projectDependencyManifest = manifest
            ensureDependencyChecklistAnchorIfNeeded()
            markDependencyChecklistForCurrentTurn()
            Task {
                await saveProjectDependencyManifest(manifest)
            }

        case .modeChange(let newMode):
            if let parsed = ProjectMode(rawValue: newMode) {
                mode = parsed
                restartContinuation = Self.makeModeChangeRestartContinuation(mode: parsed)
            }

        case .projectIdentityChange(let name):
            restartContinuation = Self.makeProjectRenameRestartContinuation(name: name)

        case .askUser(let questions, let toolUseId):
            let parsed = questions.map { q in
                AskUserQuestion(
                    question: q["question"] as? String ?? "",
                    options: q["options"] as? [String],
                    multiSelect: q["multi_select"] as? Bool ?? false
                )
            }
            integrationApproval = nil
            questionQueue = QuestionQueue(questions: parsed, toolUseId: toolUseId)
            if !currentSegmentContent.isEmpty {
                if !suppressIntermediateAssistantText {
                    appendAssistantSegmentMessage(currentSegmentContent)
                }
            }
            finalizePendingDependencyChecklistAnchorIfNeeded()
            pendingAssistantContent = ""
            currentSegmentContent = ""

            isGenerating = false
            generationStatus = nil
            Task { await saveLocally() }

        case .integrationApprovalRequested(let request, let toolUseId):
            questionQueue = nil
            integrationApproval = IntegrationApprovalState(request: request, toolUseId: toolUseId)
            if !currentSegmentContent.isEmpty {
                if !suppressIntermediateAssistantText {
                    appendAssistantSegmentMessage(currentSegmentContent)
                }
            }
            finalizePendingDependencyChecklistAnchorIfNeeded()
            pendingAssistantContent = ""
            currentSegmentContent = ""

            isGenerating = false
            generationStatus = nil
            Task { await saveLocally() }

        case .done(let accumulatedText, _):
            let finalizedSteps = finalizeUnfinishedToolSteps(
                activeSteps,
                fallbackOutput: restartContinuation == nil
                    ? "Tool call did not complete."
                    : "Skipped because the session restarted with refreshed project context."
            )
            if !finalizedSteps.isEmpty {
                flushToolStepsToChatIfNeeded(finalizedSteps)
                activeSteps = []
            }
            if !currentSegmentContent.isEmpty {
                appendAssistantSegmentMessage(currentSegmentContent)
            } else if accumulatedText.isEmpty {
                let assistantMsg = BuilderMessage(
                    id: UUID().uuidString,
                    conversationId: "",
                    role: "assistant",
                    content: "",
                    versionId: nil,
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    mode: mode
                )
                withAnimation(.none) {
                    messages.append(assistantMsg)
                    chatItems.append(.message(assistantMsg))
                }
                anchorDependencyChecklistIfNeeded(afterAssistantMessageId: assistantMsg.id)
            }
            finalizePendingDependencyChecklistAnchorIfNeeded()
            pendingAssistantContent = ""
            currentSegmentContent = ""
            generationStatus = nil

        case .error(let message):
            if !currentSegmentContent.isEmpty {
                appendAssistantSegmentMessage(currentSegmentContent)
                currentSegmentContent = ""
            }
            if !activeSteps.isEmpty {
                flushToolStepsToChatIfNeeded(
                    finalizeUnfinishedToolSteps(
                        activeSteps,
                        fallbackOutput: "Generation stopped before this tool call completed."
                    )
                )
                activeSteps = []
            }
            finalizePendingDependencyChecklistAnchorIfNeeded()
            pendingAssistantContent = ""
            generationStatus = nil
            if isAutoFixingBuild {
                if let latestCompilerError = BuilderBuildFixSupport.extractCompilerDiagnostics(from: message) {
                    latestBuildFixError = latestCompilerError
                    if let buildFixMessageId {
                        updateBuildFixState(messageId: buildFixMessageId, error: latestCompilerError, resolved: false)
                    }
                }
                lastFailedRequest = nil
                chatItems.append(.error(id: UUID().uuidString, message: message))
                return
            }
            lastFailedRequest = QueuedMessage(
                text: text,
                attachments: attachments,
                requiredSkillNames: requiredSkillNames,
                action: messageAction,
                mode: mode
            )
            chatItems.append(.error(id: UUID().uuidString, message: message))
        }
    }

    func appendAssistantSegmentMessage(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = BuilderMessage(
            id: UUID().uuidString,
            conversationId: "",
            role: "assistant",
            content: content,
            versionId: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            mode: mode
        )
        withAnimation(.none) {
            messages.append(message)
            chatItems.append(.message(message))
        }
        anchorDependencyChecklistIfNeeded(afterAssistantMessageId: message.id)
    }

    func cacheFileSnapshot(path: String, content: String) {
        cachedReadFiles[path] = content
        cachedReadFileOrder.removeAll { $0 == path }
        cachedReadFileOrder.append(path)
    }

    func removeCachedFileSnapshot(path: String) {
        cachedReadFiles.removeValue(forKey: path)
        cachedReadFileOrder.removeAll { $0 == path }
    }

    static func makeModeChangeRestartContinuation(mode: ProjectMode) -> RestartContinuation {
        RestartContinuation(
            note: "[Mode switched to \(mode.label). Continue with the current plan and files. Do not re-ask questions or switch modes.]",
            event: BuilderSystemEvent(
                kind: .modeChange,
                title: "Mode switched to \(mode.label)",
                detail: "Continuing with refreshed project context."
            )
        )
    }

    static func makeProjectRenameRestartContinuation(name: String) -> RestartContinuation {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Untitled Project" : trimmedName
        return RestartContinuation(
            note: "[Project renamed to \(displayName). Continue with the current plan and files. Do not rename it again unless asked.]",
            event: BuilderSystemEvent(
                kind: .projectRename,
                title: "Project renamed to \(displayName)",
                detail: "Continuing with refreshed project context."
            )
        )
    }

    private func makeSupabaseToolHandlers(appAccessToken: String) -> SupabaseToolHandlers? {
        guard let projectRef = SupabaseManagementService.projectRef(from: environmentValuesByKey["SUPABASE_URL"]) else {
            return nil
        }

        let oauthService = SupabaseManagementOAuthService.shared
        let managementService = SupabaseManagementService.shared
        let currentAppAccessToken: @Sendable () async -> String = { [weak self] in
            guard let self else { return appAccessToken }
            return await self.currentSessionAccessToken(fallback: appAccessToken)
        }

        let authorize: @Sendable () async throws -> Void = {
            _ = try await oauthService.validAccessToken(appAccessToken: await currentAppAccessToken())
        }

        return SupabaseToolHandlers(
            read: { input in
                try await authorize()
                return try await managementService.readForAgent(
                    projectRef: projectRef,
                    input: input
                )
            },
            write: { input in
                try await authorize()
                return try await managementService.writeForAgent(
                    projectRef: projectRef,
                    input: input
                )
            },
            sql: { input in
                try await authorize()
                return try await managementService.executeSQLForAgent(
                    projectRef: projectRef,
                    input: input
                )
            },
            settings: { input in
                try await authorize()
                return try await managementService.manageSettingsForAgent(
                    projectRef: projectRef,
                    input: input
                )
            }
        )
    }

    private func makeBackendToolHandlers(
        appAccessToken: String,
        workspaceRoot: URL
    ) -> BackendToolHandlers? {
        guard activeProject != nil,
              let projectURL = environmentValuesByKey["SUPABASE_URL"],
              let projectRef = SupabaseManagementService.projectRef(from: projectURL) else {
            return nil
        }

        let oauthService = SupabaseManagementOAuthService.shared
        let knownRemoteSecrets = projectBackendState.secrets.map(\.name)
        let publicAPIKey = environmentValuesByKey["SUPABASE_ANON_KEY"] ?? environmentValuesByKey["SUPABASE_PUBLISHABLE_KEY"]
        let hostedEnvironmentVariables = environmentVariables
        let currentAppAccessToken: @Sendable () async -> String = { [weak self] in
            guard let self else { return appAccessToken }
            return await self.currentSessionAccessToken(fallback: appAccessToken)
        }

        let authorize: @Sendable ([String]) async throws -> String = { requiredScopes in
            return try await oauthService.validAccessToken(
                appAccessToken: await currentAppAccessToken(),
                requiredScopes: requiredScopes
            )
        }

        return BackendToolHandlers(
            status: {
                let localFunctions = Self.discoverLocalSupabaseFunctions(in: workspaceRoot)
                let localSecrets = Self.hostedBackendSecretNames(variables: hostedEnvironmentVariables)
                let remoteFunctions = (try? await authorize(["edge_functions_read"])).flatMap { accessToken in
                    try? Self.listSupabaseFunctionNames(
                        projectRef: projectRef,
                        accessToken: accessToken
                    )
                } ?? []
                let remoteSecrets = (try? await authorize(["edge_functions_secrets_read"])).flatMap { accessToken in
                    try? Self.listSupabaseSecretNames(
                        projectRef: projectRef,
                        accessToken: accessToken
                    )
                } ?? []

                return BackendStatusSnapshot(
                    providerID: .supabase,
                    projectRef: projectRef,
                    projectURL: projectURL,
                    remoteFunctionNames: Self.sortedUniqueStrings(localFunctions + remoteFunctions),
                    remoteSecretNames: Self.sortedUniqueStrings(knownRemoteSecrets + localSecrets + remoteSecrets)
                )
            },
            linkProvider: {
                _ = try await authorize([])
                return BackendProviderLink(
                    providerID: .supabase,
                    projectRef: projectRef,
                    projectURL: projectURL
                )
            },
            deploy: { input in
                let hostedSecrets = Self.hostedBackendSecrets(variables: hostedEnvironmentVariables)
                do {
                    let accessToken = try await authorize(
                        hostedSecrets.isEmpty
                            ? ["edge_functions_write"]
                            : SupabaseManagementOAuthService.managedBackendWriteScopes
                    )
                    if !hostedSecrets.isEmpty {
                        try Self.syncSupabaseSecrets(
                            projectRef: projectRef,
                            secrets: hostedSecrets,
                            accessToken: accessToken
                        )
                    }
                    return try Self.deploySupabaseFunction(
                        projectRef: projectRef,
                        functionName: input.functionName,
                        verifyJWT: input.verifyJWT,
                        accessToken: accessToken,
                        workspaceRoot: workspaceRoot
                    )
                } catch {
                    throw Self.normalizedSupabaseBackendError(
                        error,
                        action: "deploy backend changes"
                    )
                }
            },
            invoke: { input in
                return try await Self.invokeSupabaseFunction(
                    projectURL: projectURL,
                    publicAPIKey: publicAPIKey,
                    functionName: input.functionName,
                    requestJSON: input.requestJSON,
                    authMode: input.authMode,
                    userAccessToken: await currentAppAccessToken()
                )
            },
            setSecret: { secretName, secretValue in
                do {
                    let accessToken = try await authorize(["edge_functions_secrets_write"])
                    return try Self.setSupabaseSecret(
                        projectRef: projectRef,
                        secretName: secretName,
                        secretValue: secretValue,
                        accessToken: accessToken
                    )
                } catch {
                    throw Self.normalizedSupabaseBackendError(
                        error,
                        action: "sync backend secrets"
                    )
                }
            },
            listLogs: { _, _ in
                []
            },
            persistState: { [weak self] state in
                guard let self else { return }
                await self.saveProjectBackendState(state)
            }
        )
    }

    private func makeSuperwallToolHandlers() -> SuperwallToolHandlers? {
        guard let project = activeProject else { return nil }

        let service = SuperwallManagementService.shared
        let projectName = project.name
        let projectID = project.id
        let suggestedPlacements = ProjectSuperwallState.suggestedPlacements(
            plan: projectPlan,
            tasks: projectTasks
        )

        return SuperwallToolHandlers(
            status: { state in
                await service.statusText(for: state)
            },
            bootstrapProject: { [weak self] input, state in
                let bundleID = XcodePreviewService.bundleId(from: projectName)
                let nextState = try await service.bootstrapProject(
                    projectName: projectName,
                    bundleID: bundleID,
                    state: state,
                    preferredOrganizationID: input.organizationID,
                    preferredProjectID: input.projectID,
                    preferredApplicationID: input.applicationID
                )
                await self?.upsertSuperwallPublicAPIKeyIfNeeded(nextState.applicationPublicAPIKey)
                return SuperwallToolOperationResult(
                    state: nextState,
                    summary: "Linked Superwall project `\(nextState.projectName ?? "unknown")`."
                )
            },
            bootstrapStarterMonetization: { [weak self] input, state in
                let bundleID = XcodePreviewService.bundleId(from: projectName)
                let previewAppUserID = Self.trimmedNonEmpty(input.previewAppUserID)
                    ?? "tenx-preview-\(projectID)"
                let placements = (input.placements?.isEmpty == false ? input.placements : nil) ?? suggestedPlacements
                let nextState = try await service.bootstrapStarterMonetization(
                    state: state,
                    bundleID: bundleID,
                    placements: placements,
                    previewAppUserID: previewAppUserID,
                    paywallID: input.paywallID
                )
                await self?.upsertSuperwallPublicAPIKeyIfNeeded(nextState.applicationPublicAPIKey)
                return SuperwallToolOperationResult(
                    state: nextState,
                    summary: "Attached starter Superwall monetization to `\(nextState.paywallName ?? "selected paywall")` with \(nextState.products.count) product(s), \(nextState.placements.count) placement(s), and preview user `\(previewAppUserID)`."
                )
            },
            syncPreviewTestUser: { input, state in
                let previewAppUserID = Self.trimmedNonEmpty(input.previewAppUserID)
                    ?? state.previewAppUserID
                    ?? "tenx-preview-\(projectID)"
                let nextState = try await service.syncPreviewTestUser(
                    state: state,
                    previewAppUserID: previewAppUserID
                )
                return SuperwallToolOperationResult(
                    state: nextState,
                    summary: "Marked `\(previewAppUserID)` as a Superwall test-mode user."
                )
            },
            listPaywalls: { state in
                guard let applicationID = state.applicationID else {
                    throw SuperwallManagementServiceError.invalidInput("Link a Superwall application first.")
                }
                return try await service.listPaywalls(applicationID: applicationID)
            },
            listTemplates: { state in
                guard let applicationID = state.applicationID else {
                    throw SuperwallManagementServiceError.invalidInput("Link a Superwall application first.")
                }
                return try await service.listTemplates(applicationID: applicationID)
            },
            openDashboard: { state in
                guard let urlString = Self.trimmedNonEmpty(state.applicationDashboardURL),
                      let url = URL(string: urlString) else {
                    throw SuperwallManagementServiceError.invalidInput("Link a Superwall application first.")
                }
                let opened = await MainActor.run {
                    NSWorkspace.shared.open(url)
                }
                if opened {
                    return "Opened the linked Superwall dashboard."
                }
                throw SuperwallManagementServiceError.invalidInput("Couldn't open the Superwall dashboard.")
            },
            openPaywalls: { state in
                guard let url = state.paywallsDashboardURL else {
                    throw SuperwallManagementServiceError.invalidInput("Link a Superwall application first.")
                }
                let opened = await MainActor.run {
                    NSWorkspace.shared.open(url)
                }
                if opened {
                    return "Opened the linked Superwall paywalls."
                }
                throw SuperwallManagementServiceError.invalidInput("Couldn't open the Superwall paywalls.")
            },
            openTemplates: { state in
                guard let url = state.templatesDashboardURL else {
                    throw SuperwallManagementServiceError.invalidInput("Link a Superwall application first.")
                }
                let opened = await MainActor.run {
                    NSWorkspace.shared.open(url)
                }
                if opened {
                    return "Opened the linked Superwall templates."
                }
                throw SuperwallManagementServiceError.invalidInput("Couldn't open the Superwall templates.")
            },
            persistState: { [weak self] state in
                guard let self else { return }
                await self.saveProjectSuperwallState(state)
            }
        )
    }

    private func upsertSuperwallPublicAPIKeyIfNeeded(_ publicAPIKey: String?) async {
        let trimmedValue = publicAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedValue.isEmpty else { return }

        let envKey = "SUPERWALL_PUBLIC_API_KEY"
        let currentValue = environmentVariables.first { $0.normalizedKey == envKey }?.value
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentValue != trimmedValue,
              let field = ProjectIntegrations.definition(for: .supabase).fields.first(where: { $0.envKey == envKey }) else {
            return
        }

        var nextVariables = environmentVariables.filter { $0.normalizedKey != envKey }
        let existingID = environmentVariables.first { $0.normalizedKey == envKey }?.id
        nextVariables.append(
            ProjectEnvironmentVariable(
                id: existingID ?? UUID().uuidString,
                key: envKey,
                description: field.description,
                value: trimmedValue,
                scope: field.scope
            )
        )
        try? await saveEnvironmentVariables(nextVariables)
    }

    private nonisolated static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private nonisolated static func discoverLocalSupabaseFunctions(in workspaceRoot: URL) -> [String] {
        let functionsDirectory = workspaceRoot.appendingPathComponent("supabase/functions", isDirectory: true)
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: functionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let names = candidates.compactMap { url -> String? in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                return nil
            }
            let name = url.lastPathComponent
            guard !name.hasPrefix("_"),
                  FileManager.default.fileExists(
                    atPath: url.appendingPathComponent("index.ts").path
                  ) else {
                return nil
            }
            return name
        }

        return sortedUniqueStrings(names)
    }

    private nonisolated static func listSupabaseFunctionNames(
        projectRef: String,
        accessToken: String
    ) throws -> [String] {
        let data = try performSupabaseManagementRequest(
            path: "/v1/projects/\(projectRef)/functions",
            method: "GET",
            accessToken: accessToken
        )

        return parseNamedObjects(from: data, primaryKeys: ["name", "slug"])
    }

    private nonisolated static func listSupabaseSecretNames(
        projectRef: String,
        accessToken: String
    ) throws -> [String] {
        let data = try performSupabaseManagementRequest(
            path: "/v1/projects/\(projectRef)/secrets",
            method: "GET",
            accessToken: accessToken
        )

        return parseNamedObjects(from: data, primaryKeys: ["name"])
    }

    private nonisolated static func deploySupabaseFunction(
        projectRef: String,
        functionName: String,
        verifyJWT: Bool,
        accessToken: String,
        workspaceRoot: URL
    ) throws -> String {
        let upload = try createSupabaseFunctionUpload(
            functionName: functionName,
            workspaceRoot: workspaceRoot
        )

        let responseData = try performSupabaseMultipartRequest(
            path: "/v1/projects/\(projectRef)/functions/deploy?slug=\(functionName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? functionName)",
            accessToken: accessToken,
            files: upload.files,
            formFields: [
                "metadata": try jsonString(from: upload.metadata(verifyJWT: verifyJWT))
            ]
        )
        if let object = try? JSONSerialization.jsonObject(with: responseData),
           let rendered = prettyJSONString(object),
           rendered != "[]" {
            return rendered
        }
        return "Deployed `\(functionName)` to Supabase project `\(projectRef)`."
    }

    private nonisolated static func setSupabaseSecret(
        projectRef: String,
        secretName: String,
        secretValue: String,
        accessToken: String
    ) throws -> String {
        try syncSupabaseSecrets(
            projectRef: projectRef,
            secrets: [(name: secretName, value: secretValue)],
            accessToken: accessToken
        )
        return "Saved backend secret `\(secretName)` and synced it to Supabase."
    }

    nonisolated static func syncSupabaseSecrets(
        projectRef: String,
        secrets: [(name: String, value: String)],
        accessToken: String
    ) throws {
        guard !secrets.isEmpty else { return }
        let responseData = try performSupabaseManagementRequest(
            path: "/v1/projects/\(projectRef)/secrets",
            method: "POST",
            accessToken: accessToken,
            jsonBody: secrets.map {
                [
                    "name": $0.name,
                    "value": $0.value,
                ]
            },
            expectedStatusCodes: [200, 201]
        )
        _ = responseData
    }

    private nonisolated static func hostedBackendSecretNames(
        variables: [ProjectEnvironmentVariable]
    ) -> [String] {
        variables
            .filter { $0.scope == .hosted }
            .map(\.normalizedKey)
            .filter { !$0.isEmpty }
            .sorted()
    }

    private nonisolated static func hostedBackendSecrets(
        variables: [ProjectEnvironmentVariable]
    ) -> [(name: String, value: String)] {
        variables.compactMap { variable in
            guard variable.scope == .hosted else { return nil }
            let name = variable.normalizedKey
            let value = variable.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            return (name: name, value: value)
        }
    }

    private nonisolated static func normalizedSupabaseBackendError(
        _ error: Error,
        action: String
    ) -> Error {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.localizedCaseInsensitiveContains("missing required scopes") else {
            return error
        }
        return NSError(
            domain: "SupabaseBackend",
            code: 403,
            userInfo: [
                NSLocalizedDescriptionKey: "Supabase still isn't granting the required backend permissions to \(action). Reconnect Supabase in Integrations, then retry."
            ]
        )
    }

    nonisolated static func invokeSupabaseFunction(
        projectURL: String,
        publicAPIKey: String?,
        functionName: String,
        requestJSON: AnyCodableValue?,
        authMode: BackendInvokeAuthMode,
        userAccessToken: String?,
        session: URLSession = .shared
    ) async throws -> String {
        let trimmedProjectURL = projectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmedProjectURL) else {
            throw NSError(
                domain: "BackendInvoke",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase URL is invalid."]
            )
        }

        let requestURL = baseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(functionName)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedPublicAPIKey = publicAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPublicAPIKey, !trimmedPublicAPIKey.isEmpty {
            request.setValue(trimmedPublicAPIKey, forHTTPHeaderField: "apikey")
        }

        switch authMode {
        case .userJWT:
            guard let trimmedUserAccessToken = userAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmedUserAccessToken.isEmpty else {
                throw NSError(
                    domain: "BackendInvoke",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "A signed-in Supabase user session is required for `auth_mode: user_jwt`. Sign in again and retry."]
                )
            }
            request.setValue("Bearer \(trimmedUserAccessToken)", forHTTPHeaderField: "Authorization")
        case .anon:
            guard let trimmedPublicAPIKey, !trimmedPublicAPIKey.isEmpty else {
                throw NSError(
                    domain: "BackendInvoke",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "A Supabase publishable key is required for `auth_mode: anon`."]
                )
            }
            request.setValue("Bearer \(trimmedPublicAPIKey)", forHTTPHeaderField: "Authorization")
        case .none:
            break
        }

        if let requestJSON {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestJSON.jsonObject, options: [.sortedKeys])
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "BackendInvoke",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Supabase returned an invalid response."]
            )
        }

        let responseText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if (200...299).contains(httpResponse.statusCode) {
            if responseText.isEmpty {
                return "Invoked `\(functionName)` successfully."
            }
            return responseText
        }

        let message = responseText.isEmpty
            ? "Supabase function returned status \(httpResponse.statusCode)."
            : "Supabase function returned status \(httpResponse.statusCode): \(responseText)"
        throw NSError(
            domain: "BackendInvoke",
            code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private nonisolated static func parseNamedObjects(
        from data: Data,
        primaryKeys: [String]
    ) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let dictionaries: [[String: Any]]
        if let array = object as? [[String: Any]] {
            dictionaries = array
        } else if let dictionary = object as? [String: Any] {
            let nestedArrays = dictionary.values.compactMap { $0 as? [[String: Any]] }
            dictionaries = nestedArrays.first ?? []
        } else {
            dictionaries = []
        }

        let names = dictionaries.compactMap { dictionary -> String? in
            for key in primaryKeys {
                if let value = dictionary[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            return nil
        }

        return sortedUniqueStrings(names)
    }

    private nonisolated static func createSupabaseFunctionUpload(
        functionName: String,
        workspaceRoot: URL
    ) throws -> SupabaseFunctionUpload {
        let functionsRoot = workspaceRoot.appendingPathComponent("supabase/functions", isDirectory: true)
        let functionDirectory = functionsRoot.appendingPathComponent(functionName, isDirectory: true)
        let entrypointURL = functionDirectory.appendingPathComponent("index.ts")

        guard FileManager.default.fileExists(atPath: entrypointURL.path) else {
            throw NSError(
                domain: "SupabaseDeploy",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing `supabase/functions/\(functionName)/index.ts`."]
            )
        }

        let rootImportMapURL = functionsRoot.appendingPathComponent("import_map.json")
        let functionImportMapURL = functionDirectory.appendingPathComponent("import_map.json")
        let sharedDirectoryURL = functionsRoot.appendingPathComponent("_shared", isDirectory: true)
        let importMapURL: URL? =
            if FileManager.default.fileExists(atPath: rootImportMapURL.path) {
                rootImportMapURL
            } else if FileManager.default.fileExists(atPath: functionImportMapURL.path) {
                functionImportMapURL
            } else {
                nil
            }

        var fileURLs = try recursiveFileURLs(in: functionDirectory)
        if FileManager.default.fileExists(atPath: sharedDirectoryURL.path) {
            fileURLs += try recursiveFileURLs(in: sharedDirectoryURL)
        }
        if let importMapURL {
            fileURLs.append(importMapURL)
        }

        let files = try sortedUniqueStrings(fileURLs.map { try relativePath(for: $0, workspaceRoot: workspaceRoot) })
            .map { relativePath in
                let fileURL = workspaceRoot.appendingPathComponent(relativePath)
                return SupabaseMultipartFile(
                    fieldName: "file",
                    filename: relativePath,
                    data: try Data(contentsOf: fileURL)
                )
            }

        return SupabaseFunctionUpload(
            functionName: functionName,
            entrypointPath: try relativePath(for: entrypointURL, workspaceRoot: workspaceRoot),
            importMapPath: try importMapURL.map { try relativePath(for: $0, workspaceRoot: workspaceRoot) },
            files: files
        )
    }

    private nonisolated static func recursiveFileURLs(in directoryURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var fileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                continue
            }
            fileURLs.append(fileURL)
        }
        return fileURLs
    }

    private nonisolated static func relativePath(for fileURL: URL, workspaceRoot: URL) throws -> String {
        let workspacePath = workspaceRoot.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw NSError(
                domain: "SupabaseDeploy",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Supabase file is outside the project workspace: \(fileURL.path)"]
            )
        }
        return String(filePath.dropFirst(prefix.count))
    }

    private nonisolated static func performSupabaseManagementRequest(
        path: String,
        method: String,
        accessToken: String,
        jsonBody: Any? = nil,
        expectedStatusCodes: Set<Int> = Set(200...299)
    ) throws -> Data {
        guard let url = supabaseManagementURL(path: path) else {
            throw NSError(
                domain: "SupabaseManagement",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Supabase request URL is invalid."]
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [.sortedKeys])
        }

        return try performSupabaseRequest(request, expectedStatusCodes: expectedStatusCodes)
    }

    private nonisolated static func performSupabaseMultipartRequest(
        path: String,
        accessToken: String,
        files: [SupabaseMultipartFile],
        formFields: [String: String],
        expectedStatusCodes: Set<Int> = Set(200...299)
    ) throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = supabaseManagementURL(path: path) else {
            throw NSError(
                domain: "SupabaseManagement",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Supabase request URL is invalid."]
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = multipartFormData(
            boundary: boundary,
            files: files,
            formFields: formFields
        )

        return try performSupabaseRequest(request, expectedStatusCodes: expectedStatusCodes)
    }

    private nonisolated static func supabaseManagementURL(path: String) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let pieces = trimmedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents(string: "https://api.supabase.com")
        components?.percentEncodedPath = "/" + pieces[0].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if pieces.count > 1 {
            components?.percentEncodedQuery = String(pieces[1])
        }
        return components?.url
    }

    private nonisolated static func performSupabaseRequest(
        _ request: URLRequest,
        expectedStatusCodes: Set<Int>
    ) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var response: URLResponse?
        var responseError: Error?

        URLSession.shared.dataTask(with: request) { data, urlResponse, error in
            responseData = data ?? Data()
            response = urlResponse
            responseError = error
            semaphore.signal()
        }.resume()

        semaphore.wait()

        if let responseError {
            throw responseError
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "SupabaseManagement",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase returned an invalid response."]
            )
        }
        guard expectedStatusCodes.contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "SupabaseManagement",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: supabaseErrorMessage(from: responseData)]
            )
        }

        return responseData
    }

    private nonisolated static func multipartFormData(
        boundary: String,
        files: [SupabaseMultipartFile],
        formFields: [String: String]
    ) -> Data {
        var data = Data()
        let lineBreak = "\r\n"

        for key in formFields.keys.sorted() {
            guard let value = formFields[key] else { continue }
            data.append(Data("--\(boundary)\(lineBreak)".utf8))
            data.append(Data("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)".utf8))
            data.append(Data(value.utf8))
            data.append(Data(lineBreak.utf8))
        }

        for file in files {
            data.append(Data("--\(boundary)\(lineBreak)".utf8))
            data.append(Data("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.filename)\"\(lineBreak)".utf8))
            data.append(Data("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)".utf8))
            data.append(file.data)
            data.append(Data(lineBreak.utf8))
        }
        data.append(Data("--\(boundary)--\(lineBreak)".utf8))
        return data
    }

    private nonisolated static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "SupabaseManagement",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode Supabase metadata."]
            )
        }
        return string
    }

    private nonisolated static func prettyJSONString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func supabaseErrorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error", "detail"] {
                if let value = json[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text! : "Supabase request failed."
    }

    private nonisolated static func sortedUniqueStrings(_ values: [String]) -> [String] {
        Array(
            Set(
                values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func resolvedRequiredSkillNames(
        explicit: [String],
        text: String,
        attachments: [BuilderMessageAttachment],
        action: BuilderMessageAction?
    ) -> [String] {
        _ = text
        _ = attachments
        _ = action
        return orderedUniqueSkillNames(explicit)
    }

    private func orderedUniqueSkillNames(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }
        return ordered
    }

    private func legacyRestoreTree(beforeMessageAt idx: Int) -> [String: String]? {
        let priorMessages = messages.prefix(idx).reversed()

        guard let versionId = priorMessages
            .first(where: { $0.role == "assistant" && $0.versionId != nil })?
            .versionId
        else {
            return messages.prefix(idx).contains(where: Self.isUserAuthoredMessage) ? nil : [:]
        }

        return versions.first(where: { $0.id == versionId })?.fileTree
    }
}
