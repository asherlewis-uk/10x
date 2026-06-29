import Foundation
import XCTest
@testable import TenXAppCore

final class ProviderConfigRepositoryTests: XCTestCase {
    private var repository: ProviderConfigRepository!
    private var database: CockpitDatabase!

    override func setUp() async throws {
        try await super.setUp()
        database = try CockpitDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent("\\(UUID().uuidString).sqlite"))
        repository = ProviderConfigRepository(database: database)
        ProviderKeychainStore.testServiceOverride = "app.kasey.11x.test.provider"
        ProviderKeychainStore.remove(for: "OPENAI_API_KEY")
    }

    override func tearDown() async throws {
        ProviderKeychainStore.remove(for: "OPENAI_API_KEY")
        ProviderKeychainStore.testServiceOverride = nil
        try await super.tearDown()
    }

    func testSaveAndLoadConfig() async throws {
        let config = ProviderConfig(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "Test Provider",
            baseURL: "https://api.openai.com",
            model: "gpt-4.1",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await repository.save(config)

        let loaded = await repository.loadConfig()
        XCTAssertEqual(loaded?.baseURL, "https://api.openai.com")
        XCTAssertEqual(loaded?.model, "gpt-4.1")
        XCTAssertEqual(loaded?.displayName, "Test Provider")
    }

    func testAPIKeyIsStoredInKeychain() async throws {
        await repository.setAPIKey("sk-secret-12345")
        let apiKey = await repository.apiKey()
        XCTAssertEqual(apiKey, "sk-secret-12345")
    }

    func testValidatedConfigRequiresKey() async throws {
        try await repository.save(.init(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "Test",
            baseURL: "https://api.openai.com",
            model: "gpt-4.1",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ))

        do {
            _ = try await repository.validatedConfig()
            XCTFail("Expected missing API key error")
        } catch let error as ProviderConfigError {
            XCTAssertEqual(error, .missingAPIKey)
        }
    }

    func testPublicMetadataExcludesAPIKey() async throws {
        let config = ProviderConfig(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "Test",
            baseURL: "https://api.openai.com",
            model: "gpt-4.1",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let metadata = config.publicMetadata()
        XCTAssertEqual(metadata["base_url"] as? String, "https://api.openai.com")
        XCTAssertEqual(metadata["model"] as? String, "gpt-4.1")
        XCTAssertNil(metadata["api_key"])
        XCTAssertNil(metadata["OPENAI_API_KEY"])
    }
}
