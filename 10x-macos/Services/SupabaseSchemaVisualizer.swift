import Foundation

struct SupabaseSchemaPreview: Equatable, Sendable {
    struct Table: Identifiable, Equatable, Sendable {
        let schema: String
        let name: String
        let columns: [String]

        var id: String { schema == "public" ? name : "\(schema).\(name)" }
        var displayName: String { id }
    }

    struct Migration: Identifiable, Equatable, Sendable {
        let relativePath: String
        let fileName: String
        let sql: String

        var id: String { relativePath }
    }

    let tables: [Table]
    let migrations: [Migration]
    let scannedFileCount: Int
    let sourceSummary: String
    let emptyStateMessage: String?
    let bootstrapCommand: String?

    var isEmpty: Bool {
        tables.isEmpty
    }

    var tableCount: Int {
        tables.count
    }

    var migrationCount: Int {
        migrations.count
    }

    func mergingMetadata(from other: SupabaseSchemaPreview) -> SupabaseSchemaPreview {
        SupabaseSchemaPreview(
            tables: tables,
            migrations: migrations.isEmpty ? other.migrations : migrations,
            scannedFileCount: scannedFileCount == 0 ? other.scannedFileCount : scannedFileCount,
            sourceSummary: sourceSummary,
            emptyStateMessage: emptyStateMessage,
            bootstrapCommand: bootstrapCommand ?? other.bootstrapCommand
        )
    }

    static func isUserVisibleTable(schema: String, name: String) -> Bool {
        !managedSchemas.contains(schema.lowercased()) && !managedTableIDs.contains("\(schema.lowercased()).\(name.lowercased())")
    }

    private static let managedSchemas: Set<String> = [
        "auth",
        "extensions",
        "graphql",
        "graphql_public",
        "information_schema",
        "net",
        "pg_catalog",
        "pgmq",
        "realtime",
        "storage",
        "supabase_functions",
        "supabase_migrations",
        "vault",
    ]

    private static let managedTableIDs: Set<String> = [
        "public.schema_migrations",
    ]
}

enum SupabaseSchemaVisualizer {
    static func load(from projectRoot: URL?) -> SupabaseSchemaPreview {
        guard let projectRoot else {
            return SupabaseSchemaPreview(
                tables: [],
                migrations: [],
                scannedFileCount: 0,
                sourceSummary: "",
                emptyStateMessage: "Open a local project to inspect Supabase migrations.",
                bootstrapCommand: nil
            )
        }

        let fileManager = FileManager.default
        let supabaseDirectory = projectRoot.appendingPathComponent("supabase", isDirectory: true)
        guard fileManager.fileExists(atPath: supabaseDirectory.path) else {
            return SupabaseSchemaPreview(
                tables: [],
                migrations: [],
                scannedFileCount: 0,
                sourceSummary: "",
                emptyStateMessage: "No local supabase folder found in this project.",
                bootstrapCommand: nil
            )
        }

        let migrationDirectory = supabaseDirectory.appendingPathComponent("migrations", isDirectory: true)
        var sqlFiles: [URL] = []

        if fileManager.fileExists(atPath: migrationDirectory.path) {
            sqlFiles.append(contentsOf: recursiveSQLFiles(in: migrationDirectory))
        }

        sqlFiles.append(contentsOf: directSQLFiles(in: supabaseDirectory))

        let uniqueFiles = Array(Set(sqlFiles)).sorted(by: { lhs, rhs in
            lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        })

        guard !uniqueFiles.isEmpty else {
            return SupabaseSchemaPreview(
                tables: [],
                migrations: [],
                scannedFileCount: 0,
                sourceSummary: "",
                emptyStateMessage: "No local Supabase SQL migrations found yet.",
                bootstrapCommand: "supabase db reset"
            )
        }

        return preview(forSQLFiles: uniqueFiles, projectRoot: projectRoot)
    }

    static func preview(forSQLFiles files: [URL], projectRoot: URL? = nil) -> SupabaseSchemaPreview {
        var tableColumns: [String: [String]] = [:]
        let migrations = files.compactMap { file -> SupabaseSchemaPreview.Migration? in
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            applyStatements(in: contents, to: &tableColumns)
            return SupabaseSchemaPreview.Migration(
                relativePath: relativePath(for: file, projectRoot: projectRoot),
                fileName: file.lastPathComponent,
                sql: contents.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let tables = tableColumns
            .compactMap { identifier, columns -> SupabaseSchemaPreview.Table? in
                let components = tableComponents(for: identifier)
                guard SupabaseSchemaPreview.isUserVisibleTable(schema: components.schema, name: components.name) else {
                    return nil
                }
                return SupabaseSchemaPreview.Table(
                    schema: components.schema,
                    name: components.name,
                    columns: columns
                )
            }
            .sorted(by: { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            })

        let sourceSummary = files.count == 1
            ? "1 SQL file scanned"
            : "\(files.count) SQL files scanned"

        return SupabaseSchemaPreview(
            tables: tables,
            migrations: migrations,
            scannedFileCount: files.count,
            sourceSummary: sourceSummary,
            emptyStateMessage: tables.isEmpty ? "No user-created tables could be parsed from the local SQL files." : nil,
            bootstrapCommand: "supabase db reset"
        )
    }

    private static func applyStatements(in sql: String, to tables: inout [String: [String]]) {
        let lines = sql.components(separatedBy: .newlines)
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]

            if let droppedTable = droppedTableName(in: line) {
                tables.removeValue(forKey: droppedTable)
                lineIndex += 1
                continue
            }

            if let alteration = addedColumn(in: line) {
                appendColumn(alteration.column, to: alteration.table, in: &tables)
                lineIndex += 1
                continue
            }

            if let createdTable = createdTableName(in: line) {
                let body = collectCreateTableBody(startingAt: lineIndex, lines: lines)
                let columns = parsedColumns(fromCreateTableBody: body.bodyLines)
                tables[createdTable] = columns
                lineIndex = body.endLineIndex + 1
                continue
            }

            lineIndex += 1
        }
    }

    private static func collectCreateTableBody(
        startingAt startLineIndex: Int,
        lines: [String]
    ) -> (bodyLines: [String], endLineIndex: Int) {
        var bodyLines: [String] = []
        var balance = 0
        var foundOpeningParen = false
        var lineIndex = startLineIndex

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if line.contains("(") {
                foundOpeningParen = true
            }

            if foundOpeningParen, lineIndex > startLineIndex {
                bodyLines.append(line)
            }

            balance += line.filter { $0 == "(" }.count
            balance -= line.filter { $0 == ")" }.count

            if foundOpeningParen, balance <= 0 {
                break
            }

            lineIndex += 1
        }

        return (bodyLines, lineIndex)
    }

    private static func parsedColumns(fromCreateTableBody lines: [String]) -> [String] {
        var columns: [String] = []

        for line in lines {
            guard let column = columnName(in: line) else { continue }
            if !columns.contains(column) {
                columns.append(column)
            }
        }

        return columns
    }

    private static func appendColumn(_ column: String, to table: String, in tables: inout [String: [String]]) {
        var columns = tables[table] ?? []
        if !columns.contains(column) {
            columns.append(column)
        }
        tables[table] = columns
    }

    private static func createdTableName(in line: String) -> String? {
        capture(
            pattern: #"(?i)^\s*create\s+table\s+(?:if\s+not\s+exists\s+)?((?:"?[A-Za-z0-9_]+"?\.)?"?[A-Za-z0-9_]+"?)"#,
            in: line
        ).map(normalizedIdentifier)
    }

    private static func droppedTableName(in line: String) -> String? {
        capture(
            pattern: #"(?i)^\s*drop\s+table\s+(?:if\s+exists\s+)?((?:"?[A-Za-z0-9_]+"?\.)?"?[A-Za-z0-9_]+"?)"#,
            in: line
        ).map(normalizedIdentifier)
    }

    private static func addedColumn(in line: String) -> (table: String, column: String)? {
        guard let table = capture(
            pattern: #"(?i)^\s*alter\s+table\s+(?:only\s+)?((?:"?[A-Za-z0-9_]+"?\.)?"?[A-Za-z0-9_]+"?)\s+add\s+column\s+(?:if\s+not\s+exists\s+)?"?([A-Za-z_][A-Za-z0-9_]*)"?\b"#,
            in: line,
            group: 1
        ) else {
            return nil
        }

        guard let column = capture(
            pattern: #"(?i)^\s*alter\s+table\s+(?:only\s+)?((?:"?[A-Za-z0-9_]+"?\.)?"?[A-Za-z0-9_]+"?)\s+add\s+column\s+(?:if\s+not\s+exists\s+)?"?([A-Za-z_][A-Za-z0-9_]*)"?\b"#,
            in: line,
            group: 2
        ) else {
            return nil
        }

        return (normalizedIdentifier(table), normalizedIdentifier(column))
    }

    private static func columnName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        let ignoredPrefixes = [
            "--",
            "constraint ",
            "primary key",
            "foreign key",
            "unique ",
            "check ",
            "exclude ",
            ")",
        ]

        guard !ignoredPrefixes.contains(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }

        return capture(
            pattern: #"^\s*"?(?<name>[A-Za-z_][A-Za-z0-9_]*)"?\s+"#,
            in: line
        ).map(normalizedIdentifier)
    }

    private static func capture(pattern: String, in line: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              let range = Range(match.range(at: group), in: line) else {
            return nil
        }
        return String(line[range])
    }

    private static func normalizedIdentifier(_ rawIdentifier: String) -> String {
        rawIdentifier
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tableComponents(for identifier: String) -> (schema: String, name: String) {
        let normalized = normalizedIdentifier(identifier)
        let parts = normalized.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0].lowercased(), parts[1].lowercased())
        }
        return ("public", normalized.lowercased())
    }

    private static func relativePath(for file: URL, projectRoot: URL?) -> String {
        guard let projectRoot else { return file.lastPathComponent }
        let standardizedRoot = projectRoot.standardizedFileURL.path
        let standardizedFile = file.standardizedFileURL.path
        let basePath = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
        if standardizedFile.hasPrefix(basePath) {
            return String(standardizedFile.dropFirst(basePath.count))
        }
        return file.lastPathComponent
    }

    private static func recursiveSQLFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let fileURL = item as? URL,
                  fileURL.pathExtension.lowercased() == "sql" else {
                return nil
            }
            return fileURL
        }
    }

    private static func directSQLFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { $0.pathExtension.lowercased() == "sql" }
    }
}
