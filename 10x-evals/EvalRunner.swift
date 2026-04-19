import Foundation
@testable import TenXAppCore

enum EvalQuestionResponse: Equatable {
    case answer(String)
    case skip
}

struct EvalQuestionResponder {
    private let strategy: EvalQuestionStrategy
    private let scriptedAnswers: [String]
    private(set) var nextAnswerIndex = 0

    init(strategy: EvalQuestionStrategy, scriptedAnswers: [String]) {
        self.strategy = strategy
        self.scriptedAnswers = scriptedAnswers
    }

    mutating func nextResponse() throws -> EvalQuestionResponse {
        switch strategy {
        case .skip:
            return .skip
        case .answersThenSkip:
            guard nextAnswerIndex < scriptedAnswers.count else {
                return .skip
            }

            let answer = scriptedAnswers[nextAnswerIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            nextAnswerIndex += 1
            if answer.isEmpty {
                return .skip
            }
            return .answer(answer)
        case .fail:
            throw EvalRunError.questionEncounteredWithoutHandler
        }
    }
}

struct EvalRunResult {
    let caseID: String
    let projectID: String
    let projectName: String
    let projectDirectory: URL
    let planSaved: Bool
    let previewCaptured: Bool
    let usedSkills: [String]
}

@MainActor
final class EvalRunner {
    private static let planApprovalMessage = "The plan looks great. Start building the app now."

    private var session: AppSession
    private let reporter: StdoutReporter

    init(session: AppSession, reporter: StdoutReporter = StdoutReporter()) {
        self.session = session
        self.reporter = reporter
    }

    func runSuite(_ suite: EvalSuite, filterCaseID: String? = nil) async throws -> [EvalRunResult] {
        try await syncSession()

        let selectedCases = suite.cases.filter { caseSpec in
            guard let filterCaseID else { return true }
            return caseSpec.id == filterCaseID
        }

        if let filterCaseID, selectedCases.isEmpty {
            throw EvalRunError.caseNotFound(filterCaseID)
        }

        var results: [EvalRunResult] = []
        for caseSpec in selectedCases {
            let resolvedCase = try ResolvedEvalCase(suiteName: suite.suite, defaults: suite.defaults, caseSpec: caseSpec)
            results.append(try await runCase(resolvedCase))
        }
        return results
    }

    private func runCase(_ caseSpec: ResolvedEvalCase) async throws -> EvalRunResult {
        reporter.heading("")
        reporter.heading("== \(caseSpec.suiteName) / \(caseSpec.id) ==")

        let viewModel = BuilderViewModel()
        var questionResponder = EvalQuestionResponder(
            strategy: caseSpec.questionStrategy,
            scriptedAnswers: caseSpec.questionAnswers
        )

        reporter.caseEvent(caseSpec.id, "creating project `\(caseSpec.projectName)`")
        await viewModel.createProject(name: caseSpec.projectName, accessToken: session.accessToken)
        try await waitForProjectReady(
            viewModel: viewModel,
            caseSpec: caseSpec,
            description: "waiting for project setup"
        )

        guard let project = viewModel.activeProject else {
            throw EvalRunError.projectCreationFailed
        }

        viewModel.designStyle = caseSpec.designStyle
        viewModel.onboardingData = caseSpec.onboardingData
        viewModel.mode = .plan

        let projectDirectory = LocalProjectStore.projectRootDirectory(projectName: project.name, projectId: project.id)
        reporter.caseEvent(caseSpec.id, "project path: \(projectDirectory.path)")
        reporter.caseEvent(caseSpec.id, "sending initial prompt")

        if let error = viewModel.sendMessage(caseSpec.prompt, accessToken: session.accessToken) {
            throw EvalRunError.invalidInitialMessage(error)
        }

        for step in caseSpec.steps {
            switch step {
            case .waitForPlan:
                reporter.caseEvent(caseSpec.id, "waiting for saved plan")
                try await waitUntil(
                    timeout: caseSpec.timeouts.planSeconds ?? EvalTimeouts.defaults.planSeconds ?? 300,
                    description: "waiting for plan",
                    viewModel: viewModel,
                    caseSpec: caseSpec,
                    questionResponder: &questionResponder
                ) {
                    let hasPlan = !(viewModel.projectPlan?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    guard hasPlan, viewModel.questionQueue == nil else { return false }
                    if !viewModel.isGenerating { return true }
                    return viewModel.mode != .plan
                }
                reporter.caseEvent(caseSpec.id, "plan saved")

            case .approvePlan:
                if viewModel.mode != .plan {
                    reporter.caseEvent(caseSpec.id, "skipping approval because build mode already started")
                    continue
                }
                try await waitUntil(
                    timeout: caseSpec.timeouts.idleSeconds ?? EvalTimeouts.defaults.idleSeconds ?? 300,
                    description: "waiting to approve plan",
                    viewModel: viewModel,
                    caseSpec: caseSpec,
                    questionResponder: &questionResponder
                ) {
                    !viewModel.isGenerating && viewModel.questionQueue == nil
                }
                reporter.caseEvent(caseSpec.id, "approving plan")
                if let error = viewModel.sendMessage(Self.planApprovalMessage, accessToken: session.accessToken) {
                    throw EvalRunError.invalidStepMessage(error)
                }

            case .sendMessage(let message):
                try await waitUntil(
                    timeout: caseSpec.timeouts.idleSeconds ?? EvalTimeouts.defaults.idleSeconds ?? 300,
                    description: "waiting to send follow-up message",
                    viewModel: viewModel,
                    caseSpec: caseSpec,
                    questionResponder: &questionResponder
                ) {
                    !viewModel.isGenerating && viewModel.questionQueue == nil
                }
                reporter.caseEvent(caseSpec.id, "sending follow-up message")
                if let error = viewModel.sendMessage(message, accessToken: session.accessToken) {
                    throw EvalRunError.invalidStepMessage(error)
                }

            case .waitForPreview:
                reporter.caseEvent(caseSpec.id, "waiting for simulator preview")
                try await waitUntil(
                    timeout: caseSpec.timeouts.previewSeconds ?? EvalTimeouts.defaults.previewSeconds ?? 900,
                    description: "waiting for preview",
                    viewModel: viewModel,
                    caseSpec: caseSpec,
                    questionResponder: &questionResponder
                ) {
                    viewModel.previewScreenshot != nil
                        && !viewModel.isGenerating
                        && !viewModel.isPreviewLoading
                        && viewModel.questionQueue == nil
                }
                reporter.caseEvent(caseSpec.id, "preview captured")

            case .waitForIdle:
                reporter.caseEvent(caseSpec.id, "waiting for idle state")
                try await waitUntil(
                    timeout: caseSpec.timeouts.idleSeconds ?? EvalTimeouts.defaults.idleSeconds ?? 300,
                    description: "waiting for idle state",
                    viewModel: viewModel,
                    caseSpec: caseSpec,
                    questionResponder: &questionResponder
                ) {
                    !viewModel.isGenerating
                        && !viewModel.isPreviewLoading
                        && viewModel.questionQueue == nil
                }

            case .stop:
                reporter.caseEvent(caseSpec.id, "stopping after requested step")
                let result = finalizedResult(
                    caseSpec: caseSpec,
                    viewModel: viewModel,
                    fallbackProject: project,
                    fallbackDirectory: projectDirectory
                )
                reporter.caseEvent(caseSpec.id, "used skills: \(formattedUsedSkills(result.usedSkills))")
                try assertExpectedSkillsIfNeeded(caseSpec: caseSpec, usedSkills: result.usedSkills)
                await viewModel.stopPreviewScreenCaptureLoop()
                return result
            }
        }

        let result = finalizedResult(
            caseSpec: caseSpec,
            viewModel: viewModel,
            fallbackProject: project,
            fallbackDirectory: projectDirectory
        )
        reporter.caseEvent(caseSpec.id, "used skills: \(formattedUsedSkills(result.usedSkills))")
        try assertExpectedSkillsIfNeeded(caseSpec: caseSpec, usedSkills: result.usedSkills)
        await viewModel.stopPreviewScreenCaptureLoop()
        return result
    }

    private func finalizedResult(
        caseSpec: ResolvedEvalCase,
        viewModel: BuilderViewModel,
        fallbackProject: BuilderProject,
        fallbackDirectory: URL
    ) -> EvalRunResult {
        let finalProject = viewModel.activeProject ?? fallbackProject
        let finalDirectory = LocalProjectStore.projectRootDirectory(
            projectName: finalProject.name,
            projectId: finalProject.id
        )

        return EvalRunResult(
            caseID: caseSpec.id,
            projectID: finalProject.id,
            projectName: finalProject.name,
            projectDirectory: FileManager.default.fileExists(atPath: finalDirectory.path) ? finalDirectory : fallbackDirectory,
            planSaved: !(viewModel.projectPlan?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            previewCaptured: viewModel.previewScreenshot != nil,
            usedSkills: usedSkillNames(from: viewModel)
        )
    }

    private func waitForProjectReady(
        viewModel: BuilderViewModel,
        caseSpec: ResolvedEvalCase,
        description: String
    ) async throws {
        let timeout = caseSpec.timeouts.projectReadySeconds ?? EvalTimeouts.defaults.projectReadySeconds ?? 60
        var questionResponder = EvalQuestionResponder.constantSkip
        try await waitUntil(
            timeout: timeout,
            description: description,
            viewModel: viewModel,
            caseSpec: caseSpec,
            questionResponder: &questionResponder
        ) {
            viewModel.activeProject != nil && viewModel.activeChat != nil
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        description: String,
        viewModel: BuilderViewModel,
        caseSpec: ResolvedEvalCase,
        questionResponder: inout EvalQuestionResponder,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await handleQuestionIfNeeded(
                viewModel: viewModel,
                caseSpec: caseSpec,
                questionResponder: &questionResponder
            )

            if let buildError = viewModel.buildError?.trimmingCharacters(in: .whitespacesAndNewlines),
               !buildError.isEmpty,
               !viewModel.isGenerating,
               !viewModel.isPreviewLoading {
                throw EvalRunError.builderFailure(buildError)
            }

            if condition() {
                return
            }

            try await Task.sleep(for: .milliseconds(200))
        }

        throw EvalRunError.timeout(description)
    }

    private func handleQuestionIfNeeded(
        viewModel: BuilderViewModel,
        caseSpec: ResolvedEvalCase,
        questionResponder: inout EvalQuestionResponder
    ) async throws {
        guard viewModel.questionQueue?.currentQuestion != nil else { return }

        let response = try questionResponder.nextResponse()
        switch response {
        case .answer(let answer):
            reporter.caseEvent(caseSpec.id, "answering question")
            viewModel.answerCurrentQuestion(answer, accessToken: session.accessToken)
        case .skip:
            reporter.caseEvent(caseSpec.id, "skipping question with best-judgment answer")
            viewModel.skipCurrentQuestion(accessToken: session.accessToken)
        }

        try await Task.sleep(for: .milliseconds(100))
    }

    private func syncSession() async throws {
        do {
            _ = try await SupabaseService.shared.setSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        } catch {
            let refreshedSession = try await refreshSession(using: session.refreshToken)
            session = refreshedSession
            _ = try await SupabaseService.shared.setSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        }
    }

    private func refreshSession(using refreshToken: String) async throws -> AppSession {
        guard !Config.supabaseURL.isEmpty,
              let url = URL(string: "\(Config.supabaseURL)/auth/v1/token?grant_type=refresh_token") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        let refreshedToken = (json["refresh_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let user = json["user"] as? [String: Any]
        let resolvedRefreshToken = {
            guard let refreshedToken, !refreshedToken.isEmpty else { return refreshToken }
            return refreshedToken
        }()

        return AppSession(
            accessToken: accessToken,
            refreshToken: resolvedRefreshToken,
            userId: user?["id"] as? String ?? session.userId,
            userEmail: user?["email"] as? String ?? session.userEmail
        )
    }

    private func assertExpectedSkillsIfNeeded(
        caseSpec: ResolvedEvalCase,
        usedSkills: [String]
    ) throws {
        guard !caseSpec.expectedSkills.isEmpty else { return }

        let usedSet = Set(usedSkills.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let missing = caseSpec.expectedSkills.filter { !usedSet.contains($0) }
        guard missing.isEmpty else {
            throw EvalRunError.missingExpectedSkills(expected: caseSpec.expectedSkills, used: usedSkills)
        }
    }

    private func formattedUsedSkills(_ skills: [String]) -> String {
        let trimmed = skills.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return trimmed.isEmpty ? "(none)" : trimmed.joined(separator: ", ")
    }

    private func usedSkillNames(from viewModel: BuilderViewModel) -> [String] {
        var used: [String] = []
        var seen: Set<String> = []

        for step in recordedToolSteps(from: viewModel) {
            guard step.name == "use_skill", step.status == .success,
                  let name = skillName(from: step),
                  seen.insert(name).inserted else {
                continue
            }
            used.append(name)
        }

        return used
    }

    private func recordedToolSteps(from viewModel: BuilderViewModel) -> [BuilderToolStep] {
        var steps: [BuilderToolStep] = []

        for item in viewModel.chatItems {
            if case .toolSteps(_, let groupedSteps) = item {
                steps.append(contentsOf: groupedSteps)
            }
        }

        steps.append(contentsOf: viewModel.activeSteps)
        return steps
    }

    private func skillName(from step: BuilderToolStep) -> String? {
        let previews = [step.inputPreview, step.label, step.outputPreview]

        for preview in previews {
            guard let preview else { continue }

            if let range = preview.range(of: "skill:", options: .caseInsensitive) {
                let trailing = preview[range.upperBound...]
                    .split(whereSeparator: \.isNewline)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if let trailing, !trailing.isEmpty {
                    return trailing
                }
            }

            let match = preview
                .lowercased()
                .replacingOccurrences(of: "learning ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !match.isEmpty,
               !match.contains("skill"),
               !match.contains("reviewing") {
                if match.contains("-") || match.contains(" ") {
                    return match
                }
            }
        }

        return nil
    }
}

enum EvalRunError: LocalizedError {
    case caseNotFound(String)
    case invalidInitialMessage(String)
    case invalidStepMessage(String)
    case questionEncounteredWithoutHandler
    case builderFailure(String)
    case timeout(String)
    case projectCreationFailed
    case missingExpectedSkills(expected: [String], used: [String])

    var errorDescription: String? {
        switch self {
        case .caseNotFound(let caseID):
            return "Case `\(caseID)` was not found in the suite."
        case .invalidInitialMessage(let message), .invalidStepMessage(let message):
            return message
        case .questionEncounteredWithoutHandler:
            return "The eval encountered an `ask_user` prompt and the case is configured to fail instead of auto-answering."
        case .builderFailure(let message):
            return message
        case .timeout(let description):
            return "Timed out while \(description)."
        case .projectCreationFailed:
            return "The builder project could not be created."
        case .missingExpectedSkills(let expected, let used):
            let expectedText = expected.joined(separator: ", ")
            let usedText = used.isEmpty ? "(none)" : used.joined(separator: ", ")
            return "Expected skill use for [\(expectedText)] but observed [\(usedText)]."
        }
    }
}

private extension EvalQuestionResponder {
    static var constantSkip: EvalQuestionResponder {
        EvalQuestionResponder(strategy: .skip, scriptedAnswers: [])
    }
}
