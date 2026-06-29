import XCTest
@testable import TenXAppCore

final class ProjectIntegrationSupportTests: XCTestCase {
    private let validLegacyOpenAIKey = "sk-" + String(repeating: "a", count: 48)
    private let validProjectScopedOpenAIKey = "sk-proj-" + String(repeating: "a", count: 120)

    func testSupabaseClientKeysAreNotMarkedSensitive() {
        XCTAssertFalse(ProjectEnvironmentSecurity.isSensitive(key: "SUPABASE_URL"))
        XCTAssertFalse(ProjectEnvironmentSecurity.isSensitive(key: "SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertFalse(ProjectEnvironmentSecurity.isSensitive(key: "SUPABASE_ANON_KEY"))
        XCTAssertFalse(ProjectEnvironmentSecurity.isSensitive(key: "SUPERWALL_PUBLIC_API_KEY"))
    }

    func testManagedAdminSupabaseValuesStaySensitive() {
        XCTAssertTrue(ProjectEnvironmentSecurity.isSensitive(key: "SUPABASE_MANAGEMENT_TOKEN"))
        XCTAssertTrue(ProjectEnvironmentSecurity.isSensitive(key: "SUPABASE_DB_PASSWORD"))
        XCTAssertTrue(ProjectEnvironmentSecurity.isSensitive(key: "SUPABASE_DB_URL"))
        XCTAssertTrue(ProjectEnvironmentSecurity.isSensitive(key: "OPENAI_API_KEY"))
    }

    func testPublicPrefixesOverrideHeuristic() {
        XCTAssertFalse(ProjectEnvironmentSecurity.isSensitive(key: "PUBLIC_GOOGLE_CLIENT_ID"))
        XCTAssertFalse(ProjectEnvironmentSecurity.isSensitive(key: "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"))
        XCTAssertFalse(ProjectEnvironmentSecurity.isSensitive(key: "VITE_SUPABASE_URL"))
    }

    func testToolEnvironmentOmitsSecretsButKeepsClientSafeValues() {
        let environment = ProjectEnvironmentSecurity.toolEnvironment(from: [
            ProjectEnvironmentVariable(key: "OPENAI_API_KEY", value: "sk-test"),
            ProjectEnvironmentVariable(key: "SUPABASE_ANON_KEY", value: "sb_publishable_test"),
            ProjectEnvironmentVariable(key: "SUPABASE_PUBLISHABLE_KEY", value: "sb_publishable_test"),
            ProjectEnvironmentVariable(key: "SUPERWALL_PUBLIC_API_KEY", value: "pk_test_123"),
        ])

        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertEqual(environment["SUPABASE_ANON_KEY"], "sb_publishable_test")
        XCTAssertEqual(environment["SUPABASE_PUBLISHABLE_KEY"], "sb_publishable_test")
        XCTAssertEqual(environment["SUPERWALL_PUBLIC_API_KEY"], "pk_test_123")
    }

    func testChatSecretWarningBlocksOpenAIKeyPastes() {
        let warning = ProjectEnvironmentSecurity.secretPasteWarning(in: validProjectScopedOpenAIKey)

        XCTAssertEqual(
            warning,
            "Don't paste `OPENAI_API_KEY` into chat. Chat messages are persisted with the project conversation. Add it in Integrations under Hosted Keys instead; 10x syncs hosted values to Supabase secrets and keeps them out of project files and generated source."
        )
    }

    func testChatSecretWarningBlocksSensitiveAssignments() {
        let warning = ProjectEnvironmentSecurity.secretPasteWarning(
            in: "SUPABASE_MANAGEMENT_TOKEN = super-secret-management-token"
        )

        XCTAssertEqual(
            warning,
            "Don't paste `SUPABASE_MANAGEMENT_TOKEN` into chat. Chat messages are persisted with the project conversation. Add server-side values in Integrations under Hosted Keys instead so 10x can sync them to Supabase secrets."
        )
    }

    func testChatSecretWarningIgnoresPlaceholderExamples() {
        XCTAssertNil(ProjectEnvironmentSecurity.secretPasteWarning(in: "OPENAI_API_KEY=sk-..."))
    }

    func testBundledSupabaseSkillIsAvailableLocally() {
        let skill = BundledSkillsCatalog.skill(named: "supabase")

        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.name, "supabase")
        XCTAssertTrue(skill?.content.contains("enabling or connecting the built-in Supabase integration") == true)
        XCTAssertTrue(skill?.content.contains("Do not ask the user to manually paste `SUPABASE_URL` or `SUPABASE_PUBLISHABLE_KEY`.") == true)
        XCTAssertTrue(skill?.content.contains("Sign in with Apple") == true)
        XCTAssertTrue(skill?.content.contains("Sign in with Google") == true)
        XCTAssertTrue(skill?.content.contains("Email-only") == true)
        XCTAssertTrue(skill?.content.contains("which auth type to start with first") == true)
        XCTAssertTrue(skill?.content.contains("temporary dev bypass for now") == true)
        XCTAssertTrue(skill?.content.contains("storage buckets") == true)
        XCTAssertTrue(skill?.content.contains("Do not silently fall back to `SampleData`") == true)
        XCTAssertTrue(skill?.content.contains("disable Confirm Email by default") == true)
        XCTAssertTrue(skill?.content.contains("Prefer the official Supabase Swift SDK") == true)
        XCTAssertTrue(skill?.content.contains("do not only say \"configure Supabase.\"") == true)
        XCTAssertTrue(skill?.content.contains("Auth > URL Configuration") == true)
        XCTAssertTrue(skill?.content.contains("Email confirmation is managed in Supabase") == true)
    }

    func testBundledBackendSkillIsAvailableLocally() {
        let skill = BundledSkillsCatalog.skill(named: "backend")

        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.name, "backend")
        XCTAssertTrue(skill?.content.contains("Managed Supabase backend work belongs in the `Backend` workspace") == true)
        XCTAssertTrue(skill?.content.contains("Use `backend_manage`") == true)
        XCTAssertTrue(skill?.content.contains("Do not build a generic open proxy") == true)
        XCTAssertTrue(skill?.content.contains("Ask for approval before deploys") == true)
    }

    func testBuilderPromptsPreferSupabaseIntegrationFlowOverManualKeys() {
        let prompt = BuilderPrompts.systemPrompt(mode: .build)

        XCTAssertTrue(
            prompt.contains("Prefer the built-in Supabase connect flow")
        )
        XCTAssertTrue(
            prompt.contains("Do not ask them to manually type `SUPABASE_URL` or `SUPABASE_PUBLISHABLE_KEY` unless they choose to edit them there.")
        )
        XCTAssertTrue(
            prompt.contains("Managed Supabase backend work belongs in Backend, not Integrations. Load `backend` before using `backend_manage`.")
        )
        XCTAssertTrue(
            prompt.contains("Never ask the user to paste API keys, tokens, or secrets into chat.")
        )
        XCTAssertTrue(
            prompt.contains("Integrations has separate Client Keys and Hosted Keys.")
        )
        XCTAssertTrue(
            prompt.contains("Default to a mock/local-first first pass unless the user explicitly asks for a real integration now.")
        )
        XCTAssertTrue(
            prompt.contains("Do not open a brand new project by asking about Supabase, Superwall, backend, or secrets.")
        )
        XCTAssertTrue(
            prompt.contains("When the user explicitly asks to wire real Supabase auth, ask which auth type to start with first")
        )
        XCTAssertTrue(
            prompt.contains("save it with `update_project_dependencies`")
        )
        XCTAssertTrue(
            prompt.contains("When the user asks for real auth, paywall/subscription, or backend wiring, call `update_project_dependencies` immediately")
        )
        XCTAssertTrue(
            prompt.contains("use `supabase_manage_settings` with `update_auth` to set `email_confirmations_enabled` to `false`")
        )
        XCTAssertTrue(
            prompt.contains("After saving those real auth/paywall/backend dependencies, stop and wait for the user to configure them")
        )
        XCTAssertTrue(
            prompt.contains("If any required auth/paywall/backend dependency is still unresolved and does not allow mock data, do not continue the real implementation.")
        )
        XCTAssertTrue(
            prompt.contains("do not just say \"configure Supabase.\"")
        )
        XCTAssertTrue(
            prompt.contains("do not mention managed client key names unless the user explicitly asks which keys were added")
        )
        XCTAssertTrue(
            prompt.contains("Do not use filler narration such as \"Let me check\"")
        )
        XCTAssertFalse(
            prompt.contains("prefer the built-in Connect Supabase flow, which imports `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`")
        )
        XCTAssertFalse(
            prompt.contains("Required Skills Selected By User")
        )
    }

    func testBuilderPromptsLoadBackendSkillWhenBackendWorkIsInScope() {
        let prompt = BuilderPrompts.systemPrompt(mode: .build)

        XCTAssertTrue(
            prompt.contains("Backend, serverless, webhook, secret-backed API, or Supabase Edge Function requests should load `backend`.")
        )
        XCTAssertTrue(
            prompt.contains("If the request fits the managed Supabase backend path, use Backend dependencies instead of warning that all production backend work is unsupported.")
        )
    }

    func testBuilderPromptsTreatAIModelsSkillAsCurrentAuthority() {
        let prompt = BuilderPrompts.systemPrompt(mode: .build)

        XCTAssertTrue(
            prompt.contains("AI/provider requests like OpenAI, Anthropic, Claude, Groq, ElevenLabs, model selection, chat completions, responses API, TTS, or STT should load `ai-models`.")
        )
        XCTAssertTrue(
            prompt.contains("do not rely on stale model memory before loading `ai-models`")
        )
    }

    func testPlanPromptDefaultsToMockFirstBeforeIntegrations() {
        let prompt = BuilderPrompts.systemPrompt(mode: .plan)

        XCTAssertTrue(
            prompt.contains("Do not ask Supabase, Superwall, backend, or auth setup questions in the initial batch.")
        )
        XCTAssertTrue(
            prompt.contains("Default the first version to mock/local data unless the user explicitly asks for real integrations now.")
        )
        XCTAssertTrue(
            prompt.contains("Use an empty dependency list for mock-first MVPs.")
        )
        XCTAssertTrue(
            prompt.contains("If the MVP is mock/local-first, mention that only as a short implementation note, not the headline or first bullet")
        )
        XCTAssertTrue(
            prompt.contains("do not center the follow-up summary on deferred integrations or mock data")
        )
    }

    @MainActor
    func testEmptyDependencyManifestDoesNotShowDependencyChecklist() {
        let viewModel = BuilderViewModel()
        viewModel.projectDependencyManifest = ProjectDependencyManifest(dependencies: [])

        XCTAssertFalse(viewModel.hasDependencyChecklist)
    }

    func testPlanPromptRequiresExplicitApprovalBeforeSwitchingToBuild() {
        let prompt = BuilderPrompts.systemPrompt(mode: .plan)

        XCTAssertTrue(
            prompt.contains("Switch to build mode only after the user explicitly approves the plan or clearly asks you to start building.")
        )
        XCTAssertTrue(
            prompt.contains("Do not call `change_mode` just because the plan feels complete.")
        )
        XCTAssertTrue(
            prompt.contains("wait for explicit build approval")
        )
    }

    func testBuilderPromptContextTreatsNewProjectNameAsWorkingTitle() {
        let context = BuilderPrompts.messageContext(
            mode: .build,
            projectName: "AI calorie tracker from photos",
            currentFileTree: [:],
            plan: nil
        )
        let prefix = context.prefixMessages.joined(separator: "\n")

        XCTAssertTrue(prefix.contains("auto-generated working title"))
        XCTAssertTrue(prefix.contains("Still include the naming question in the initial `ask_user` batch"))
        XCTAssertTrue(prefix.contains("offer 2-4 short name ideas"))
    }

    func testBuilderPromptContextIncludesSupabaseSetupGuidance() {
        let context = BuilderPrompts.messageContext(
            mode: .build,
            projectName: "Wanderlist",
            currentFileTree: [:],
            plan: nil,
            environmentVariables: [
                ProjectEnvironmentVariable(key: "SUPABASE_URL", value: "https://abc123.supabase.co"),
                ProjectEnvironmentVariable(key: "SUPABASE_PUBLISHABLE_KEY", value: "sb_publishable_test"),
            ]
        )
        let prefix = context.prefixMessages.joined(separator: "\n")

        XCTAssertTrue(prefix.contains("## Project Supabase"))
        XCTAssertTrue(prefix.contains("https://supabase.com/dashboard/project/abc123/auth/providers"))
        XCTAssertTrue(prefix.contains("https://supabase.com/dashboard/project/abc123/auth/url-configuration"))
        XCTAssertFalse(prefix.contains("## Project Superwall"))
        XCTAssertFalse(prefix.contains("https://superwall.com/applications/app_1/rules"))
        XCTAssertTrue(prefix.contains("Tell the user exactly what is managed where"))
        XCTAssertTrue(prefix.contains("do not recite these variable names unless the user explicitly asks which keys are present"))
    }

    func testBuilderProjectDecodesDependencyManifestFromSettings() {
        let manifest = ProjectDependencyManifest(
            dependencies: [
                ProjectDependencyRequirement(
                    id: "supabase",
                    title: "Supabase",
                    summary: "Connect Supabase for auth and database.",
                    integrationID: .supabase,
                    envKeys: ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"],
                    safety: .clientRuntime,
                    allowsMockDataUntilConfigured: true
                ),
            ]
        )
        let project = BuilderProject(
            id: "project-1",
            userId: "user-1",
            name: "Iron",
            description: nil,
            slug: "iron",
            platform: "swiftui",
            status: "active",
            currentVersionId: nil,
            settings: [
                BuilderProject.dependencyManifestSettingsKey: AnyCodableValue.encode(manifest) ?? .null,
            ],
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )

        XCTAssertEqual(project.dependencyManifest, manifest)
    }

    func testBundledRegistryIncludesLocalSkills() {
        let names = Set(BundledSkillsCatalog.registry.map(\.name))

        XCTAssertTrue(names.contains("ai-models"))
        XCTAssertTrue(names.contains("backend"))
        XCTAssertTrue(names.contains("supabase"))
        XCTAssertFalse(names.contains("superwall"))
    }

    func testManagedIntegrationsExposeExpectedFields() {
        let openAI = ProjectIntegrations.definition(for: .openAI)
        let supabase = ProjectIntegrations.definition(for: .supabase)
        let openAIFields = Set(openAI.fields.map(\.envKey))
        let supabaseFields = Set(supabase.fields.map(\.envKey))

        XCTAssertEqual(openAIFields, Set(["OPENAI_API_KEY"]))
        XCTAssertEqual(supabaseFields, Set(["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY"]))
        XCTAssertEqual(Set(openAI.hostedFields.map(\.envKey)), Set(["OPENAI_API_KEY"]))
        XCTAssertEqual(Set(openAI.clientFields.map(\.envKey)), Set<String>())
        XCTAssertEqual(Set(supabase.clientFields.map(\.envKey)), supabaseFields)
        XCTAssertTrue(supabase.hostedFields.isEmpty)
        XCTAssertFalse(openAIFields.contains("OPENAI_BASE_URL"))
        XCTAssertFalse(openAIFields.contains("OPENAI_MODEL"))
        XCTAssertFalse(supabaseFields.contains("SUPABASE_MANAGEMENT_TOKEN"))
        XCTAssertFalse(supabaseFields.contains("SUPABASE_DB_PASSWORD"))
        XCTAssertFalse(supabaseFields.contains("SUPABASE_DB_URL"))
    }

    func testSetupGuidanceDisappearsOnceManagedIntegrationIsConfigured() {
        let openAI = ProjectIntegrations.definition(for: .openAI)
        let supabase = ProjectIntegrations.definition(for: .supabase)

        XCTAssertFalse(openAI.visibleGuidanceSections(values: [:]).isEmpty)
        XCTAssertTrue(
            openAI.visibleGuidanceSections(values: ["OPENAI_API_KEY": validLegacyOpenAIKey]).isEmpty
        )

        XCTAssertFalse(supabase.visibleGuidanceSections(values: [:]).isEmpty)
    }

    func testOpenAIIntegrationRejectsTruncatedLegacyKey() {
        let openAI = ProjectIntegrations.definition(for: .openAI)
        let status = openAI.capabilityStatuses(values: ["OPENAI_API_KEY": "sk-short"]).first

        XCTAssertEqual(status?.label, "Backend OpenAI Key")
        XCTAssertEqual(status?.isReady, false)
        XCTAssertTrue(status?.detail.contains("51 characters") == true)
    }

    func testOpenAIIntegrationAcceptsProjectScopedKeyShape() {
        let openAI = ProjectIntegrations.definition(for: .openAI)
        let status = openAI.capabilityStatuses(values: ["OPENAI_API_KEY": validProjectScopedOpenAIKey]).first

        XCTAssertEqual(status?.label, "Backend OpenAI Key")
        XCTAssertEqual(status?.isReady, true)
        XCTAssertEqual(status?.detail, "Backend OpenAI API key is configured.")
    }

    func testOpenAIIntegrationExplainsSafeStorage() {
        let openAI = ProjectIntegrations.definition(for: .openAI)

        XCTAssertEqual(
            openAI.fields.first?.description,
            "Backend OpenAI API key synced to Supabase secrets. Use it for backend or server-side work, not client code."
        )
        XCTAssertTrue(openAI.fields.first?.helperText.contains("not in chat") == true)
        XCTAssertTrue(openAI.guidanceSections.first?.markdown.contains("not in chat") == true)
        XCTAssertTrue(openAI.guidanceSections.first?.markdown.contains("Supabase secrets") == true)
        XCTAssertEqual(openAI.fields.first?.scope, .hosted)
        XCTAssertTrue(ProjectIntegrations.definition(for: .supabase).fields.allSatisfy { $0.scope == .client })
    }

    func testOpenAIIntegrationAcceptsRemoteHostedKey() {
        let openAI = ProjectIntegrations.definition(for: .openAI)
        let status = openAI.capabilityStatuses(
            values: [:],
            remoteHostedKeys: ["OPENAI_API_KEY"]
        ).first

        XCTAssertEqual(status?.isReady, true)
        XCTAssertEqual(status?.detail, "Backend OpenAI API key is configured in Supabase.")
    }

    func testExplicitClientScopeOverridesSensitiveKeyHeuristic() {
        let environment = ProjectEnvironmentSecurity.toolEnvironment(from: [
            ProjectEnvironmentVariable(
                key: "STRIPE_PUBLISHABLE_KEY",
                value: "pk_test_123",
                scope: .client
            )
        ])

        XCTAssertEqual(environment["STRIPE_PUBLISHABLE_KEY"], "pk_test_123")
    }

    func testIntegrationGuidanceAvoidsEmbeddedCodeSnippets() {
        let supabaseGuidance = ProjectIntegrations.definition(for: .supabase).guidanceSections.map(\.markdown).joined(separator: "\n")
        let openAIGuidance = ProjectIntegrations.definition(for: .openAI).guidanceSections.map(\.markdown).joined(separator: "\n")

        XCTAssertFalse(supabaseGuidance.contains("```"))
        XCTAssertFalse(openAIGuidance.contains("```"))
    }

    func testManagedIntegrationMergePreservesDescriptions() {
        let existing = [
            ProjectEnvironmentVariable(
                id: "existing-supabase-url",
                key: "SUPABASE_URL",
                description: "old",
                value: "https://old.supabase.co"
            ),
            ProjectEnvironmentVariable(
                id: "custom-key",
                key: "FEATURE_FLAG",
                description: "Existing custom flag",
                value: "enabled"
            ),
        ]

        let merged = ProjectIntegrations.mergedVariables(
            managedDrafts: [
                .supabase: [
                    "SUPABASE_URL": "https://next.supabase.co",
                    "SUPABASE_ANON_KEY": "sb_publishable_test",
                    "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
                ],
            ],
            customVariables: [
                ProjectEnvironmentVariable(
                    id: "custom-key",
                    key: "FEATURE_FLAG",
                    description: "Existing custom flag",
                    value: "enabled"
                )
            ],
            existingVariables: existing
        )

        let supabaseURL = merged.first { $0.key == "SUPABASE_URL" }
        let anonKey = merged.first { $0.key == "SUPABASE_ANON_KEY" }
        let publishableKey = merged.first { $0.key == "SUPABASE_PUBLISHABLE_KEY" }
        let custom = merged.first { $0.key == "FEATURE_FLAG" }

        XCTAssertEqual(supabaseURL?.id, "existing-supabase-url")
        XCTAssertEqual(
            supabaseURL?.description,
            "Client-side Supabase project URL saved in the project's `.env.local`."
        )
        XCTAssertEqual(
            anonKey?.description,
            "Client-side Supabase anon key saved in the project's `.env.local`."
        )
        XCTAssertEqual(
            publishableKey?.description,
            "Client-side Supabase publishable key alias saved in the project's `.env.local` for compatibility."
        )
        XCTAssertEqual(custom?.description, "Existing custom flag")
    }

    func testSupabaseCapabilityAcceptsAnonKeyAlias() {
        let supabase = ProjectIntegrations.definition(for: .supabase)
        let status = supabase.capabilityStatuses(
            values: [
                "SUPABASE_URL": "https://example.supabase.co",
                "SUPABASE_ANON_KEY": "sb_publishable_test",
            ]
        ).first

        XCTAssertEqual(status?.isReady, true)
    }

    func testManagedIntegrationMergePreservesRemoteHostedMetadata() {
        let merged = ProjectIntegrations.mergedVariables(
            managedDrafts: [.openAI: [:]],
            customVariables: [],
            existingVariables: [
                ProjectEnvironmentVariable(
                    id: "openai",
                    key: "OPENAI_API_KEY",
                    description: "Backend OpenAI API key synced to Supabase secrets. Use it for backend or server-side work, not client code.",
                    value: "",
                    scope: .hosted
                )
            ],
            remoteHostedKeys: ["OPENAI_API_KEY"]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.key, "OPENAI_API_KEY")
        XCTAssertEqual(merged.first?.value, "")
        XCTAssertEqual(merged.first?.scope, .hosted)
    }

    func testDisplayVariablesSurfaceRemoteCustomBackendSecrets() {
        let displayed = ProjectIntegrations.displayVariables(
            existingVariables: [],
            backendState: ProjectBackendState(
                secrets: [
                    .init(name: "STRIPE_SECRET_KEY", updatedAt: "2026-04-17T10:00:00Z"),
                    .init(name: "OPENAI_API_KEY", updatedAt: "2026-04-17T10:00:00Z")
                ]
            )
        )

        let customVariables = ProjectIntegrations.customVariables(from: displayed)
        let stripeSecret = customVariables.first { $0.key == "STRIPE_SECRET_KEY" }
        let openAISecret = customVariables.first { $0.key == "OPENAI_API_KEY" }

        XCTAssertEqual(stripeSecret?.scope, .hosted)
        XCTAssertEqual(stripeSecret?.value, "")
        XCTAssertNil(openAISecret)
        XCTAssertTrue(displayed.contains(where: { $0.key == "OPENAI_API_KEY" && $0.scope == .hosted }))
    }

    func testDisplayVariablesSeedSupabaseURLFromBackendLink() {
        let displayed = ProjectIntegrations.displayVariables(
            existingVariables: [],
            backendState: ProjectBackendState(
                providerID: .supabase,
                linkedProjectRef: "proj123",
                linkedProjectURL: "https://proj123.supabase.co"
            )
        )

        let supabaseURL = displayed.first { $0.key == "SUPABASE_URL" }

        XCTAssertEqual(supabaseURL?.value, "https://proj123.supabase.co")
        XCTAssertEqual(supabaseURL?.scope, .client)
    }

    func testSupabaseIntegrationRemovesObsoleteBackendWarning() {
        let warning = BuilderProjectWarning(
            title: "Backend limitation",
            requestedCapability: "Production backend or cloud services from scratch",
            message: "10x does not deliver a production backend from scratch.",
            fallback: "Use mocked flows."
        )

        XCTAssertEqual(
            BuilderProjectWarning.normalized([warning], supportsManagedSupabaseBackend: false),
            [warning]
        )
        XCTAssertTrue(
            BuilderProjectWarning.normalized([warning], supportsManagedSupabaseBackend: true).isEmpty
        )
    }

    func testManagedSupabaseBackendDoesNotClearOpenProxyWarning() {
        let warning = BuilderProjectWarning(
            title: "Backend limitation",
            requestedCapability: "Production backend or cloud services from scratch",
            message: "Open proxy backends are still unsupported.",
            fallback: "Use named endpoints."
        )

        XCTAssertEqual(
            BuilderProjectWarning.normalized([warning], supportsManagedSupabaseBackend: true),
            [warning]
        )
    }

    func testManagedSupabaseBackendClearsSupabaseEdgeFunctionWarning() {
        let warning = BuilderProjectWarning(
            title: "Backend limitation",
            requestedCapability: "Custom backend or cloud services outside supported integrations",
            message: "Supabase Edge Functions are supported through the managed Backend workspace.",
            fallback: "Use Backend for named functions and secrets."
        )

        XCTAssertTrue(
            BuilderProjectWarning.normalized([warning], supportsManagedSupabaseBackend: true).isEmpty
        )
    }

    func testManagedSupabaseBackendDoesNotClearNonSupabaseEdgeFunctionWarning() {
        let warning = BuilderProjectWarning(
            title: "Backend limitation",
            requestedCapability: "Custom backend or cloud services outside supported integrations",
            message: "Cloudflare edge functions are outside the supported integrations.",
            fallback: "Use the managed Supabase backend instead."
        )

        XCTAssertEqual(
            BuilderProjectWarning.normalized([warning], supportsManagedSupabaseBackend: true),
            [warning]
        )
    }

    func testManagedBackendDependencyResolvesOnlyThroughBackendState() {
        let requirement = ProjectDependencyRequirement(
            id: "supabase-backend",
            title: "Supabase Backend",
            summary: "Set up managed backend functions.",
            setupSurface: .backend,
            backendProviderID: .supabase,
            backendCapabilityIDs: ["managed-serverless-backend"],
            envKeys: ["SUPABASE_URL"],
            safety: .backendOnly,
            allowsMockDataUntilConfigured: true
        )
        let variables = [
            ProjectEnvironmentVariable(
                key: "SUPABASE_URL",
                value: "https://example.supabase.co"
            )
        ]

        let unresolved = requirement.resolve(using: variables, backendState: .empty)
        XCTAssertFalse(unresolved.isResolved)
        XCTAssertEqual(unresolved.detail, "Supabase backend still needs setup in Backend.")

        let resolved = requirement.resolve(
            using: variables,
            backendState: ProjectBackendState(
                providerID: .supabase,
                linkedProjectRef: "example",
                linkedProjectURL: "https://example.supabase.co"
            )
        )
        XCTAssertTrue(resolved.isResolved)
        XCTAssertEqual(resolved.detail, "Supabase backend is configured.")
    }
}
