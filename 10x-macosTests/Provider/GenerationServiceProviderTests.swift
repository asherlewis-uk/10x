import Foundation
import XCTest
@testable import TenXAppCore

final class GenerationServiceProviderTests: XCTestCase {
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

    func testGenerationUsesProviderAdapterNotCredits() async throws {
        try await repository.save(.init(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "Mock",
            baseURL: "https://api.mock.local",
            model: "mock-model",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ))
        await repository.setAPIKey("sk-test-key-1234567890")

        OpenAIProviderURLProtocolStub.reset()
        OpenAIProviderURLProtocolStub.setResponseBody(OpenAIProviderURLProtocolStub.singleChunkCompletion(content: "done"))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIProviderURLProtocolStub.self]
        let session = URLSession(configuration: config)
        let adapter = OpenAIProviderAdapter(configRepository: repository, session: session)

        let service = GenerationService(providerAdapter: adapter)

        let contentBox = SendableBox("")
        let outcome = await service.runGeneration(
            systemPrompt: "sys",
            claudeMessages: [["role": "user", "content": "hi"]],
            tools: [],
            toolExecutor: ToolExecutor(workspaceRoot: FileManager.default.temporaryDirectory, projectName: "Test", targetName: "Test", currentMode: .build),
            accessToken: "unused-token",
            projectId: "proj-123",
            sessionId: "sess-123",
            billingGroupId: "billing-123",
            billingMessagePreview: "preview",
            onEvent: { event in
                if case .content(let delta) = event {
                    contentBox.value += delta
                }
            }
        )

        switch outcome {
        case .completed:
            break
        case .failed(let message):
            XCTFail("Expected completed, got failed: \(message)")
        }
        XCTAssertEqual(contentBox.value, "done")

        // The request should go to the configured provider, not a vendor backend.
        let requestURL = OpenAIProviderURLProtocolStub.lastRequest()?.url?.absoluteString ?? ""
        XCTAssertTrue(requestURL.hasPrefix("https://api.mock.local"), "Expected mock provider URL, got \(requestURL)")
        XCTAssertFalse(requestURL.contains("10x.app"))
        XCTAssertFalse(requestURL.contains("supabase"))
    }
}


final class SendableBox: @unchecked Sendable {
    var value: String
    init(_ value: String) {
        self.value = value
    }
}
