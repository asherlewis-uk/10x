import Foundation

extension BuilderViewModel {
    func chatItem(from message: BuilderMessage) -> ChatItem {
        if let systemEvent = message.restartNoteSystemEvent {
            return .systemEvent(systemEvent)
        }
        if message.role == "build_fix",
           let data = message.content.data(using: .utf8),
           let fix = try? JSONDecoder().decode(BuildFixContent.self, from: data) {
            return .buildFix(id: message.id, error: fix.error, resolved: fix.resolved)
        }
        return .message(message)
    }

    func rebuiltChatItems(
        messages: [BuilderMessage],
        persistedTimeline: [BuilderChatTimelineItem]
    ) -> [ChatItem] {
        guard !persistedTimeline.isEmpty else {
            return messages.compactMap { message in
                guard shouldRenderMessageInChat(message) else { return nil }
                return chatItem(from: message)
            }
        }

        let messagesById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        var renderedMessageIds: Set<String> = []
        var items: [ChatItem] = []

        for item in persistedTimeline {
            switch item {
            case .message(let messageId):
                guard let message = messagesById[messageId],
                      shouldRenderMessageInChat(message) else { continue }
                renderedMessageIds.insert(messageId)
                let renderedItem = chatItem(from: message)
                if case .systemEvent(let event) = renderedItem,
                   Self.shouldCoalesceSystemEvent(event, in: items) {
                    continue
                }
                items.append(renderedItem)

            case .systemEvent(let event):
                guard Self.shouldKeepPersistedSystemEvent(event) else { continue }
                renderedMessageIds.insert(event.id)
                guard !Self.shouldCoalesceSystemEvent(event, in: items) else { continue }
                items.append(.systemEvent(event))
            case .toolSteps(let id, let steps):
                guard !steps.isEmpty else { continue }
                guard Self.shouldKeepToolSteps(steps, preceding: items) else { continue }
                items.append(.toolSteps(id: id, steps: steps))
            }
        }

        for message in messages where !renderedMessageIds.contains(message.id) {
            guard shouldRenderMessageInChat(message) else { continue }
            let renderedItem = chatItem(from: message)
            if case .systemEvent(let event) = renderedItem,
               Self.shouldCoalesceSystemEvent(event, in: items) {
                continue
            }
            items.append(renderedItem)
        }

        return items
    }

    func latestBuildFixMessageId(in messages: [BuilderMessage]) -> String? {
        messages.last(where: { $0.role == "build_fix" })?.id
    }

    func latestUnresolvedBuildFixMessageId(in messages: [BuilderMessage]) -> String? {
        messages.reversed().first { message in
            guard message.role == "build_fix",
                  let data = message.content.data(using: .utf8),
                  let fix = try? JSONDecoder().decode(BuildFixContent.self, from: data) else {
                return false
            }

            return !fix.resolved
        }?.id
    }

    var latestStoredBuildIssueText: String? {
        guard let latestMessage = messages.reversed().first(where: { $0.role == "build_fix" }),
              let data = latestMessage.content.data(using: .utf8),
              let fix = try? JSONDecoder().decode(BuildFixContent.self, from: data),
              !fix.resolved else {
            return nil
        }
        return fix.error
    }

    func resolveLatestStoredBuildIssueIfNeeded() {
        guard let messageId = latestUnresolvedBuildFixMessageId(in: messages) else { return }
        updateBuildFixState(messageId: messageId, error: nil, resolved: true)
    }

    func shouldRenderMessageInChat(_ message: BuilderMessage) -> Bool {
        if message.restartNoteSystemEvent != nil {
            return false
        }
        if message.role == "build_fix" {
            return true
        }
        return message.hasVisibleContent
    }

    func persistedTimeline(from chatItems: [ChatItem]) -> [BuilderChatTimelineItem] {
        var timeline: [BuilderChatTimelineItem] = []
        var precedingItems: [ChatItem] = []

        for item in chatItems {
            switch item {
            case .message(let message):
                timeline.append(.message(messageId: message.id))
            case .systemEvent(let event):
                guard Self.shouldKeepPersistedSystemEvent(event) else { continue }
                timeline.append(.systemEvent(event))
            case .toolSteps(let id, let steps):
                guard !steps.isEmpty, Self.shouldKeepToolSteps(steps, preceding: precedingItems) else { continue }
                timeline.append(.toolSteps(id: id, steps: steps))
            case .buildFix(let id, _, _):
                timeline.append(.message(messageId: id))
            case .error:
                continue
            }

            precedingItems.append(item)
        }

        return timeline
    }

    func persistedTimelineSnapshot() -> [BuilderChatTimelineItem] {
        var timeline = persistedTimeline(from: chatItems)
        guard persistCurrentRunToolSteps else { return timeline }
        let completedSteps = activeSteps.filter { $0.status != .running }
        guard !completedSteps.isEmpty else { return timeline }

        timeline.append(.toolSteps(id: toolStepsGroupId(for: completedSteps), steps: completedSteps))
        return timeline
    }

    func toolStepsGroupId(for steps: [BuilderToolStep]) -> String {
        "tools-\(steps.first?.id.uuidString ?? UUID().uuidString)"
    }

    func appendToolStepsToChat(_ steps: [BuilderToolStep]) {
        guard !steps.isEmpty else { return }
        let groupId = toolStepsGroupId(for: steps)
        chatItems.append(.toolSteps(id: groupId, steps: steps))
    }

    func flushToolStepsToChatIfNeeded(_ steps: [BuilderToolStep]) {
        guard persistCurrentRunToolSteps else { return }
        appendToolStepsToChat(steps)
    }

    func finalizeUnfinishedToolSteps(
        _ steps: [BuilderToolStep],
        fallbackOutput: String
    ) -> [BuilderToolStep] {
        steps.map { step in
            guard step.status == .running else { return step }

            var finalized = step
            finalized.status = .error
            let hasOutputPreview = !(finalized.outputPreview?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true)
            if !hasOutputPreview {
                finalized.outputPreview = fallbackOutput
            }
            return finalized
        }
    }

    func finalizeAnsweredQuestionSteps(_ steps: [BuilderToolStep]) -> [BuilderToolStep] {
        steps.map { step in
            guard step.status == .running, step.name == "ask_user" else { return step }

            var finalized = step
            finalized.status = .success
            return finalized
        }
    }

    func appendSystemEventToChat(_ event: BuilderSystemEvent) {
        guard !Self.shouldCoalesceSystemEvent(event, in: chatItems) else { return }
        chatItems.append(.systemEvent(event))
    }

    func ensureDependencyChecklistAnchorIfNeeded() {
        guard hasDependencyChecklist else {
            dependencyChecklistAnchorMessageId = nil
            pendingDependencyChecklistAnchor = false
            return
        }
        if let anchorMessageId = dependencyChecklistAnchorMessageId,
           messages.contains(where: { $0.id == anchorMessageId && $0.role == "assistant" }) {
            return
        }
        dependencyChecklistAnchorMessageId = messages.last(where: { $0.role == "assistant" })?.id
    }

    func markDependencyChecklistForCurrentTurn() {
        pendingDependencyChecklistAnchor = true
    }

    func anchorDependencyChecklistIfNeeded(afterAssistantMessageId messageId: String) {
        guard pendingDependencyChecklistAnchor else { return }
        dependencyChecklistAnchorMessageId = messageId
        pendingDependencyChecklistAnchor = false
    }

    func finalizePendingDependencyChecklistAnchorIfNeeded() {
        guard pendingDependencyChecklistAnchor else { return }
        dependencyChecklistAnchorMessageId = messages.last(where: { $0.role == "assistant" })?.id
        pendingDependencyChecklistAnchor = false
    }

    static func shouldKeepToolSteps(_ steps: [BuilderToolStep], preceding items: [ChatItem]) -> Bool {
        true
    }

    static func shouldKeepPersistedSystemEvent(_ event: BuilderSystemEvent) -> Bool {
        event.kind != .dependencyChecklist
    }

    static func isEquivalentSystemEvent(_ lhs: BuilderSystemEvent, _ rhs: BuilderSystemEvent) -> Bool {
        lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.detail == rhs.detail
    }

    static func shouldCoalesceSystemEvent(_ newEvent: BuilderSystemEvent, in items: [ChatItem]) -> Bool {
        for item in items.reversed() {
            switch item {
            case .toolSteps, .error:
                continue
            case .systemEvent(let existing):
                return isEquivalentSystemEvent(existing, newEvent)
            case .message(let message):
                if let existing = message.restartNoteSystemEvent {
                    return isEquivalentSystemEvent(existing, newEvent)
                }
                return false
            case .buildFix:
                return false
            }
        }

        return false
    }
}
