import Foundation

/// Generic key/value settings store backed by SQLite.
actor AppSettingsRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    func string(forKey key: String) async throws -> String? {
        let rows = try await db.query("""
            SELECT value_json FROM app_settings WHERE key = \(CockpitDatabase.escaped(key)) LIMIT 1;
        """)
        guard let json = rows.first?["value_json"] else { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    func set(_ value: String, forKey key: String) async throws {
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8) ?? "null"
        let now = isoTimestamp()
        let sql = """
        INSERT INTO app_settings (key, value_json, updated_at)
        VALUES (\(CockpitDatabase.escaped(key)), \(CockpitDatabase.escaped(json)), \(CockpitDatabase.escaped(now)))
        ON CONFLICT(key) DO UPDATE SET
            value_json = excluded.value_json,
            updated_at = excluded.updated_at;
        """
        try await db.execute(sql)
    }

    func remove(_ key: String) async throws {
        try await db.execute("DELETE FROM app_settings WHERE key = \(CockpitDatabase.escaped(key));")
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
