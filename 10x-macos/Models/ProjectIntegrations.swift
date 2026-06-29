import Foundation

enum ProjectIntegrationID: String, CaseIterable, Codable, Identifiable {
    case openAI = "openai"
    case supabase = "supabase"
    // Superwall removed in 11x local cockpit

    var id: String { rawValue }
}

struct ProjectIntegrationField: Identifiable, Hashable {
    let envKey: String
    let scope: ProjectEnvironmentScope
    let label: String
    let description: String
    let helperText: String
    let placeholder: String
    let exampleValue: String?

    var id: String { envKey }
}

struct ProjectIntegrationGuidanceSection: Identifiable, Hashable {
    let id: String
    let title: String
    let markdown: String
    let visibleWhenConfigured: Bool

    init(
        id: String,
        title: String,
        markdown: String,
        visibleWhenConfigured: Bool = false
    ) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.visibleWhenConfigured = visibleWhenConfigured
    }
}

struct ProjectIntegrationCapabilityStatus: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let isReady: Bool
}

struct ProjectIntegrationDefinition: Identifiable, Hashable {
    let id: ProjectIntegrationID
    let title: String
    let summary: String
    let fields: [ProjectIntegrationField]
    let guidanceSections: [ProjectIntegrationGuidanceSection]

    var managedKeys: Set<String> {
        Set(fields.map(\.envKey))
    }

    var clientFields: [ProjectIntegrationField] {
        fields.filter { $0.scope == .client }
    }

    var hostedFields: [ProjectIntegrationField] {
        fields.filter { $0.scope == .hosted }
    }

    func isConfigured(values: [String: String], remoteHostedKeys: Set<String> = []) -> Bool {
        capabilityStatuses(values: values, remoteHostedKeys: remoteHostedKeys).allSatisfy(\.isReady)
    }

    func visibleGuidanceSections(values: [String: String], remoteHostedKeys: Set<String> = []) -> [ProjectIntegrationGuidanceSection] {
        let configured = isConfigured(values: values, remoteHostedKeys: remoteHostedKeys)
        return guidanceSections.filter { section in
            !configured || section.visibleWhenConfigured
        }
    }

    func capabilityStatuses(values: [String: String], remoteHostedKeys: Set<String> = []) -> [ProjectIntegrationCapabilityStatus] {
        switch id {
        case .openAI:
            let apiKey = Self.trimmedValue(for: "OPENAI_API_KEY", in: values)
            let baseURL = Self.trimmedValue(for: "OPENAI_BASE_URL", in: values)
            let model = Self.trimmedValue(for: "OPENAI_MODEL", in: values)
            let keyValidation = ProjectIntegrations.validationMessage(
                for: .openAI,
                envKey: "OPENAI_API_KEY",
                value: apiKey
            )
            let hasRemoteKey = remoteHostedKeys.contains("OPENAI_API_KEY")
            let isKeyReady = (!apiKey.isEmpty && keyValidation == nil) || (apiKey.isEmpty && hasRemoteKey)

            var statuses: [ProjectIntegrationCapabilityStatus] = []
            statuses.append(
                ProjectIntegrationCapabilityStatus(
                    id: "openai-key",
                    label: "OpenAI API Key",
                    detail: !apiKey.isEmpty
                        ? (keyValidation ?? "OpenAI API key is configured.")
                        : (hasRemoteKey
                            ? "OpenAI API key is configured in a secure backend store."
                            : "Add `OPENAI_API_KEY` under Provider Secrets."),
                    isReady: isKeyReady
                )
            )
            statuses.append(
                ProjectIntegrationCapabilityStatus(
                    id: "openai-base-url",
                    label: "Provider Base URL",
                    detail: baseURL.isEmpty
                        ? "Set `OPENAI_BASE_URL` (e.g. https://api.openai.com or your local gateway)."
                        : "Base URL: \(baseURL)",
                    isReady: !baseURL.isEmpty && URL(string: baseURL) != nil
                )
            )
            statuses.append(
                ProjectIntegrationCapabilityStatus(
                    id: "openai-model",
                    label: "Model",
                    detail: model.isEmpty
                        ? "Set `OPENAI_MODEL` (e.g. gpt-4.1)."
                        : "Model: \(model)",
                    isReady: !model.isEmpty
                )
            )
            return statuses

        case .supabase:
            let url = Self.trimmedValue(for: "SUPABASE_URL", in: values)
            let anonKey = Self.trimmedValue(for: "SUPABASE_ANON_KEY", in: values)
            let publishableKey = Self.trimmedValue(for: "SUPABASE_PUBLISHABLE_KEY", in: values)
            let publicKey = anonKey.isEmpty ? publishableKey : anonKey

            return [
                ProjectIntegrationCapabilityStatus(
                    id: "supabase-client-runtime",
                    label: "Client Runtime",
                    detail: url.isEmpty || publicKey.isEmpty
                        ? "Connect Supabase to link the project runtime."
                        : "Client-safe Supabase runtime is configured for auth and database access.",
                    isReady: !url.isEmpty && !publicKey.isEmpty
                ),
            ]
        // Superwall removed in 11x local cockpit
        }
    }

    private static func trimmedValue(for key: String, in values: [String: String]) -> String {
        values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum ProjectIntegrations {
    private static let legacyOpenAIKeyLength = 51
    private static let modernOpenAIKeyMinimumLength = 100

    static let all: [ProjectIntegrationDefinition] = [
        .init(
            id: .openAI,
            title: "OpenAI-compatible Provider",
            summary: "",
            fields: [
                ProjectIntegrationField(
                    envKey: "OPENAI_API_KEY",
                    scope: .hosted,
                    label: "API Key",
                    description: "OpenAI-compatible API key. Stored in the OS keychain, never exposed to the UI or exported with the project.",
                    helperText: "Paste it here, not in chat. Chat messages are persisted with the project conversation.",
                    placeholder: "sk-...",
                    exampleValue: "sk-..."
                ),
                ProjectIntegrationField(
                    envKey: "OPENAI_BASE_URL",
                    scope: .client,
                    label: "Base URL",
                    description: "OpenAI-compatible base URL. Examples: https://api.openai.com, an Ollama OpenAI-compatible endpoint, vLLM, OpenRouter, or a local gateway.",
                    helperText: "Must expose /v1/chat/completions.",
                    placeholder: "https://api.openai.com",
                    exampleValue: "https://api.openai.com"
                ),
                ProjectIntegrationField(
                    envKey: "OPENAI_MODEL",
                    scope: .client,
                    label: "Model",
                    description: "Model identifier passed to /v1/chat/completions.",
                    helperText: "Examples: gpt-4.1, qwen2.5-coder:32b, mistral-large-latest.",
                    placeholder: "gpt-4.1",
                    exampleValue: "gpt-4.1"
                ),
            ],
            guidanceSections: [
                .init(
                    id: "openai-credentials",
                    title: "",
                    markdown: """
                    - Get a key from your provider (OpenAI, OpenRouter, a local gateway, etc.).
                    - Paste the secret key in Provider Secrets, not in chat.
                    - 11x stores the key in the OS keychain and keeps it out of project files, exports, and generated source.
                    - `OPENAI_BASE_URL` and `OPENAI_MODEL` configure which provider and model 11x calls.
                    """
                ),
            ]
        ),
        .init(
            id: .supabase,
            title: "Supabase",
            summary: "",
            fields: [
                ProjectIntegrationField(
                    envKey: "SUPABASE_URL",
                    scope: .client,
                    label: "URL",
                    description: "Client-side Supabase project URL saved in the project's `.env.local`.",
                    helperText: "",
                    placeholder: "https://your-project.supabase.co",
                    exampleValue: "https://your-project.supabase.co"
                ),
                ProjectIntegrationField(
                    envKey: "SUPABASE_ANON_KEY",
                    scope: .client,
                    label: "Anon Key",
                    description: "Client-side Supabase anon key saved in the project's `.env.local`.",
                    helperText: "",
                    placeholder: "sb_publishable_...",
                    exampleValue: "sb_publishable_..."
                ),
                ProjectIntegrationField(
                    envKey: "SUPABASE_PUBLISHABLE_KEY",
                    scope: .client,
                    label: "Publishable Key",
                    description: "Client-side Supabase publishable key alias saved in the project's `.env.local` for compatibility.",
                    helperText: "10x keeps this alias in sync with `SUPABASE_ANON_KEY` for compatibility.",
                    placeholder: "sb_publishable_...",
                    exampleValue: "sb_publishable_..."
                ),
            ],
            guidanceSections: [
                .init(
                    id: "supabase-backend-plan-note",
                    title: "",
                    markdown: """
                    - Supabase client runtime setup works on ordinary projects, but 10x's managed Backend deploy path depends on the linked project's available Supabase plan and management capabilities.
                    - Edge Functions are not universally Pro-only, but if Backend deploys return a Supabase plan restriction, use a project plan that supports that backend operation or switch to another Supabase project.
                    - Hosted keys sync to Supabase secrets. Only client-safe Supabase values belong here in the project runtime config.
                    """
                ),
            ]
        ),
        .init(
            // Superwall removed in 11x local cockpit
            id: .supabase,
            title: "Supabase",
            summary: "",
            fields: [
                ProjectIntegrationField(
                    envKey: "SUPERWALL_PUBLIC_API_KEY",
                    scope: .client,
                    label: "Public API Key",
                    description: "Public API key for the linked Superwall app.",
                    helperText: "",
                    placeholder: "pk_live_...",
                    exampleValue: "pk_test_..."
                ),
            ],
            guidanceSections: []
        ),
    ]

    static var managedKeys: Set<String> {
        Set(all.flatMap(\.fields).map(\.envKey))
    }

    static func definition(for id: ProjectIntegrationID) -> ProjectIntegrationDefinition {
        all.first { $0.id == id }!
    }

    static func field(envKey: String) -> ProjectIntegrationField? {
        all.flatMap(\.fields).first { $0.envKey == envKey }
    }

    static func validationMessage(
        for integrationID: ProjectIntegrationID,
        envKey: String,
        value: String
    ) -> String? {
        switch (integrationID, envKey) {
        case (.openAI, "OPENAI_API_KEY"):
            openAIKeyValidationMessage(for: value)
        default:
            nil
        }
    }

    static func values(
        for definition: ProjectIntegrationDefinition,
        in variables: [ProjectEnvironmentVariable]
    ) -> [String: String] {
        let existingByKey = Dictionary(
            uniqueKeysWithValues: variables.map { ($0.normalizedKey, $0.value) }
        )

        return definition.fields.reduce(into: [String: String]()) { partialResult, field in
            partialResult[field.envKey] = existingByKey[field.envKey] ?? ""
        }
    }

    static func customVariables(from variables: [ProjectEnvironmentVariable]) -> [ProjectEnvironmentVariable] {
        variables.filter { !managedKeys.contains($0.normalizedKey) }
    }

    static func displayVariables(
        existingVariables: [ProjectEnvironmentVariable],
        backendState: ProjectBackendState
    ) -> [ProjectEnvironmentVariable] {
        let normalizedExisting = existingVariables.map { variable in
            ProjectEnvironmentVariable(
                id: variable.id,
                key: variable.normalizedKey,
                description: variable.description.trimmingCharacters(in: .whitespacesAndNewlines),
                value: variable.value,
                scope: variable.scope
            )
        }
        let existingByKey = Dictionary(
            uniqueKeysWithValues: normalizedExisting.map { ($0.normalizedKey, $0) }
        )
        let managedFieldsByKey = Dictionary(
            uniqueKeysWithValues: all.flatMap { definition in
                definition.fields.map { ($0.envKey, $0) }
            }
        )

        var supplementalVariables: [ProjectEnvironmentVariable] = backendState.secrets.compactMap { secret in
            let key = ProjectEnvironmentSecurity.normalizedKey(secret.name)
            guard !key.isEmpty else { return nil }

            let existing = existingByKey[key]
            let managedField = managedFieldsByKey[key]
            let existingDescription = existing?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = existingDescription.isEmpty ? (managedField?.description ?? "") : existingDescription
            let value = existing?.value ?? ""
            let scope = existing?.scope ?? managedField?.scope ?? .hosted

            return ProjectEnvironmentVariable(
                id: existing?.id ?? secret.id,
                key: key,
                description: description,
                value: value,
                scope: scope
            )
        }

        let linkedSupabaseURL = backendState.linkedProjectURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkedSupabaseRef = backendState.linkedProjectRef?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSupabaseURL: String? = {
            if let linkedSupabaseURL, !linkedSupabaseURL.isEmpty {
                return linkedSupabaseURL
            }
            if let linkedSupabaseRef, !linkedSupabaseRef.isEmpty {
                return "https://\(linkedSupabaseRef).supabase.co"
            }
            return nil
        }()

        if let resolvedSupabaseURL, !resolvedSupabaseURL.isEmpty {
            let key = "SUPABASE_URL"
            let existing = existingByKey[key]
            let managedField = managedFieldsByKey[key]
            let existingDescription = existing?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = existingDescription.isEmpty ? (managedField?.description ?? "") : existingDescription
            let existingValue = existing?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let value = existingValue.isEmpty ? resolvedSupabaseURL : existingValue
            let scope = existing?.scope ?? managedField?.scope ?? .client

            supplementalVariables.append(
                ProjectEnvironmentVariable(
                    id: existing?.id ?? key,
                    key: key,
                    description: description,
                    value: value,
                    scope: scope
                )
            )
        }

        return mergedDisplayVariables(primary: normalizedExisting, supplemental: supplementalVariables)
    }

    static func mergedVariables(
        managedDrafts: [ProjectIntegrationID: [String: String]],
        customVariables: [ProjectEnvironmentVariable],
        existingVariables: [ProjectEnvironmentVariable],
        remoteHostedKeys: Set<String> = []
    ) -> [ProjectEnvironmentVariable] {
        let existingByKey = Dictionary(
            uniqueKeysWithValues: existingVariables.map { ($0.normalizedKey, $0) }
        )

        let managedVariables = all.flatMap { definition in
            let values = managedDrafts[definition.id] ?? [:]

            return definition.fields.compactMap { field -> ProjectEnvironmentVariable? in
                let rawValue = values[field.envKey] ?? ""
                let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let existing = existingByKey[field.envKey]
                if trimmedValue.isEmpty {
                    guard field.scope == .hosted, remoteHostedKeys.contains(field.envKey) else { return nil }
                    return ProjectEnvironmentVariable(
                        id: existing?.id ?? UUID().uuidString,
                        key: field.envKey,
                        description: field.description,
                        value: "",
                        scope: field.scope
                    )
                }

                return ProjectEnvironmentVariable(
                    id: existing?.id ?? UUID().uuidString,
                    key: field.envKey,
                    description: field.description,
                    value: trimmedValue,
                    scope: field.scope
                )
            }
        }

        let normalizedCustom = customVariables.compactMap { variable -> ProjectEnvironmentVariable? in
            let key = variable.normalizedKey
            guard !key.isEmpty, !managedKeys.contains(key) else { return nil }

            return ProjectEnvironmentVariable(
                id: variable.id,
                key: key,
                description: variable.description.trimmingCharacters(in: .whitespacesAndNewlines),
                value: variable.value,
                scope: variable.scope
            )
        }

        return managedVariables + normalizedCustom
    }

    private static func mergedDisplayVariables(
        primary: [ProjectEnvironmentVariable],
        supplemental: [ProjectEnvironmentVariable]
    ) -> [ProjectEnvironmentVariable] {
        var merged = primary

        for variable in supplemental {
            let key = variable.normalizedKey
            guard !key.isEmpty else { continue }

            if let index = merged.firstIndex(where: { $0.normalizedKey == key }) {
                let existing = merged[index]
                let description = existing.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? variable.description
                    : existing.description
                let value = existing.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? variable.value
                    : existing.value

                merged[index] = ProjectEnvironmentVariable(
                    id: existing.id,
                    key: key,
                    description: description,
                    value: value,
                    scope: existing.scope
                )
            } else {
                merged.append(variable)
            }
        }

        return merged
    }

    private static func openAIKeyValidationMessage(for rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("sk-proj-") || value.hasPrefix("sk-admin-") {
            guard value.range(
                of: #"^(sk-proj-|sk-admin-)[A-Za-z0-9_-]+$"#,
                options: .regularExpression
            ) != nil else {
                return "OpenAI API keys can only contain letters, numbers, dashes, and underscores."
            }
            // OpenAI still accepts legacy 51-character `sk-...` keys, but current
            // project/admin keys are substantially longer. Use a conservative
            // minimum here so incomplete pastes are rejected without hard-coding
            // a format OpenAI may change again.
            guard value.count >= modernOpenAIKeyMinimumLength else {
                return "That OpenAI key looks too short. Project-scoped keys should be much longer."
            }
            return nil
        }

        guard value.hasPrefix("sk-") else {
            return "OpenAI API keys should start with `sk-`, `sk-proj-`, or `sk-admin-`."
        }
        guard value.range(of: #"^sk-[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return "OpenAI API keys can only contain letters, numbers, dashes, and underscores."
        }
        guard value.count == legacyOpenAIKeyLength else {
            return "Legacy OpenAI API keys should be exactly 51 characters."
        }
        return nil
    }
}
