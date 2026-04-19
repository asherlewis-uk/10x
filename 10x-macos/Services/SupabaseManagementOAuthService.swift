import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

enum SupabaseManagementOAuthError: LocalizedError {
    case invalidAuthorizeURL
    case callbackMissing
    case codeMissing
    case stateMismatch
    case missingAppSession
    case oauthFailed(String)
    case expiredSession

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
            return "Sign in to 10x before connecting Supabase."
        case .oauthFailed(let message):
            return message
        case .expiredSession:
            return "Your Supabase connection expired. Connect again."
        }
    }
}

@MainActor
final class SupabaseManagementOAuthService {
    static let shared = SupabaseManagementOAuthService()
    static let edgeFunctionWriteScopes = ["edge_functions_write"]
    static let edgeFunctionSecretWriteScopes = ["edge_functions_secrets_write"]
    static let managedBackendWriteScopes = edgeFunctionWriteScopes + edgeFunctionSecretWriteScopes

    private let callbackScheme = "app.10x.macos"
    private let apiClient = APIClient()
    private let tokenStore = SupabaseManagementTokenStore()
    private var webAuthSession: ASWebAuthenticationSession?
    private let presentationProvider = SupabaseOAuthPresentationProvider()

    func hasUsableSession(requiredScopes: [String] = []) -> Bool {
        guard let session = tokenStore.session(allowUserInteraction: false) else {
            return false
        }
        let usable = !session.needsRefresh || session.refreshToken?.isEmpty == false
        if !usable {
            tokenStore.clear()
        }
        return usable && session.hasScopes(requiredScopes)
    }

    func disconnect() {
        tokenStore.clear()
    }

    func connect(appAccessToken: String) async throws {
        guard !appAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SupabaseManagementOAuthError.missingAppSession
        }

        let pendingSession = PendingSupabaseOAuthSession.make()
        let startResponse: SupabaseOAuthStartResponse = try await apiClient.post(
            APIClient.builder("supabase/oauth/start"),
            json: [
                "state": pendingSession.state,
                "code_challenge": pendingSession.codeChallenge,
            ],
            accessToken: appAccessToken
        )

        guard let authorizeURL = URL(string: startResponse.authorizeURL) else {
            throw SupabaseManagementOAuthError.invalidAuthorizeURL
        }

        let callbackURL = try await runWebAuthenticationSession(url: authorizeURL)
        let callback = try oauthCallback(from: callbackURL)
        guard callback.state == pendingSession.state else {
            throw SupabaseManagementOAuthError.stateMismatch
        }

        let tokenResponse: SupabaseOAuthTokenResponse = try await apiClient.post(
            APIClient.builder("supabase/oauth/redeem"),
            json: [
                "code": callback.code,
                "code_verifier": pendingSession.codeVerifier,
            ],
            accessToken: appAccessToken
        )

        persist(tokenResponse)
    }

    func validAccessToken(appAccessToken: String, requiredScopes: [String] = []) async throws -> String {
        guard let session = tokenStore.session() else {
            throw SupabaseManagementOAuthError.expiredSession
        }
        let hasRequiredScopes = !session.hasKnownScopeAuthorization || session.hasScopes(requiredScopes)
        let shouldRefreshForScopes =
            session.hasKnownScopeAuthorization && !hasRequiredScopes && session.refreshToken?.isEmpty == false
        if !session.needsRefresh && !shouldRefreshForScopes {
            guard hasRequiredScopes else {
                throw SupabaseManagementOAuthError.oauthFailed(missingScopeMessage(for: requiredScopes))
            }
            return session.accessToken
        }

        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            guard hasRequiredScopes else {
                throw SupabaseManagementOAuthError.oauthFailed(missingScopeMessage(for: requiredScopes))
            }
            tokenStore.clear()
            throw SupabaseManagementOAuthError.expiredSession
        }

        let tokenResponse: SupabaseOAuthTokenResponse
        do {
            tokenResponse = try await apiClient.post(
                APIClient.builder("supabase/oauth/refresh"),
                json: ["refresh_token": refreshToken],
                accessToken: appAccessToken
            )
        } catch APIError.unauthorized {
            tokenStore.clear()
            throw SupabaseManagementOAuthError.expiredSession
        }

        persist(tokenResponse, fallbackRefreshToken: refreshToken, fallbackScope: session.scope)
        guard let refreshedSession = tokenStore.session() else {
            tokenStore.clear()
            throw SupabaseManagementOAuthError.expiredSession
        }
        guard !refreshedSession.hasKnownScopeAuthorization || refreshedSession.hasScopes(requiredScopes) else {
            throw SupabaseManagementOAuthError.oauthFailed(missingScopeMessage(for: requiredScopes))
        }
        return refreshedSession.accessToken
    }

    private func persist(
        _ response: SupabaseOAuthTokenResponse,
        fallbackRefreshToken: String? = nil,
        fallbackScope: String? = nil
    ) {
        tokenStore.saveOAuthSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? fallbackRefreshToken,
            expiresIn: response.expiresIn,
            tokenType: response.tokenType,
            scope: response.scope ?? fallbackScope
        )
    }

    private func missingScopeMessage(for requiredScopes: [String]) -> String {
        let normalizedScopes = Set(
            requiredScopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        if normalizedScopes.contains("edge_functions_secrets_write") {
            return "Supabase needs backend secret access before 10x can sync hosted keys. Reconnect Supabase in Integrations and try again."
        }
        if normalizedScopes.contains("edge_functions_write") {
            return "Supabase needs Edge Function deploy access before 10x can deploy backend changes. Reconnect Supabase in Integrations and try again."
        }
        return "Supabase needs additional permissions before 10x can continue. Reconnect Supabase in Integrations and try again."
    }

    private func runWebAuthenticationSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let completionHandler: @Sendable (URL?, (any Error)?) -> Void = { [weak self] callbackURL, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.webAuthSession = nil

                    if let error {
                        if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            continuation.resume(throwing: error)
                            return
                        }
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let callbackURL else {
                        continuation.resume(throwing: SupabaseManagementOAuthError.callbackMissing)
                        return
                    }

                    continuation.resume(returning: callbackURL)
                }
            }

            let session: ASWebAuthenticationSession
            if #available(macOS 14.4, *) {
                session = ASWebAuthenticationSession(
                    url: url,
                    callback: .customScheme(callbackScheme),
                    completionHandler: completionHandler
                )
            } else {
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme,
                    completionHandler: completionHandler
                )
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = presentationProvider
            webAuthSession = session
            if !session.start() {
                self.webAuthSession = nil
                continuation.resume(
                    throwing: SupabaseManagementOAuthError.oauthFailed("Could not start the Supabase sign-in flow.")
                )
            }
        }
    }

    private func oauthCallback(from callbackURL: URL) throws -> SupabaseOAuthCallback {
        let components: URLComponents?

        if let fragment = callbackURL.fragment {
            components = URLComponents(string: "?\(fragment)")
        } else {
            components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        }

        let items = components?.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        if let error = params["error"], !error.isEmpty {
            throw SupabaseManagementOAuthError.oauthFailed(error.removingPercentEncoding ?? error)
        }

        guard let code = params["code"], !code.isEmpty else {
            throw SupabaseManagementOAuthError.codeMissing
        }
        guard let state = params["state"], !state.isEmpty else {
            throw SupabaseManagementOAuthError.stateMismatch
        }

        return SupabaseOAuthCallback(code: code, state: state)
    }
}

private struct SupabaseOAuthStartResponse: Decodable {
    let authorizeURL: String

    private enum CodingKeys: String, CodingKey {
        case authorizeURL = "authorize_url"
    }
}

private struct SupabaseOAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let scope: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

private struct PendingSupabaseOAuthSession {
    let state: String
    let codeVerifier: String

    var codeChallenge: String {
        Self.codeChallenge(for: codeVerifier)
    }

    static func make() -> PendingSupabaseOAuthSession {
        PendingSupabaseOAuthSession(
            state: randomURLSafeString(length: 32),
            codeVerifier: randomURLSafeString(length: 64)
        )
    }

    private static func codeChallenge(for codeVerifier: String) -> String {
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func randomURLSafeString(length: Int) -> String {
        let byteCount = max(length, 32)
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if result != errSecSuccess {
            var fallback = ""
            while fallback.count < length {
                fallback += UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            return fallback
        }
        return Data(bytes).base64URLEncodedString()
    }
}

private struct SupabaseOAuthCallback {
    let code: String
    let state: String
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class SupabaseOAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
