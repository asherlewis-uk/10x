import Foundation

/// Local asset metadata entry.
struct LocalAsset: Codable, Identifiable, Sendable {
    let id: String
    let projectId: String
    let kind: String
    let relativePath: String
    let mimeType: String?
    let sizeBytes: Int?
    let checksum: String?
    let createdAt: String
    let updatedAt: String
}

/// Stores asset metadata in SQLite while files live in the app support directory.
actor AssetRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    func saveAsset(_ asset: LocalAsset) async throws {
        let sql = """
        INSERT INTO assets (id, project_id, kind, relative_path, mime_type, size_bytes, checksum, created_at, updated_at)
        VALUES (\(CockpitDatabase.escaped(asset.id)),
                \(CockpitDatabase.escaped(asset.projectId)),
                \(CockpitDatabase.escaped(asset.kind)),
                \(CockpitDatabase.escaped(asset.relativePath)),
                \(asset.mimeType.map(CockpitDatabase.escaped) ?? "NULL"),
                \(asset.sizeBytes.map(String.init) ?? "NULL"),
                \(asset.checksum.map(CockpitDatabase.escaped) ?? "NULL"),
                \(CockpitDatabase.escaped(asset.createdAt)),
                \(CockpitDatabase.escaped(asset.updatedAt)))
        ON CONFLICT(id) DO UPDATE SET
            kind = excluded.kind,
            relative_path = excluded.relative_path,
            mime_type = excluded.mime_type,
            size_bytes = excluded.size_bytes,
            checksum = excluded.checksum,
            updated_at = excluded.updated_at;
        """
        try await db.execute(sql)
    }

    func fetchAssets(projectId: String) async throws -> [LocalAsset] {
        let rows = try await db.query("""
            SELECT id, project_id, kind, relative_path, mime_type, size_bytes, checksum, created_at, updated_at
            FROM assets
            WHERE project_id = \(CockpitDatabase.escaped(projectId))
            ORDER BY created_at DESC;
        """)
        return rows.compactMap(Self.asset(from:))
    }

    private static func asset(from row: [String: String]) -> LocalAsset? {
        guard let id = row["id"],
              let projectId = row["project_id"],
              let kind = row["kind"],
              let relativePath = row["relative_path"],
              let createdAt = row["created_at"],
              let updatedAt = row["updated_at"]
        else { return nil }
        return LocalAsset(
            id: id,
            projectId: projectId,
            kind: kind,
            relativePath: relativePath,
            mimeType: row["mime_type"],
            sizeBytes: row["size_bytes"].flatMap(Int.init),
            checksum: row["checksum"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
