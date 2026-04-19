import AppKit
import Foundation

extension BuilderViewModel {
    private func persistedProjectStatus(
        for project: BuilderProject
    ) async -> BuilderProjectStatusState? {
        let currentStatus = projectStatusState
        if currentStatus.hasContent {
            return BuilderProjectStatusState.merged(
                projectStatus: currentStatus,
                projectDependencyManifest: project.dependencyManifest
            )
        }
        let localStatus = await localStore.loadProjectStatus(projectName: project.name, projectId: project.id)
        return BuilderProjectStatusState.merged(
            projectStatus: localStatus,
            projectDependencyManifest: project.dependencyManifest
        )
    }

    func createChat() {
        guard canManageChats else { return }
        guard !isCurrentChatEmpty else {
            showChatSidebar = false
            return
        }

        Task {
            let project = activeProject
            await saveLocally(touchChat: false)

            let chat = makeAutoNamedChat(projectName: activeProject?.name)
            let projectStatus: BuilderProjectStatusState? = if let project {
                await persistedProjectStatus(for: project)
            } else {
                nil
            }
            chats.insert(chat, at: 0)
            activeChat = chat
            applyChatState(.empty, projectStatus: projectStatus)
            showChatSidebar = false

            await saveLocally(touchChat: false)
        }
    }

    func selectChat(_ chat: BuilderChat) {
        guard canManageChats else { return }
        guard activeChat?.id != chat.id else { return }

        Task {
            guard let project = activeProject else { return }
            let projectStatus = await persistedProjectStatus(for: project)
            await saveLocally(touchChat: false)
            let nextState = await localStore.loadChatState(
                projectName: project.name,
                projectId: project.id,
                chatId: chat.id
            ) ?? .empty

            guard activeProject?.id == project.id else { return }

            activeChat = chat
            applyChatState(nextState, projectStatus: projectStatus)
            showChatSidebar = false
            scheduleGeneratedChatTitleIfNeeded()
            await saveLocally(touchChat: false)
        }
    }

    func renameChat(_ chat: BuilderChat, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let index = chats.firstIndex(where: { $0.id == chat.id }) else { return }

        chats[index].name = trimmedName
        chats[index].isAutoNamed = false
        chats[index].hasGeneratedTitle = true
        chats[index].updatedAt = BuilderChat.timestamp()

        if activeChat?.id == chat.id {
            activeChat = chats[index]
        }

        Task { await saveLocally(touchChat: false) }
    }

    func deleteChat(_ chat: BuilderChat) {
        guard let project = activeProject else { return }
        guard let index = chats.firstIndex(where: { $0.id == chat.id }) else { return }
        guard canManageChats else { return }
        titleRequestsInFlight.remove(chat.id)

        let remainingChats = chats.enumerated()
            .filter { $0.offset != index }
            .map(\.element)

        chats.remove(at: index)

        if activeChat?.id == chat.id {
            let replacementChat = remainingChats.first ?? makeAutoNamedChat(projectName: project.name)
            if remainingChats.isEmpty {
                chats = [replacementChat]
            }
            activeChat = replacementChat

            if remainingChats.isEmpty {
                Task {
                    let projectStatus = await persistedProjectStatus(for: project)
                    applyChatState(.empty, projectStatus: projectStatus)
                    await localStore.deleteChatState(projectName: project.name, projectId: project.id, chatId: chat.id)
                    await saveLocally(touchChat: false)
                }
                return
            } else {
                Task {
                    let projectStatus = await persistedProjectStatus(for: project)
                    applyChatState(.empty, projectStatus: projectStatus)
                    let state = await localStore.loadChatState(
                        projectName: project.name,
                        projectId: project.id,
                        chatId: replacementChat.id
                    ) ?? .empty
                    applyChatState(state, projectStatus: projectStatus)
                    await localStore.deleteChatState(projectName: project.name, projectId: project.id, chatId: chat.id)
                    await saveLocally(touchChat: false)
                }
                return
            }
        }

        Task {
            await localStore.deleteChatState(projectName: project.name, projectId: project.id, chatId: chat.id)
            await saveLocally(touchChat: false)
        }
    }

    func saveLocally(touchChat: Bool = true) async {
        guard let project = activeProject,
              var chat = activeChat
        else { return }

        let persistedMessages = await localStore.persistAttachments(
            in: messages,
            projectName: project.name,
            projectId: project.id,
            chatId: chat.id
        )
        messages = persistedMessages
        syncRenderedMessages(with: persistedMessages)

        chat.name = resolvedChatName(for: chat, messages: persistedMessages)
        chat.messageCount = visibleMessageCount
        chat.lastMessagePreview = lastVisibleMessagePreview
        if touchChat {
            chat.updatedAt = BuilderChat.timestamp()
        }
        replaceChat(chat)

        let index = BuilderChatIndex(
            chats: chats,
            activeChatId: activeChat?.id
        )
        let timeline = persistedTimelineSnapshot()
        let derivedContextState = contextManager.deriveContextState(
            messages: persistedMessages,
            timeline: timeline,
            cachedReadFiles: cachedReadFiles,
            cachedReadFileOrder: cachedReadFileOrder,
            projectPlan: projectPlan,
            projectTasks: projectTasks
        )
        contextState = derivedContextState
        let pendingQuestionQueue = questionQueue?.persistedState
        let pendingIntegrationApproval = integrationApproval?.persistedState
        let state = BuilderChatState(
            messages: persistedMessages,
            plan: projectPlan,
            tasks: projectTasks,
            warnings: projectWarnings,
            snapshots: generationSnapshots,
            cachedReadFiles: cachedReadFiles,
            cachedReadFileOrder: cachedReadFileOrder,
            contextState: derivedContextState,
            timeline: timeline,
            dependencyChecklistAnchorMessageId: dependencyChecklistAnchorMessageId,
            pendingQuestionQueue: pendingQuestionQueue,
            pendingIntegrationApproval: pendingIntegrationApproval,
            pendingToolSteps: hasPendingUserResponse ? activeSteps : []
        )

        await localStore.saveChatIndex(index, projectName: project.name, projectId: project.id)
        await localStore.saveProjectStatus(
            projectStatusState,
            projectName: project.name,
            projectId: project.id,
            projectDir: localProjectPath
        )
        await localStore.saveChatState(
            state,
            chat: chat,
            projectName: project.name,
            projectId: project.id,
            projectDir: localProjectPath
        )
        await localStore.saveMessages(persistedMessages, projectName: project.name, projectId: project.id, projectDir: localProjectPath)
        await localStore.saveFileTree(fileTree, projectName: project.name, projectId: project.id)
        await localStore.saveReviewState(appStoreReviewState, projectName: project.name, projectId: project.id)
    }

    func syncRenderedMessages(with updatedMessages: [BuilderMessage]) {
        let messagesById = Dictionary(uniqueKeysWithValues: updatedMessages.map { ($0.id, $0) })
        chatItems = chatItems.map { item in
            guard case .message(let existingMessage) = item,
                  let updatedMessage = messagesById[existingMessage.id]
            else {
                return item
            }
            return chatItem(from: updatedMessage)
        }
    }

    func revealAttachment(_ attachment: BuilderMessageAttachment, in messageId: String) {
        guard let project = activeProject,
              let chat = activeChat
        else { return }

        Task { @MainActor in
            guard let resolved = await localStore.resolveAttachmentFile(
                for: attachment,
                messageId: messageId,
                projectName: project.name,
                projectId: project.id,
                chatId: chat.id
            ) else {
                return
            }

            let didUpdateAttachment = replaceAttachment(resolved.attachment, in: messageId)
            if didUpdateAttachment {
                await saveLocally(touchChat: false)
            }

            NSWorkspace.shared.activateFileViewerSelecting([resolved.url])
        }
    }

    func initializeChats(
        projectName: String,
        projectId: String,
        projectStatus: BuilderProjectStatusState?
    ) async -> Bool {
        if let index = await localStore.loadChatIndex(projectName: projectName, projectId: projectId),
           !index.chats.isEmpty {
            let hydratedChats = await hydratedChats(from: index.chats, projectName: projectName, projectId: projectId)
            chats = hydratedChats
            let selectedChat = hydratedChats.first(where: { $0.id == index.activeChatId }) ?? hydratedChats[0]
            activeChat = selectedChat
            let state = await localStore.loadChatState(
                projectName: projectName,
                projectId: projectId,
                chatId: selectedChat.id
            ) ?? .empty
            applyChatState(state, projectStatus: projectStatus)
            return true
        }

        let chat = makeAutoNamedChat(projectName: projectName)
        chats = [chat]
        activeChat = chat
        applyChatState(.empty, projectStatus: projectStatus)
        return false
    }

    func applyChatState(
        _ state: BuilderChatState,
        projectStatus: BuilderProjectStatusState? = nil
    ) {
        messages = state.messages
        chatItems = rebuiltChatItems(messages: state.messages, persistedTimeline: state.timeline)
        let resolvedProjectStatus = BuilderProjectStatusState.resolve(
            projectStatus: projectStatus,
            chatState: state,
            projectDependencyManifest: activeProject?.dependencyManifest
        )
        projectPlan = resolvedProjectStatus.plan
        projectTasks = resolvedProjectStatus.tasks
        projectWarnings = resolvedProjectStatus.warnings
        projectDependencyManifest = resolvedProjectStatus.dependencyManifest
        generationSnapshots = state.snapshots
        cachedReadFiles = state.cachedReadFiles
        cachedReadFileOrder = state.cachedReadFileOrder.filter { state.cachedReadFiles[$0] != nil }
        contextState = state.contextState
        if cachedReadFileOrder.isEmpty, !cachedReadFiles.isEmpty {
            cachedReadFileOrder = cachedReadFiles.keys.sorted()
        }
        dependencyChecklistAnchorMessageId = state.dependencyChecklistAnchorMessageId
        pendingDependencyChecklistAnchor = false

        showResumePrompt = state.messages.last(where: { Self.isResumeRelevantMessage($0) }).map(Self.isUserAuthoredMessage) ?? false
        questionQueue = state.pendingQuestionQueue.map(QuestionQueue.init(persisted:))
        integrationApproval = state.pendingIntegrationApproval.map(IntegrationApprovalState.init(persisted:))
        messageQueue = []
        activeSteps = state.pendingToolSteps
        pendingAssistantContent = ""
        generationStatus = nil
        buildError = nil
        lastFailedRequest = nil
        pendingInputPrefill = nil
        pendingAttachmentPrefill = nil
        pendingRequiredSkillPrefill = nil
        pendingMessageActionPrefill = nil
        pendingAttachmentAppend = nil
        pendingPreviewViewMentionAppend = nil
        isAutoFixingBuild = false
        consecutiveAutomaticBuildFixFailures = 0
        lastPreviewCompileError = nil
        latestBuildFixError = nil
        suppressIntermediateAssistantText = false

        if !hasProjectStatusContent, viewMode == .roadmap {
            viewMode = .canvas
        }
        if hasPendingUserResponse {
            showResumePrompt = false
        }
        ensureDependencyChecklistAnchorIfNeeded()
    }

    var visibleMessageCount: Int {
        Self.visibleMessageCount(in: messages)
    }

    var lastVisibleMessagePreview: String? {
        Self.lastVisibleMessagePreview(in: messages)
    }

    var isCurrentChatEmpty: Bool {
        visibleMessageCount == 0
            && pendingAssistantContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && activeSteps.isEmpty
            && !isGenerating
    }

    func hydratedChats(
        from chats: [BuilderChat],
        projectName: String,
        projectId: String
    ) async -> [BuilderChat] {
        var hydrated: [BuilderChat] = []

        for var chat in chats {
            let state = await localStore.loadChatState(
                projectName: projectName,
                projectId: projectId,
                chatId: chat.id
            )
            let stateMessages = state?.messages ?? []

            if chat.isAutoNamed {
                chat.name = resolvedChatName(
                    for: chat,
                    messages: stateMessages,
                    projectName: projectName,
                    existingChats: chats
                )
            }
            chat.messageCount = Self.visibleMessageCount(in: stateMessages)
            chat.lastMessagePreview = Self.lastVisibleMessagePreview(in: stateMessages)
            hydrated.append(chat)
        }

        return hydrated
    }

    func resolvedChatName(
        for chat: BuilderChat?,
        messages: [BuilderMessage],
        projectName: String? = nil,
        existingChats: [BuilderChat]? = nil
    ) -> String {
        let currentName = chat?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isAutoNamed = chat?.isAutoNamed ?? Self.shouldAutoName(currentName)
        guard isAutoNamed else { return currentName }
        if !(chat?.hasGeneratedTitle ?? false) {
            return currentName.isEmpty ? "New Chat" : currentName
        }
        if !Self.shouldAutoName(currentName) {
            return currentName
        }
        return generatedBlankChatName(
            for: chat,
            projectName: projectName ?? activeProject?.name,
            existingChats: existingChats ?? chats
        )
    }

    func makeAutoNamedChat(
        projectName: String?,
        messages: [BuilderMessage] = [],
        existingChats: [BuilderChat]? = nil
    ) -> BuilderChat {
        var chat = BuilderChat(
            name: "New Chat",
            isAutoNamed: true,
            hasGeneratedTitle: false,
            messageCount: Self.visibleMessageCount(in: messages),
            lastMessagePreview: Self.lastVisibleMessagePreview(in: messages)
        )
        chat.name = resolvedChatName(
            for: chat,
            messages: messages,
            projectName: projectName,
            existingChats: existingChats ?? chats
        )
        return chat
    }

    func rememberAccessToken(_ accessToken: String) {
        syncSessionAccessToken(accessToken)
    }

    func syncSessionAccessToken(_ accessToken: String?) {
        let trimmed = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sessionAccessToken = trimmed.isEmpty ? nil : trimmed
    }

    func scheduleGeneratedChatTitleIfNeeded() {
        guard let chat = activeChat,
              chat.isAutoNamed,
              !chat.hasGeneratedTitle,
              !titleRequestsInFlight.contains(chat.id),
              let accessToken = sessionAccessToken,
              let query = firstUserQuery(in: messages)
        else {
            return
        }

        titleRequestsInFlight.insert(chat.id)
        Task {
            await requestGeneratedChatTitle(
                for: chat.id,
                userQuery: query,
                projectName: activeProject?.name,
                accessToken: accessToken
            )
        }
    }

    func firstUserQuery(in messages: [BuilderMessage]) -> String? {
        guard let content = messages.first(where: Self.isUserAuthoredMessage)?.titleInputText else {
            return nil
        }

        let normalized = content
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    func requestGeneratedChatTitle(
        for chatId: String,
        userQuery: String,
        projectName: String?,
        accessToken: String
    ) async {
        defer { titleRequestsInFlight.remove(chatId) }

        do {
            var payload: [String: Any] = ["user_query": userQuery]
            if let projectName, !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["project_name"] = projectName
            }

            let response: ChatTitleResponse = try await apiClient.post(
                APIClient.builder("chat-title"),
                json: payload,
                accessToken: accessToken
            )
            await applyGeneratedChatTitle(response.title, to: chatId)
        } catch {
            print("Failed to generate chat title: \(error)")
        }
    }

    func applyGeneratedChatTitle(_ rawTitle: String, to chatId: String) async {
        let normalizedTitle = normalizedGeneratedTitle(rawTitle)
        guard !normalizedTitle.isEmpty,
              let chatIndex = chats.firstIndex(where: { $0.id == chatId }),
              chats[chatIndex].isAutoNamed,
              !chats[chatIndex].hasGeneratedTitle
        else {
            return
        }

        chats[chatIndex].name = normalizedTitle
        chats[chatIndex].hasGeneratedTitle = true

        if activeChat?.id == chatId {
            activeChat = chats[chatIndex]
        }

        await saveLocally(touchChat: false)
    }

    func normalizedGeneratedTitle(_ rawTitle: String) -> String {
        let lineCandidates = rawTitle
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidates = lineCandidates + [rawTitle]
        let cleanedCandidates = candidates.compactMap(cleanGeneratedTitleCandidate)

        return cleanedCandidates.first(where: {
            let wordCount = $0.split(whereSeparator: \.isWhitespace).count
            return (2...6).contains(wordCount)
        }) ?? cleanedCandidates.first ?? ""
    }

    private func cleanGeneratedTitleCandidate(_ rawCandidate: String) -> String? {
        var title = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.hasPrefix("```") else { return nil }

        let patterns = [
            #"(?i)^(?:title|chat title|project title)\s*[:\-]\s*"#,
            #"^#+\s*"#,
            #"^[>\-*+]\s+"#,
            #"^\d+[.)]\s*"#,
            #"^[A-Za-z]{2,16}\s*#\s+"#,
        ]

        for _ in 0..<3 {
            let previous = title
            for pattern in patterns {
                title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*_ "))
            if title == previous {
                break
            }
        }

        title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*_ "))
            .replacingOccurrences(of: #"[.,:;!?]+$"#, with: "", options: .regularExpression)

        guard !title.isEmpty, title.lowercased() != "title" else { return nil }
        let words = title.split(whereSeparator: \.isWhitespace)
        guard words.count <= 6 else {
            return words.prefix(6).joined(separator: " ")
        }
        return title
    }

    static func isUserAuthoredMessage(_ message: BuilderMessage) -> Bool {
        message.role == "user" && !message.isInternalRestartNote
    }

    static func isResumeRelevantMessage(_ message: BuilderMessage) -> Bool {
        guard message.role != "build_fix", !message.isInternalRestartNote else { return false }
        return message.role == "user" || message.hasVisibleContent
    }

    static func lastUserAuthoredMessage(in messages: [BuilderMessage]) -> BuilderMessage? {
        messages.last(where: isUserAuthoredMessage)
    }

    static func visibleMessageCount(in messages: [BuilderMessage]) -> Int {
        messages.filter { $0.role != "build_fix" && !$0.isInternalRestartNote }.count
    }

    static func lastVisibleMessagePreview(in messages: [BuilderMessage]) -> String? {
        messages.reversed().compactMap { message -> String? in
            guard message.role != "build_fix", !message.isInternalRestartNote else { return nil }
            let normalized = message.previewText?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized, !normalized.isEmpty else { return nil }
            return String(normalized.prefix(90))
        }.first
    }

    private func replaceAttachment(
        _ updatedAttachment: BuilderMessageAttachment,
        in messageId: String
    ) -> Bool {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageId }),
              let attachmentIndex = messages[messageIndex].attachments.firstIndex(where: { $0.id == updatedAttachment.id })
        else {
            return false
        }

        guard messages[messageIndex].attachments[attachmentIndex] != updatedAttachment else {
            return false
        }

        messages[messageIndex].attachments[attachmentIndex] = updatedAttachment
        syncRenderedMessages(with: messages)
        return true
    }

    private func replaceChat(_ updated: BuilderChat) {
        chats.removeAll { $0.id == updated.id }
        chats.insert(updated, at: 0)

        if activeChat?.id == updated.id {
            activeChat = updated
        }
    }

    private func generatedBlankChatName(
        for chat: BuilderChat?,
        projectName: String?,
        existingChats: [BuilderChat]
    ) -> String {
        let projectStem = Self.projectStem(from: projectName)
        let period = Self.dayPeriod(from: chat?.createdAt)
        let nouns = [
            "Draft",
            "Notes",
            "Exploration",
            "Outline",
            "Concept",
            "Review",
            "Sketch",
            "Sprint",
        ]
        let takenNames = Set(
            existingChats
                .filter { $0.id != chat?.id }
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let seed = Self.stableSeed(from: "\(chat?.id ?? "")|\(chat?.createdAt ?? "")")

        for offset in 0..<nouns.count {
            let noun = nouns[(seed + offset) % nouns.count]
            let candidate = "\(projectStem) \(period) \(noun)"
            if !takenNames.contains(candidate.lowercased()) {
                return candidate
            }
        }

        return "\(projectStem) \(period) Workspace"
    }

    private static func shouldAutoName(_ name: String) -> Bool {
        BuilderChat.isPlaceholderName(name)
    }

    private static func projectStem(from projectName: String?) -> String {
        let trimmed = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let words = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !words.isEmpty else { return "Project" }
        return Array(words.prefix(2)).joined(separator: " ")
    }

    private static func dayPeriod(from rawValue: String?) -> String {
        let date = rawValue.flatMap(date(from:)) ?? Date()
        let hour = Calendar.current.component(.hour, from: date)

        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<22:
            return "Evening"
        default:
            return "Night"
        }
    }

    private static func stableSeed(from rawValue: String) -> Int {
        abs(rawValue.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult &* 33) &+ Int(scalar.value)
        })
    }

    private static func date(from rawValue: String) -> Date? {
        fractionalDateFormatter.date(from: rawValue) ?? fallbackDateFormatter.date(from: rawValue)
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackDateFormatter = ISO8601DateFormatter()
}
