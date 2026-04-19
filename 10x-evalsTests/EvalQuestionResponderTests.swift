import XCTest
@testable import TenXEvals

final class EvalQuestionResponderTests: XCTestCase {
    func testAnswersThenSkipConsumesProvidedAnswersInOrder() throws {
        var responder = EvalQuestionResponder(
            strategy: .answersThenSkip,
            scriptedAnswers: ["first", "second"]
        )

        XCTAssertEqual(try responder.nextResponse(), .answer("first"))
        XCTAssertEqual(try responder.nextResponse(), .answer("second"))
        XCTAssertEqual(try responder.nextResponse(), .skip)
    }

    func testFailStrategyThrows() {
        var responder = EvalQuestionResponder(
            strategy: .fail,
            scriptedAnswers: []
        )

        XCTAssertThrowsError(try responder.nextResponse())
    }
}
