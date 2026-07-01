import XCTest
@testable import TenXAppCore

final class LocalCockpitUXTests: XCTestCase {
    private var database: CockpitDatabase!

    override func setUp() async throws {
        try await super.setUp()
        database = try CockpitDatabase(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("cockpit.sqlite")
        )
    }

    // MARK: - Local mode badge

    func testLocalBadgeReflectsLocalCockpit() {
        XCTAssertEqual(AppIdentity.localBadgeTitle, "11x")
        let details = AppIdentity.localBadgeDetails
        XCTAssertTrue(details.contains("Single-user cockpit"), "Badge should mention single-user cockpit")
        XCTAssertTrue(details.contains("Unlimited local"), "Badge should mention unlimited local")
        XCTAssertTrue(details.contains("Local workspace"), "Badge should mention local workspace")
    }

    // MARK: - Billing/credit/pricing UI absence

    func testSettingsSectionsAre11xLocalCockpit() {
        let rawValues = Set(SettingsSection.allCases.map(\.rawValue))
        XCTAssertTrue(rawValues.contains("General"), "General section must exist")
        XCTAssertTrue(rawValues.contains("Provider"), "Provider section must exist")
        XCTAssertTrue(rawValues.contains("Storage"), "Storage section must exist")
        XCTAssertTrue(rawValues.contains("Diagnostics"), "Diagnostics section must exist")
        XCTAssertTrue(rawValues.contains("About"), "About section must exist")
        XCTAssertFalse(rawValues.contains("Billing"), "Billing section must not exist in settings")
        XCTAssertFalse(rawValues.contains("Plans"), "Plans section must not exist in settings")
        XCTAssertFalse(rawValues.contains("Account"), "Account section must not exist in settings")
        XCTAssertFalse(rawValues.contains("Subscription"), "Subscription section must not exist in settings")
    }

    func testAppTabUsesSettingsNotAccount() {
        let projectTab = AppTab.project(name: "Test", projectId: "1")
        let settingsTab = AppTab.settings()
        XCTAssertEqual(projectTab.kind, .project)
        XCTAssertEqual(settingsTab.kind, .settings)
        XCTAssertEqual(settingsTab.label, "Settings")
        XCTAssertEqual(settingsTab.icon, "gearshape")
        // Account/billing tab kinds no longer exist.
    }



    // MARK: - Home branding

    func testHomeDoesNotUse10xBranding() {
        let source = try! String(contentsOfFile: "10x-macos/Views/HomeView.swift")
        XCTAssertFalse(source.contains("10XbuilderLogo"), "HomeView must not reference the 10XbuilderLogo asset")
    }

    func testHomeSamplePromptsExcludeBillingVocabulary() {
        let source = try! String(contentsOfFile: "10x-macos/Views/HomeView.swift")
        let lower = source.lowercased()
        let banned = ["subscription", "billing", "credits", "paywall", "upgrade", "checkout"]
        for word in banned {
            XCTAssertFalse(
                lower.contains(word),
                "Home sample prompts must not include billing vocabulary: \"(word)\""
            )
        }
    }

    func testHomeEmptyStateInvitesBuilding() {
        let source = try! String(contentsOfFile: "10x-macos/Views/HomeView.swift")
        let lower = source.lowercased()
        XCTAssertTrue(
            lower.contains("no projects yet") || lower.contains("start building"),
            "Home empty state should invite the user to start building"
        )
    }

    func testLocalEntitlementsDisableMonetization() {
        XCTAssertFalse(LocalEntitlements.billingEnabled)
        XCTAssertFalse(LocalEntitlements.creditsEnabled)
        XCTAssertFalse(LocalEntitlements.canPurchaseCredits)
        XCTAssertFalse(LocalEntitlements.paymentsEnabled)
        XCTAssertFalse(LocalEntitlements.usageTrackingGatesFeatures)
        XCTAssertEqual(LocalEntitlements.creditsRemaining, .infinity)
    }

    // MARK: - Provider setup

    func testMissingProviderKeyProducesSetupError() async throws {
        let repository = ProviderConfigRepository(database: database)
        ProviderKeychainStore.testServiceOverride = "app.kasey.11x.test.provider"
        defer {
            ProviderKeychainStore.remove(for: "OPENAI_API_KEY")
            ProviderKeychainStore.testServiceOverride = nil
        }
        ProviderKeychainStore.remove(for: "OPENAI_API_KEY")

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
            XCTAssertTrue(
                error.localizedDescription.contains("Settings"),
                "Error should direct user to Settings: \(error.localizedDescription)"
            )
        }
    }

    func testProviderPublicMetadataExcludesKey() {
        let config = ProviderConfig(
            id: ProviderConfigRepository.defaultConfigID,
            providerType: .openAICompatible,
            displayName: "Test",
            baseURL: "https://api.example.invalid",
            model: "gpt-test",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let metadata = config.publicMetadata()
        XCTAssertNil(metadata["api_key"])
        XCTAssertNil(metadata["OPENAI_API_KEY"])
        XCTAssertEqual(metadata["base_url"] as? String, "https://api.example.invalid")
        XCTAssertEqual(metadata["model"] as? String, "gpt-test")
    }

    // MARK: - Local export / storage path

    func testLocalAssetStoragePathIsUnderAppSupport() {
        let url = LocalAssetStorage.defaultAssetRootURL()
        let path = url.path
        XCTAssertTrue(path.contains("Application Support/11x"), "Asset root should be under 11x app support: \(path)")
        XCTAssertTrue(path.hasSuffix("/assets"), "Asset root should end with assets: \(path)")
    }

    func testLocalExportRootIsNotGatedByBilling() {
        let exportRoot = AppIdentity.appSupportDirectory.appendingPathComponent("exports", isDirectory: true)
        XCTAssertTrue(exportRoot.path.contains("/11x/"))
        XCTAssertFalse(LocalEntitlements.canUseBilling)
        XCTAssertTrue(LocalEntitlements.canExport)
    }

    // MARK: - No login requirement

    @MainActor
    func testAuthManagerCreatesLocalProfileWithoutRemoteLogin() async {
        let auth = AuthManager()
        await auth.loadLocalProfile()
        XCTAssertTrue(auth.isAuthenticated, "Local profile should authenticate without remote login")
        XCTAssertNotNil(auth.userId)
        let token = await auth.validAccessToken()
        XCTAssertNotNil(token)
    }

    @MainActor
    func testFirstProjectCanBeCreatedWithoutRemoteLogin() async throws {
        let auth = AuthManager()
        await auth.loadLocalProfile()
        guard let _ = await auth.validAccessToken(), let userId = auth.userId else {
            XCTFail("Local profile did not produce token")
            return
        }

        let projects = ProjectRepository(database: database)
        let project = try await projects.createProject(userId: userId, name: "First Local Project")
        XCTAssertEqual(project.name, "First Local Project")
        XCTAssertEqual(project.userId, userId)

        let loaded = try await projects.getProject(id: project.id)
        XCTAssertEqual(loaded?.name, "First Local Project")
    }



    // MARK: - Builder / Review reframe

    func testChatViewsDoNotContainBillingLanguage() {
        let panelSource = try! String(contentsOfFile: "10x-macos/Views/Chat/ChatPanelView.swift")
        let inputSource = try! String(contentsOfFile: "10x-macos/Views/Chat/ChatInputView.swift")
        let combined = (panelSource + inputSource).lowercased()
        let banned = ["billing", "credits", "paywall", "upgrade", "subscribe", "purchase", "checkout", "plans & packs"]
        for word in banned {
            XCTAssertFalse(
                combined.contains(word),
                "Chat views must not contain billing vocabulary: \"\(word)\""
            )
        }
    }

    func testReviewViewUsesLocalExportLanguage() {
        let source = try! String(contentsOfFile: "10x-macos/Views/Preview/ReviewView.swift")
        let lower = source.lowercased()
        XCTAssertFalse(
            lower.contains("app store submission generation is not available"),
            "ReviewView should not repeat disabled-SaaS framing"
        )
        XCTAssertFalse(
            lower.contains("hosted publishing is not available"),
            "ReviewView should not use disabled-SaaS language"
        )
        XCTAssertFalse(
            lower.contains("marketing assets"),
            "ReviewView should refer to review assets, not marketing assets"
        )
        XCTAssertTrue(
            lower.contains("export locally") || lower.contains("export the packet") || lower.contains("your own workflow") || lower.contains("release pipeline"),
            "ReviewView should surface local export language"
        )
        XCTAssertTrue(
            lower.contains("exportappsubmissionpacket") || lower.contains("export submission packet") || lower.contains("export packet"),
            "ReviewView should expose export submission packet action"
        )
    }

    func testProjectStatePersistsAfterReload() async throws {
        let projects = ProjectRepository(database: database)
        let profile = try await ProfileRepository(database: database).loadOrCreateProfile()

        let project = try await projects.createProject(userId: profile.id, name: "Reload Test")

        // Simulate a fresh repository reading the same database
        let secondRead = ProjectRepository(database: database)
        let loaded = try await secondRead.getProject(id: project.id)
        XCTAssertEqual(loaded?.name, "Reload Test")
        XCTAssertEqual(loaded?.status, "active")
    }
}
