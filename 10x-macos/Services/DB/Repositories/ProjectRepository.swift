import Foundation

/// SQL-backed project metadata repository.
actor ProjectRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    func fetchProjects(userId: String, status: String? = nil) async throws -> [BuilderProject] {
        var sql = "SELECT * FROM projects WHERE user_id = \(CockpitDatabase.escaped(userId))"
        if let status {
            sql += " AND status = \(CockpitDatabase.escaped(status))"
        }
        sql += " ORDER BY updated_at DESC;"
        let rows = try await db.query(sql)
        return rows.compactMap { Self.project(from: $0) }
    }

    func getProject(id: String) async throws -> BuilderProject? {
        let rows = try await db.query("SELECT * FROM projects WHERE id = \(CockpitDatabase.escaped(id)) LIMIT 1;")
        return rows.first.flatMap(Self.project(from:))
    }

    func createProject(userId: String, name: String, platform: String = "swiftui") async throws -> BuilderProject {
        let id = UUID().uuidString
        let now = isoTimestamp()
        let slug = Self.slugify(name)
        let sql = """
        INSERT INTO projects (id, user_id, name, description, slug, platform, status, current_version_id, settings_json, created_at, updated_at)
        VALUES (\(CockpitDatabase.escaped(id)),
                \(CockpitDatabase.escaped(userId)),
                \(CockpitDatabase.escaped(name)),
                NULL,
                \(CockpitDatabase.escaped(slug)),
                \(CockpitDatabase.escaped(platform)),
                'active',
                NULL,
                NULL,
                \(CockpitDatabase.escaped(now)),
                \(CockpitDatabase.escaped(now)));
        """
        try await db.execute(sql)
        return try await getProject(id: id)!
    }

    func updateProject(id: String, name: String? = nil, description: String? = nil, slug: String? = nil, settings: [String: AnyCodableValue]? = nil) async throws -> BuilderProject {
        let now = isoTimestamp()
        var sets: [String] = ["updated_at = \(CockpitDatabase.escaped(now))"]
        if let name { sets.append("name = \(CockpitDatabase.escaped(name))") }
        if let description { sets.append("description = \(CockpitDatabase.escaped(description))") }
        if let slug { sets.append("slug = \(CockpitDatabase.escaped(slug))") }
        if let settings {
            let data = try JSONEncoder().encode(settings)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            sets.append("settings_json = \(CockpitDatabase.escaped(json))")
        }
        let sql = """
        UPDATE projects
        SET \(sets.joined(separator: ", "))
        WHERE id = \(CockpitDatabase.escaped(id));
        """
        try await db.execute(sql)
        return try await getProject(id: id)!
    }

    func archiveProject(id: String) async throws -> BuilderProject {
        try await setStatus(id: id, status: "archived")
        return try await getProject(id: id)!
    }

    func unarchiveProject(id: String) async throws -> BuilderProject {
        try await setStatus(id: id, status: "active")
        return try await getProject(id: id)!
    }

    func deleteProject(id: String) async throws {
        try await db.execute("DELETE FROM projects WHERE id = \(CockpitDatabase.escaped(id));")
    }

    func setCurrentVersionId(projectId: String, versionId: String) async throws {
        let now = isoTimestamp()
        let sql = """
        UPDATE projects
        SET current_version_id = \(CockpitDatabase.escaped(versionId)), updated_at = \(CockpitDatabase.escaped(now))
        WHERE id = \(CockpitDatabase.escaped(projectId));
        """
        try await db.execute(sql)
    }

    // MARK: - Private helpers

    private func setStatus(id: String, status: String) async throws {
        let now = isoTimestamp()
        let sql = """
        UPDATE projects
        SET status = \(CockpitDatabase.escaped(status)), updated_at = \(CockpitDatabase.escaped(now))
        WHERE id = \(CockpitDatabase.escaped(id));
        """
        try await db.execute(sql)
    }

    private static func project(from row: [String: String]) -> BuilderProject? {
        guard let id = row["id"],
              let userId = row["user_id"],
              let name = row["name"],
              let slug = row["slug"],
              let platform = row["platform"],
              let status = row["status"],
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"]
        else { return nil }

        let settings: [String: AnyCodableValue]? = row["settings_json"].flatMap { json in
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String: AnyCodableValue].self, from: data)
        }

        return BuilderProject(
            id: id,
            userId: userId,
            name: name,
            description: row["description"],
            slug: slug,
            platform: platform,
            status: status,
            currentVersionId: row["current_version_id"],
            settings: settings,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func slugify(_ name: String) -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let hex = (0..<3).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        return "\(slug.isEmpty ? "project" : slug)-\(hex)"
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
