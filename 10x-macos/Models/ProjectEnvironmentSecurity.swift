import Foundation

enum ProjectEnvironmentSecurity {
    private nonisolated static let sensitiveMarkers = [
        "KEY",
        "TOKEN",
        "SECRET",
        "PASSWORD",
        "PRIVATE",
        "CREDENTIAL",
    ]

    private nonisolated static let explicitlySensitiveKeys: Set<String> = [
        "OPENAI_API_KEY",
        "SUPERWALL_API_KEY",
        "SUPABASE_DB_PASSWORD",
        "SUPABASE_DB_URL",
        "SUPABASE_MANAGEMENT_TOKEN",
    ]

    private nonisolated static let explicitlyPublicKeys: Set<String> = [
        "OPENAI_BASE_URL",
        "OPENAI_MODEL",
        "SUPERWALL_PUBLIC_API_KEY",
        "SUPABASE_ANON_KEY",
        "SUPABASE_PROJECT_REF",
        "SUPABASE_PUBLISHABLE_KEY",
        "SUPABASE_URL",
    ]

    private nonisolated static let explicitlyPublicPrefixes = [
        "EXPO_PUBLIC_",
        "NEXT_PUBLIC_",
        "PUBLIC_",
        "VITE_",
    ]

    nonisolated static func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizedDescription(_ description: String) -> String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func isSensitive(key: String) -> Bool {
        let normalized = normalizedKey(key).uppercased()
        guard !normalized.isEmpty else { return false }
        if explicitlySensitiveKeys.contains(normalized) {
            return true
        }
        if explicitlyPublicKeys.contains(normalized) {
            return false
        }
        if explicitlyPublicPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return false
        }
        return sensitiveMarkers.contains { normalized.contains($0) }
    }

    nonisolated static func runtimeEnvironment(from variables: [ProjectEnvironmentVariable]) -> [String: String] {
        variables.reduce(into: [String: String]()) { partialResult, variable in
            let key = normalizedKey(variable.key)
            guard !key.isEmpty else { return }
            partialResult[key] = variable.value
        }
    }

    nonisolated static func clientRuntimeEnvironment(from variables: [ProjectEnvironmentVariable]) -> [String: String] {
        variables.reduce(into: [String: String]()) { partialResult, variable in
            let key = normalizedKey(variable.key)
            guard !key.isEmpty, variable.scope == .client else { return }
            partialResult[key] = variable.value
        }
    }

    nonisolated static func hostedEnvironment(from variables: [ProjectEnvironmentVariable]) -> [String: String] {
        variables.reduce(into: [String: String]()) { partialResult, variable in
            let key = normalizedKey(variable.key)
            guard !key.isEmpty, variable.scope == .hosted else { return }
            partialResult[key] = variable.value
        }
    }

    nonisolated static func toolEnvironment(from variables: [ProjectEnvironmentVariable]) -> [String: String] {
        clientRuntimeEnvironment(from: variables)
    }

    nonisolated static func bundledEnvironment(from variables: [ProjectEnvironmentVariable]) -> [String: String] {
        clientRuntimeEnvironment(from: variables)
    }

    nonisolated static func configuredKeys(from variables: [ProjectEnvironmentVariable]) -> [String] {
        Array(
            Set(
                variables.compactMap { variable in
                    let key = normalizedKey(variable.key)
                    return key.isEmpty ? nil : key
                }
            )
        ).sorted()
    }

    nonisolated static func sensitiveKeys(from variables: [ProjectEnvironmentVariable]) -> [String] {
        configuredKeys(from: variables.filter { $0.scope == .hosted })
    }

    nonisolated static func plainKeys(from variables: [ProjectEnvironmentVariable]) -> [String] {
        configuredKeys(from: variables.filter { $0.scope == .client })
    }

    nonisolated static func secretPasteWarning(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if containsLikelyOpenAIKey(trimmed) || firstSensitiveAssignmentKey(in: trimmed) == "OPENAI_API_KEY" {
            return "Don't paste `OPENAI_API_KEY` into chat. Chat messages are persisted with the project conversation. Add it in Integrations under Hosted Keys instead; 10x syncs hosted values to Supabase secrets and keeps them out of project files and generated source."
        }

        guard let key = firstSensitiveAssignmentKey(in: trimmed) else { return nil }
        return "Don't paste `\(key)` into chat. Chat messages are persisted with the project conversation. Add server-side values in Integrations under Hosted Keys instead so 10x can sync them to Supabase secrets."
    }

    nonisolated static func sanitizedForDisk(_ variable: ProjectEnvironmentVariable) -> ProjectEnvironmentVariable {
        let key = normalizedKey(variable.key)
        return ProjectEnvironmentVariable(
            id: variable.id,
            key: key,
            description: normalizedDescription(variable.description),
            value: variable.scope == .hosted ? "" : variable.value,
            scope: variable.scope
        )
    }

    private nonisolated static func containsLikelyOpenAIKey(_ text: String) -> Bool {
        text.range(
            of: #"\bsk-(proj-|admin-)?[A-Za-z0-9_-]{32,}\b"#,
            options: .regularExpression
        ) != nil
    }

    private nonisolated static func firstSensitiveAssignmentKey(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?mi)["']?([A-Z][A-Z0-9_]{2,})["']?\s*(?:=|:)\s*["']?([^\s,"'`]+)"#
        ) else {
            return nil
        }

        let searchRange = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: searchRange) {
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let key = normalizedKey(String(text[keyRange])).uppercased()
            let value = String(text[valueRange])
            guard isSensitive(key: key), !looksLikePlaceholderSecretValue(value) else {
                continue
            }
            return key
        }

        return nil
    }

    private nonisolated static func looksLikePlaceholderSecretValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return true }

        let lowered = trimmed.lowercased()
        let placeholderFragments = [
            "...",
            "<secret",
            "<token",
            "<key",
            "your_",
            "your-",
            "example",
            "placeholder",
            "server-only",
            "paste-here",
            "xxx",
        ]

        return placeholderFragments.contains { lowered.contains($0) }
    }
}
