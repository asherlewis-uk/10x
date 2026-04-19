import XCTest
@testable import TenXAppCore

final class BuilderProjectStatusStateTests: XCTestCase {
    func testPreservesDependencyManifestAcrossEmptyChatState() {
        let manifest = ProjectDependencyManifest(
            dependencies: [
                ProjectDependencyRequirement(
                    id: "supabase",
                    title: "Supabase",
                    summary: "Connect Supabase for auth and data.",
                    integrationID: .supabase,
                    envKeys: ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"],
                    safety: .clientRuntime,
                    allowsMockDataUntilConfigured: true
                ),
            ]
        )
        let projectStatus = BuilderProjectStatusState(dependencyManifest: manifest)

        let resolved = BuilderProjectStatusState.resolve(
            projectStatus: projectStatus,
            chatState: .empty
        )

        XCTAssertEqual(resolved.dependencyManifest, manifest)
    }

    func testMergesDependencyManifestFromProjectMetadataWhenLocalStatusMissingIt() {
        let manifest = ProjectDependencyManifest(
            dependencies: [
                ProjectDependencyRequirement(
                    id: "openai-backend",
                    title: "OpenAI backend",
                    summary: "Keep the API key off-device.",
                    envKeys: ["OPENAI_API_KEY"],
                    safety: .backendOnly,
                    allowsMockDataUntilConfigured: true
                ),
            ]
        )
        let merged = BuilderProjectStatusState.merged(
            projectStatus: BuilderProjectStatusState(plan: "Plan only"),
            projectDependencyManifest: manifest
        )

        XCTAssertEqual(merged?.dependencyManifest, manifest)
    }

    func testFallsBackToLegacyChatStatusWhenProjectStatusMissing() {
        let warning = BuilderProjectWarning(title: "Capability warning", message: "Needs review.")
        let chatState = BuilderChatState(
            messages: [],
            plan: "Legacy plan",
            tasks: "- [ ] Legacy task",
            warnings: [warning],
            snapshots: []
        )

        let resolved = BuilderProjectStatusState.resolve(projectStatus: nil, chatState: chatState)

        XCTAssertEqual(resolved.plan, "Legacy plan")
        XCTAssertEqual(resolved.tasks, "- [ ] Legacy task")
        XCTAssertEqual(resolved.warnings, [warning])
    }

    func testPreservesProjectStatusAcrossEmptyChatState() {
        let warning = BuilderProjectWarning(title: "Capability warning", message: "Needs review.")
        let projectStatus = BuilderProjectStatusState(
            plan: "Shared plan",
            tasks: "- [ ] Shared task",
            warnings: [warning]
        )

        let resolved = BuilderProjectStatusState.resolve(projectStatus: projectStatus, chatState: .empty)

        XCTAssertEqual(resolved.plan, "Shared plan")
        XCTAssertEqual(resolved.tasks, "- [ ] Shared task")
        XCTAssertEqual(resolved.warnings, [warning])
    }

    func testBackfillsLegacyWarningsWhenProjectStatusHasOnlyPlanAndTasks() {
        let warning = BuilderProjectWarning(title: "Capability warning", message: "Needs review.")
        let projectStatus = BuilderProjectStatusState(
            plan: "Shared plan",
            tasks: "- [ ] Shared task",
            warnings: []
        )
        let chatState = BuilderChatState(
            messages: [],
            plan: nil,
            tasks: nil,
            warnings: [warning],
            snapshots: []
        )

        let resolved = BuilderProjectStatusState.resolve(projectStatus: projectStatus, chatState: chatState)

        XCTAssertEqual(resolved.plan, "Shared plan")
        XCTAssertEqual(resolved.tasks, "- [ ] Shared task")
        XCTAssertEqual(resolved.warnings, [warning])
    }
}
