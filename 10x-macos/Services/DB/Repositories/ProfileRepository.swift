import Foundation

/// Local single-user profile. No remote auth required.
struct LocalProfile: Codable, Equatable, Sendable {
    let id: String
    var email: String?
    var name: String?
    let createdAt: String
    var updatedAt: String
}

/// Reads and writes the single local user profile.
actor ProfileRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    /// Load the existing local profile, or create one on first launch.
    func loadOrCreateProfile() async throws -> LocalProfile {
        if let existing = try await loadProfile() {
            return existing
        }
        let now = isoTimestamp()
        let profile = LocalProfile(
            id: UUID().uuidString,
            email: "local@11x.local",
            name: "Local User",
            createdAt: now,
            updatedAt: now
        )
        try await saveProfile(profile)
        return profile
    }

    func loadProfile() async throws -> LocalProfile? {
        let rows = try await db.query("SELECT id, email, name, created_at, updated_at FROM local_profile LIMIT 1;")
        guard let row = rows.first else { return nil }
        return LocalProfile(
            id: row["id"] ?? "",
            email: row["email"],
            name: row["name"],
            createdAt: row["created_at"] ?? "",
            updatedAt: row["updated_at"] ?? ""
        )
    }

    func saveProfile(_ profile: LocalProfile) async throws {
        let sql = """
        INSERT INTO local_profile (id, email, name, created_at, updated_at)
        VALUES (\(CockpitDatabase.escaped(profile.id)),
                \(profile.email.map(CockpitDatabase.escaped) ?? "NULL"),
                \(profile.name.map(CockpitDatabase.escaped) ?? "NULL"),
                \(CockpitDatabase.escaped(profile.createdAt)),
                \(CockpitDatabase.escaped(profile.updatedAt)))
        ON CONFLICT(id) DO UPDATE SET
            email = excluded.email,
            name = excluded.name,
            updated_at = excluded.updated_at;
        """
        try await db.execute(sql)
    }

    func update(email: String?, name: String?) async throws -> LocalProfile {
        var profile = try await loadOrCreateProfile()
        let now = isoTimestamp()
        if let email { profile.email = email }
        if let name { profile.name = name }
        profile.updatedAt = now
        try await saveProfile(profile)
        return profile
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
