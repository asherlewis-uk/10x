import Foundation
import SQLite3

enum CockpitDatabaseError: LocalizedError {
    case openFailed(path: String)
    case execFailed(sql: String, message: String)
    case queryFailed(sql: String, message: String)
    case migrationMissing(version: String)
    case migrationCorrupted(version: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path):
            return "Failed to open SQLite database at \(path)"
        case .execFailed(let sql, let message):
            return "SQL execution failed: \(message)\nSQL: \(sql)"
        case .queryFailed(let sql, let message):
            return "SQL query failed: \(message)\nSQL: \(sql)"
        case .migrationMissing(let version):
            return "Missing migration \(version)"
        case .migrationCorrupted(let version):
            return "Migration \(version) produced an error"
        }
    }
}

/// Low-level SQLite connection wrapper for the 11x local cockpit.
/// Runs migrations from bundled SQL files and tracks applied versions in
/// `schema_migrations`.
actor CockpitDatabase {
    nonisolated static let databaseFileName = "cockpit.sqlite"

    static var shared: CockpitDatabase = {
        try! CockpitDatabase(url: defaultDatabaseURL())
    }()

    private let db: OpaquePointer
    private let path: String

    /// Use this to create isolated test databases.
    init(url: URL) throws {
        let path = url.path
        self.path = path

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var db: OpaquePointer?
        let status = sqlite3_open_v2(
            path,
            &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK, let opened = db else {
            throw CockpitDatabaseError.openFailed(path: path)
        }
        self.db = opened

        try Self.enableWAL(db: opened)
        try Self.createMigrationsTable(db: opened)
        try Self.applyBundledMigrations(db: opened)
    }

    deinit {
        sqlite3_close(db)
    }

    /// Run a statement that does not return rows. Safe for DDL and DML.
    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard status == SQLITE_OK else {
            let message = String(cString: errorMessage!)
            throw CockpitDatabaseError.execFailed(sql: sql, message: message)
        }
    }

    /// Run a SELECT and return rows as column-name to value dictionaries.
    func query(_ sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw CockpitDatabaseError.queryFailed(sql: sql, message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let columnCount = sqlite3_column_count(stmt)
        var columnNames: [String] = []
        for i in 0..<Int(columnCount) {
            columnNames.append(String(cString: sqlite3_column_name(stmt, Int32(i))))
        }

        var rows: [[String: String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<Int(columnCount) {
                let name = columnNames[i]
                if let cString = sqlite3_column_text(stmt, Int32(i)) {
                    row[name] = String(cString: cString)
                } else {
                    row[name] = nil
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Run an INSERT/UPDATE/DELETE and return the last inserted row id.
    @discardableResult
    func executeReturningRowID(_ sql: String) throws -> Int64 {
        try execute(sql)
        return sqlite3_last_insert_rowid(db)
    }

    /// Escape a string literal for safe inclusion in raw SQL. Prefer parameters.
    nonisolated static func escaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    nonisolated static func defaultDatabaseURL() -> URL {
        AppIdentity.appSupportDirectory.appendingPathComponent(databaseFileName)
    }

    // MARK: - Private helpers

    private nonisolated static func enableWAL(db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard status == SQLITE_OK else {
            throw CockpitDatabaseError.execFailed(sql: "PRAGMA journal_mode = WAL;", message: String(cString: errorMessage!))
        }
    }

    private nonisolated static func createMigrationsTable(db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let sql = """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version TEXT PRIMARY KEY NOT NULL,
            applied_at TEXT NOT NULL
        );
        """
        let status = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard status == SQLITE_OK else {
            throw CockpitDatabaseError.execFailed(sql: sql, message: String(cString: errorMessage!))
        }
    }

    private nonisolated static func appliedMigrations(db: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        let sql = "SELECT version FROM schema_migrations;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw CockpitDatabaseError.queryFailed(sql: sql, message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var versions: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            versions.insert(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return versions
    }

    private nonisolated static func applyBundledMigrations(db: OpaquePointer) throws {
        let migrations = bundledMigrationSQL()
        let applied = try appliedMigrations(db: db)

        for (version, sql) in migrations.sorted(by: { $0.key < $1.key }) {
            guard !applied.contains(version) else { continue }

            var errorMessage: UnsafeMutablePointer<CChar>?
            let status = sqlite3_exec(db, sql, nil, nil, &errorMessage)
            defer { sqlite3_free(errorMessage) }
            guard status == SQLITE_OK else {
                throw CockpitDatabaseError.migrationCorrupted(version: version)
            }

            let markSQL = """
            INSERT INTO schema_migrations (version, applied_at)
            VALUES (\(escaped(version)), \(escaped(isoTimestamp())));
            """
            let markStatus = sqlite3_exec(db, markSQL, nil, nil, &errorMessage)
            defer { sqlite3_free(errorMessage) }
            guard markStatus == SQLITE_OK else {
                throw CockpitDatabaseError.migrationCorrupted(version: version)
            }
        }
    }

    private nonisolated static func bundledMigrationSQL() -> [String: String] {
        MigrationSet.migrations
    }

    private nonisolated static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
