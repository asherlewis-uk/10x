import Foundation

/// Tracks legacy 10x project imports so duplicate imports are detected and
/// import reports can reference the resulting 11x project.
actor LegacyImportRepository {
    private let db: CockpitDatabase

    init(database: CockpitDatabase = CockpitDatabase.shared) {
        self.db = database
    }

    /// Find a completed import matching the source path, legacy id, or fingerprint.
    /// Incomplete/failed imports are ignored so retries are not permanently blocked.
    func findCompletedImport(
        sourcePath: String,
        legacyProjectId: String?,
        contentFingerprint: String
    ) async throws -> LegacyImportRecord? {
        let completedCondition = "status = \(CockpitDatabase.escaped(LegacyImportStatus.completed.rawValue))"
        let normalizedPath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path

        if let byPath = try await record(where: "\(completedCondition) AND source_path = \(CockpitDatabase.escaped(normalizedPath))"),
           await projectExists(id: byPath.projectId) {
            return byPath
        }

        if let legacyProjectId, !legacyProjectId.isEmpty,
           let byLegacyId = try await record(where: "\(completedCondition) AND legacy_project_id = \(CockpitDatabase.escaped(legacyProjectId))"),
           await projectExists(id: byLegacyId.projectId) {
            return byLegacyId
        }

        if let byFingerprint = try await record(where: "\(completedCondition) AND content_fingerprint = \(CockpitDatabase.escaped(contentFingerprint))"),
           await projectExists(id: byFingerprint.projectId) {
            return byFingerprint
        }

        return nil
    }

    /// Begin tracking an import with status `in_progress`.
    func startImport(
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
        INSERT INTO legacy_imports (id, source_path, legacy_project_id, manifest_id, content_fingerprint, project_id, status, started_at, imported_at)
        VALUES (\(CockpitDatabase.escaped(id)),
                \(CockpitDatabase.escaped(normalizedPath)),
                \(legacyProjectId.map(CockpitDatabase.escaped) ?? "NULL"),
                \(manifestId.map(CockpitDatabase.escaped) ?? "NULL"),
                \(CockpitDatabase.escaped(contentFingerprint)),
                \(CockpitDatabase.escaped(projectId)),
                \(CockpitDatabase.escaped(LegacyImportStatus.inProgress.rawValue)),
                \(CockpitDatabase.escaped(now)),
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
            status: .inProgress,
            errorMessage: nil,
            startedAt: now,
            completedAt: nil,
            importedAt: now
        )
    }

    /// Mark an import as completed.
    func completeImport(id: String) async throws {
        let now = Self.isoTimestamp()
        try await db.execute("""
            UPDATE legacy_imports
            SET status = \(CockpitDatabase.escaped(LegacyImportStatus.completed.rawValue)),
                completed_at = \(CockpitDatabase.escaped(now)),
                error_message = NULL
            WHERE id = \(CockpitDatabase.escaped(id));
        """)
    }

    /// Mark an import as failed with an optional error message.
    func failImport(id: String, errorMessage: String?) async throws {
        let now = Self.isoTimestamp()
        let message = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await db.execute("""
            UPDATE legacy_imports
            SET status = \(CockpitDatabase.escaped(LegacyImportStatus.failed.rawValue)),
                error_message = \(message.map(CockpitDatabase.escaped) ?? "NULL"),
                completed_at = \(CockpitDatabase.escaped(now))
            WHERE id = \(CockpitDatabase.escaped(id));
        """)
    }

    /// Remove any import tracking rows for a project. Used when a project is deleted.
    func deleteImports(projectId: String) async throws {
        try await db.execute("""
            DELETE FROM legacy_imports
            WHERE project_id = \(CockpitDatabase.escaped(projectId));
        """)
    }

    func getImport(id: String) async throws -> LegacyImportRecord? {
        let rows = try await db.query("""
            SELECT id, source_path, legacy_project_id, manifest_id, content_fingerprint, project_id,
                   status, error_message, started_at, completed_at, imported_at
            FROM legacy_imports
            WHERE id = \(CockpitDatabase.escaped(id))
            LIMIT 1;
        """)
        return rows.first.flatMap(Self.record(from:))
    }

    // MARK: - Private helpers

    private func projectExists(id: String) async -> Bool {
        let rows = try? await db.query("""
            SELECT 1 FROM projects WHERE id = \(CockpitDatabase.escaped(id)) LIMIT 1;
        """)
        return rows?.isEmpty == false
    }

    private func record(where condition: String) async throws -> LegacyImportRecord? {
        let sql = """
            SELECT id, source_path, legacy_project_id, manifest_id, content_fingerprint, project_id,
                   status, error_message, started_at, completed_at, imported_at
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
              let statusRaw = row["status"],
              let startedAt = row["started_at"],
              let importedAt = row["imported_at"]
        else { return nil }
        return LegacyImportRecord(
            id: id,
            sourcePath: sourcePath,
            legacyProjectId: row["legacy_project_id"],
            manifestId: row["manifest_id"],
            contentFingerprint: contentFingerprint,
            projectId: projectId,
            status: LegacyImportStatus(rawValue: statusRaw) ?? .failed,
            errorMessage: row["error_message"],
            startedAt: startedAt,
            completedAt: row["completed_at"],
            importedAt: importedAt
        )
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

enum LegacyImportStatus: String, Codable, Sendable {
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
}

struct LegacyImportRecord: Codable, Identifiable, Sendable {
    let id: String
    let sourcePath: String
    let legacyProjectId: String?
    let manifestId: String?
    let contentFingerprint: String
    let projectId: String
    let status: LegacyImportStatus
    let errorMessage: String?
    let startedAt: String
    let completedAt: String?
    let importedAt: String
}
