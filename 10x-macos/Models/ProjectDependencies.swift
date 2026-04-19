import Foundation

nonisolated enum ProjectDependencySafety: String, Codable, Sendable, CaseIterable, Hashable {
    case clientRuntime
    case backendOnly
    case developmentOnlyRemoveBeforeShip

    var title: String {
        switch self {
        case .clientRuntime:
            return "Client-safe"
        case .backendOnly:
            return "Backend only"
        case .developmentOnlyRemoveBeforeShip:
            return "Remove before ship"
        }
    }

    var detail: String {
        switch self {
        case .clientRuntime:
            return "Safe to ship in the client runtime."
        case .backendOnly:
            return "Do not ship this dependency or secret in the client."
        case .developmentOnlyRemoveBeforeShip:
            return "Temporary development setup that must be removed before release."
        }
    }
}

private extension ProjectDependencySafety {
    nonisolated static func looseMatch(from rawValue: String?) -> Self? {
        let normalized = ProjectDependencyRequirement.normalizedIdentifier(rawValue ?? "")
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("backend")
            || normalized.contains("server")
            || normalized.contains("secret")
            || normalized.contains("private") {
            return .backendOnly
        }
        if normalized.contains("development")
            || normalized.contains("dev")
            || normalized.contains("debug")
            || normalized.contains("temporary")
            || normalized.contains("removebeforeship") {
            return .developmentOnlyRemoveBeforeShip
        }
        if normalized.contains("client")
            || normalized.contains("runtime")
            || normalized.contains("public") {
            return .clientRuntime
        }

        return nil
    }
}

nonisolated struct ProjectDependencyRequirement: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let setupSurface: ProjectSetupSurface
    let integrationID: ProjectIntegrationID?
    let backendProviderID: ProjectBackendProviderID?
    let backendCapabilityIDs: [String]
    let envKeys: [String]
    let safety: ProjectDependencySafety
    let allowsMockDataUntilConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case setupSurface = "setup_surface"
        case integrationID = "integration_id"
        case backendProviderID = "backend_provider_id"
        case backendCapabilityIDs = "backend_capability_ids"
        case envKeys = "env_keys"
        case safety
        case allowsMockDataUntilConfigured = "allows_mock_data_until_configured"
    }

    init(
        id: String,
        title: String,
        summary: String,
        setupSurface: ProjectSetupSurface? = nil,
        integrationID: ProjectIntegrationID? = nil,
        backendProviderID: ProjectBackendProviderID? = nil,
        backendCapabilityIDs: [String] = [],
        envKeys: [String] = [],
        safety: ProjectDependencySafety,
        allowsMockDataUntilConfigured: Bool
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.setupSurface = setupSurface ?? Self.defaultSetupSurface(
            integrationID: integrationID,
            backendProviderID: backendProviderID
        )
        self.integrationID = integrationID
        self.backendProviderID = backendProviderID
        self.backendCapabilityIDs = backendCapabilityIDs
            .map(Self.normalizedIdentifier)
            .filter { !$0.isEmpty }
        self.envKeys = envKeys
            .map(ProjectEnvironmentSecurity.normalizedKey)
            .filter { !$0.isEmpty }
        self.safety = safety
        self.allowsMockDataUntilConfigured = allowsMockDataUntilConfigured
    }

    init?(looseInput: [String: Any]) {
        let titleSeed = Self.string(in: looseInput, keys: ["title", "name", "dependency", "service", "provider"])
        let integrationID = ProjectIntegrationID.looseMatch(
            from: Self.string(in: looseInput, keys: ["integration_id", "integrationId", "integration", "provider", "service"])
                ?? titleSeed
        )
        let setupSurface = ProjectSetupSurface.looseMatch(
            from: Self.string(in: looseInput, keys: ["setup_surface", "setupSurface"])
        )
        let backendProviderID = ProjectBackendProviderID.looseMatch(
            from: Self.string(
                in: looseInput,
                keys: ["backend_provider_id", "backendProviderId", "backend_provider", "backendProvider"]
            ) ?? Self.backendProviderSeed(
                title: titleSeed,
                setupSurface: setupSurface,
                backendCapabilityIDs: Self.stringArray(
                    in: looseInput,
                    keys: ["backend_capability_ids", "backendCapabilityIds"]
                ) ?? []
            )
        )
        let backendCapabilityIDs = Self.stringArray(
            in: looseInput,
            keys: ["backend_capability_ids", "backendCapabilityIds"]
        ) ?? []
        let envKeys = Self.stringArray(in: looseInput, keys: ["env_keys", "envKeys", "keys"])
            ?? integrationID?.dependencyEnvKeys
            ?? []
        let title = titleSeed
            ?? integrationID?.dependencyTitle
            ?? backendProviderID.map { "\($0.title) Backend" }
            ?? envKeys.first.map(Self.displayTitle)
            ?? ""

        guard !title.isEmpty || integrationID != nil || backendProviderID != nil || !envKeys.isEmpty else { return nil }

        let resolvedSetupSurface = setupSurface
            ?? Self.defaultSetupSurface(integrationID: integrationID, backendProviderID: backendProviderID)

        let safety = ProjectDependencySafety.looseMatch(
            from: Self.string(in: looseInput, keys: ["safety", "classification", "scope", "exposure"])
        ) ?? Self.defaultSafety(
            integrationID: integrationID,
            backendProviderID: backendProviderID,
            envKeys: envKeys,
            title: title
        )
        let summary = Self.string(
            in: looseInput,
            keys: ["summary", "description", "detail", "details", "message", "reason", "notes"]
        ) ?? integrationID?.dependencySummary
            ?? backendProviderID?.dependencySummary
            ?? Self.defaultSummary(title: title, envKeys: envKeys, safety: safety)
        let id = Self.string(in: looseInput, keys: ["id", "key", "slug", "dependencyId"])
            ?? integrationID?.rawValue
            ?? backendProviderID.map { "\($0.rawValue)-backend" }
            ?? Self.normalizedIdentifier(envKeys.first ?? title)
        let allowsMockDataUntilConfigured = Self.bool(
            in: looseInput,
            keys: ["allows_mock_data_until_configured", "allowsMockDataUntilConfigured"]
        ) ?? true

        self.init(
            id: id,
            title: title,
            summary: summary,
            setupSurface: resolvedSetupSurface,
            integrationID: integrationID,
            backendProviderID: backendProviderID,
            backendCapabilityIDs: backendCapabilityIDs,
            envKeys: envKeys,
            safety: safety,
            allowsMockDataUntilConfigured: allowsMockDataUntilConfigured
        )

        guard normalized != nil else { return nil }
    }

    init?(shorthand value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ProjectDependencyManifest.isNoDependenciesValue(trimmed) else { return nil }

        self.init(looseInput: ["title": trimmed])
    }

    var normalized: Self? {
        guard !id.isEmpty, !title.isEmpty, !summary.isEmpty else { return nil }
        return Self(
            id: id,
            title: title,
            summary: summary,
            setupSurface: setupSurface,
            integrationID: integrationID,
            backendProviderID: backendProviderID,
            backendCapabilityIDs: backendCapabilityIDs,
            envKeys: envKeys,
            safety: safety,
            allowsMockDataUntilConfigured: allowsMockDataUntilConfigured
        )
    }

    fileprivate nonisolated static func normalizedIdentifier(_ string: String) -> String {
        string
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private static func string(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let rawValue = input[key] else { continue }
            let value = (rawValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func stringArray(in input: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            guard let rawValue = input[key] else { continue }

            let values: [String]
            switch rawValue {
            case let items as [String]:
                values = items
            case let items as [Any]:
                values = items.compactMap { $0 as? String }
            case let value as String:
                values = value.components(separatedBy: CharacterSet(charactersIn: ",\n;"))
            default:
                continue
            }

            let normalizedValues = values
                .map(ProjectEnvironmentSecurity.normalizedKey)
                .filter { !$0.isEmpty }
            if !normalizedValues.isEmpty {
                return normalizedValues
            }
        }
        return nil
    }

    private static func bool(in input: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let rawValue = input[key] else { continue }

            switch rawValue {
            case let value as Bool:
                return value
            case let value as NSNumber:
                return value.boolValue
            case let value as String:
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "y", "1":
                    return true
                case "false", "no", "n", "0":
                    return false
                default:
                    continue
                }
            default:
                continue
            }
        }
        return nil
    }

    private static func defaultSafety(
        integrationID: ProjectIntegrationID?,
        backendProviderID: ProjectBackendProviderID?,
        envKeys: [String],
        title: String
    ) -> ProjectDependencySafety {
        if backendProviderID != nil {
            return .backendOnly
        }

        if let integrationID {
            switch integrationID {
            case .supabase:
                return .clientRuntime
            case .superwall:
                return .clientRuntime
            case .openAI:
                return .backendOnly
            }
        }

        let normalizedTokens = ([title] + envKeys).map(normalizedIdentifier)
        if normalizedTokens.contains(where: {
            $0.contains("dev")
                || $0.contains("debug")
                || $0.contains("mock")
                || $0.contains("bypass")
                || $0.contains("local")
        }) {
            return .developmentOnlyRemoveBeforeShip
        }

        if envKeys.contains(where: { ProjectEnvironmentSecurity.isSensitive(key: $0) }) {
            return .backendOnly
        }

        return .clientRuntime
    }

    private static func defaultSetupSurface(
        integrationID: ProjectIntegrationID?,
        backendProviderID: ProjectBackendProviderID?
    ) -> ProjectSetupSurface {
        if backendProviderID != nil {
            return .backend
        }
        if integrationID != nil {
            return .integration
        }
        return .external
    }

    private static func defaultSummary(
        title: String,
        envKeys: [String],
        safety: ProjectDependencySafety
    ) -> String {
        if !envKeys.isEmpty {
            let keys = envKeys.map { "`\($0)`" }.joined(separator: ", ")
            switch safety {
            case .clientRuntime:
                return "Configure \(keys) for client runtime access."
            case .backendOnly:
                return "Provide \(keys) as backend-only configuration and keep it off-device."
            case .developmentOnlyRemoveBeforeShip:
                return "Use \(keys) only for development, then remove it before shipping."
            }
        }

        return "Configure \(title)."
    }

    private static func backendProviderSeed(
        title: String?,
        setupSurface: ProjectSetupSurface?,
        backendCapabilityIDs: [String]
    ) -> String? {
        guard let title else { return nil }
        if setupSurface == .backend || !backendCapabilityIDs.isEmpty || suggestsBackend(title) {
            return title
        }
        return nil
    }

    private static func suggestsBackend(_ title: String) -> Bool {
        let normalized = normalizedIdentifier(title)
        return normalized.contains("backend")
            || normalized.contains("server")
            || normalized.contains("function")
            || normalized.contains("edge")
    }

    private static func displayTitle(from value: String) -> String {
        let parts = value
            .components(separatedBy: CharacterSet(charactersIn: "_- "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return "Dependency" }

        return parts
            .map { part in
                let uppercased = part.uppercased()
                if uppercased.count <= 4 || part == uppercased {
                    return uppercased
                }
                return String(uppercased.prefix(1)) + uppercased.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

nonisolated struct ProjectDependencyManifest: Codable, Sendable, Hashable {
    let dependencies: [ProjectDependencyRequirement]

    init(dependencies: [ProjectDependencyRequirement]) {
        self.dependencies = dependencies.compactMap(\.normalized)
    }

    var isEmpty: Bool {
        dependencies.isEmpty
    }

    init?(toolInput: [String: Any]) {
        if JSONSerialization.isValidJSONObject(toolInput),
           let data = try? JSONSerialization.data(withJSONObject: toolInput, options: [.sortedKeys]),
           let manifest = try? JSONDecoder().decode(Self.self, from: data) {
            self = manifest
            return
        }

        guard let rawDependencies = toolInput["dependencies"] else {
            return nil
        }

        if let value = rawDependencies as? String, Self.isNoDependenciesValue(value) {
            self = Self(dependencies: [])
            return
        }

        guard let items = rawDependencies as? [Any] else { return nil }

        let dependencies = items.compactMap { item -> ProjectDependencyRequirement? in
            if let input = item as? [String: Any] {
                return ProjectDependencyRequirement(looseInput: input)
            }
            if let value = item as? String {
                return ProjectDependencyRequirement(shorthand: value)
            }
            return nil
        }

        guard dependencies.count == items.count else { return nil }
        self = Self(dependencies: dependencies)
    }

    fileprivate static func isNoDependenciesValue(_ value: String) -> Bool {
        let normalized = ProjectDependencyRequirement.normalizedIdentifier(value)
        return normalized.isEmpty || normalized == "none" || normalized == "nodependencies" || normalized == "norequirements"
    }
}

private extension ProjectIntegrationID {
    nonisolated static func looseMatch(from rawValue: String?) -> Self? {
        guard let rawValue else { return nil }

        let normalized = ProjectDependencyRequirement.normalizedIdentifier(rawValue)
        if normalized.contains("supabase") {
            return .supabase
        }
        if normalized.contains("superwall") {
            return .superwall
        }
        if normalized.contains("openai") {
            return .openAI
        }

        return nil
    }

    nonisolated var dependencyTitle: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .supabase:
            return "Supabase"
        case .superwall:
            return "Superwall"
        }
    }

    nonisolated var dependencyEnvKeys: [String] {
        switch self {
        case .openAI:
            return ["OPENAI_API_KEY"]
        case .supabase:
            return ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"]
        case .superwall:
            return ["SUPERWALL_PUBLIC_API_KEY"]
        }
    }

    nonisolated var dependencySummary: String {
        switch self {
        case .openAI:
            return "Configure the OpenAI integration before using live AI responses."
        case .supabase:
            return "Connect the built-in Supabase integration in Integrations."
        case .superwall:
            return "Connect the built-in Superwall integration in Integrations."
        }
    }
}

private extension ProjectBackendProviderID {
    nonisolated static func looseMatch(from rawValue: String?) -> Self? {
        guard let rawValue else { return nil }

        let normalized = ProjectDependencyRequirement.normalizedIdentifier(rawValue)
        if normalized.contains("supabase") {
            return .supabase
        }

        return nil
    }

    nonisolated var dependencySummary: String {
        switch self {
        case .supabase:
            return "Configure the managed Supabase backend in Backend."
        }
    }
}

private extension ProjectSetupSurface {
    nonisolated static func looseMatch(from rawValue: String?) -> Self? {
        guard let rawValue else { return nil }

        let normalized = ProjectDependencyRequirement.normalizedIdentifier(rawValue)
        switch normalized {
        case "integration", "integrations":
            return .integration
        case "backend":
            return .backend
        case "external":
            return .external
        default:
            return nil
        }
    }
}

nonisolated struct ProjectDependencyResolution: Sendable, Hashable {
    let requirement: ProjectDependencyRequirement
    let isResolved: Bool
    let configuredKeys: [String]
    let missingKeys: [String]
    let detail: String
}

nonisolated struct ProjectDependencyResolutionContext: Sendable {
    let environmentVariables: [ProjectEnvironmentVariable]
    let backendState: ProjectBackendState

    static let empty = Self(environmentVariables: [], backendState: .empty)
}

extension ProjectDependencyRequirement {
    func resolve(
        using variables: [ProjectEnvironmentVariable],
        backendState: ProjectBackendState = .empty
    ) -> ProjectDependencyResolution {
        let remoteHostedKeys = Set(backendState.secrets.map { ProjectEnvironmentSecurity.normalizedKey($0.name) })
        let configuredValues = Dictionary(
            uniqueKeysWithValues: variables.map { ($0.normalizedKey, $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
        let configuredKeys = envKeys.filter {
            !(configuredValues[$0] ?? "").isEmpty || remoteHostedKeys.contains($0)
        }
        let missingKeys = envKeys.filter { !configuredKeys.contains($0) }

        if setupSurface == .backend, let backendProviderID {
            let backendReady = isBackendConfigured(providerID: backendProviderID, backendState: backendState)
            let isResolved = backendReady && missingKeys.isEmpty
            let detail = isResolved
                ? "\(backendProviderID.title) backend is configured."
                : "\(backendProviderID.title) backend still needs setup in Backend."
            return ProjectDependencyResolution(
                requirement: self,
                isResolved: isResolved,
                configuredKeys: configuredKeys,
                missingKeys: missingKeys,
                detail: detail
            )
        }

        if let integrationID {
            let definition = ProjectIntegrations.definition(for: integrationID)
            let values = ProjectIntegrations.values(for: definition, in: variables)
            let isResolved = definition.isConfigured(values: values, remoteHostedKeys: remoteHostedKeys)
            let detail = isResolved
                ? "\(definition.title) is configured."
                : "\(definition.title) still needs setup in Integrations."
            return ProjectDependencyResolution(
                requirement: self,
                isResolved: isResolved,
                configuredKeys: configuredKeys,
                missingKeys: missingKeys,
                detail: detail
            )
        }

        let isResolved = missingKeys.isEmpty
        let detail: String
        if isResolved {
            detail = envKeys.isEmpty ? "Dependency is recorded." : "All required values are configured."
        } else if let missing = missingKeys.first, missingKeys.count == 1 {
            detail = "Missing `\(missing)`."
        } else if !missingKeys.isEmpty {
            detail = "Missing \(missingKeys.count) required values."
        } else {
            detail = "Dependency is not configured yet."
        }

        return ProjectDependencyResolution(
            requirement: self,
            isResolved: isResolved,
            configuredKeys: configuredKeys,
            missingKeys: missingKeys,
            detail: detail
        )
    }

    private func isBackendConfigured(
        providerID: ProjectBackendProviderID,
        backendState: ProjectBackendState
    ) -> Bool {
        guard backendState.providerID == providerID, backendState.isConfigured else {
            return false
        }

        if backendCapabilityIDs.isEmpty {
            return true
        }

        return backendCapabilityIDs.allSatisfy { capabilityID in
            switch (providerID, capabilityID) {
            case (.supabase, "managedserverlessbackend"):
                return true
            default:
                return false
            }
        }
    }
}
