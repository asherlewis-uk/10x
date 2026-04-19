import XCTest
@testable import TenXAppCore

final class BuilderGenerationRequestPlannerTests: XCTestCase {
    func testExecutePlanActionSwitchesIntoBuildMode() {
        let decision = BuilderGenerationRequestPlanner.explicitModeSwitch(
            for: .executePlan,
            currentMode: .plan
        )

        XCTAssertEqual(decision?.mode, .build)
        XCTAssertEqual(
            decision?.detail,
            "Start Building was selected, so the project is continuing in build mode."
        )
    }

    func testExecutePlanActionDoesNotSwitchWhenAlreadyInBuildMode() {
        let decision = BuilderGenerationRequestPlanner.explicitModeSwitch(
            for: .executePlan,
            currentMode: .build
        )

        XCTAssertNil(decision)
    }

    func testRegularMessagesDoNotTriggerAutomaticModeSwitch() {
        let decision = BuilderGenerationRequestPlanner.explicitModeSwitch(
            for: nil,
            currentMode: .plan
        )

        XCTAssertNil(decision)
    }

    func testBuildModeKeepsIntermediateAssistantTextVisible() {
        XCTAssertFalse(
            BuilderGenerationRequestPlanner.shouldSuppressIntermediateAssistantText(
                requestType: .build,
                mode: .build,
                hasFileTree: true
            )
        )
    }

    func testBuildModeDoesNotHideIntermediateAssistantTextForExistingProjects() {
        XCTAssertFalse(
            BuilderGenerationRequestPlanner.shouldSuppressIntermediateAssistantText(
                requestType: .neutral,
                mode: .build,
                hasFileTree: true
            )
        )
    }

    func testProjectPlanLanguageStillClassifiesAsPlanningRequest() {
        let requestType = BuilderGenerationRequestPlanner.classifyGenerationRequest(
            requestText: "please revise the roadmap and project plan",
            isBuildFix: false
        )

        guard case .plan = requestType else {
            return XCTFail("Expected plan request type.")
        }
    }

    func testRealSupabaseAuthAndBackendRequestClassifiesAsLiveSetup() {
        let requestType = BuilderGenerationRequestPlanner.classifyGenerationRequest(
            requestText: "I want real Supabase auth and backend wired in now.",
            isBuildFix: false
        )

        guard case .liveSetup = requestType else {
            return XCTFail("Expected live setup request type.")
        }
    }

    func testLiveSetupRequestForcesDependencyUpdateToolFirst() {
        let options = BuilderGenerationRequestPlanner.requestOptionsForGeneration(
            requestType: .liveSetup
        )

        XCTAssertEqual(options.toolChoice?["type"] as? String, "tool")
        XCTAssertEqual(options.toolChoice?["name"] as? String, "update_project_dependencies")
        XCTAssertNil(options.thinking)
    }

    func testNeutralRequestKeepsAdaptiveThinking() {
        let options = BuilderGenerationRequestPlanner.requestOptionsForGeneration(
            requestType: .neutral
        )

        XCTAssertEqual(options.thinking?["type"] as? String, "adaptive")
    }
}
