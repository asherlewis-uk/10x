import Foundation

enum SupabaseManagementServiceError: LocalizedError {
    case missingAccessToken
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case malformedResponse(String)
    case missingPublishableKey
    case invalidInput(String)

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

    var apiURL: String {
        "https://\(ref).supabase.co"
    }

    var dashboardURL: URL? {
        URL(string: "https://supabase.com/dashboard/project/\(ref)")
    }

    var authProvidersDashboardURL: URL? {
        URL(string: "https://supabase.com/dashboard/project/\(ref)/auth/providers")
    }

    var authURLConfigurationDashboardURL: URL? {
        URL(string: "https://supabase.com/dashboard/project/\(ref)/auth/url-configuration")
    }

    var authTemplatesDashboardURL: URL? {
        URL(string: "https://supabase.com/dashboard/project/\(ref)/auth/templates")
    }
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

struct SupabaseManagementTokenStore: Sendable {
    static let accessTokenKey = "supabase_management_access_token"
    static let refreshTokenKey = "supabase_management_refresh_token"
    static let expiresAtKey = "supabase_management_access_token_expires_at"
    static let tokenTypeKey = "supabase_management_token_type"
    static let scopeKey = "supabase_management_scope"

    let store: AuthTokenStore

    init(service: String = "\(AuthKeychainStore.defaultService).integrations.supabase-management") {
        self.store = AuthTokenStore(service: service)
    }

    struct Session: Equatable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let tokenType: String?
        let scope: String?

        var needsRefresh: Bool {
            guard let expiresAt else { return false }
            return expiresAt <= Date().addingTimeInterval(60)
        }

        var isPersonalAccessToken: Bool {
            refreshToken == nil && expiresAt == nil && (scope?.isEmpty ?? true)
        }

        var hasKnownScopeAuthorization: Bool {
            isPersonalAccessToken || !(scope?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        func hasScopes(_ requiredScopes: [String]) -> Bool {
            let normalizedScopes = Self.normalized(requiredScopes)
            guard !normalizedScopes.isEmpty else { return true }
            if isPersonalAccessToken {
                return true
            }

            let grantedScopes = Self.normalized(scope)
            guard !grantedScopes.isEmpty else { return false }
            if grantedScopes.contains("all") {
                return true
            }
            return normalizedScopes.isSubset(of: grantedScopes)
        }

        private static func normalized(_ scopes: [String]) -> Set<String> {
            Set(
                scopes
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        }

        private static func normalized(_ scopeString: String?) -> Set<String> {
            Set(
                (scopeString ?? "")
                    .split { $0.isWhitespace || $0 == "," }
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        }
    }

    func token(allowUserInteraction: Bool = true) -> String? {
        session(allowUserInteraction: allowUserInteraction)?.accessToken
    }

    func session(allowUserInteraction: Bool = true) -> Session? {
        let value = store.string(
            for: Self.accessTokenKey,
            allowUserInteraction: allowUserInteraction
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }

        let refreshToken = store.string(
            for: Self.refreshTokenKey,
            allowUserInteraction: allowUserInteraction
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAtString = store.string(
            for: Self.expiresAtKey,
            allowUserInteraction: allowUserInteraction
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAt = expiresAtString.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        let tokenType = store.string(
            for: Self.tokenTypeKey,
            allowUserInteraction: allowUserInteraction
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = store.string(
            for: Self.scopeKey,
            allowUserInteraction: allowUserInteraction
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Session(
            accessToken: value,
            refreshToken: refreshToken?.isEmpty == false ? refreshToken : nil,
            expiresAt: expiresAt,
            tokenType: tokenType?.isEmpty == false ? tokenType : nil,
            scope: scope?.isEmpty == false ? scope : nil
        )
    }

    func setToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        savePersonalAccessToken(trimmed)
    }

    func savePersonalAccessToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        store.set(trimmed.isEmpty ? nil : trimmed, for: Self.accessTokenKey)
        store.remove(Self.refreshTokenKey)
        store.remove(Self.expiresAtKey)
        store.remove(Self.tokenTypeKey)
        store.remove(Self.scopeKey)
    }

    func saveOAuthSession(
        accessToken: String,
        refreshToken: String?,
        expiresIn: Int?,
        tokenType: String?,
        scope: String?
    ) {
        let trimmedAccessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccessToken.isEmpty else {
            clear()
            return
        }

        store.set(trimmedAccessToken, for: Self.accessTokenKey)
        store.set(refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.refreshTokenKey)
        if let expiresIn {
            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970
            store.set(String(expiresAt), for: Self.expiresAtKey)
        } else {
            store.remove(Self.expiresAtKey)
        }
        store.set(tokenType?.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.tokenTypeKey)
        store.set(scope?.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.scopeKey)
    }

    func clear() {
        store.remove(Self.accessTokenKey)
        store.remove(Self.refreshTokenKey)
        store.remove(Self.expiresAtKey)
        store.remove(Self.tokenTypeKey)
        store.remove(Self.scopeKey)
    }

    func hasStoredSession(allowUserInteraction: Bool = true) -> Bool {
        store.hasValue(for: Self.accessTokenKey, allowUserInteraction: allowUserInteraction)
    }
}

actor SupabaseManagementService {
    static let shared = SupabaseManagementService()

    private static let defaultProjectRegion = "us-east-1"
    private let baseURL = URL(string: "https://api.supabase.com")!
    private let session: URLSession
    private let tokenStore: SupabaseManagementTokenStore

    init(
        session: URLSession = {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            return URLSession(configuration: configuration)
        }(),
        tokenStore: SupabaseManagementTokenStore = .init()
    ) {
        self.session = session
        self.tokenStore = tokenStore
    }

    func fetchProjects() async throws -> [SupabaseManagementProject] {
        let token = try requireToken()
        let data = try await performRequest(path: "/v1/projects", method: "GET", token: token)
        return try Self.parseProjects(from: data)
    }

    func fetchOrganizations() async throws -> [SupabaseManagementOrganization] {
        let token = try requireToken()
        let data = try await performRequest(path: "/v1/organizations", method: "GET", token: token)
        return try Self.parseOrganizations(from: data)
    }

    func fetchConnectionDetails(for project: SupabaseManagementProject) async throws -> SupabaseProjectConnectionDetails {
        let token = try requireToken()

        async let keysData = performRequest(
            path: "/v1/projects/\(project.ref)/api-keys",
            method: "GET",
            token: token
        )
        async let authConfigData = performOptionalRequest(
            path: "/v1/projects/\(project.ref)/config/auth",
            method: "GET",
            token: token
        )

        let publishableKey = try Self.parsePublishableKey(from: try await keysData)
        let authProviders = try await authConfigData.flatMap(Self.parseAuthProviders(from:))

        return SupabaseProjectConnectionDetails(
            project: project,
            publishableKey: publishableKey,
            authProviders: authProviders
        )
    }

    func fetchLiveSchemaPreview(for projectRef: String) async throws -> SupabaseSchemaPreview {
        let token = try requireToken()
        let query = """
        select
          table_schema,
          table_name,
          column_name,
          data_type,
          ordinal_position
        from information_schema.columns
        where table_schema not in (
          'auth',
          'extensions',
          'graphql',
          'graphql_public',
          'information_schema',
          'net',
          'pg_catalog',
          'pgmq',
          'realtime',
          'storage',
          'supabase_functions',
          'supabase_migrations',
          'vault'
        )
        order by table_schema, table_name, ordinal_position;
        """

        let data = try await performRequest(
            path: "/v1/projects/\(projectRef)/database/query/read-only",
            method: "POST",
            token: token,
            body: [
                "query": query,
                "parameters": [],
            ],
            expectedStatusCodes: [200, 201]
        )

        return try Self.parseSchemaPreview(from: data)
    }

    func createProject(
        name: String,
        organization: SupabaseManagementOrganization
    ) async throws -> SupabaseManagementProject {
        let trimmedName = Self.trimmed(name) ?? ""
        guard !trimmedName.isEmpty else {
            throw SupabaseManagementServiceError.invalidInput("Project name is required.")
        }

        let data = try await performRequest(
            path: "/v1/projects",
            method: "POST",
            token: try requireToken(),
            body: [
                "organization_id": organization.id,
                "name": trimmedName,
                "region": try await defaultRegion(for: organization),
                "db_pass": Self.generatedDatabasePassword(),
            ],
            expectedStatusCodes: [200, 201, 202]
        )

        let root = try Self.jsonObject(from: data)
        if let dictionary = root as? [String: Any],
           let project = Self.project(from: dictionary) {
            return project
        }
        if let project = Self.arrayOfDictionaries(from: root).compactMap(Self.project(from:)).first {
            return project
        }

        throw SupabaseManagementServiceError.malformedResponse("project creation response")
    }

    func waitForProvisionedProject(ref: String) async throws -> SupabaseProjectConnectionDetails {
        let deadline = Date().addingTimeInterval(240)

        while Date() < deadline {
            if let project = try await fetchProjects().first(where: { $0.ref == ref }) {
                let status = project.status?.uppercased() ?? ""
                if !status.contains("CREATING"),
                   let details = try? await fetchConnectionDetails(for: project) {
                    return details
                }
            }

            try await Task.sleep(nanoseconds: 5_000_000_000)
        }

        throw SupabaseManagementServiceError.invalidInput(
            "Supabase is still provisioning this project. Refresh again in a minute."
        )
    }

    func readForAgent(
        projectRef: String,
        input: SupabaseReadTableInput
    ) async throws -> String {
        if let table = Self.trimmed(input.table), !table.isEmpty {
            let schema = Self.trimmed(input.schema) ?? "public"
            let query = try Self.selectQuery(
                schema: schema,
                table: table,
                columns: input.columns ?? [],
                filters: input.filters ?? [:],
                limit: min(max(input.limit ?? 25, 1), 200)
            )
            let data = try await runSQLQuery(
                projectRef: projectRef,
                query: query,
                readOnly: true
            )
            let rows = Self.resultRows(from: try Self.jsonObject(from: data))
            return """
            Read \(rows.count) row\(rows.count == 1 ? "" : "s") from \(schema).\(table).
            \(Self.prettyJSONString(rows) ?? "[]")
            """
        }

        let preview = try await fetchLiveSchemaPreview(for: projectRef)
        let lines = preview.tables.map { table in
            let columns = table.columns.prefix(6).joined(separator: ", ")
            return "- \(table.displayName): \(columns)"
        }
        let summary = lines.isEmpty ? "- No user-created tables found." : lines.joined(separator: "\n")
        return """
        \(preview.sourceSummary)
        \(summary)
        """
    }

    func executeSQLForAgent(
        projectRef: String,
        input: SupabaseExecuteSQLInput
    ) async throws -> String {
        let sql = Self.trimmed(input.sql) ?? ""
        guard !sql.isEmpty else {
            throw SupabaseManagementServiceError.invalidInput("Provide `sql` to execute.")
        }

        let data = try await runSQLQuery(
            projectRef: projectRef,
            query: sql,
            readOnly: false
        )
        let root = try Self.jsonObject(from: data)
        let rows = Self.resultRows(from: root)

        if !rows.isEmpty {
            return """
            Executed SQL in \(projectRef) and returned \(rows.count) row\(rows.count == 1 ? "" : "s").
            \(Self.prettyJSONString(rows) ?? "[]")
            """
        }

        if let rendered = Self.prettyJSONString(root) {
            return """
            Executed SQL in \(projectRef).
            \(rendered)
            """
        }

        return "Executed SQL in \(projectRef)."
    }

    func writeForAgent(
        projectRef: String,
        input: SupabaseWriteTableInput
    ) async throws -> String {
        let schema = Self.trimmed(input.schema) ?? "public"
        let table = try Self.requiredIdentifier(input.table, label: "table")
        let query: String

        switch input.operation {
        case .insert:
            let rows = input.rows?.isEmpty == false
                ? input.rows!
                : (input.values.map { [$0] } ?? [])
            query = try Self.insertQuery(schema: schema, table: table, rows: rows)
        case .update:
            query = try Self.updateQuery(
                schema: schema,
                table: table,
                values: input.values ?? [:],
                filters: input.filters ?? [:]
            )
        case .delete:
            query = try Self.deleteQuery(
                schema: schema,
                table: table,
                filters: input.filters ?? [:]
            )
        }

        let data = try await runSQLQuery(
            projectRef: projectRef,
            query: query,
            readOnly: false
        )
        let rows = Self.resultRows(from: try Self.jsonObject(from: data))
        return """
        \(input.operation.rawValue.capitalized) affected \(rows.count) row\(rows.count == 1 ? "" : "s") in \(schema).\(table).
        \(Self.prettyJSONString(rows) ?? "[]")
        """
    }

    func manageSettingsForAgent(
        projectRef: String,
        input: SupabaseManageSettingsInput
    ) async throws -> String {
        switch input.action ?? .describeAuth {
        case .describeAuth:
            let config = try await fetchAuthProviders(for: projectRef)
            return Self.renderAuthProviders(config, projectRef: projectRef, verb: "Current")
        case .updateAuth:
            var fields: [String: Any] = [:]
            let assignBool: (String, Bool?) -> Void = { key, value in
                if let value {
                    fields[key] = value
                }
            }
            let assignInt: (String, Int?) -> Void = { key, value in
                if let value {
                    fields[key] = value
                }
            }

            [
                ("external_email_enabled", input.emailEnabled),
                ("external_phone_enabled", input.phoneEnabled),
                ("external_anonymous_users_enabled", input.anonymousUsersEnabled),
                ("disable_signup", input.signupsEnabled.map(!)),
                ("mailer_secure_email_change_enabled", input.secureEmailChangeEnabled),
                ("mailer_allow_unverified_email_sign_ins", input.allowUnverifiedEmailSignIns),
                ("password_hibp_enabled", input.leakedPasswordProtectionEnabled),
                ("refresh_token_rotation_enabled", input.refreshTokenRotationEnabled),
                ("sessions_single_per_user", input.singleSessionPerUser),
                ("security_update_password_require_reauthentication", input.requireReauthenticationForPasswordChanges),
                ("external_apple_enabled", input.appleEnabled),
                ("external_google_enabled", input.googleEnabled),
                ("mailer_autoconfirm", input.emailConfirmationsEnabled.map(!)),
                ("sms_autoconfirm", input.phoneConfirmationsEnabled.map(!)),
            ].forEach(assignBool)

            [
                ("rate_limit_email_sent", input.rateLimitEmailSent),
                ("rate_limit_sms_sent", input.rateLimitSMSSent),
                ("password_min_length", input.passwordMinLength),
            ].forEach(assignInt)

            guard !fields.isEmpty else {
                throw SupabaseManagementServiceError.invalidInput(
                    "Provide at least one auth setting to update."
                )
            }

            _ = try await performRequest(
                path: "/v1/projects/\(projectRef)/config/auth",
                method: "PATCH",
                token: try requireToken(),
                body: fields,
                expectedStatusCodes: [200, 201, 204]
            )
            let config = try await fetchAuthProviders(for: projectRef)
            return Self.renderAuthProviders(config, projectRef: projectRef, verb: "Updated")
        }
    }

    private func fetchAuthProviders(for projectRef: String) async throws -> SupabaseAuthProviderSnapshot {
        let data = try await performRequest(
            path: "/v1/projects/\(projectRef)/config/auth",
            method: "GET",
            token: try requireToken()
        )
        return try Self.parseAuthProviders(from: data)
    }

    private func runSQLQuery(
        projectRef: String,
        query: String,
        readOnly: Bool
    ) async throws -> Data {
        try await performRequest(
            path: "/v1/projects/\(projectRef)/database/query\(readOnly ? "/read-only" : "")",
            method: "POST",
            token: try requireToken(),
            body: [
                "query": query,
                "parameters": [],
            ],
            expectedStatusCodes: [200, 201]
        )
    }

    private func requireToken() throws -> String {
        guard let token = tokenStore.token() else {
            throw SupabaseManagementServiceError.missingAccessToken
        }
        return token
    }

    private func performOptionalRequest(
        path: String,
        method: String,
        token: String
    ) async throws -> Data? {
        do {
            return try await performRequest(path: path, method: method, token: token)
        } catch let error as SupabaseManagementServiceError {
            switch error {
            case .requestFailed(let statusCode, _):
                if statusCode == 401 || statusCode == 403 || statusCode == 404 {
                    return nil
                }
                throw error
            default:
                throw error
            }
        }
    }

    private func performRequest(
        path: String,
        method: String,
        token: String,
        body: [String: Any]? = nil,
        expectedStatusCodes: Set<Int> = Set(200...299)
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "10x-macos/\(Config.appVersion) (\(Config.appBuild))",
            forHTTPHeaderField: "User-Agent"
        )

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseManagementServiceError.invalidResponse
        }

        guard expectedStatusCodes.contains(httpResponse.statusCode) else {
            throw SupabaseManagementServiceError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
            )
        }

        return data
    }

    nonisolated static func parseProjects(from data: Data) throws -> [SupabaseManagementProject] {
        let root = try jsonObject(from: data)
        return arrayOfDictionaries(from: root).compactMap(project(from:)).sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }

    nonisolated static func parseOrganizations(from data: Data) throws -> [SupabaseManagementOrganization] {
        let root = try jsonObject(from: data)
        return arrayOfDictionaries(from: root)
            .compactMap(organization(from:))
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    nonisolated static func parsePublishableKey(from data: Data) throws -> String {
        let root = try jsonObject(from: data)
        let keyDictionaries = arrayOfDictionaries(from: root)

        let keys = keyDictionaries.compactMap { dictionary -> (value: String, rank: Int)? in
            guard let value = firstString(in: dictionary, keys: ["api_key", "apiKey", "key", "value"]),
                  !value.isEmpty else {
                return nil
            }

            let type = firstString(in: dictionary, keys: ["type"])?.lowercased() ?? ""
            let name = firstString(in: dictionary, keys: ["name", "description"])?.lowercased() ?? ""
            guard let rank = clientSafeAPIKeyRank(value: value, type: type, name: name) else {
                return nil
            }
            return (value, rank)
        }

        if let best = keys.sorted(by: { $0.rank < $1.rank }).first {
            return best.value
        }

        throw SupabaseManagementServiceError.missingPublishableKey
    }

    nonisolated static func parseAuthProviders(from data: Data) throws -> SupabaseAuthProviderSnapshot {
        let root = try jsonObject(from: data)
        guard let dictionary = root as? [String: Any] else {
            throw SupabaseManagementServiceError.malformedResponse("auth configuration")
        }

        return SupabaseAuthProviderSnapshot(
            emailEnabled: firstBool(in: dictionary, keys: ["external_email_enabled", "email_enabled"]),
            emailConfirmationsEnabled: firstBool(in: dictionary, keys: ["mailer_autoconfirm"]).map(!),
            phoneEnabled: firstBool(in: dictionary, keys: ["external_phone_enabled"]),
            phoneConfirmationsEnabled: firstBool(in: dictionary, keys: ["sms_autoconfirm"]).map(!),
            anonymousUsersEnabled: firstBool(in: dictionary, keys: ["external_anonymous_users_enabled"]),
            signupsEnabled: firstBool(in: dictionary, keys: ["disable_signup"]).map(!),
            secureEmailChangeEnabled: firstBool(in: dictionary, keys: ["mailer_secure_email_change_enabled"]),
            allowUnverifiedEmailSignIns: firstBool(in: dictionary, keys: ["mailer_allow_unverified_email_sign_ins"]),
            passwordMinLength: firstInt(in: dictionary, keys: ["password_min_length"]),
            leakedPasswordProtectionEnabled: firstBool(in: dictionary, keys: ["password_hibp_enabled"]),
            refreshTokenRotationEnabled: firstBool(in: dictionary, keys: ["refresh_token_rotation_enabled"]),
            singleSessionPerUser: firstBool(in: dictionary, keys: ["sessions_single_per_user"]),
            requireReauthenticationForPasswordChanges: firstBool(in: dictionary, keys: ["security_update_password_require_reauthentication"]),
            rateLimitEmailSent: firstInt(in: dictionary, keys: ["rate_limit_email_sent"]),
            rateLimitSMSSent: firstInt(in: dictionary, keys: ["rate_limit_sms_sent"]),
            appleEnabled: firstBool(in: dictionary, keys: ["external_apple_enabled"]) ?? false,
            googleEnabled: firstBool(in: dictionary, keys: ["external_google_enabled"]) ?? false
        )
    }

    nonisolated static func parseSchemaPreview(from data: Data) throws -> SupabaseSchemaPreview {
        let root = try jsonObject(from: data)
        let rowDictionaries = resultRows(from: root)

        let groupedColumns = rowDictionaries.reduce(into: [String: [(position: Int, label: String)]]()) { partialResult, row in
            guard let schema = firstString(in: row, keys: ["table_schema"]),
                  let table = firstString(in: row, keys: ["table_name"]),
                  let column = firstString(in: row, keys: ["column_name"]) else {
                return
            }
            guard SupabaseSchemaPreview.isUserVisibleTable(schema: schema, name: table) else {
                return
            }

            let type = firstString(in: row, keys: ["data_type"]) ?? ""
            let position = firstInt(in: row, keys: ["ordinal_position"]) ?? Int.max
            let label = type.isEmpty ? column : "\(column) (\(type))"
            partialResult["\(schema.lowercased()).\(table.lowercased())", default: []].append((position, label))
        }

        let unsortedTables: [SupabaseSchemaPreview.Table] = groupedColumns.map { name, entries in
            let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
            let schema = parts.count == 2 ? parts[0] : "public"
            let tableName = parts.count == 2 ? parts[1] : name
            let columns = entries
                .sorted(by: { lhs, rhs in
                    if lhs.position != rhs.position {
                        return lhs.position < rhs.position
                    }
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                })
                .map(\.label)

            return SupabaseSchemaPreview.Table(
                schema: schema,
                name: tableName,
                columns: columns
            )
        }

        let tables = unsortedTables.sorted(by: { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        })

        return SupabaseSchemaPreview(
            tables: tables,
            migrations: [],
            scannedFileCount: 0,
            sourceSummary: tables.isEmpty ? "Live schema" : "Live schema · \(tables.count) user table\(tables.count == 1 ? "" : "s")",
            emptyStateMessage: tables.isEmpty ? "No user-created database tables were returned." : nil,
            bootstrapCommand: nil
        )
    }

    nonisolated static func projectRef(from urlOrHost: String?) -> String? {
        guard var value = urlOrHost?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard let host = URL(string: value)?.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        guard host.hasSuffix(".supabase.co") else {
            return nil
        }

        let hostComponents = host.split(separator: ".").map(String.init)
        if hostComponents.first == "db", hostComponents.count >= 4 {
            return hostComponents[1]
        }
        guard hostComponents.count >= 3 else {
            return nil
        }
        return hostComponents.first
    }

    private nonisolated static func project(from dictionary: [String: Any]) -> SupabaseManagementProject? {
        let name = firstString(in: dictionary, keys: ["name"]) ?? "Supabase Project"
        let status = firstString(in: dictionary, keys: ["status"])
        let region = firstString(in: dictionary, keys: ["region"])
        let database = dictionary["database"] as? [String: Any]
        let databaseHost = firstString(in: database, keys: ["host"])

        let ref = firstString(in: dictionary, keys: ["ref", "project_ref"])
            ?? projectRef(from: firstString(in: dictionary, keys: ["api_url", "apiUrl"]))
            ?? projectRef(from: databaseHost)

        guard let ref, !ref.isEmpty else { return nil }

        let id = firstString(in: dictionary, keys: ["id"]) ?? ref

        return SupabaseManagementProject(
            id: id,
            ref: ref,
            name: name,
            status: status,
            region: region,
            databaseHost: databaseHost
        )
    }

    private nonisolated static func organization(from dictionary: [String: Any]) -> SupabaseManagementOrganization? {
        guard let id = firstString(in: dictionary, keys: ["id", "organization_id"]) else {
            return nil
        }

        return SupabaseManagementOrganization(
            id: id,
            name: firstString(in: dictionary, keys: ["name", "slug"]) ?? "Supabase Organization",
            slug: firstString(in: dictionary, keys: ["slug"])
        )
    }

    private nonisolated static func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SupabaseManagementServiceError.malformedResponse("JSON payload")
        }
    }

    private nonisolated static func arrayOfDictionaries(from object: Any) -> [[String: Any]] {
        if let array = object as? [[String: Any]] {
            return array
        }

        if let dictionary = object as? [String: Any] {
            for key in ["projects", "organizations", "result", "data", "items"] {
                if let nested = dictionary[key] {
                    let dictionaries = arrayOfDictionaries(from: nested)
                    if !dictionaries.isEmpty {
                        return dictionaries
                    }
                }
            }
        }

        return []
    }

    private nonisolated static func resultRows(from object: Any) -> [[String: Any]] {
        if let rows = object as? [[String: Any]] {
            return rows
        }

        if let dictionary = object as? [String: Any] {
            for key in ["result", "rows", "data"] {
                if let nested = dictionary[key] {
                    let rows = resultRows(from: nested)
                    if !rows.isEmpty {
                        return rows
                    }
                }
            }
        }

        return []
    }

    private nonisolated static func firstString(in dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else { return nil }

        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }

    private nonisolated static func firstBool(in dictionary: [String: Any]?, keys: [String]) -> Bool? {
        guard let dictionary else { return nil }

        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
        }

        return nil
    }

    private nonisolated static func firstInt(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
            if let value = dictionary[key] as? String, let intValue = Int(value) {
                return intValue
            }
        }

        return nil
    }

    private nonisolated static func clientSafeAPIKeyRank(
        value: String,
        type: String,
        name: String
    ) -> Int? {
        if value.hasPrefix("sb_publishable_") || type.contains("publishable") || name.contains("publishable") {
            return 0
        }
        if name.contains("anon") || type.contains("anon") {
            return 1
        }
        return nil
    }

    private nonisolated static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }

        for key in ["message", "error", "detail"] {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }

        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    private nonisolated static func selectQuery(
        schema: String,
        table: String,
        columns: [String],
        filters: [String: AnyCodableValue],
        limit: Int
    ) throws -> String {
        let projection: String
        if columns.isEmpty {
            projection = "*"
        } else {
            projection = try columns.map { column in
                if trimmed(column) == "*" {
                    return "*"
                }
                return try Self.quotedIdentifier(column)
            }.joined(separator: ", ")
        }

        var query = """
        select \(projection)
        from \(try qualifiedTable(schema: schema, table: table))
        """
        let whereClause = try sqlWhereClause(filters)
        if !whereClause.isEmpty {
            query += "\n\(whereClause)"
        }
        query += "\nlimit \(limit);"
        return query
    }

    private nonisolated static func insertQuery(
        schema: String,
        table: String,
        rows: [[String: AnyCodableValue]]
    ) throws -> String {
        guard let firstRow = rows.first, !firstRow.isEmpty else {
            throw SupabaseManagementServiceError.invalidInput("Provide `values` or `rows` for an insert.")
        }

        let keys = firstRow.keys.sorted()
        guard rows.allSatisfy({ Set($0.keys) == Set(keys) }) else {
            throw SupabaseManagementServiceError.invalidInput("All insert rows must use the same columns.")
        }

        let columns = try keys.map { try Self.quotedIdentifier($0) }.joined(separator: ", ")
        let values = try rows.map { row in
            let fragments = try keys.map { key in
                try Self.sqlLiteral(row[key] ?? .null)
            }.joined(separator: ", ")
            return "(\(fragments))"
        }.joined(separator: ", ")

        return """
        insert into \(try qualifiedTable(schema: schema, table: table)) (\(columns))
        values \(values)
        returning *;
        """
    }

    private nonisolated static func updateQuery(
        schema: String,
        table: String,
        values: [String: AnyCodableValue],
        filters: [String: AnyCodableValue]
    ) throws -> String {
        guard !values.isEmpty else {
            throw SupabaseManagementServiceError.invalidInput("Provide `values` for an update.")
        }
        let whereClause = try sqlWhereClause(filters)
        guard !whereClause.isEmpty else {
            throw SupabaseManagementServiceError.invalidInput("Provide `filters` for updates so the change stays scoped.")
        }

        let assignments = try values.keys.sorted().map { key in
            "\(try Self.quotedIdentifier(key)) = \(try Self.sqlLiteral(values[key] ?? .null))"
        }.joined(separator: ", ")

        return """
        update \(try qualifiedTable(schema: schema, table: table))
        set \(assignments)
        \(whereClause)
        returning *;
        """
    }

    private nonisolated static func deleteQuery(
        schema: String,
        table: String,
        filters: [String: AnyCodableValue]
    ) throws -> String {
        let whereClause = try sqlWhereClause(filters)
        guard !whereClause.isEmpty else {
            throw SupabaseManagementServiceError.invalidInput("Provide `filters` for deletes so the change stays scoped.")
        }

        return """
        delete from \(try qualifiedTable(schema: schema, table: table))
        \(whereClause)
        returning *;
        """
    }

    private nonisolated static func sqlWhereClause(
        _ filters: [String: AnyCodableValue]
    ) throws -> String {
        guard !filters.isEmpty else { return "" }
        let predicates = try filters.keys.sorted().map { key in
            "\(try Self.quotedIdentifier(key)) = \(try Self.sqlLiteral(filters[key] ?? .null))"
        }.joined(separator: " and ")
        return "where \(predicates)"
    }

    private nonisolated static func qualifiedTable(schema: String, table: String) throws -> String {
        "\(try Self.quotedIdentifier(schema)).\(try Self.quotedIdentifier(table))"
    }

    private nonisolated static func quotedIdentifier(_ raw: String) throws -> String {
        let value = try Self.requiredIdentifier(raw, label: "identifier")
        return "\"\(value)\""
    }

    private nonisolated static func requiredIdentifier(_ raw: String, label: String) throws -> String {
        let value = trimmed(raw) ?? ""
        guard !value.isEmpty else {
            throw SupabaseManagementServiceError.invalidInput("Missing \(label).")
        }
        guard value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            throw SupabaseManagementServiceError.invalidInput("Unsupported \(label) `\(value)`. Use simple schema, table, and column names.")
        }
        return value
    }

    private nonisolated static func sqlLiteral(_ value: AnyCodableValue) throws -> String {
        switch value {
        case .string(let string):
            return "'\(string.replacingOccurrences(of: "'", with: "''"))'"
        case .int(let int):
            return String(int)
        case .double(let double):
            return String(double)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .array, .dictionary:
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8) ?? "null"
            return "'\(json.replacingOccurrences(of: "'", with: "''"))'::jsonb"
        }
    }

    nonisolated static func renderAuthProviders(
        _ snapshot: SupabaseAuthProviderSnapshot,
        projectRef: String,
        verb: String
    ) -> String {
        let dashboardRoot = "https://supabase.com/dashboard/project/\(projectRef)"
        let providersURL = "\(dashboardRoot)/auth/providers"
        let urlConfigurationURL = "\(dashboardRoot)/auth/url-configuration"
        let emailTemplatesURL = "\(dashboardRoot)/auth/templates"
        let callbackURL = "https://\(projectRef).supabase.co/auth/v1/callback"
        let emailConfirmationGuidance: String
        if snapshot.emailConfirmationsEnabled == true {
            emailConfirmationGuidance = "Confirm Email is currently required. If users are getting stuck, verify the Email provider toggle, URL Configuration, and the confirmation email template."
        } else if snapshot.emailConfirmationsEnabled == false {
            emailConfirmationGuidance = "Confirm Email is currently disabled. Turn it on in Auth > Providers > Email if new users should verify before first sign-in."
        } else {
            emailConfirmationGuidance = "Check Auth > Providers > Email to decide whether Confirm Email should be required for first sign-in."
        }
        var lines = [
            "\(verb) auth settings for \(projectRef):",
            "- Signups: \(boolSummary(snapshot.signupsEnabled))",
            "- Email: \(boolSummary(snapshot.emailEnabled))",
            "- Email confirmations: \(confirmationSummary(snapshot.emailConfirmationsEnabled))",
            "- Secure email change: \(boolSummary(snapshot.secureEmailChangeEnabled))",
            "- Allow unverified email sign-ins: \(boolSummary(snapshot.allowUnverifiedEmailSignIns))",
            "- Phone: \(boolSummary(snapshot.phoneEnabled))",
            "- Phone confirmations: \(confirmationSummary(snapshot.phoneConfirmationsEnabled))",
            "- Anonymous users: \(boolSummary(snapshot.anonymousUsersEnabled))",
            "- Minimum password length: \(intSummary(snapshot.passwordMinLength))",
            "- Leaked password protection: \(boolSummary(snapshot.leakedPasswordProtectionEnabled))",
            "- Refresh token rotation: \(boolSummary(snapshot.refreshTokenRotationEnabled))",
            "- Single session per user: \(boolSummary(snapshot.singleSessionPerUser))",
            "- Require reauthentication for password changes: \(boolSummary(snapshot.requireReauthenticationForPasswordChanges))",
            "- Email rate limit/hour: \(intSummary(snapshot.rateLimitEmailSent))",
            "- SMS rate limit/hour: \(intSummary(snapshot.rateLimitSMSSent))",
            "- Apple: \(snapshot.appleEnabled ? "enabled" : "disabled")",
            "- Google: \(snapshot.googleEnabled ? "enabled" : "disabled")",
            "",
            "Manage these auth settings in Supabase Dashboard:",
            "- Auth Providers: \(providersURL)",
            "- URL Configuration: \(urlConfigurationURL)",
            "- Email Templates: \(emailTemplatesURL)",
            "",
            "Scope:",
            "- App code: native Apple/Google sign-in UI, `redirectTo` or deep-link handling, and exchanging the returned credential into a real Supabase session.",
            "- Supabase dashboard: provider enable toggles, provider client IDs and secrets, Confirm Email behavior, Site URL, Redirect URLs, email templates, and SMTP delivery.",
            "",
            "What to fill in:",
            "- Email: manage this in Auth > Providers > Email. \(emailConfirmationGuidance)",
            "- Redirects: use URL Configuration for Site URL and every confirmation, magic-link, reset-password, or social-login redirect target your app uses.",
            "- Templates: use Email Templates for confirm-signup, magic-link, and reset-password content or redirect behavior.",
            "- Apple: in Auth > Providers > Apple, fill Client IDs and Secret. In Apple Developer, create an App ID, Services ID, and Sign in with Apple key. Register the Services ID for web OAuth plus any native bundle IDs you use. Copy the Callback URL shown in Supabase; for most hosted projects it is \(callbackURL). If the project uses a custom Auth domain, use the provider page's Callback URL instead.",
            "- Google: in Auth > Providers > Google, fill Client ID and Secret. In Google Cloud, create a web OAuth client and add the exact Supabase callback URL as an authorized redirect URI. If you use multiple client IDs, keep the web client ID first.",
        ]
        return lines.joined(separator: "\n")
    }

    private nonisolated static func confirmationSummary(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return value ? "required" : "disabled"
    }

    private nonisolated static func intSummary(_ value: Int?) -> String {
        value.map(String.init) ?? "unknown"
    }

    private nonisolated static func boolSummary(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return value ? "enabled" : "disabled"
    }

    private nonisolated static func prettyJSONString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func defaultRegion(for organization: SupabaseManagementOrganization) async throws -> String {
        guard let slug = organization.slug, !slug.isEmpty else {
            return Self.defaultProjectRegion
        }

        let data = try? await performRequest(
            path: "/v1/organizations/\(slug)/projects?limit=20",
            method: "GET",
            token: try requireToken()
        )
        if let data,
           let project = try? Self.parseProjects(from: data).first,
           let region = Self.trimmed(project.region),
           !region.isEmpty {
            return region
        }

        return Self.defaultProjectRegion
    }

    private nonisolated static func generatedDatabasePassword() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let random = String((0..<28).map { _ in alphabet.randomElement() ?? "x" })
        return "Tx1!\(random)"
    }
}
