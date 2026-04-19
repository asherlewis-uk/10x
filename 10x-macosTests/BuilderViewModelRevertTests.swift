import AppKit
import XCTest
@testable import TenXAppCore

final class BuilderViewModelRevertTests: XCTestCase {
    @MainActor
    func testRevertPreservesEarlierToolStepsAndRemovesLaterOnes() async {
        let viewModel = BuilderViewModel()
        let user1 = makeMessage(id: "user-1", role: "user", content: "Create the login screen")
        let assistant1 = makeMessage(id: "assistant-1", role: "assistant", content: "Done")
        let user2 = makeMessage(id: "user-2", role: "user", content: "Change the CTA color")
        let assistant2 = makeMessage(id: "assistant-2", role: "assistant", content: "Updated")
        let stepBeforeRevert = BuilderToolStep(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            toolUseId: "tool-1",
            name: "edit_file",
            label: "Editing LoginView.swift",
            status: .success
        )
        let stepAfterRevert = BuilderToolStep(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            toolUseId: "tool-2",
            name: "edit_file",
            label: "Editing Theme.swift",
            status: .success
        )

        viewModel.messages = [user1, assistant1, user2, assistant2]
        viewModel.chatItems = [
            .message(user1),
            .toolSteps(id: "tools-before", steps: [stepBeforeRevert]),
            .message(assistant1),
            .message(user2),
            .toolSteps(id: "tools-after", steps: [stepAfterRevert]),
            .message(assistant2),
        ]

        await viewModel.revertToMessage(user2.id)

        XCTAssertEqual(viewModel.messages.map(\.id), [user1.id, assistant1.id])
        XCTAssertEqual(viewModel.chatItems.map(\.id), [user1.id, "tools-before", assistant1.id])

        guard case .toolSteps(_, let preservedSteps) = viewModel.chatItems[1] else {
            return XCTFail("Expected the earlier tool steps to remain in chat.")
        }

        XCTAssertEqual(preservedSteps, [stepBeforeRevert])
    }

    @MainActor
    func testRevertKeepsExistingPreviewScreenshotWhileNonEmptyProjectRebuilds() async {
        let viewModel = BuilderViewModel()
        let user1 = makeMessage(id: "user-1", role: "user", content: "Build the app")
        let assistant1 = makeMessage(id: "assistant-1", role: "assistant", content: "Done")
        let user2 = makeMessage(id: "user-2", role: "user", content: "Change the home screen")
        let assistant2 = makeMessage(id: "assistant-2", role: "assistant", content: "Updated")
        let previewImage = NSImage(size: NSSize(width: 32, height: 32))

        viewModel.messages = [user1, assistant1, user2, assistant2]
        viewModel.previewScreenshot = previewImage
        viewModel.generationSnapshots = [
            ProjectSnapshot(
                messageCountBefore: 2,
                fileTree: ["ContentView.swift": "struct ContentView: View {}"],
                plan: nil,
                tasks: nil,
                warnings: [],
                cachedReadFiles: [:],
                cachedReadFileOrder: [],
                contextState: .empty
            )
        ]

        await viewModel.revertToMessage(user2.id)

        XCTAssertNotNil(viewModel.previewScreenshot)
        XCTAssertTrue(viewModel.previewScreenshot === previewImage)
    }

    @MainActor
    func testRevertClearsPreviewScreenshotWhenRestoredProjectIsEmpty() async {
        let viewModel = BuilderViewModel()
        let user1 = makeMessage(id: "user-1", role: "user", content: "Build the app")
        let assistant1 = makeMessage(id: "assistant-1", role: "assistant", content: "Done")
        let user2 = makeMessage(id: "user-2", role: "user", content: "Start over")
        let assistant2 = makeMessage(id: "assistant-2", role: "assistant", content: "Reset")

        viewModel.messages = [user1, assistant1, user2, assistant2]
        viewModel.previewScreenshot = NSImage(size: NSSize(width: 32, height: 32))
        viewModel.generationSnapshots = [
            ProjectSnapshot(
                messageCountBefore: 2,
                fileTree: [:],
                plan: nil,
                tasks: nil,
                warnings: [],
                cachedReadFiles: [:],
                cachedReadFileOrder: [],
                contextState: .empty
            )
        ]

        await viewModel.revertToMessage(user2.id)

        XCTAssertNil(viewModel.previewScreenshot)
    }

    @MainActor
    func testRespondingToIntegrationApprovalKeepsRunningSupabaseSQLStepActiveWithoutAddingChatHistory() async {
        let viewModel = BuilderViewModel()
        let runningStep = BuilderToolStep(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            toolUseId: "tool-supabase-sql",
            name: "supabase_execute_sql",
            label: "Running create table saved_movies (...)",
            status: .running
        )

        viewModel.activeSteps = [runningStep]
        viewModel.integrationApproval = BuilderViewModel.IntegrationApprovalState(
            request: IntegrationApprovalRequest(
                integration: "supabase",
                scope: "write",
                integrationName: "Supabase",
                actionDescription: "run SQL"
            ),
            toolUseId: "tool-supabase-sql"
        )

        viewModel.respondToIntegrationApproval(true, accessToken: "token")

        XCTAssertNil(viewModel.integrationApproval)
        XCTAssertEqual(viewModel.activeSteps, [runningStep])
        XCTAssertTrue(viewModel.chatItems.isEmpty)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    private func makeMessage(id: String, role: String, content: String) -> BuilderMessage {
        BuilderMessage(
            id: id,
            conversationId: "conversation",
            role: role,
            content: content,
            versionId: nil,
            createdAt: "2026-04-11T12:00:00Z"
        )
    }
}
