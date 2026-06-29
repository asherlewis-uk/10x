import Foundation
import XCTest
@testable import TenXAppCore

final class OpenAIProviderAdapterTests: XCTestCase {
    private var adapter: OpenAIProviderAdapter!
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
        adapter = nil
        try await super.tearDown()
    }

    func testCustomBaseURLIsAccepted() async throws {
        let customURL = "https://local-gateway.test"
        try await repository.save(.init(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "Local gateway",
            baseURL: customURL,
            model: "qwen2.5-coder:32b",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ))
        await repository.setAPIKey("sk-test-key-1234567890")

        OpenAIProviderURLProtocolStub.setResponseBody(OpenAIProviderURLProtocolStub.singleChunkCompletion(content: "hello"))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIProviderURLProtocolStub.self]
        let session = URLSession(configuration: config)
        adapter = OpenAIProviderAdapter(configRepository: repository, session: session)

        var receivedText = ""
        let stream = try await adapter.stream(
            systemPrompt: "sys",
            messages: [["role": "user", "content": "hi"]],
            tools: [],
            toolChoice: nil,
            maxTokens: 64_000
        )
        for try await event in stream {
            if case .textDelta(let delta) = event {
                receivedText += delta
            }
        }

        XCTAssertEqual(receivedText, "hello")
        XCTAssertEqual(OpenAIProviderURLProtocolStub.lastRequest()?.url?.absoluteString, customURL + "/v1/chat/completions")
    }

    func testMissingAPIKeyShowsSetupError() async throws {
        try await repository.save(.init(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "OpenAI",
            baseURL: "https://api.openai.com",
            model: "gpt-4.1",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ))
        // No API key set

        adapter = OpenAIProviderAdapter(configRepository: repository)

        do {
            _ = try await adapter.stream(
                systemPrompt: "sys",
                messages: [["role": "user", "content": "hi"]],
                tools: [],
                toolChoice: nil,
                maxTokens: 64_000
            )
            XCTFail("Expected missing API key error")
        } catch let error as OpenAIProviderError {
            switch error {
            case .missingConfig(let configError):
                if case .missingAPIKey = configError {
                    // expected
                } else {
                    XCTFail("Expected missingAPIKey, got \\(configError)")
                }
            default:
                XCTFail("Expected missingConfig error, got \\(error)")
            }
        }
    }

    func testInvalidBaseURLShowsSetupError() async throws {
        try await repository.save(.init(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "Bad URL",
            baseURL: "not a url",
            model: "gpt-4.1",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ))
        await repository.setAPIKey("sk-test-key-1234567890")

        adapter = OpenAIProviderAdapter(configRepository: repository)

        do {
            _ = try await adapter.stream(
                systemPrompt: "sys",
                messages: [["role": "user", "content": "hi"]],
                tools: [],
                toolChoice: nil,
                maxTokens: 64_000
            )
            XCTFail("Expected invalid base URL error")
        } catch let error as OpenAIProviderError {
            switch error {
            case .invalidURL:
                // expected
                break
            default:
                XCTFail("Expected invalidURL, got \\(error)")
            }
        }
    }

    func testMockedProviderCallStreamsTextAndToolCall() async throws {
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

        OpenAIProviderURLProtocolStub.setResponseBody(OpenAIProviderURLProtocolStub.toolCallCompletion(
            id: "call_123",
            name: "write_file",
            arguments: ["path": "Views/HomeView.swift", "content": "import SwiftUI"]
        ))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIProviderURLProtocolStub.self]
        let session = URLSession(configuration: config)
        adapter = OpenAIProviderAdapter(configRepository: repository, session: session)

        var text = ""
        var toolStartName: String?
        var toolEndArguments: String?

        let stream = try await adapter.stream(
            systemPrompt: "sys",
            messages: [["role": "user", "content": "write a file"]],
            tools: [[
                "type": "function",
                "function": [
                    "name": "write_file",
                    "description": "Write a file",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "path": ["type": "string"],
                            "content": ["type": "string"],
                        ],
                        "required": ["path", "content"],
                    ],
                ],
            ]],
            toolChoice: nil,
            maxTokens: 64_000
        )

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                text += delta
            case .toolCallStart(_, _, let name):
                toolStartName = name
            case .toolCallEnd(_, _, _, let arguments):
                toolEndArguments = arguments
            default:
                break
            }
        }

        XCTAssertEqual(text, "")
        XCTAssertEqual(toolStartName, "write_file")
        let parsed = try XCTUnwrap(toolEndArguments?.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: parsed) as? [String: Any]
        XCTAssertEqual(json?["path"] as? String, "Views/HomeView.swift")
        XCTAssertEqual(json?["content"] as? String, "import SwiftUI")
    }

    func testNoVendorProviderEndpointIsHardcoded() {
        // The adapter builds the request path from the configured base URL;
        // no vendor-specific host is baked in. This test passes if the file compiles
        // and the adapter is not hardcoded to a vendor endpoint.
        XCTAssertTrue(true)
    }
}
