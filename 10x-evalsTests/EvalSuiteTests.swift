import XCTest
@testable import TenXEvals

final class EvalSuiteTests: XCTestCase {
    func testSuiteDecodesDefaultAndCustomSteps() throws {
        let yaml = """
        suite: smoke
        defaults:
          question_strategy: answers_then_skip
          question_answers:
            - first
          expected_skills:
            - ui-design
          steps:
            - wait_for_plan
            - approve_plan
        cases:
          - id: simple
            prompt: Build a habit tracker
            expected_skills:
              - ml-and-vision
            steps:
              - wait_for_plan
              - send_message: Make it monochrome
              - stop
        """

        let suiteURL = try writeTemporarySuite(yaml)
        defer { try? FileManager.default.removeItem(at: suiteURL) }

        let suite = try EvalSuite.load(from: suiteURL)
        let resolved = try ResolvedEvalCase(suiteName: suite.suite, defaults: suite.defaults, caseSpec: suite.cases[0])

        XCTAssertEqual(resolved.suiteName, "smoke")
        XCTAssertEqual(resolved.questionStrategy, .answersThenSkip)
        XCTAssertEqual(resolved.questionAnswers, ["first"])
        XCTAssertEqual(resolved.expectedSkills, ["ml-and-vision"])
        XCTAssertEqual(resolved.steps, [.waitForPlan, .sendMessage("Make it monochrome"), .stop])
        XCTAssertEqual(resolved.projectName, "Build a habit tracker")
    }

    func testResolvedPromptAppendsOnboardingContext() throws {
        let suite = EvalSuite(
            suite: "smoke",
            defaults: nil,
            cases: [
                EvalCase(
                    id: "onboarding",
                    prompt: "Build a meal planner",
                    projectName: nil,
                    questionStrategy: nil,
                    questionAnswers: nil,
                    expectedSkills: nil,
                    steps: nil,
                    timeouts: nil,
                    onboarding: EvalOnboardingSpec(
                        designStyle: "Minimal",
                        targetAudience: ["Professionals"],
                        additionalDetails: "Keep the main flow fast."
                    )
                )
            ]
        )

        let resolved = try ResolvedEvalCase(suiteName: suite.suite, defaults: suite.defaults, caseSpec: suite.cases[0])

        XCTAssertTrue(resolved.prompt.contains("User preferences from onboarding"))
        XCTAssertTrue(resolved.prompt.contains("Minimal"))
        XCTAssertEqual(resolved.designStyle, .minimal)
        XCTAssertEqual(resolved.onboardingData?.targetAudience, [.professionals])
    }

    func testValidateRejectsDuplicateCaseIDs() throws {
        let suite = EvalSuite(
            suite: "dupes",
            defaults: nil,
            cases: [
                EvalCase(id: "same", prompt: "One", projectName: nil, questionStrategy: nil, questionAnswers: nil, expectedSkills: nil, steps: nil, timeouts: nil, onboarding: nil),
                EvalCase(id: "same", prompt: "Two", projectName: nil, questionStrategy: nil, questionAnswers: nil, expectedSkills: nil, steps: nil, timeouts: nil, onboarding: nil),
            ]
        )

        XCTAssertThrowsError(try suite.validate())
    }

    private func writeTemporarySuite(_ yaml: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
