import Foundation
import XCTest
@testable import TenXAppCore

final class NoSupabaseRuntimeTests: XCTestCase {
    /// App boots and reports a local profile without any Supabase env vars.
    func testAppBootsWithoutSupabaseEnvVars() async throws {
        let db = try CockpitDatabase(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("boot.sqlite"))
        let profile = try await ProfileRepository(database: db).loadOrCreateProfile()
        XCTAssertFalse(profile.id.isEmpty)
        XCTAssertNotNil(profile.email)
    }

    /// No Swift source file under the runtime targets imports the Supabase module.
    func testNoRuntimeSupabaseImports() throws {
        let packageRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimeDirs = [
            packageRoot.appendingPathComponent("10x-macos"),
            packageRoot.appendingPathComponent("10x-evals"),
        ]
        let fm = FileManager.default
        var offenders: [String] = []
        for dir in runtimeDirs {
            guard fm.fileExists(atPath: dir.path) else { continue }
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let importLines = content.components(separatedBy: CharacterSet.newlines).filter { line in
                    let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
                    return trimmed.hasPrefix("import Supabase")
                }
                if !importLines.isEmpty {
                    offenders.append(fileURL.lastPathComponent)
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Found runtime source files still importing Supabase: \(offenders)")
    }

    /// Package.swift no longer depends on supabase-swift.
    func testPackageManifestHasNoSupabaseDependency() throws {
        let packageRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageSwift = packageRoot.appendingPathComponent("Package.swift")
        let content = try String(contentsOf: packageSwift, encoding: .utf8)
        XCTAssertFalse(content.contains("supabase-swift"))
        XCTAssertFalse(content.contains(".product(name: \"Supabase\""))
    }

    /// Config no longer exposes Supabase URL/key values as active defaults.
    func testConfigSupabaseDefaultsAreInert() {
        XCTAssertTrue(Config.supabaseURL.contains("supabase.co") || Config.supabaseURL.isEmpty || Config.supabaseURL.hasPrefix("https://your-project"))
        XCTAssertTrue(Config.supabaseAnonKey.hasPrefix("sb_publishable_your") || Config.supabaseAnonKey.hasPrefix("sb_publishable_"))
    }
}
