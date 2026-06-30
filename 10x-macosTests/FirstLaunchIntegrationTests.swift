import Foundation
import XCTest
@testable import TenXAppCore

/// End-to-end regression test covering the first-launch local cockpit flow:
/// fresh database, local profile, provider configuration, project creation,
/// mocked generation, and persistence across a simulated restart.
@MainActor
final class FirstLaunchIntegrationTests: XCTestCase {
    private var database: CockpitDatabase!
    private var databaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("first-launch.sqlite")
        database = try CockpitDatabase(url: databaseURL)
        ProviderKeychainStore.testServiceOverride = "app.kasey.11x.test.first-launch"
        ProviderKeychainStore.remove(for: "OPENAI_API_KEY")
    }

    override func tearDown() async throws {
        ProviderKeychainStore.remove(for: "OPENAI_API_KEY")
        ProviderKeychainStore.testServiceOverride = nil
        try await super.tearDown()
    }

    func testFirstLaunchLocalSetupFlow() async throws {
        // 1. App boots with no Supabase/Superwall config.
        XCTAssertTrue(Config.supabaseURL.isEmpty)
        XCTAssertTrue(Config.supabaseAnonKey.isEmpty)
        XCTAssertTrue(Config.hostedAppsBaseURL.isEmpty)
        XCTAssertTrue(Config.sparkleFeedURL.isEmpty)
        XCTAssertFalse(LocalEntitlements.canUseHostedVendorBackend)
        XCTAssertFalse(LocalEntitlements.canUseBilling)

        // 2. Create local profile without remote login.
        let auth = AuthManager()
        await auth.loadLocalProfile()
        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertNotNil(auth.userId)
        let accessToken = await auth.validAccessToken()
        XCTAssertNotNil(accessToken)

        // 3. Configure provider with custom base URL.
        let providerRepository = ProviderConfigRepository(database: database)
        let customBaseURL = "https://local-gateway.test"
        try await providerRepository.save(.init(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "Local gateway",
            baseURL: customBaseURL,
            model: "qwen2.5-coder:32b",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ))
        await providerRepository.setAPIKey("sk-test-key-1234567890")
        let loadedConfig = await providerRepository.loadConfig()
        XCTAssertEqual(loadedConfig?.baseURL, customBaseURL)

        // 4. Create first project.
        guard let userId = auth.userId else {
            XCTFail("Local profile missing user id")
            return
        }
        let projects = ProjectRepository(database: database)
        let project = try await projects.createProject(userId: userId, name: "First Launch Project")
        XCTAssertEqual(project.name, "First Launch Project")
        XCTAssertEqual(project.status, "active")

        // 5. Run mocked generation.
        OpenAIProviderURLProtocolStub.reset()
        OpenAIProviderURLProtocolStub.setResponseBody(
            OpenAIProviderURLProtocolStub.singleChunkCompletion(content: "hello local cockpit")
        )

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIProviderURLProtocolStub.self]
        let session = URLSession(configuration: config)
        let adapter = OpenAIProviderAdapter(configRepository: providerRepository, session: session)
        let service = GenerationService(providerAdapter: adapter)

        let contentBox = SendableBox("")
        let outcome = await service.runGeneration(
            systemPrompt: "sys",
            claudeMessages: [["role": "user", "content": "hi"]],
            tools: [],
            toolExecutor: ToolExecutor(
                workspaceRoot: FileManager.default.temporaryDirectory,
                projectName: project.name,
                targetName: project.name,
                currentMode: .build
            ),
            accessToken: "unused-token",
            projectId: project.id,
            sessionId: "sess-1",
            billingGroupId: "",
            billingMessagePreview: nil,
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
            XCTFail("Expected completed generation, got failed: \(message)")
        }
        XCTAssertEqual(contentBox.value, "hello local cockpit")

        // 6. Persist generation history.
        let versions = VersionRepository(database: database)
        let version = try await versions.createVersion(
            projectId: project.id,
            conversationId: "chat-1",
            fileTree: ["App.swift": "// generated"],
            prompt: "Build an app"
        )
        XCTAssertEqual(version.versionNumber, 1)

        // 7. Simulate quit/reopen by reconnecting to the same database file.
        let restartedDB = try CockpitDatabase(url: databaseURL)
        let restartedProjects = ProjectRepository(database: restartedDB)
        let restartedVersions = VersionRepository(database: restartedDB)

        let reloadedProject = try await restartedProjects.getProject(id: project.id)
        XCTAssertEqual(reloadedProject?.name, "First Launch Project")

        let reloadedVersions = try await restartedVersions.fetchVersions(projectId: project.id)
        XCTAssertEqual(reloadedVersions.count, 1)
        XCTAssertEqual(reloadedVersions.first?.prompt, "Build an app")
    }
}
