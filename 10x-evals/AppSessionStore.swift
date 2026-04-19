import Foundation

struct AppSession: Equatable {
    let accessToken: String
    let refreshToken: String
    let userId: String?
    let userEmail: String?
}

struct AppSessionStore {
    let suiteName: String

    init(suiteName: String = "app.10x.macos") {
        self.suiteName = suiteName
    }

    func load() throws -> AppSession {
        let defaults = UserDefaults(suiteName: suiteName)
        let persistentDomain = defaults?.persistentDomain(forName: suiteName)
            ?? UserDefaults.standard.persistentDomain(forName: suiteName)

        guard defaults != nil || persistentDomain != nil else {
            throw AppSessionStoreError.missingSuite(suiteName)
        }

        if let storedSession = sessionFromSupabaseStorage(
            defaults: defaults,
            persistentDomain: persistentDomain
        ) {
            return storedSession
        }

        guard let accessToken = stringValue(
            forKey: "tenx_access_token",
            defaults: defaults,
            persistentDomain: persistentDomain,
        ) else {
            throw AppSessionStoreError.missingAccessToken(suiteName)
        }

        guard let refreshToken = stringValue(
            forKey: "tenx_refresh_token",
            defaults: defaults,
            persistentDomain: persistentDomain,
        ) else {
            throw AppSessionStoreError.missingRefreshToken(suiteName)
        }

        return AppSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: stringValue(
                forKey: "tenx_user_id",
                defaults: defaults,
                persistentDomain: persistentDomain
            ),
            userEmail: stringValue(
                forKey: "tenx_user_email",
                defaults: defaults,
                persistentDomain: persistentDomain
            )
        )
    }

    private func stringValue(
        forKey key: String,
        defaults: UserDefaults?,
        persistentDomain: [String: Any]?
    ) -> String? {
        if let value = defaults?.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        if let value = persistentDomain?[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func sessionFromSupabaseStorage(
        defaults: UserDefaults?,
        persistentDomain: [String: Any]?
    ) -> AppSession? {
        let domainKeys = Array(persistentDomain?.keys ?? Dictionary<String, Any>().keys).filter {
            $0.hasPrefix("tenx.supabase.auth.") && $0.hasSuffix("-auth-token")
        }

        for key in domainKeys.sorted() {
            let data = defaults?.data(forKey: key) ?? persistentDomain?[key] as? Data
            guard let data else { continue }
            guard let payload = try? JSONDecoder().decode(StoredSupabaseSession.self, from: data) else {
                continue
            }

            let accessToken = payload.accessToken.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let refreshToken = payload.refreshToken.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !accessToken.isEmpty, !refreshToken.isEmpty else { continue }

            return AppSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                userId: payload.user?.id,
                userEmail: payload.user?.email
            )
        }

        return nil
    }
}

private struct StoredSupabaseSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: StoredSupabaseUser?
}

private struct StoredSupabaseUser: Decodable {
    let id: String?
    let email: String?
}

enum AppSessionStoreError: LocalizedError, Equatable {
    case missingSuite(String)
    case missingAccessToken(String)
    case missingRefreshToken(String)

    var errorDescription: String? {
        switch self {
        case .missingSuite(let suiteName):
            return "Failed to open the app defaults domain `\(suiteName)`."
        case .missingAccessToken:
            return "No saved app session found. Sign in through the macOS app first."
        case .missingRefreshToken:
            return "The saved app session is incomplete. Sign in through the macOS app again."
        }
    }
}
