import Foundation

nonisolated struct BuilderChat: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var isAutoNamed: Bool
    var hasGeneratedTitle: Bool
    let createdAt: String
    var updatedAt: String
    var messageCount: Int
    var lastMessagePreview: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        isAutoNamed: Bool = false,
        hasGeneratedTitle: Bool? = nil,
        createdAt: String = BuilderChat.timestamp(),
        updatedAt: String? = nil,
        messageCount: Int = 0,
        lastMessagePreview: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isAutoNamed = isAutoNamed
        self.hasGeneratedTitle = hasGeneratedTitle ?? !isAutoNamed
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.messageCount = messageCount
        self.lastMessagePreview = lastMessagePreview
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isAutoNamed
        case hasGeneratedTitle
        case createdAt
        case updatedAt
        case messageCount
        case lastMessagePreview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let decodedIsAutoNamed = try container.decodeIfPresent(Bool.self, forKey: .isAutoNamed)
            ?? BuilderChat.isPlaceholderName(name)
        isAutoNamed = decodedIsAutoNamed
        hasGeneratedTitle = try container.decodeIfPresent(Bool.self, forKey: .hasGeneratedTitle)
            ?? !decodedIsAutoNamed
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        lastMessagePreview = try container.decodeIfPresent(String.self, forKey: .lastMessagePreview)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isAutoNamed, forKey: .isAutoNamed)
        try container.encode(hasGeneratedTitle, forKey: .hasGeneratedTitle)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encodeIfPresent(lastMessagePreview, forKey: .lastMessagePreview)
    }

    static func timestamp() -> String {
        BuilderChat.isoFormatter.string(from: Date())
    }

    static func isPlaceholderName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed == "New Chat" { return true }
        return trimmed.range(of: #"^Chat\s+\d+$"#, options: .regularExpression) != nil
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

nonisolated struct BuilderChatIndex: Codable, Sendable {
    var chats: [BuilderChat]
    var activeChatId: String?
}

nonisolated struct PersistedQuestionQueue: Codable, Sendable {
    var questions: [AskUserQuestion]
    var toolUseId: String
    var currentIndex: Int
    var answers: [String: String]
}

nonisolated struct PersistedIntegrationApproval: Codable, Sendable {
    var request: IntegrationApprovalRequest
    var toolUseId: String
}

nonisolated struct BuilderSystemEvent: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case modeChange
        case projectRename
        case dependencyChecklist
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String?

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        title: String,
        detail: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

nonisolated enum BuilderChatTimelineItem: Codable, Sendable, Identifiable {
    case message(messageId: String)
    case toolSteps(id: String, steps: [BuilderToolStep])
    case systemEvent(BuilderSystemEvent)

    var id: String {
        switch self {
        case .message(let messageId):
            return messageId
        case .toolSteps(let id, _):
            return id
        case .systemEvent(let event):
            return event.id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case messageId
        case id
        case steps
        case event
    }

    private enum ItemType: String, Codable {
        case message
        case toolSteps
        case systemEvent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)

        switch type {
        case .message:
            self = .message(messageId: try container.decode(String.self, forKey: .messageId))
        case .toolSteps:
            self = .toolSteps(
                id: try container.decode(String.self, forKey: .id),
                steps: try container.decode([BuilderToolStep].self, forKey: .steps)
            )
        case .systemEvent:
            self = .systemEvent(try container.decode(BuilderSystemEvent.self, forKey: .event))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .message(let messageId):
            try container.encode(ItemType.message, forKey: .type)
            try container.encode(messageId, forKey: .messageId)
        case .toolSteps(let id, let steps):
            try container.encode(ItemType.toolSteps, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(steps, forKey: .steps)
        case .systemEvent(let event):
            try container.encode(ItemType.systemEvent, forKey: .type)
            try container.encode(event, forKey: .event)
        }
    }
}

nonisolated struct BuilderChatState: Codable, Sendable {
    var messages: [BuilderMessage]
    var plan: String?
    var tasks: String?
    var warnings: [BuilderProjectWarning]
    var snapshots: [ProjectSnapshot]
    var cachedReadFiles: [String: String]
    var cachedReadFileOrder: [String]
    var contextState: BuilderContextState
    var timeline: [BuilderChatTimelineItem]
    var dependencyChecklistAnchorMessageId: String?
    var pendingQuestionQueue: PersistedQuestionQueue?
    var pendingIntegrationApproval: PersistedIntegrationApproval?
    var pendingToolSteps: [BuilderToolStep]

    init(
        messages: [BuilderMessage],
        plan: String?,
        tasks: String?,
        warnings: [BuilderProjectWarning] = [],
        snapshots: [ProjectSnapshot],
        cachedReadFiles: [String: String] = [:],
        cachedReadFileOrder: [String] = [],
        contextState: BuilderContextState = .empty,
        timeline: [BuilderChatTimelineItem] = [],
        dependencyChecklistAnchorMessageId: String? = nil,
        pendingQuestionQueue: PersistedQuestionQueue? = nil,
        pendingIntegrationApproval: PersistedIntegrationApproval? = nil,
        pendingToolSteps: [BuilderToolStep] = []
    ) {
        self.messages = messages
        self.plan = plan
        self.tasks = tasks
        self.warnings = warnings
        self.snapshots = snapshots
        self.cachedReadFiles = cachedReadFiles
        self.cachedReadFileOrder = cachedReadFileOrder
        self.contextState = contextState
        self.timeline = timeline
        self.dependencyChecklistAnchorMessageId = dependencyChecklistAnchorMessageId
        self.pendingQuestionQueue = pendingQuestionQueue
        self.pendingIntegrationApproval = pendingIntegrationApproval
        self.pendingToolSteps = pendingToolSteps
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case plan
        case tasks
        case warnings
        case snapshots
        case cachedReadFiles
        case cachedReadFileOrder
        case contextState
        case timeline
        case dependencyChecklistAnchorMessageId
        case pendingQuestionQueue
        case pendingIntegrationApproval
        case pendingToolSteps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decode([BuilderMessage].self, forKey: .messages)
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        tasks = try container.decodeIfPresent(String.self, forKey: .tasks)
        warnings = try container.decodeIfPresent([BuilderProjectWarning].self, forKey: .warnings) ?? []
        snapshots = try container.decodeIfPresent([ProjectSnapshot].self, forKey: .snapshots) ?? []
        cachedReadFiles = try container.decodeIfPresent([String: String].self, forKey: .cachedReadFiles) ?? [:]
        cachedReadFileOrder = try container.decodeIfPresent([String].self, forKey: .cachedReadFileOrder) ?? []
        contextState = try container.decodeIfPresent(BuilderContextState.self, forKey: .contextState) ?? .empty
        timeline = try container.decodeIfPresent([BuilderChatTimelineItem].self, forKey: .timeline) ?? []
        dependencyChecklistAnchorMessageId = try container.decodeIfPresent(String.self, forKey: .dependencyChecklistAnchorMessageId)
        pendingQuestionQueue = try container.decodeIfPresent(PersistedQuestionQueue.self, forKey: .pendingQuestionQueue)
        pendingIntegrationApproval = try container.decodeIfPresent(PersistedIntegrationApproval.self, forKey: .pendingIntegrationApproval)
        pendingToolSteps = try container.decodeIfPresent([BuilderToolStep].self, forKey: .pendingToolSteps) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encodeIfPresent(tasks, forKey: .tasks)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(snapshots, forKey: .snapshots)
        try container.encode(cachedReadFiles, forKey: .cachedReadFiles)
        try container.encode(cachedReadFileOrder, forKey: .cachedReadFileOrder)
        try container.encode(contextState, forKey: .contextState)
        try container.encode(timeline, forKey: .timeline)
        try container.encodeIfPresent(dependencyChecklistAnchorMessageId, forKey: .dependencyChecklistAnchorMessageId)
        try container.encodeIfPresent(pendingQuestionQueue, forKey: .pendingQuestionQueue)
        try container.encodeIfPresent(pendingIntegrationApproval, forKey: .pendingIntegrationApproval)
        try container.encode(pendingToolSteps, forKey: .pendingToolSteps)
    }

    static let empty = BuilderChatState(
        messages: [],
        plan: nil,
        tasks: nil,
        warnings: [],
        snapshots: [],
        cachedReadFiles: [:],
        cachedReadFileOrder: [],
        contextState: .empty,
        timeline: [],
        dependencyChecklistAnchorMessageId: nil,
        pendingQuestionQueue: nil,
        pendingIntegrationApproval: nil,
        pendingToolSteps: []
    )
}
