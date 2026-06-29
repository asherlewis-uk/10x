import Foundation

/// SQL-backed version metadata repository.
actor VersionRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    func fetchVersions(projectId: String) async throws -> [BuilderVersion] {
        let sql = """
        SELECT id, project_id, version_number, file_tree_json, prompt, status, created_at
        FROM versions
        WHERE project_id = \(CockpitDatabase.escaped(projectId))
        ORDER BY version_number DESC;
        """
        let rows = try await db.query(sql)
        return rows.compactMap(Self.version(from:))
    }

    func getVersion(projectId: String, versionId: String) async throws -> BuilderVersion? {
        let sql = """
        SELECT id, project_id, version_number, file_tree_json, prompt, status, created_at
        FROM versions
        WHERE id = \(CockpitDatabase.escaped(versionId))
          AND project_id = \(CockpitDatabase.escaped(projectId))
        LIMIT 1;
        """
        let rows = try await db.query(sql)
        return rows.first.flatMap(Self.version(from:))
    }

    func createVersion(
        projectId: String,
        conversationId: String,
        fileTree: [String: String],
        prompt: String,
        status: String = "ready"
    ) async throws -> BuilderVersion {
        let existing = try await fetchVersions(projectId: projectId)
        let nextNumber = (existing.first?.versionNumber ?? 0) + 1
        let id = UUID().uuidString
        let now = isoTimestamp()
        let treeData = try JSONEncoder().encode(fileTree)
        let treeJSON = String(data: treeData, encoding: .utf8) ?? "{}"

        let sql = """
        INSERT INTO versions (id, project_id, version_number, file_tree_json, prompt, status, created_at)
        VALUES (\(CockpitDatabase.escaped(id)),
                \(CockpitDatabase.escaped(projectId)),
                \(nextNumber),
                \(CockpitDatabase.escaped(treeJSON)),
                \(CockpitDatabase.escaped(prompt)),
                \(CockpitDatabase.escaped(status)),
                \(CockpitDatabase.escaped(now)));
        """
        try await db.execute(sql)
        try await ProjectRepository(database: db).setCurrentVersionId(projectId: projectId, versionId: id)
        return try await getVersion(projectId: projectId, versionId: id)!
    }

    private static func version(from row: [String: String]) -> BuilderVersion? {
        guard let id = row["id"],
              let projectId = row["project_id"],
              let versionNumberString = row["version_number"],
              let versionNumber = Int(versionNumberString),
              let prompt = row["prompt"],
              let status = row["status"],
              let createdAt = row["created_at"]
        else { return nil }

        let fileTree: [String: String] = {
            guard let json = row["file_tree_json"], let data = json.data(using: .utf8) else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }()

        return BuilderVersion(
            id: id,
            projectId: projectId,
            versionNumber: versionNumber,
            fileTree: fileTree,
            prompt: prompt,
            status: status,
            createdAt: createdAt
        )
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
