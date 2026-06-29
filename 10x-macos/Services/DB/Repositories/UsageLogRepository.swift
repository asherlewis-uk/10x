import Foundation

/// Local diagnostics-only usage log entry.
struct LocalUsageLog: Codable, Identifiable, Sendable {
    let id: String
    let projectId: String?
    let kind: String
    let payload: [String: AnyCodableValue]
    let createdAt: String
}

/// Stores usage diagnostics locally. Never gates features.
actor UsageLogRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    func addLog(projectId: String? = nil, kind: String, payload: [String: AnyCodableValue]) async throws {
        let id = UUID().uuidString
        let now = isoTimestamp()
        let payloadData = try JSONEncoder().encode(payload)
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
        let projectIdSQL = projectId.map(CockpitDatabase.escaped) ?? "NULL"
        let sql = """
        INSERT INTO usage_logs (id, project_id, kind, payload_json, created_at)
        VALUES (\(CockpitDatabase.escaped(id)),
                \(projectIdSQL),
                \(CockpitDatabase.escaped(kind)),
                \(CockpitDatabase.escaped(payloadJSON)),
                \(CockpitDatabase.escaped(now)));
        """
        try await db.execute(sql)
    }

    func fetchLogs(projectId: String? = nil, limit: Int = 100) async throws -> [LocalUsageLog] {
        var sql = "SELECT id, project_id, kind, payload_json, created_at FROM usage_logs"
        var conditions: [String] = []
        if let projectId {
            conditions.append("project_id = \(CockpitDatabase.escaped(projectId))")
        }
        if !conditions.isEmpty {
            sql += " WHERE \(conditions.joined(separator: " AND "))"
        }
        sql += " ORDER BY created_at DESC LIMIT \(max(limit, 0));"
        let rows = try await db.query(sql)
        return rows.compactMap(Self.log(from:))
    }

    private static func log(from row: [String: String]) -> LocalUsageLog? {
        guard let id = row["id"],
              let kind = row["kind"],
              let payloadJSON = row["payload_json"],
              let createdAt = row["created_at"]
        else { return nil }
        let payload: [String: AnyCodableValue] = {
            guard let data = payloadJSON.data(using: .utf8) else { return [:] }
            return (try? JSONDecoder().decode([String: AnyCodableValue].self, from: data)) ?? [:]
        }()
        return LocalUsageLog(
            id: id,
            projectId: row["project_id"],
            kind: kind,
            payload: payload,
            createdAt: createdAt
        )
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
