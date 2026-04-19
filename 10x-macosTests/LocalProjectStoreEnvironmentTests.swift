import Foundation
import XCTest
@testable import TenXAppCore

final class LocalProjectStoreEnvironmentTests: XCTestCase {
    func testLoadEnvironmentVariablesRepairsStaleClientDotEnvFromMetadata() async throws {
        let store = LocalProjectStore()
        let projectName = "Env Repair \(UUID().uuidString)"
        let projectId = UUID().uuidString

        addTeardownBlock {
            await store.deleteProjectData(projectName: projectName, projectId: projectId)
            ProjectKeychainStore.removeStoredValues(projectId: projectId)
        }

        await store.saveEnvironmentVariables(
            [
                ProjectEnvironmentVariable(
                    key: "SUPABASE_URL",
                    description: "Supabase URL",
                    value: "https://correct.supabase.co",
                    scope: .client
                ),
                ProjectEnvironmentVariable(
                    key: "SUPABASE_PUBLISHABLE_KEY",
                    description: "Supabase key",
                    value: "sb_publishable_correct",
                    scope: .client
                ),
            ],
            projectName: projectName,
            projectId: projectId
        )

        let dotEnvURL = LocalProjectStore.projectRootDirectory(projectName: projectName, projectId: projectId)
            .appendingPathComponent(".env.local")
        try """
        # scope: client
        SUPABASE_URL=https://stale.supabase.co
        """.write(to: dotEnvURL, atomically: true, encoding: .utf8)

        let loaded = await store.loadEnvironmentVariables(projectName: projectName, projectId: projectId)
        let repairedDotEnv = try String(contentsOf: dotEnvURL, encoding: .utf8)

        XCTAssertEqual(
            loaded.first(where: { $0.key == "SUPABASE_URL" })?.value,
            "https://correct.supabase.co"
        )
        XCTAssertEqual(
            loaded.first(where: { $0.key == "SUPABASE_PUBLISHABLE_KEY" })?.value,
            "sb_publishable_correct"
        )
        XCTAssertTrue(repairedDotEnv.contains("SUPABASE_URL=https://correct.supabase.co"))
        XCTAssertTrue(repairedDotEnv.contains("SUPABASE_ANON_KEY=sb_publishable_correct"))
        XCTAssertTrue(repairedDotEnv.contains("SUPABASE_PUBLISHABLE_KEY=sb_publishable_correct"))
    }

    func testLoadEnvironmentVariablesRestoresHostedSecretValuesFromKeychain() async throws {
        let store = LocalProjectStore()
        let projectName = "Hosted Secret \(UUID().uuidString)"
        let projectId = UUID().uuidString

        addTeardownBlock {
            await store.deleteProjectData(projectName: projectName, projectId: projectId)
            ProjectKeychainStore.removeStoredValues(projectId: projectId)
        }

        await store.saveEnvironmentVariables(
            [
                ProjectEnvironmentVariable(
                    key: "SUPABASE_URL",
                    description: "Supabase URL",
                    value: "https://correct.supabase.co",
                    scope: .client
                ),
                ProjectEnvironmentVariable(
                    key: "OPENAI_API_KEY",
                    description: "OpenAI",
                    value: "sk-test-secret",
                    scope: .hosted
                ),
            ],
            projectName: projectName,
            projectId: projectId
        )

        let loaded = await store.loadEnvironmentVariables(projectName: projectName, projectId: projectId)

        XCTAssertEqual(
            loaded.first(where: { $0.key == "OPENAI_API_KEY" })?.value,
            "sk-test-secret"
        )
        XCTAssertEqual(
            ProjectKeychainStore.value(projectId: projectId, key: "OPENAI_API_KEY"),
            "sk-test-secret"
        )
    }
}
