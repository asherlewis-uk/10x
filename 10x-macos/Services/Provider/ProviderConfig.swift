import Foundation

/// Identifies a supported provider adapter type.
enum ProviderType: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai-compatible"
}

/// Metadata for a user-owned OpenAI-compatible provider configuration.
/// Secrets (API keys) are intentionally excluded from this struct and from
/// any Codable serialization; they live in the OS keychain only.
struct ProviderConfig: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var providerType: ProviderType
    var displayName: String
    var baseURL: String
    var model: String
    var createdAt: String
    var updatedAt: String

    /// JSON payload that is safe to expose to UI, local exports, or diagnostics.
    /// Does not contain the API key.
    func publicMetadata() -> [String: Any] {
        [
            "id": id,
            "provider_type": providerType.rawValue,
            "display_name": displayName,
            "base_url": baseURL,
            "model": model,
            "created_at": createdAt,
            "updated_at": updatedAt,
        ]
    }

    static func defaultConfig() -> ProviderConfig {
        ProviderConfig(
            id: "default",
            providerType: .openAICompatible,
            displayName: "OpenAI-compatible provider",
            baseURL: Config.openAIBaseURL,
            model: Config.openAIModel,
            createdAt: isoTimestamp(),
            updatedAt: isoTimestamp()
        )
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

/// Errors surfaced when a provider is not ready to make a request.
enum ProviderConfigError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case missingModel
    case missingProviderConfig

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing. Add it in Settings under Provider."
        case .invalidBaseURL:
            return "Provider base URL is invalid. Check Settings under Provider."
        case .missingModel:
            return "Model is not configured. Set OPENAI_MODEL in Settings under Provider."
        case .missingProviderConfig:
            return "Provider is not configured. Add your OpenAI-compatible provider details in Settings."
        }
    }
}
