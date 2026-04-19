import Foundation
import XCTest
@testable import TenXAppCore

final class SupabaseSchemaVisualizerTests: XCTestCase {
    func testVisualizerParsesTablesAcrossMigrations() throws {
        let root = try makeTemporaryProjectRoot()
        let migrations = root.appendingPathComponent("supabase/migrations", isDirectory: true)
        try FileManager.default.createDirectory(at: migrations, withIntermediateDirectories: true)

        try """
        create table public.profiles (
          id uuid primary key,
          username text not null
        );
        """.write(
            to: migrations.appendingPathComponent("001_profiles.sql"),
            atomically: true,
            encoding: .utf8
        )

        try """
        alter table public.profiles add column avatar_url text;
        create table tasks (
          id uuid primary key,
          title text
        );
        create table storage.objects (
          id uuid primary key
        );
        """.write(
            to: migrations.appendingPathComponent("002_more.sql"),
            atomically: true,
            encoding: .utf8
        )

        let preview = SupabaseSchemaVisualizer.load(from: root)

        XCTAssertEqual(preview.scannedFileCount, 2)
        XCTAssertEqual(preview.tableCount, 2)
        XCTAssertEqual(preview.migrationCount, 2)
        XCTAssertEqual(preview.bootstrapCommand, "supabase db reset")
        XCTAssertEqual(preview.tables.map(\.displayName), ["profiles", "tasks"])
        XCTAssertEqual(preview.tables.first(where: { $0.displayName == "profiles" })?.columns, ["id", "username", "avatar_url"])
        XCTAssertEqual(preview.tables.first(where: { $0.name == "tasks" })?.columns, ["id", "title"])
        XCTAssertEqual(preview.migrations.map(\.fileName), ["001_profiles.sql", "002_more.sql"])
        XCTAssertEqual(preview.migrations.last?.relativePath, "supabase/migrations/002_more.sql")
    }

    func testVisualizerHandlesMissingSupabaseFolder() throws {
        let root = try makeTemporaryProjectRoot()

        let preview = SupabaseSchemaVisualizer.load(from: root)

        XCTAssertTrue(preview.tables.isEmpty)
        XCTAssertTrue(preview.migrations.isEmpty)
        XCTAssertEqual(preview.emptyStateMessage, "No local supabase folder found in this project.")
    }

    private func makeTemporaryProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}
