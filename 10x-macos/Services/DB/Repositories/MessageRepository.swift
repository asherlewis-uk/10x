import Foundation

/// SQL-backed message repository. Conversations are still loaded from
/// LocalProjectStore by default; this table provides durable SQL backing
/// for the same data where it is useful.
actor MessageRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    func fetchMessages(projectId: String, conversationId: String) async throws -> [BuilderMessage] {
        let sql = """
        SELECT id, project_id, conversation_id, role, content, version_id, created_at
        FROM messages
        WHERE project_id = \(CockpitDatabase.escaped(projectId))
          AND conversation_id = \(CockpitDatabase.escaped(conversationId))
        ORDER BY created_at ASC;
        """
        let rows = try await db.query(sql)
        return rows.compactMap(Self.message(from:))
    }

    func addMessage(_ message: BuilderMessage, projectId: String) async throws {
        let sql = """
        INSERT INTO messages (id, project_id, conversation_id, role, content, version_id, created_at)
        VALUES (\(CockpitDatabase.escaped(message.id)),
                \(CockpitDatabase.escaped(projectId)),
                \(CockpitDatabase.escaped(message.conversationId)),
                \(CockpitDatabase.escaped(message.role)),
                \(CockpitDatabase.escaped(message.content)),
                \(message.versionId.map(CockpitDatabase.escaped) ?? "NULL"),
                \(CockpitDatabase.escaped(message.createdAt)))
        ON CONFLICT(id) DO UPDATE SET
            role = excluded.role,
            content = excluded.content,
            version_id = excluded.version_id;
        """
        try await db.execute(sql)
    }

    func deleteMessages(projectId: String) async throws {
        try await db.execute("DELETE FROM messages WHERE project_id = \(CockpitDatabase.escaped(projectId));")
    }

    private static func message(from row: [String: String]) -> BuilderMessage? {
        guard let id = row["id"],
              let conversationId = row["conversation_id"],
              let role = row["role"],
              let content = row["content"],
              let createdAt = row["created_at"]
        else { return nil }
        return BuilderMessage(
            id: id,
            conversationId: conversationId,
            role: role,
            content: content,
            versionId: row["version_id"],
            createdAt: createdAt
        )
    }
}
