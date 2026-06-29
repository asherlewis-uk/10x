import Foundation

enum SupabaseManagementOAuthError: LocalizedError {
    case invalidAuthorizeURL
    case callbackMissing
    case codeMissing
    case stateMismatch
    case missingAppSession
    case oauthFailed(String)
    case expiredSession
    case unavailableInLocalCockpit

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:
            return "Supabase OAuth returned an invalid authorize URL."
        case .callbackMissing:
            return "Supabase OAuth did not return a callback URL."
        case .codeMissing:
            return "Supabase OAuth did not return an authorization code."
        case .stateMismatch:
            return "Supabase OAuth state did not match. Connect again."
        case .missingAppSession:
            return "Sign in to 11x before connecting Supabase."
        case .oauthFailed(let message):
            return message
        case .expiredSession:
            return "Your Supabase connection expired. Connect again."
        case .unavailableInLocalCockpit:
            return "Supabase management OAuth is not available in the 11x local cockpit."
        }
    }
}

/// Stubbed Supabase management OAuth service for 11x local cockpit compatibility.
/// All remote Supabase management flows are disabled.
@MainActor
final class SupabaseManagementOAuthService {
    static let shared = SupabaseManagementOAuthService()
    static let edgeFunctionWriteScopes: [String] = []
    static let edgeFunctionSecretWriteScopes: [String] = []
    static let managedBackendWriteScopes: [String] = []

    func hasUsableSession(requiredScopes: [String] = []) -> Bool { false }
    func disconnect() { }
    func connect(appAccessToken: String) async throws {
        throw SupabaseManagementOAuthError.unavailableInLocalCockpit
    }
    func validAccessToken(appAccessToken: String, requiredScopes: [String] = []) async throws -> String {
        throw SupabaseManagementOAuthError.unavailableInLocalCockpit
    }
}
