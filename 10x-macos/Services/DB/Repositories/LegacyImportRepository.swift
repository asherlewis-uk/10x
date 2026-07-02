import Foundation

/// Tracks legacy 10x project imports so duplicate imports are detected and
/// import reports can reference the resulting 11x project.
actor LegacyImportRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    func findImport(
        sourcePath: String,
        legacyProjectId: String?,
        contentFingerprint: String
    ) async throws -> LegacyImportRecord? {
        let normalizedPath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
        let byPath = try await record(where: "source_path = \(CockpitDatabase.escaped(normalizedPath))")
        if let byPath { return byPath }

        if let legacyProjectId, !legacyProjectId.isEmpty {
            let byLegacyId = try await record(
                where: "legacy_project_id = \(CockpitDatabase.escaped(legacyProjectId))"
            )
            if let byLegacyId { return byLegacyId }
        }

        let byFingerprint = try await record(
            where: "content_fingerprint = \(CockpitDatabase.escaped(contentFingerprint))"
        )
        return byFingerprint
    }

    func recordImport(
        sourcePath: String,
        legacyProjectId: String?,
        manifestId: String?,
        contentFingerprint: String,
        projectId: String
    ) async throws -> LegacyImportRecord {
        let id = UUID().uuidString
        let now = Self.isoTimestamp()
        let normalizedPath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
        let sql = """
        INSERT INTO legacy_imports (id, source_path, legacy_project_id, manifest_id, content_fingerprint, project_id, imported_at)
        VALUES (\(CockpitDatabase.escaped(id)),
                \(CockpitDatabase.escaped(normalizedPath)),
                \(legacyProjectId.map(CockpitDatabase.escaped) ?? "NULL"),
                \(manifestId.map(CockpitDatabase.escaped) ?? "NULL"),
                \(CockpitDatabase.escaped(contentFingerprint)),
                \(CockpitDatabase.escaped(projectId)),
                \(CockpitDatabase.escaped(now)));
        """
        try await db.execute(sql)
        return LegacyImportRecord(
            id: id,
            sourcePath: normalizedPath,
            legacyProjectId: legacyProjectId,
            manifestId: manifestId,
            contentFingerprint: contentFingerprint,
            projectId: projectId,
            importedAt: now
        )
    }

    func getImport(id: String) async throws -> LegacyImportRecord? {
        let rows = try await db.query("""
            SELECT id, source_path, legacy_project_id, manifest_id, content_fingerprint, project_id, imported_at
            FROM legacy_imports
            WHERE id = \(CockpitDatabase.escaped(id))
            LIMIT 1;
        """)
        return rows.first.flatMap(Self.record(from:))
    }

    // MARK: - Private helpers

    private func record(where condition: String) async throws -> LegacyImportRecord? {
        let sql = """
            SELECT id, source_path, legacy_project_id, manifest_id, content_fingerprint, project_id, imported_at
            FROM legacy_imports
            WHERE \(condition)
            ORDER BY imported_at DESC
            LIMIT 1;
        """
        let rows = try await db.query(sql)
        return rows.first.flatMap(Self.record(from:))
    }

    private static func record(from row: [String: String]) -> LegacyImportRecord? {
        guard let id = row["id"],
              let sourcePath = row["source_path"],
              let contentFingerprint = row["content_fingerprint"],
              let projectId = row["project_id"],
              let importedAt = row["imported_at"]
        else { return nil }
        return LegacyImportRecord(
            id: id,
            sourcePath: sourcePath,
            legacyProjectId: row["legacy_project_id"],
            manifestId: row["manifest_id"],
            contentFingerprint: contentFingerprint,
            projectId: projectId,
            importedAt: importedAt
        )
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

struct LegacyImportRecord: Codable, Identifiable, Sendable {
    let id: String
    let sourcePath: String
    let legacyProjectId: String?
    let manifestId: String?
    let contentFingerprint: String
    let projectId: String
    let importedAt: String
}
