import Foundation

/// SQLite-backed storage for provider metadata. Secrets are not stored here.
actor ProviderConfigRepository {
    static let defaultConfigID = "default"
    private static let apiKeyKey = "OPENAI_API_KEY"

    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    func loadConfig(id: String = defaultConfigID) async -> ProviderConfig? {
        let rows = try? await db.query("""
            SELECT id, provider_type, display_name, base_url, model, created_at, updated_at
            FROM provider_configs
            WHERE id = \(CockpitDatabase.escaped(id))
            LIMIT 1;
        """)
        guard let row = rows?.first else { return nil }
        return config(from: row)
    }

    func loadOrCreateDefaultConfig() async -> ProviderConfig {
        if let existing = await loadConfig() {
            return existing
        }
        let config = ProviderConfig.defaultConfig()
        try? await save(config)
        return config
    }

    func save(_ config: ProviderConfig) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let sql = """
        INSERT INTO provider_configs (id, provider_type, display_name, base_url, model, created_at, updated_at)
        VALUES (
            \(CockpitDatabase.escaped(config.id)),
            \(CockpitDatabase.escaped(config.providerType.rawValue)),
            \(CockpitDatabase.escaped(config.displayName)),
            \(CockpitDatabase.escaped(config.baseURL)),
            \(CockpitDatabase.escaped(config.model)),
            \(CockpitDatabase.escaped(config.createdAt)),
            \(CockpitDatabase.escaped(now))
        )
        ON CONFLICT(id) DO UPDATE SET
            provider_type = excluded.provider_type,
            display_name = excluded.display_name,
            base_url = excluded.base_url,
            model = excluded.model,
            updated_at = excluded.updated_at;
        """
        try await db.execute(sql)
    }

    func setBaseURL(_ baseURL: String, id: String = defaultConfigID) async throws {
        var config = (await loadConfig(id: id)) ?? ProviderConfig.defaultConfig()
        config.baseURL = baseURL
        config.updatedAt = ISO8601DateFormatter().string(from: Date())
        try await save(config)
    }

    func setModel(_ model: String, id: String = defaultConfigID) async throws {
        var config = (await loadConfig(id: id)) ?? ProviderConfig.defaultConfig()
        config.model = model
        config.updatedAt = ISO8601DateFormatter().string(from: Date())
        try await save(config)
    }

    func setAPIKey(_ apiKey: String?, id: String = defaultConfigID) async {
        ProviderKeychainStore.set(apiKey, for: Self.apiKeyKey)
    }

    func apiKey(id: String = defaultConfigID) -> String? {
        ProviderKeychainStore.value(for: Self.apiKeyKey)
    }

    func validatedConfig(id: String = defaultConfigID) async throws -> (config: ProviderConfig, apiKey: String) {
        guard let config = await loadConfig(id: id) else {
            throw ProviderConfigError.missingProviderConfig
        }
        guard !config.baseURL.isEmpty, URL(string: config.baseURL) != nil else {
            throw ProviderConfigError.invalidBaseURL
        }
        guard !config.model.isEmpty else {
            throw ProviderConfigError.missingModel
        }
        guard let apiKey = apiKey(id: id)?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw ProviderConfigError.missingAPIKey
        }
        return (config, apiKey)
    }

    private func config(from row: [String: String]) -> ProviderConfig {
        ProviderConfig(
            id: row["id"] ?? ProviderConfigRepository.defaultConfigID,
            providerType: ProviderType(rawValue: row["provider_type"] ?? "") ?? .openAICompatible,
            displayName: row["display_name"] ?? "",
            baseURL: row["base_url"] ?? "",
            model: row["model"] ?? "",
            createdAt: row["created_at"] ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: row["updated_at"] ?? ISO8601DateFormatter().string(from: Date())
        )
    }
}
