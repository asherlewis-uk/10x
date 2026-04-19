import Foundation

nonisolated enum ProjectSetupSurface: String, Codable, Sendable, CaseIterable, Hashable {
    case integration
    case backend
    case external

    var title: String {
        switch self {
        case .integration:
            return "Integrations"
        case .backend:
            return "Backend"
        case .external:
            return "External setup"
        }
    }
}

nonisolated enum ProjectBackendProviderID: String, Codable, Sendable, CaseIterable, Hashable {
    case supabase

    var title: String {
        switch self {
        case .supabase:
            return "Supabase"
        }
    }
}

nonisolated struct ProjectBackendFunctionRecord: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let verifyJWT: Bool
    let sourcePath: String
    let updatedAt: String
    let lastDeployedAt: String?
    let lastInvocationSummary: String?

    init(
        id: String? = nil,
        name: String,
        summary: String,
        verifyJWT: Bool,
        sourcePath: String,
        updatedAt: String,
        lastDeployedAt: String? = nil,
        lastInvocationSummary: String? = nil
    ) {
        self.id = id ?? name
        self.name = name
        self.summary = summary
        self.verifyJWT = verifyJWT
        self.sourcePath = sourcePath
        self.updatedAt = updatedAt
        self.lastDeployedAt = lastDeployedAt
        self.lastInvocationSummary = lastInvocationSummary
    }
}

nonisolated struct ProjectBackendSecretRecord: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let updatedAt: String
    let lastSyncedAt: String?

    init(
        id: String? = nil,
        name: String,
        updatedAt: String,
        lastSyncedAt: String? = nil
    ) {
        self.id = id ?? name
        self.name = name
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
    }
}

nonisolated struct ProjectBackendLogEntry: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let timestamp: String
    let message: String
    let level: String
    let functionName: String?

    init(
        id: String = UUID().uuidString,
        timestamp: String,
        message: String,
        level: String = "info",
        functionName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
        self.level = level
        self.functionName = functionName
    }

    var isError: Bool {
        level.caseInsensitiveCompare("error") == .orderedSame
    }
}

nonisolated enum ProjectBackendFailureSource: String, Codable, Sendable, Hashable {
    case invoke
    case logs
}

nonisolated struct ProjectBackendFailureRecord: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let functionName: String
    let timestamp: String
    let requestSummary: String?
    let errorSummary: String
    let source: ProjectBackendFailureSource
    let relatedLogIDs: [String]
    let resolvedAt: String?

    init(
        id: String = UUID().uuidString,
        functionName: String,
        timestamp: String,
        requestSummary: String? = nil,
        errorSummary: String,
        source: ProjectBackendFailureSource,
        relatedLogIDs: [String] = [],
        resolvedAt: String? = nil
    ) {
        self.id = id
        self.functionName = functionName
        self.timestamp = timestamp
        self.requestSummary = requestSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.errorSummary = errorSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.relatedLogIDs = relatedLogIDs
        self.resolvedAt = resolvedAt
    }

    var isOpen: Bool {
        (resolvedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

nonisolated struct ProjectBackendState: Codable, Sendable, Hashable {
    let providerID: ProjectBackendProviderID?
    let linkedProjectRef: String?
    let linkedProjectURL: String?
    let functions: [ProjectBackendFunctionRecord]
    let secrets: [ProjectBackendSecretRecord]
    let recentLogs: [ProjectBackendLogEntry]
    let recentFailures: [ProjectBackendFailureRecord]
    let lastDeploySummary: String?
    let lastStatusRefreshAt: String?
    let lastUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case providerID
        case linkedProjectRef
        case linkedProjectURL
        case functions
        case secrets
        case recentLogs
        case recentFailures
        case lastDeploySummary
        case lastStatusRefreshAt
        case lastUpdatedAt
    }

    init(
        providerID: ProjectBackendProviderID? = nil,
        linkedProjectRef: String? = nil,
        linkedProjectURL: String? = nil,
        functions: [ProjectBackendFunctionRecord] = [],
        secrets: [ProjectBackendSecretRecord] = [],
        recentLogs: [ProjectBackendLogEntry] = [],
        recentFailures: [ProjectBackendFailureRecord] = [],
        lastDeploySummary: String? = nil,
        lastStatusRefreshAt: String? = nil,
        lastUpdatedAt: String? = nil
    ) {
        self.providerID = providerID
        self.linkedProjectRef = linkedProjectRef
        self.linkedProjectURL = linkedProjectURL
        self.functions = functions
        self.secrets = secrets
        self.recentLogs = recentLogs
        self.recentFailures = recentFailures
        self.lastDeploySummary = lastDeploySummary
        self.lastStatusRefreshAt = lastStatusRefreshAt
        self.lastUpdatedAt = lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decodeIfPresent(ProjectBackendProviderID.self, forKey: .providerID)
        linkedProjectRef = try container.decodeIfPresent(String.self, forKey: .linkedProjectRef)
        linkedProjectURL = try container.decodeIfPresent(String.self, forKey: .linkedProjectURL)
        functions = try container.decodeIfPresent([ProjectBackendFunctionRecord].self, forKey: .functions) ?? []
        secrets = try container.decodeIfPresent([ProjectBackendSecretRecord].self, forKey: .secrets) ?? []
        recentLogs = try container.decodeIfPresent([ProjectBackendLogEntry].self, forKey: .recentLogs) ?? []
        recentFailures = try container.decodeIfPresent([ProjectBackendFailureRecord].self, forKey: .recentFailures) ?? []
        lastDeploySummary = try container.decodeIfPresent(String.self, forKey: .lastDeploySummary)
        lastStatusRefreshAt = try container.decodeIfPresent(String.self, forKey: .lastStatusRefreshAt)
        lastUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastUpdatedAt)
    }

    static let empty = ProjectBackendState()

    var isConfigured: Bool {
        providerID != nil && !(linkedProjectRef?.isEmpty ?? true)
    }

    var openFailures: [ProjectBackendFailureRecord] {
        recentFailures
            .filter(\.isOpen)
            .sorted { $0.timestamp > $1.timestamp }
    }

    var openFailureCount: Int {
        openFailures.count
    }

    var hasUnsyncedSecrets: Bool {
        secrets.contains(where: { $0.lastSyncedAt == nil })
    }

    var latestDeployAt: String? {
        functions.compactMap(\.lastDeployedAt).max()
    }

    var latestOpenFailure: ProjectBackendFailureRecord? {
        openFailures.first
    }

    var attentionSortedFunctions: [ProjectBackendFunctionRecord] {
        functions.sorted { lhs, rhs in
            let lhsHasFailure = latestOpenFailure(for: lhs.name) != nil
            let rhsHasFailure = latestOpenFailure(for: rhs.name) != nil
            if lhsHasFailure != rhsHasFailure {
                return lhsHasFailure && !rhsHasFailure
            }

            let lhsNeedsDeploy = lhs.lastDeployedAt == nil
            let rhsNeedsDeploy = rhs.lastDeployedAt == nil
            if lhsNeedsDeploy != rhsNeedsDeploy {
                return lhsNeedsDeploy && !rhsNeedsDeploy
            }

            let lhsActivity = [lhs.updatedAt, lhs.lastDeployedAt ?? "", latestOpenFailure(for: lhs.name)?.timestamp ?? ""].max() ?? ""
            let rhsActivity = [rhs.updatedAt, rhs.lastDeployedAt ?? "", latestOpenFailure(for: rhs.name)?.timestamp ?? ""].max() ?? ""
            if lhsActivity != rhsActivity {
                return lhsActivity > rhsActivity
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func latestOpenFailure(for functionName: String) -> ProjectBackendFailureRecord? {
        openFailures.first {
            $0.functionName.caseInsensitiveCompare(functionName) == .orderedSame
        }
    }
}

extension ProjectBackendState {
    private nonisolated static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private nonisolated func updating(
        providerID: ProjectBackendProviderID? = nil,
        linkedProjectRef: String? = nil,
        linkedProjectURL: String? = nil,
        functions: [ProjectBackendFunctionRecord]? = nil,
        secrets: [ProjectBackendSecretRecord]? = nil,
        recentLogs: [ProjectBackendLogEntry]? = nil,
        recentFailures: [ProjectBackendFailureRecord]? = nil,
        lastDeploySummary: String?? = nil,
        lastStatusRefreshAt: String?? = nil,
        lastUpdatedAt: String? = nil
    ) -> Self {
        Self(
            providerID: providerID ?? self.providerID,
            linkedProjectRef: linkedProjectRef ?? self.linkedProjectRef,
            linkedProjectURL: linkedProjectURL ?? self.linkedProjectURL,
            functions: functions ?? self.functions,
            secrets: secrets ?? self.secrets,
            recentLogs: recentLogs ?? self.recentLogs,
            recentFailures: recentFailures ?? self.recentFailures,
            lastDeploySummary: lastDeploySummary ?? self.lastDeploySummary,
            lastStatusRefreshAt: lastStatusRefreshAt ?? self.lastStatusRefreshAt,
            lastUpdatedAt: lastUpdatedAt ?? Self.now()
        )
    }

    private nonisolated func sortedLogs(_ entries: [ProjectBackendLogEntry], limit: Int = 20) -> [ProjectBackendLogEntry] {
        var seenIDs = Set<String>()
        let deduped = entries.filter { seenIDs.insert($0.id).inserted }
        return Array(deduped.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    private nonisolated func sortedFailures(_ entries: [ProjectBackendFailureRecord], limit: Int = 20) -> [ProjectBackendFailureRecord] {
        var seenIDs = Set<String>()
        let deduped = entries.filter { seenIDs.insert($0.id).inserted }
        return Array(deduped.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    nonisolated func linking(to link: BackendProviderLink) -> Self {
        updating(
            providerID: link.providerID,
            linkedProjectRef: link.projectRef,
            linkedProjectURL: link.projectURL
        )
    }

    nonisolated func merging(snapshot: BackendStatusSnapshot) -> Self {
        let timestamp = Self.now()
        let remoteFunctions = snapshot.remoteFunctionNames.reduce(into: functions) { partialResult, name in
            guard !partialResult.contains(where: { $0.name == name }) else { return }
            partialResult.append(
                .init(
                    name: name,
                    summary: "Remote backend function.",
                    verifyJWT: true,
                    sourcePath: "supabase/functions/\(name)/index.ts",
                    updatedAt: timestamp
                )
            )
        }
        let remoteSecrets = snapshot.remoteSecretNames.reduce(into: secrets) { partialResult, name in
            guard !partialResult.contains(where: { $0.name == name }) else { return }
            partialResult.append(.init(name: name, updatedAt: timestamp))
        }

        return updating(
            providerID: snapshot.providerID,
            linkedProjectRef: snapshot.projectRef,
            linkedProjectURL: snapshot.projectURL,
            functions: remoteFunctions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            secrets: remoteSecrets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            lastUpdatedAt: timestamp
        )
    }

    nonisolated func markingStatusRefreshed(at timestamp: String = Self.now()) -> Self {
        updating(lastStatusRefreshAt: .some(timestamp), lastUpdatedAt: timestamp)
    }

    nonisolated func upsertingFunction(_ function: ProjectBackendFunctionRecord) -> Self {
        var next = functions.filter { $0.name != function.name }
        next.append(function)
        next.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return updating(functions: next)
    }

    nonisolated func markingFunctionDeployed(named functionName: String, at timestamp: String) -> Self {
        updating(
            functions: functions.map { function in
                guard function.name == functionName else { return function }
                return ProjectBackendFunctionRecord(
                    id: function.id,
                    name: function.name,
                    summary: function.summary,
                    verifyJWT: function.verifyJWT,
                    sourcePath: function.sourcePath,
                    updatedAt: function.updatedAt,
                    lastDeployedAt: timestamp,
                    lastInvocationSummary: function.lastInvocationSummary
                )
            },
            recentFailures: recentFailures.map { failure in
                guard failure.isOpen,
                      failure.functionName.caseInsensitiveCompare(functionName) == .orderedSame else {
                    return failure
                }
                return ProjectBackendFailureRecord(
                    id: failure.id,
                    functionName: failure.functionName,
                    timestamp: failure.timestamp,
                    requestSummary: failure.requestSummary,
                    errorSummary: failure.errorSummary,
                    source: failure.source,
                    relatedLogIDs: failure.relatedLogIDs,
                    resolvedAt: timestamp
                )
            },
            lastUpdatedAt: timestamp
        )
    }

    nonisolated func markingFunctionInvoked(
        named functionName: String,
        summary: String,
        at timestamp: String = Self.now()
    ) -> Self {
        updating(
            functions: functions.map { function in
                guard function.name == functionName else { return function }
                return ProjectBackendFunctionRecord(
                    id: function.id,
                    name: function.name,
                    summary: function.summary,
                    verifyJWT: function.verifyJWT,
                    sourcePath: function.sourcePath,
                    updatedAt: function.updatedAt,
                    lastDeployedAt: function.lastDeployedAt,
                    lastInvocationSummary: summary
                )
            },
            recentFailures: recentFailures.map { failure in
                guard failure.isOpen,
                      failure.functionName.caseInsensitiveCompare(functionName) == .orderedSame else {
                    return failure
                }
                return ProjectBackendFailureRecord(
                    id: failure.id,
                    functionName: failure.functionName,
                    timestamp: failure.timestamp,
                    requestSummary: failure.requestSummary,
                    errorSummary: failure.errorSummary,
                    source: failure.source,
                    relatedLogIDs: failure.relatedLogIDs,
                    resolvedAt: timestamp
                )
            },
            lastUpdatedAt: timestamp
        )
    }

    nonisolated func upsertingSecret(_ secret: ProjectBackendSecretRecord) -> Self {
        var next = secrets.filter { $0.name != secret.name }
        next.append(secret)
        next.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return updating(secrets: next)
    }

    nonisolated func with(recentLogs: [ProjectBackendLogEntry]) -> Self {
        withMergedLogs(recentLogs)
    }

    nonisolated func with(lastDeploySummary: String?) -> Self {
        updating(lastDeploySummary: .some(lastDeploySummary))
    }

    nonisolated func appendingLog(_ entry: ProjectBackendLogEntry) -> Self {
        var nextState = updating(recentLogs: sortedLogs([entry] + recentLogs))
        if entry.isError, let functionName = entry.functionName, !functionName.isEmpty {
            nextState = nextState.recordFailure(
                functionName: functionName,
                requestSummary: nil,
                errorSummary: entry.message,
                source: .logs,
                relatedLogIDs: [entry.id],
                at: entry.timestamp
            )
        }
        return nextState
    }

    nonisolated func withMergedLogs(_ logs: [ProjectBackendLogEntry]) -> Self {
        var nextState = updating(recentLogs: sortedLogs(logs))
        for log in logs where log.isError {
            guard let functionName = log.functionName, !functionName.isEmpty else { continue }
            nextState = nextState.recordFailure(
                functionName: functionName,
                requestSummary: nil,
                errorSummary: log.message,
                source: .logs,
                relatedLogIDs: [log.id],
                at: log.timestamp
            )
        }
        return nextState
    }

    nonisolated func recordFailure(
        functionName: String,
        requestSummary: String?,
        errorSummary: String,
        source: ProjectBackendFailureSource,
        relatedLogIDs: [String] = [],
        at timestamp: String = Self.now()
    ) -> Self {
        let trimmedFunctionName = functionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFunctionName.isEmpty else { return self }

        var nextFailures = recentFailures
        let normalizedRequestSummary = requestSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedErrorSummary = errorSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLogIDs = relatedLogIDs.filter { !$0.isEmpty }

        if let index = nextFailures.firstIndex(where: { failure in
            guard failure.isOpen,
                  failure.functionName.caseInsensitiveCompare(trimmedFunctionName) == .orderedSame else {
                return false
            }

            if !Set(failure.relatedLogIDs).isDisjoint(with: normalizedLogIDs) {
                return true
            }

            return failure.errorSummary == normalizedErrorSummary
        }) {
            let existing = nextFailures[index]
            nextFailures[index] = ProjectBackendFailureRecord(
                id: existing.id,
                functionName: existing.functionName,
                timestamp: timestamp,
                requestSummary: normalizedRequestSummary ?? existing.requestSummary,
                errorSummary: normalizedErrorSummary,
                source: existing.source == .invoke ? .invoke : source,
                relatedLogIDs: Array(Set(existing.relatedLogIDs + normalizedLogIDs)).sorted(),
                resolvedAt: nil
            )
        } else {
            nextFailures.append(
                ProjectBackendFailureRecord(
                    functionName: trimmedFunctionName,
                    timestamp: timestamp,
                    requestSummary: normalizedRequestSummary,
                    errorSummary: normalizedErrorSummary,
                    source: source,
                    relatedLogIDs: normalizedLogIDs
                )
            )
        }

        return updating(recentFailures: sortedFailures(nextFailures), lastUpdatedAt: timestamp)
    }
}
