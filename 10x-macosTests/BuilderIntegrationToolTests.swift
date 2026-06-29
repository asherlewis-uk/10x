import Foundation
import XCTest
@testable import TenXAppCore

final class BuilderIntegrationToolTests: XCTestCase {
    func testDependencyUpdateToolAppearsInPlanAndBuildModes() {
        let planTools = Set(
            BuilderToolDefinitions.tools(for: .plan).compactMap { $0["name"] as? String }
        )
        let buildTools = Set(
            BuilderToolDefinitions.tools(for: .build).compactMap { $0["name"] as? String }
        )

        XCTAssertTrue(planTools.contains("update_project_dependencies"))
        XCTAssertTrue(buildTools.contains("update_project_dependencies"))
    }

    func testDependencyUpdateToolSchemaIncludesSafetyAndMockFlags() {
        let tools = BuilderToolDefinitions.tools(for: .plan)
        let tool = tools.first { ($0["name"] as? String) == "update_project_dependencies" }
        let schema = tool?["input_schema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        let dependencies = properties?["dependencies"] as? [String: Any]
        let itemSchema = dependencies?["items"] as? [String: Any]
        let itemProperties = itemSchema?["properties"] as? [String: Any]

        XCTAssertNotNil(itemProperties?["integration_id"])
        XCTAssertNotNil(itemProperties?["setup_surface"])
        XCTAssertNotNil(itemProperties?["backend_provider_id"])
        XCTAssertNotNil(itemProperties?["backend_capability_ids"])
        XCTAssertNotNil(itemProperties?["env_keys"])
        XCTAssertNotNil(itemProperties?["safety"])
        XCTAssertNotNil(itemProperties?["allows_mock_data_until_configured"])
    }

    func testSupabaseToolsAppearOnlyWhenAccessIsAvailable() {
        let withoutSupabase = Set(
            BuilderToolDefinitions.tools(
                for: .build,
                integrationAvailability: .init(hasSupabaseAccess: false)
            ).compactMap { $0["name"] as? String }
        )
        let withSupabase = Set(
            BuilderToolDefinitions.tools(
                for: .build,
                integrationAvailability: .init(hasSupabaseAccess: true)
            ).compactMap { $0["name"] as? String }
        )

        XCTAssertFalse(withoutSupabase.contains("supabase_read_tables"))
        XCTAssertFalse(withoutSupabase.contains("backend_manage"))
        XCTAssertTrue(withSupabase.contains("backend_manage"))
        XCTAssertTrue(withSupabase.contains("supabase_read_tables"))
        XCTAssertTrue(withSupabase.contains("supabase_write_tables"))
        XCTAssertTrue(withSupabase.contains("supabase_execute_sql"))
        XCTAssertTrue(withSupabase.contains("supabase_manage_settings"))
    }

    func testBackendManageSchemaIncludesBackendFields() {
        let tools = BuilderToolDefinitions.tools(
            for: .build,
            integrationAvailability: .init(hasSupabaseAccess: true)
        )
        let tool = tools.first { ($0["name"] as? String) == "backend_manage" }
        let schema = tool?["input_schema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]

        XCTAssertNotNil(properties?["action"])
        XCTAssertNotNil(properties?["provider_id"])
        XCTAssertNotNil(properties?["function_name"])
        XCTAssertNotNil(properties?["verify_jwt"])
        XCTAssertNotNil(properties?["source_code"])
        XCTAssertNotNil(properties?["auth_mode"])
        XCTAssertNotNil(properties?["secret_name"])
        XCTAssertNotNil(properties?["secret_value"])
    }

    func testSupabaseManageSettingsSchemaIncludesEmailConfirmationToggle() {
        let tools = BuilderToolDefinitions.tools(
            for: .build,
            integrationAvailability: .init(hasSupabaseAccess: true)
        )
        let tool = tools.first { ($0["name"] as? String) == "supabase_manage_settings" }
        let schema = tool?["input_schema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]

        XCTAssertNotNil(properties?["email_confirmations_enabled"])
        XCTAssertNotNil(properties?["signups_enabled"])
        XCTAssertNotNil(properties?["phone_enabled"])
        XCTAssertNotNil(properties?["password_min_length"])
        XCTAssertNotNil(properties?["refresh_token_rotation_enabled"])
        XCTAssertNotNil(properties?["rate_limit_email_sent"])
    }

    func testSupabaseToolDescriptionsIncludeStorageGuidance() {
        let tools = BuilderToolDefinitions.tools(
            for: .build,
            integrationAvailability: .init(hasSupabaseAccess: true)
        )
        let readDescription = tools.first { ($0["name"] as? String) == "supabase_read_tables" }?["description"] as? String
        let writeDescription = tools.first { ($0["name"] as? String) == "supabase_write_tables" }?["description"] as? String
        let sqlDescription = tools.first { ($0["name"] as? String) == "supabase_execute_sql" }?["description"] as? String

        XCTAssertTrue(readDescription?.contains("storage.buckets") == true)
        XCTAssertTrue(writeDescription?.contains("storage.buckets") == true)
        XCTAssertTrue(sqlDescription?.contains("storage bucket setup") == true)
    }

    func testSupabaseReadDoesNotRequireApproval() async {
        let executor = makeExecutor()

        let result = await executor.execute(
            toolName: "supabase_read_tables",
            input: ["table": "profiles"]
        )

        XCTAssertEqual(result.text, "read ok")
        XCTAssertNil(result.approvalRequest)
    }

    func testSupabaseWriteRequestsApprovalUntilGranted() async {
        let executor = makeExecutor()

        let initialResult = await executor.execute(
            toolName: "supabase_write_tables",
            input: [
                "table": "profiles",
                "operation": "update",
                "values": ["name": "Ada"],
                "filters": ["id": 1],
            ]
        )

        XCTAssertNotNil(initialResult.approvalRequest)
        XCTAssertEqual(initialResult.approvalRequest?.integration, "supabase")
        XCTAssertEqual(initialResult.approvalRequest?.scope, "write")

        if let approval = initialResult.approvalRequest {
            await executor.grantIntegrationApproval(approval)
        }

        let approvedResult = await executor.execute(
            toolName: "supabase_write_tables",
            input: [
                "table": "profiles",
                "operation": "update",
                "values": ["name": "Ada"],
                "filters": ["id": 1],
            ]
        )

        XCTAssertEqual(approvedResult.text, "write ok")
    }

    func testSupabaseSettingsReadDoesNotRequireApproval() async {
        let executor = makeExecutor()

        let result = await executor.execute(
            toolName: "supabase_manage_settings",
            input: ["action": "describe_auth"]
        )

        XCTAssertEqual(result.text, "settings ok")
        XCTAssertNil(result.approvalRequest)
    }

    func testSupabaseSQLRequiresApprovalUntilGranted() async {
        let executor = makeExecutor()

        let initialResult = await executor.execute(
            toolName: "supabase_execute_sql",
            input: ["sql": "create table profiles (id uuid primary key);"]
        )

        XCTAssertEqual(initialResult.text, "Approval required before run SQL in the connected Supabase project.")
        XCTAssertEqual(initialResult.approvalRequest?.scope, "write")

        if let approval = initialResult.approvalRequest {
            await executor.grantIntegrationApproval(approval)
        }

        let approvedResult = await executor.execute(
            toolName: "supabase_execute_sql",
            input: ["sql": "create table profiles (id uuid primary key);"]
        )

        XCTAssertEqual(approvedResult.text, "sql ok")
    }

    func testSupabaseSettingsWriteRequiresApproval() async {
        let executor = makeExecutor()

        let result = await executor.execute(
            toolName: "supabase_manage_settings",
            input: ["action": "update_auth", "google_enabled": true]
        )

        XCTAssertEqual(result.text, "Approval required before change Supabase auth settings.")
        XCTAssertEqual(result.approvalRequest?.scope, "settings")
    }

    func testBackendDeployRequiresApprovalUntilGranted() async {
        let executor = makeExecutor()

        let initialResult = await executor.execute(
            toolName: "backend_manage",
            input: [
                "action": "deploy",
                "function_name": "ping",
            ]
        )

        XCTAssertEqual(initialResult.text, "Approval required before deploy backend changes to the linked Supabase project.")
        XCTAssertEqual(initialResult.approvalRequest?.integration, "supabase backend")
        XCTAssertEqual(initialResult.approvalRequest?.scope, "deploy")

        if let approval = initialResult.approvalRequest {
            await executor.grantIntegrationApproval(approval)
        }

        let approvedResult = await executor.execute(
            toolName: "backend_manage",
            input: [
                "action": "deploy",
                "function_name": "ping",
            ]
        )

        XCTAssertEqual(approvedResult.text, "deploy ok")
    }

    func testBackendSecretWriteRequiresApprovalUntilGranted() async {
        let executor = makeExecutor()

        let initialResult = await executor.execute(
            toolName: "backend_manage",
            input: [
                "action": "set_secret",
                "secret_name": "STRIPE_SECRET_KEY",
                "secret_value": "sk_test_123",
            ]
        )

        XCTAssertEqual(initialResult.text, "Approval required before create or rotate backend secrets in the linked Supabase project.")
        XCTAssertEqual(initialResult.approvalRequest?.integration, "supabase backend")
        XCTAssertEqual(initialResult.approvalRequest?.scope, "secrets")

        if let approval = initialResult.approvalRequest {
            await executor.grantIntegrationApproval(approval)
        }

        let approvedResult = await executor.execute(
            toolName: "backend_manage",
            input: [
                "action": "set_secret",
                "secret_name": "STRIPE_SECRET_KEY",
                "secret_value": "sk_test_123",
            ]
        )

        XCTAssertEqual(approvedResult.text, "secret ok")
    }

    func testBackendManageStatusUsesConfiguredBackendState() async {
        let executor = makeExecutor(
            backendState: ProjectBackendState(
                providerID: .supabase,
                linkedProjectRef: "proj123",
                linkedProjectURL: "https://proj123.supabase.co"
            )
        )

        let result = await executor.execute(
            toolName: "backend_manage",
            input: ["action": "status"]
        )

        XCTAssertTrue(result.text.contains("Backend provider: Supabase"))
        XCTAssertTrue(result.text.contains("Linked project ref: proj123"))
    }

    func testBackendStatusRefreshStoresRefreshTimestamp() async {
        final class StateBox: @unchecked Sendable {
            var state: ProjectBackendState?
        }

        let box = StateBox()
        let executor = makeExecutor(
            backendToolHandlers: BackendToolHandlers(
                status: {
                    BackendStatusSnapshot(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co",
                        remoteFunctionNames: ["ping"],
                        remoteSecretNames: []
                    )
                },
                linkProvider: {
                    BackendProviderLink(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co"
                    )
                },
                deploy: { _ in "deploy ok" },
                invoke: { _ in "invoke ok" },
                setSecret: { _, _ in "secret ok" },
                listLogs: { _, _ in [] },
                persistState: { state in
                    box.state = state
                }
            )
        )

        _ = await executor.execute(
            toolName: "backend_manage",
            input: ["action": "status"]
        )

        XCTAssertNotNil(box.state?.lastStatusRefreshAt)
    }

    func testBackendInvokeFailurePersistsOpenFailure() async {
        final class StateBox: @unchecked Sendable {
            var state: ProjectBackendState?
        }

        struct StubError: LocalizedError {
            var errorDescription: String? { "Function returned 500" }
        }

        let box = StateBox()
        let executor = makeExecutor(
            backendState: ProjectBackendState(
                providerID: .supabase,
                linkedProjectRef: "proj123",
                linkedProjectURL: "https://proj123.supabase.co",
                functions: [
                    .init(
                        name: "ping",
                        summary: "Health check",
                        verifyJWT: true,
                        sourcePath: "supabase/functions/ping/index.ts",
                        updatedAt: "2026-04-16T12:00:00Z"
                    )
                ]
            ),
            backendToolHandlers: BackendToolHandlers(
                status: {
                    BackendStatusSnapshot(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co",
                        remoteFunctionNames: ["ping"],
                        remoteSecretNames: []
                    )
                },
                linkProvider: {
                    BackendProviderLink(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co"
                    )
                },
                deploy: { _ in "deploy ok" },
                invoke: { _ in throw StubError() },
                setSecret: { _, _ in "secret ok" },
                listLogs: { _, _ in [] },
                persistState: { state in
                    box.state = state
                }
            )
        )

        let result = await executor.execute(
            toolName: "backend_manage",
            input: [
                "action": "invoke",
                "function_name": "ping",
                "request_json": ["hello": "world"],
            ]
        )

        XCTAssertEqual(result.text, "Error: Function returned 500")
        XCTAssertEqual(box.state?.openFailures.count, 1)
        XCTAssertEqual(box.state?.openFailures.first?.functionName, "ping")
    }

    func testBackendInvokeDefaultsToUserJWTAuthMode() async {
        final class CaptureBox: @unchecked Sendable {
            var input: BackendInvokeInput?
        }

        let box = CaptureBox()
        let executor = makeExecutor(
            backendToolHandlers: BackendToolHandlers(
                status: {
                    BackendStatusSnapshot(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co",
                        remoteFunctionNames: ["ping"],
                        remoteSecretNames: []
                    )
                },
                linkProvider: {
                    BackendProviderLink(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co"
                    )
                },
                deploy: { _ in "deploy ok" },
                invoke: { input in
                    box.input = input
                    return "invoke ok"
                },
                setSecret: { _, _ in "secret ok" },
                listLogs: { _, _ in [] },
                persistState: { _ in }
            )
        )

        let result = await executor.execute(
            toolName: "backend_manage",
            input: ["action": "invoke", "function_name": "ping"]
        )

        XCTAssertEqual(result.text, "invoke ok")
        XCTAssertEqual(box.input?.authMode, .userJWT)
    }

    func testBackendInvokeAcceptsExplicitAnonAuthMode() async {
        final class CaptureBox: @unchecked Sendable {
            var input: BackendInvokeInput?
        }

        let box = CaptureBox()
        let executor = makeExecutor(
            backendToolHandlers: BackendToolHandlers(
                status: {
                    BackendStatusSnapshot(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co",
                        remoteFunctionNames: ["ping"],
                        remoteSecretNames: []
                    )
                },
                linkProvider: {
                    BackendProviderLink(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co"
                    )
                },
                deploy: { _ in "deploy ok" },
                invoke: { input in
                    box.input = input
                    return "invoke ok"
                },
                setSecret: { _, _ in "secret ok" },
                listLogs: { _, _ in [] },
                persistState: { _ in }
            )
        )

        let result = await executor.execute(
            toolName: "backend_manage",
            input: [
                "action": "invoke",
                "function_name": "ping",
                "auth_mode": "anon",
            ]
        )

        XCTAssertEqual(result.text, "invoke ok")
        XCTAssertEqual(box.input?.authMode, .anon)
    }

    func testBackendListLogsMergesErrorLogsIntoFailures() async {
        final class StateBox: @unchecked Sendable {
            var state: ProjectBackendState?
        }

        let box = StateBox()
        let errorLog = ProjectBackendLogEntry(
            id: "log_1",
            timestamp: "2026-04-16T12:00:00Z",
            message: "Edge function crashed",
            level: "error",
            functionName: "ping"
        )
        let executor = makeExecutor(
            backendToolHandlers: BackendToolHandlers(
                status: {
                    BackendStatusSnapshot(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co",
                        remoteFunctionNames: ["ping"],
                        remoteSecretNames: []
                    )
                },
                linkProvider: {
                    BackendProviderLink(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co"
                    )
                },
                deploy: { _ in "deploy ok" },
                invoke: { _ in "invoke ok" },
                setSecret: { _, _ in "secret ok" },
                listLogs: { _, _ in [errorLog] },
                persistState: { state in
                    box.state = state
                }
            )
        )

        _ = await executor.execute(
            toolName: "backend_manage",
            input: ["action": "list_logs", "function_name": "ping"]
        )

        XCTAssertEqual(box.state?.openFailures.count, 1)
        XCTAssertEqual(box.state?.openFailures.first?.relatedLogIDs, ["log_1"])
    }

    func testBackendInvokeSuccessResolvesMatchingOpenFailure() async {
        final class StateBox: @unchecked Sendable {
            var state: ProjectBackendState?
        }

        let box = StateBox()
        let executor = makeExecutor(
            backendState: ProjectBackendState(
                providerID: .supabase,
                linkedProjectRef: "proj123",
                linkedProjectURL: "https://proj123.supabase.co",
                functions: [
                    .init(
                        name: "ping",
                        summary: "Health check",
                        verifyJWT: true,
                        sourcePath: "supabase/functions/ping/index.ts",
                        updatedAt: "2026-04-16T12:00:00Z"
                    )
                ],
                recentFailures: [
                    .init(
                        id: "failure_1",
                        functionName: "ping",
                        timestamp: "2026-04-16T11:00:00Z",
                        requestSummary: "{\"hello\":\"world\"}",
                        errorSummary: "Function returned 500",
                        source: .invoke
                    )
                ]
            ),
            backendToolHandlers: BackendToolHandlers(
                status: {
                    BackendStatusSnapshot(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co",
                        remoteFunctionNames: ["ping"],
                        remoteSecretNames: []
                    )
                },
                linkProvider: {
                    BackendProviderLink(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co"
                    )
                },
                deploy: { _ in "deploy ok" },
                invoke: { _ in "invoke ok" },
                setSecret: { _, _ in "secret ok" },
                listLogs: { _, _ in [] },
                persistState: { state in
                    box.state = state
                }
            )
        )

        _ = await executor.execute(
            toolName: "backend_manage",
            input: ["action": "invoke", "function_name": "ping"]
        )

        XCTAssertEqual(box.state?.openFailures.count, 0)
        XCTAssertNotNil(box.state?.recentFailures.first?.resolvedAt)
    }

    func testDependencyUpdateToolAcceptsEmptyManifest() async {
        let executor = makeExecutor()

        let result = await executor.execute(
            toolName: "update_project_dependencies",
            input: ["dependencies": []]
        )

        XCTAssertEqual(result.text, "Project dependencies saved successfully.")
        XCTAssertNil(result.approvalRequest)
    }

    func testEmptyDependencyUpdateLabelIsNeutral() {
        XCTAssertEqual(
            BuilderToolPresentation.detailedLabel(
                name: "update_project_dependencies",
                input: ["dependencies": []]
            ),
            "Confirming no setup requirements"
        )
    }

    func testDependencyUpdateToolAcceptsLooseSupabaseDependencyObject() async {
        let executor = makeExecutor()

        let result = await executor.execute(
            toolName: "update_project_dependencies",
            input: [
                "dependencies": [
                    ["title": "Supabase"],
                ],
            ]
        )

        XCTAssertEqual(result.text, "Project dependencies saved successfully.")
        XCTAssertNil(result.approvalRequest)
    }

    func testDependencyManifestInfersSupabaseDefaultsFromLooseObject() throws {
        let manifest = ProjectDependencyManifest(
            toolInput: [
                "dependencies": [
                    ["title": "Supabase"],
                ],
            ]
        )

        XCTAssertEqual(manifest?.dependencies.count, 1)
        let dependency = try XCTUnwrap(manifest?.dependencies.first)
        XCTAssertEqual(dependency.id, "supabase")
        XCTAssertEqual(dependency.integrationID, .supabase)
        XCTAssertEqual(dependency.envKeys, ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"])
        XCTAssertEqual(dependency.safety, .clientRuntime)
        XCTAssertTrue(dependency.allowsMockDataUntilConfigured)
    }

    func testDependencyManifestInfersSupabaseBackendFromBackendTitle() throws {
        let manifest = ProjectDependencyManifest(
            toolInput: [
                "dependencies": [
                    ["title": "Supabase Backend"],
                ],
            ]
        )

        XCTAssertEqual(manifest?.dependencies.count, 1)
        let dependency = try XCTUnwrap(manifest?.dependencies.first)
        XCTAssertEqual(dependency.backendProviderID, .supabase)
        XCTAssertEqual(dependency.setupSurface, .backend)
        XCTAssertEqual(dependency.safety, .backendOnly)
    }

    func testDependencyManifestAcceptsCamelCaseFieldsAndSafetyAlias() throws {
        let manifest = ProjectDependencyManifest(
            toolInput: [
                "dependencies": [
                    [
                        "title": "AI Backend",
                        "envKeys": ["OPENAI_API_KEY"],
                        "safety": "backend-only",
                        "allowsMockDataUntilConfigured": false,
                    ],
                ],
            ]
        )

        XCTAssertEqual(manifest?.dependencies.count, 1)
        let dependency = try XCTUnwrap(manifest?.dependencies.first)
        XCTAssertEqual(dependency.id, "openaiapikey")
        XCTAssertEqual(dependency.envKeys, ["OPENAI_API_KEY"])
        XCTAssertEqual(dependency.safety, .backendOnly)
        XCTAssertFalse(dependency.allowsMockDataUntilConfigured)
        XCTAssertEqual(
            dependency.summary,
            "Provide `OPENAI_API_KEY` as backend-only configuration and keep it off-device."
        )
    }

    func testDependencyManifestAcceptsBackendSetupFields() throws {
        let manifest = ProjectDependencyManifest(
            toolInput: [
                "dependencies": [
                    [
                        "id": "supabase-backend",
                        "title": "Supabase Backend",
                        "summary": "Set up managed Supabase backend support.",
                        "setup_surface": "backend",
                        "backend_provider_id": "supabase",
                        "backend_capability_ids": ["managed-serverless-backend"],
                        "safety": "backendOnly",
                        "allows_mock_data_until_configured": true,
                    ],
                ],
            ]
        )

        let dependency = try XCTUnwrap(manifest?.dependencies.first)
        XCTAssertEqual(dependency.setupSurface, .backend)
        XCTAssertEqual(dependency.backendProviderID, .supabase)
        XCTAssertEqual(dependency.backendCapabilityIDs, ["managedserverlessbackend"])
        XCTAssertEqual(dependency.safety, .backendOnly)
    }

    private func makeExecutor(
        backendState: ProjectBackendState = .init(
            providerID: .supabase,
            linkedProjectRef: "proj123",
            linkedProjectURL: "https://proj123.supabase.co"
        ),
        superwallState: ProjectSuperwallState = .init(
            projectID: "proj_sw_123",
            projectName: "Paywall Project",
            applicationID: "app_sw_123",
            applicationName: "Paywall App",
            applicationPlatform: "ios",
            applicationPublicAPIKey: "pk_test_123"
        ),
        backendToolHandlers: BackendToolHandlers? = nil
    ) -> ToolExecutor {
        ToolExecutor(
            workspaceRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            projectName: "Test",
            targetName: "Test",
            currentMode: .build,
            projectBackendState: backendState,
            projectSuperwallState: superwallState,
            supabaseToolHandlers: SupabaseToolHandlers(
                read: { _ in "read ok" },
                write: { _ in "write ok" },
                sql: { _ in "sql ok" },
                settings: { _ in "settings ok" }
            ),
            backendToolHandlers: backendToolHandlers ?? BackendToolHandlers(
                status: {
                    BackendStatusSnapshot(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co",
                        remoteFunctionNames: ["ping"],
                        remoteSecretNames: ["STRIPE_SECRET_KEY"]
                    )
                },
                linkProvider: {
                    BackendProviderLink(
                        providerID: .supabase,
                        projectRef: "proj123",
                        projectURL: "https://proj123.supabase.co"
                    )
                },
                deploy: { _ in "deploy ok" },
                invoke: { _ in "invoke ok" },
                setSecret: { _, _ in "secret ok" },
                listLogs: { _, _ in [] },
                persistState: { _ in }
            ),
            superwallToolHandlers: SuperwallToolHandlers(
                status: { _ in "superwall status ok" },
                bootstrapProject: { _, _ in
                    SuperwallToolOperationResult(
                        state: superwallState,
                        summary: "superwall bootstrap ok"
                    )
                },
                bootstrapStarterMonetization: { _, _ in
                    SuperwallToolOperationResult(
                        state: superwallState,
                        summary: "superwall starter ok"
                    )
                },
                syncPreviewTestUser: { _, _ in
                    SuperwallToolOperationResult(
                        state: superwallState,
                        summary: "superwall preview sync ok"
                    )
                },
                listPaywalls: { _ in [] },
                listTemplates: { _ in [] },
                openDashboard: { _ in "superwall dashboard ok" },
                openPaywalls: { _ in "superwall paywalls ok" },
                openTemplates: { _ in "superwall templates ok" },
                persistState: { _ in }
            )
        )
    }
}
