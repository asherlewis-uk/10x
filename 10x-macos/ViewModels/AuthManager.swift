import Foundation
import AuthenticationServices
import AppKit
import CryptoKit
import Security

/// Manages a single local user profile for the 11x local cockpit.
/// No remote auth, OAuth, Apple sign-in, or token refresh is required.
@Observable
@MainActor
final class AuthManager {
    private enum LocalAuthError: Error {
        case profileMissing
    }

    enum SignInProvider: String, Sendable {
        case local

        var progressMessage: String {
            "Loading local cockpit..."
        }
    }

    var isAuthenticated = false
    var isCheckingAuth = false
    var activeSignInProvider: SignInProvider?
    var accessToken: String?
    var refreshToken: String?
    var userId: String?
    var userEmail: String?
    var authError: String?

    private let profileRepository = ProfileRepository()
    private var profile: LocalProfile?

    var isAuthenticating: Bool {
        activeSignInProvider != nil
    }

    var signInStatusMessage: String? {
        activeSignInProvider?.progressMessage
    }

    init() {
        Task {
            await loadLocalProfile()
        }
    }

    /// Ensure a local profile exists and the manager reports authenticated.
    func loadLocalProfile() async {
        guard !isAuthenticated else { return }
        isCheckingAuth = true
        defer { isCheckingAuth = false }

        do {
            let profile = try await profileRepository.loadOrCreateProfile()
            self.profile = profile
            self.userId = profile.id
            self.userEmail = profile.email
            self.accessToken = Self.localAccessToken(for: profile.id)
            self.refreshToken = self.accessToken
            self.isAuthenticated = true
            self.authError = nil
        } catch {
            print("[Auth] Failed to load local profile: \(error)")
            self.authError = error.localizedDescription
            self.isAuthenticated = false
        }
    }

    func signInWithGoogle() {
        // No-op: 11x is local single-user only.
    }

    func signInWithApple() {
        // No-op: 11x is local single-user only.
    }

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        // No-op: native Apple sign-in is not used in 11x.
        _ = request
    }

    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, any Error>) {
        // No-op: native Apple sign-in is not used in 11x.
        _ = result
    }

    func refreshSession() async -> Bool {
        // Local session never expires.
        isAuthenticated
    }

    func validAccessToken() async -> String? {
        if !isAuthenticated {
            await loadLocalProfile()
        }
        return accessToken
    }

    func handleUnauthorized() async {
        // Local cockpit has no remote auth to refresh.
        await loadLocalProfile()
    }

    func signOut() {
        // 11x does not sign out the local profile; reset ephemeral auth state only.
        clearSessionState()
    }

    private func clearSessionState() {
        // Keep the local profile itself; just reset in-memory session markers.
        accessToken = nil
        refreshToken = nil
        userId = nil
        userEmail = nil
        isAuthenticated = false
        authError = nil
        activeSignInProvider = nil
    }

    /// Returns a stable synthetic access token containing the local user id.
    /// This keeps call sites that pass an accessToken working without remote auth.
    private nonisolated static func localAccessToken(for userId: String) -> String {
        let header = "{\"alg\":\"none\",\"typ\":\"JWT\"}".data(using: .utf8)!.base64EncodedString()
        let payload = "{\"sub\":\"\(userId)\"}".data(using: .utf8)!.base64EncodedString()
        return "\(header).\(payload)."
    }
}
