import Foundation

nonisolated struct BuilderProjectWarning: Codable, Identifiable, Sendable, Hashable {
    enum Severity: String, Codable, Sendable, Hashable {
        case warning
    }

    let id: String
    let severity: Severity
    let title: String
    let requestedCapability: String?
    let message: String
    let fallback: String?

    init(
        id: String = UUID().uuidString,
        severity: Severity = .warning,
        title: String,
        requestedCapability: String? = nil,
        message: String,
        fallback: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.requestedCapability = requestedCapability
        self.message = message
        self.fallback = fallback
    }

    init?(payload: [String: Any]) {
        guard let title = Self.normalizedString(payload["title"]),
              let message = Self.normalizedString(payload["message"]) else {
            return nil
        }

        let severity = Severity(rawValue: Self.normalizedString(payload["severity"]) ?? "") ?? .warning
        self.init(
            severity: severity,
            title: title,
            requestedCapability: Self.normalizedString(payload["requested_capability"] ?? payload["requestedCapability"]),
            message: message,
            fallback: Self.normalizedString(payload["fallback"])
        )
    }

    static func decodeList(from raw: Any?) -> [BuilderProjectWarning]? {
        if let payloads = raw as? [[String: Any]] {
            guard !payloads.isEmpty else { return [] }
            let warnings = payloads.compactMap(BuilderProjectWarning.init(payload:))
            return warnings.isEmpty ? nil : warnings
        }

        guard let rawArray = raw as? [Any] else { return nil }
        guard !rawArray.isEmpty else { return [] }

        let warnings: [BuilderProjectWarning] = rawArray.compactMap { item in
            guard let payload = normalizedPayload(from: item) else { return nil }
            return BuilderProjectWarning(payload: payload)
        }
        return warnings.isEmpty ? nil : warnings
    }

    private static func normalizedPayload(from raw: Any) -> [String: Any]? {
        if let payload = raw as? [String: Any] {
            return payload
        }
        guard let dictionary = raw as? NSDictionary else { return nil }

        var payload: [String: Any] = [:]
        for case let (key as String, value) in dictionary {
            payload[key] = value
        }
        return payload.isEmpty ? nil : payload
    }

    private static func normalizedString(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func normalized(
        _ warnings: [BuilderProjectWarning],
        supportsManagedSupabaseBackend: Bool
    ) -> [BuilderProjectWarning] {
        guard supportsManagedSupabaseBackend else { return warnings }
        return warnings.filter { !isResolvedByManagedSupabaseBackend($0) }
    }

    private nonisolated static func isResolvedByManagedSupabaseBackend(_ warning: BuilderProjectWarning) -> Bool {
        let legacyCapability = "Production backend or cloud services from scratch"
        let partialCapability = "Custom backend or cloud services outside supported integrations"
        let supportedCapability = "Managed Supabase backend functions"

        let searchableText = [
            warning.title,
            warning.requestedCapability,
            warning.message,
            warning.fallback,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if matchesCapability(warning, exact: supportedCapability) {
            return true
        }

        if searchableText.contains("non-supabase")
            || searchableText.contains("open proxy")
            || searchableText.contains("arbitrary cloud")
            || searchableText.contains("cloudflare")
            || searchableText.contains("vercel")
            || searchableText.contains("netlify")
            || searchableText.contains("aws lambda")
            || searchableText.contains("firebase")
            || searchableText.contains("self-hosted")
            || searchableText.contains("on-prem") {
            return false
        }

        let mentionsManagedSupabaseBackend =
            searchableText.contains("managed supabase backend")
            || searchableText.contains("managed backend workspace")
            || searchableText.contains("supabase edge function")
            || searchableText.contains("supabase edge functions")
            || (searchableText.contains("backend workspace") && searchableText.contains("supabase"))

        if matchesCapability(warning, exact: partialCapability) {
            return mentionsManagedSupabaseBackend
        }

        if matchesCapability(warning, exact: legacyCapability) {
            return true
        }

        return searchableText.contains("production backend")
            && searchableText.contains("cloud")
            && searchableText.contains("scratch")
            || mentionsManagedSupabaseBackend
    }

    private nonisolated static func matchesCapability(
        _ warning: BuilderProjectWarning,
        exact capability: String
    ) -> Bool {
        warning.requestedCapability?.caseInsensitiveCompare(capability) == .orderedSame
            || warning.title.caseInsensitiveCompare(capability) == .orderedSame
    }
}
