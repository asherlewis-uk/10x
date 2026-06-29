import Foundation

enum SupabaseManagementServiceError: LocalizedError {
    case missingAccessToken
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case malformedResponse(String)
    case missingPublishableKey
    case invalidInput(String)
    case unavailableInLocalCockpit

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "Connect Supabase to load your account."
        case .invalidResponse:
            return "Supabase returned an unexpected response."
        case .requestFailed(let statusCode, let message):
            return "Supabase request failed (\(statusCode)): \(message)"
        case .malformedResponse(let context):
            return "Supabase returned incomplete \(context)."
        case .missingPublishableKey:
            return "No publishable or anon key was returned for this project."
        case .invalidInput(let detail):
            return detail
        case .unavailableInLocalCockpit:
            return "Supabase management is not available in the 11x local cockpit."
        }
    }
}

struct SupabaseReadTableInput: Decodable, Sendable {
    let schema: String?
    let table: String?
    let columns: [String]?
    let filters: [String: AnyCodableValue]?
    let limit: Int?
}

struct SupabaseExecuteSQLInput: Decodable, Sendable {
    let sql: String
}

enum SupabaseWriteOperation: String, Decodable, Sendable {
    case insert
    case update
    case delete
}

struct SupabaseWriteTableInput: Decodable, Sendable {
    let schema: String?
    let table: String
    let operation: SupabaseWriteOperation
    let values: [String: AnyCodableValue]?
    let rows: [[String: AnyCodableValue]]?
    let filters: [String: AnyCodableValue]?
}

enum SupabaseManageSettingsAction: String, Decodable, Sendable {
    case describeAuth = "describe_auth"
    case updateAuth = "update_auth"
}

struct SupabaseManageSettingsInput: Decodable, Sendable {
    let action: SupabaseManageSettingsAction?
    let emailEnabled: Bool?
    let emailConfirmationsEnabled: Bool?
    let phoneEnabled: Bool?
    let phoneConfirmationsEnabled: Bool?
    let anonymousUsersEnabled: Bool?
    let signupsEnabled: Bool?
    let secureEmailChangeEnabled: Bool?
    let allowUnverifiedEmailSignIns: Bool?
    let passwordMinLength: Int?
    let leakedPasswordProtectionEnabled: Bool?
    let refreshTokenRotationEnabled: Bool?
    let singleSessionPerUser: Bool?
    let requireReauthenticationForPasswordChanges: Bool?
    let rateLimitEmailSent: Int?
    let rateLimitSMSSent: Int?
    let appleEnabled: Bool?
    let googleEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case action
        case emailEnabled = "email_enabled"
        case emailConfirmationsEnabled = "email_confirmations_enabled"
        case phoneEnabled = "phone_enabled"
        case phoneConfirmationsEnabled = "phone_confirmations_enabled"
        case anonymousUsersEnabled = "anonymous_users_enabled"
        case signupsEnabled = "signups_enabled"
        case secureEmailChangeEnabled = "secure_email_change_enabled"
        case allowUnverifiedEmailSignIns = "allow_unverified_email_sign_ins"
        case passwordMinLength = "password_min_length"
        case leakedPasswordProtectionEnabled = "leaked_password_protection_enabled"
        case refreshTokenRotationEnabled = "refresh_token_rotation_enabled"
        case singleSessionPerUser = "single_session_per_user"
        case requireReauthenticationForPasswordChanges = "require_reauthentication_for_password_changes"
        case rateLimitEmailSent = "rate_limit_email_sent"
        case rateLimitSMSSent = "rate_limit_sms_sent"
        case appleEnabled = "apple_enabled"
        case googleEnabled = "google_enabled"
    }
}

struct SupabaseManagementProject: Identifiable, Equatable, Sendable {
    let id: String
    let ref: String
    let name: String
    let status: String?
    let region: String?
    let databaseHost: String?

    var apiURL: String { "https://\(ref).supabase.co" }
    var dashboardURL: URL? { URL(string: "https://supabase.com/dashboard/project/\(ref)") }
    var authProvidersDashboardURL: URL? { URL(string: "https://supabase.com/dashboard/project/\(ref)/auth/providers") }
    var authURLConfigurationDashboardURL: URL? { URL(string: "https://supabase.com/dashboard/project/\(ref)/auth/url-configuration") }
    var authTemplatesDashboardURL: URL? { URL(string: "https://supabase.com/dashboard/project/\(ref)/auth/templates") }
}

/// Stubbed Supabase management service for 11x local cockpit compatibility.
/// All remote Supabase management operations are disabled.
actor SupabaseManagementService {
    static let shared = SupabaseManagementService()

    static func projectRef(from url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        if let schemeRange = trimmed.range(of: "://") {
            host = String(trimmed[schemeRange.upperBound...])
        } else {
            host = trimmed
        }
        let components = host.split(separator: ".")
        // abc123.supabase.co or db.abc123.supabase.co
        guard components.count >= 3,
              components[components.count - 2].lowercased() == "supabase",
              components[components.count - 1].lowercased() == "co"
        else { return nil }
        let refIndex = components.count - 3
        let ref = String(components[refIndex])
        return ref.isEmpty ? nil : ref
    }

    func readForAgent(projectRef: String, input: SupabaseReadTableInput) async throws -> String {
        throw SupabaseManagementServiceError.unavailableInLocalCockpit
    }

    func writeForAgent(projectRef: String, input: SupabaseWriteTableInput) async throws -> String {
        throw SupabaseManagementServiceError.unavailableInLocalCockpit
    }

    func executeSQLForAgent(projectRef: String, input: SupabaseExecuteSQLInput) async throws -> String {
        throw SupabaseManagementServiceError.unavailableInLocalCockpit
    }

    func manageSettingsForAgent(projectRef: String, input: SupabaseManageSettingsInput) async throws -> String {
        throw SupabaseManagementServiceError.unavailableInLocalCockpit
    }


    func createProject(name: String, organization: SupabaseManagementOrganization) async throws -> SupabaseManagementProject {
        throw SupabaseManagementServiceError.unavailableInLocalCockpit
    }
    func waitForProvisionedProject(ref: String) async throws -> SupabaseProjectConnectionDetails {
        throw SupabaseManagementServiceError.unavailableInLocalCockpit
    }
    func fetchOrganizations() async throws -> [SupabaseManagementOrganization] { [] }
    func fetchProjects() async throws -> [SupabaseManagementProject] { [] }
    func fetchConnectionDetails(for project: SupabaseManagementProject) async throws -> SupabaseProjectConnectionDetails {
        throw SupabaseManagementServiceError.unavailableInLocalCockpit
    }
    func fetchLiveSchemaPreview(for ref: String) async throws -> SupabaseSchemaPreview {
        throw SupabaseManagementServiceError.unavailableInLocalCockpit
    }
    // MARK: - Parser helpers kept for test compatibility

    static func parseProjects(from data: Data) throws -> [SupabaseManagementProject] {
        struct RawDatabase: Decodable { let host: String? }
        struct RawProject: Decodable {
            let id: String
            let name: String
            let status: String?
            let region: String?
            let database: RawDatabase?
        }
        let raw = try JSONDecoder().decode([RawProject].self, from: data)
        return raw.map {
            let ref: String
            if let host = $0.database?.host, let parsed = projectRef(from: host) {
                ref = parsed
            } else if let parsed = projectRef(from: $0.id) {
                ref = parsed
            } else {
                ref = $0.id
            }
            return SupabaseManagementProject(
                id: $0.id,
                ref: ref,
                name: $0.name,
                status: $0.status,
                region: $0.region,
                databaseHost: $0.database?.host
            )
        }
    }

    static func parseOrganizations(from data: Data) throws -> [(id: String, name: String, slug: String)] {
        struct RawOrganization: Decodable {
            let id: String
            let name: String?
            let slug: String?
        }
        do {
            let wrapper = try JSONDecoder().decode([String: [RawOrganization]].self, from: data)
            if let items = wrapper["items"] ?? wrapper["organizations"] {
                return items.map { (id: $0.id, name: $0.name ?? ($0.slug ?? ""), slug: $0.slug ?? "") }
            }
        } catch { }
        let items = try JSONDecoder().decode([RawOrganization].self, from: data)
        return items.map { (id: $0.id, name: $0.name ?? ($0.slug ?? ""), slug: $0.slug ?? "") }
    }
    static func parsePublishableKey(from data: Data) throws -> String {
        struct KeyEntry: Decodable {
            let name: String?
            let type: String?
            let apiKey: String?
            enum CodingKeys: String, CodingKey {
                case name, type
                case apiKey = "api_key"
            }
        }
        let entries = try JSONDecoder().decode([KeyEntry].self, from: data)
        guard let key = entries.first(where: {
            ($0.name?.lowercased() == "publishable" || $0.type?.lowercased() == "publishable") &&
            !($0.apiKey?.isEmpty ?? true)
        })?.apiKey else {
            throw SupabaseManagementServiceError.missingPublishableKey
        }
        return key
    }
    static func parseAuthProviders(from data: Data) throws -> String { "" }
    static func renderAuthProviders(_ snapshot: String) -> String { "" }
}

struct SupabaseManagementOrganization: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let slug: String?
}

struct SupabaseAuthProviderSnapshot: Equatable, Sendable {
    let emailEnabled: Bool?
    let emailConfirmationsEnabled: Bool?
    let phoneEnabled: Bool?
    let phoneConfirmationsEnabled: Bool?
    let anonymousUsersEnabled: Bool?
    let signupsEnabled: Bool?
    let secureEmailChangeEnabled: Bool?
    let allowUnverifiedEmailSignIns: Bool?
    let passwordMinLength: Int?
    let leakedPasswordProtectionEnabled: Bool?
    let refreshTokenRotationEnabled: Bool?
    let singleSessionPerUser: Bool?
    let requireReauthenticationForPasswordChanges: Bool?
    let rateLimitEmailSent: Int?
    let rateLimitSMSSent: Int?
    let appleEnabled: Bool
    let googleEnabled: Bool
}

struct SupabaseProjectConnectionDetails: Equatable, Sendable {
    let project: SupabaseManagementProject
    let publishableKey: String
    let authProviders: SupabaseAuthProviderSnapshot?

    var url: String {
        project.apiURL
    }
}
