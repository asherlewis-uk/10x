import Foundation
@testable import TenXAppCore
import Yams

enum EvalQuestionStrategy: String, Decodable, CaseIterable, Equatable {
    case skip
    case answersThenSkip = "answers_then_skip"
    case fail
}

enum EvalStep: Decodable, Equatable {
    case waitForPlan
    case approvePlan
    case sendMessage(String)
    case waitForPreview
    case waitForIdle
    case stop

    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case sendMessage = "send_message"
    }

    init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let rawValue = try? singleValue.decode(String.self) {
            self = try Self.decode(rawValue: rawValue)
            return
        }

        if let keyedValue = try? singleValue.decode([String: String].self) {
            if let message = keyedValue[CodingKeys.sendMessage.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                self = .sendMessage(message)
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch try Self.decode(rawValue: type) {
        case .sendMessage:
            let message = try container.decode(String.self, forKey: .message)
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .message,
                    in: container,
                    debugDescription: "`send_message` steps require a non-empty `message`."
                )
            }
            self = .sendMessage(trimmed)
        case let step:
            self = step
        }
    }

    private static func decode(rawValue: String) throws -> EvalStep {
        switch rawValue {
        case "wait_for_plan":
            return .waitForPlan
        case "approve_plan":
            return .approvePlan
        case "send_message":
            return .sendMessage("")
        case "wait_for_preview":
            return .waitForPreview
        case "wait_for_idle":
            return .waitForIdle
        case "stop":
            return .stop
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unsupported eval step `\(rawValue)`.")
            )
        }
    }
}

struct EvalTimeouts: Decodable, Equatable {
    var projectReadySeconds: TimeInterval?
    var planSeconds: TimeInterval?
    var idleSeconds: TimeInterval?
    var previewSeconds: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case projectReadySeconds = "project_ready_seconds"
        case planSeconds = "plan_seconds"
        case idleSeconds = "idle_seconds"
        case previewSeconds = "preview_seconds"
    }

    func merging(overrides: EvalTimeouts?) -> EvalTimeouts {
        guard let overrides else { return self }
        return EvalTimeouts(
            projectReadySeconds: overrides.projectReadySeconds ?? projectReadySeconds,
            planSeconds: overrides.planSeconds ?? planSeconds,
            idleSeconds: overrides.idleSeconds ?? idleSeconds,
            previewSeconds: overrides.previewSeconds ?? previewSeconds
        )
    }

    static let defaults = EvalTimeouts(
        projectReadySeconds: 60,
        planSeconds: 300,
        idleSeconds: 300,
        previewSeconds: 900
    )
}

struct EvalOnboardingSpec: Decodable, Equatable {
    var designStyle: String?
    var targetAudience: [String]
    var additionalDetails: String

    private enum CodingKeys: String, CodingKey {
        case designStyle = "design_style"
        case targetAudience = "target_audience"
        case additionalDetails = "additional_details"
    }

    init(
        designStyle: String? = nil,
        targetAudience: [String] = [],
        additionalDetails: String = ""
    ) {
        self.designStyle = designStyle
        self.targetAudience = targetAudience
        self.additionalDetails = additionalDetails
    }

    func merging(overrides: EvalOnboardingSpec?) -> EvalOnboardingSpec {
        guard let overrides else { return self }
        return EvalOnboardingSpec(
            designStyle: overrides.designStyle ?? designStyle,
            targetAudience: overrides.targetAudience.isEmpty ? targetAudience : overrides.targetAudience,
            additionalDetails: overrides.additionalDetails.isEmpty ? additionalDetails : overrides.additionalDetails
        )
    }

    func materialize() throws -> (designStyle: DesignStyle?, onboardingData: OnboardingData?) {
        let resolvedDesignStyle: DesignStyle?
        if let designStyle, !designStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let matched = DesignStyle.matching(designStyle) else {
                throw EvalSuiteError.invalidDesignStyle(designStyle)
            }
            resolvedDesignStyle = matched
        } else {
            resolvedDesignStyle = nil
        }

        let resolvedAudience = try targetAudience.map { audience in
            guard let matched = TargetAudience.matching(audience) else {
                throw EvalSuiteError.invalidTargetAudience(audience)
            }
            return matched
        }

        let trimmedDetails = additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedDesignStyle != nil || !resolvedAudience.isEmpty || !trimmedDetails.isEmpty else {
            return (nil, nil)
        }

        var onboardingData = OnboardingData()
        onboardingData.designStyle = resolvedDesignStyle
        onboardingData.targetAudience = resolvedAudience
        onboardingData.additionalDetails = trimmedDetails
        return (resolvedDesignStyle, onboardingData)
    }
}

struct EvalDefaults: Decodable, Equatable {
    var questionStrategy: EvalQuestionStrategy?
    var questionAnswers: [String]?
    var expectedSkills: [String]?
    var steps: [EvalStep]?
    var timeouts: EvalTimeouts?
    var onboarding: EvalOnboardingSpec?

    private enum CodingKeys: String, CodingKey {
        case questionStrategy = "question_strategy"
        case questionAnswers = "question_answers"
        case expectedSkills = "expected_skills"
        case steps
        case timeouts
        case onboarding
    }
}

struct EvalCase: Decodable, Equatable {
    var id: String
    var prompt: String
    var projectName: String?
    var questionStrategy: EvalQuestionStrategy?
    var questionAnswers: [String]?
    var expectedSkills: [String]?
    var steps: [EvalStep]?
    var timeouts: EvalTimeouts?
    var onboarding: EvalOnboardingSpec?

    private enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case projectName = "project_name"
        case questionStrategy = "question_strategy"
        case questionAnswers = "question_answers"
        case expectedSkills = "expected_skills"
        case steps
        case timeouts
        case onboarding
    }
}

struct EvalSuite: Decodable, Equatable {
    var suite: String
    var defaults: EvalDefaults?
    var cases: [EvalCase]

    func validate() throws {
        let trimmedSuite = suite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSuite.isEmpty else {
            throw EvalSuiteError.invalidSuite("`suite` must not be empty.")
        }
        guard !cases.isEmpty else {
            throw EvalSuiteError.invalidSuite("Define at least one case.")
        }

        var seenIDs = Set<String>()
        for caseSpec in cases {
            let trimmedID = caseSpec.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                throw EvalSuiteError.invalidCase("Each case requires a non-empty `id`.")
            }
            guard seenIDs.insert(trimmedID).inserted else {
                throw EvalSuiteError.invalidCase("Duplicate case id `\(trimmedID)`.")
            }

            let trimmedPrompt = caseSpec.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPrompt.isEmpty else {
                throw EvalSuiteError.invalidCase("Case `\(trimmedID)` requires a non-empty `prompt`.")
            }

            for step in caseSpec.steps ?? defaults?.steps ?? [] {
                if case let .sendMessage(message) = step,
                   message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw EvalSuiteError.invalidCase("Case `\(trimmedID)` has an empty `send_message` step.")
                }
            }

            for skill in caseSpec.expectedSkills ?? defaults?.expectedSkills ?? [] {
                if skill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw EvalSuiteError.invalidCase("Case `\(trimmedID)` has an empty expected skill.")
                }
            }
        }
    }

    static func load(from url: URL) throws -> EvalSuite {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()
        let suite = try decoder.decode(EvalSuite.self, from: contents)
        try suite.validate()
        return suite
    }
}

struct ResolvedEvalCase {
    let suiteName: String
    let id: String
    let prompt: String
    let projectName: String
    let questionStrategy: EvalQuestionStrategy
    let questionAnswers: [String]
    let expectedSkills: [String]
    let steps: [EvalStep]
    let timeouts: EvalTimeouts
    let designStyle: DesignStyle?
    let onboardingData: OnboardingData?

    init(suiteName: String, defaults: EvalDefaults?, caseSpec: EvalCase) throws {
        let resolvedTimeouts = EvalTimeouts.defaults
            .merging(overrides: defaults?.timeouts)
            .merging(overrides: caseSpec.timeouts)
        let onboardingSpec = defaults?.onboarding?.merging(overrides: caseSpec.onboarding) ?? caseSpec.onboarding
        let onboardingContext = try onboardingSpec?.materialize()

        self.suiteName = suiteName
        self.id = caseSpec.id.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedPrompt = caseSpec.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let onboardingData = onboardingContext?.onboardingData,
           let contextString = onboardingData.contextString() {
            self.prompt = trimmedPrompt + contextString
        } else {
            self.prompt = trimmedPrompt
        }

        let providedName = caseSpec.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectName = {
            if let providedName, !providedName.isEmpty {
                return providedName
            }
            return String(trimmedPrompt.prefix(50))
        }()

        self.questionStrategy = caseSpec.questionStrategy ?? defaults?.questionStrategy ?? .skip
        self.questionAnswers = caseSpec.questionAnswers ?? defaults?.questionAnswers ?? []
        self.expectedSkills = Self.normalizedSkillNames(caseSpec.expectedSkills ?? defaults?.expectedSkills ?? [])
        self.steps = caseSpec.steps ?? defaults?.steps ?? [.waitForPlan, .approvePlan, .waitForPreview]
        self.timeouts = resolvedTimeouts
        self.designStyle = onboardingContext?.designStyle
        self.onboardingData = onboardingContext?.onboardingData
    }

    private static func normalizedSkillNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for raw in names {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }
}

enum EvalSuiteError: LocalizedError, Equatable {
    case invalidSuite(String)
    case invalidCase(String)
    case invalidDesignStyle(String)
    case invalidTargetAudience(String)

    var errorDescription: String? {
        switch self {
        case .invalidSuite(let message), .invalidCase(let message):
            return message
        case .invalidDesignStyle(let value):
            return "Unsupported design style `\(value)`."
        case .invalidTargetAudience(let value):
            return "Unsupported target audience `\(value)`."
        }
    }
}

private extension DesignStyle {
    static func matching(_ raw: String) -> DesignStyle? {
        let normalized = raw.normalizedEvalToken
        return Self.allCases.first {
            $0.rawValue.normalizedEvalToken == normalized || $0.label.normalizedEvalToken == normalized
        }
    }
}

private extension TargetAudience {
    static func matching(_ raw: String) -> TargetAudience? {
        let normalized = raw.normalizedEvalToken
        return Self.allCases.first {
            $0.rawValue.normalizedEvalToken == normalized || $0.label.normalizedEvalToken == normalized
        }
    }
}

private extension String {
    var normalizedEvalToken: String {
        lowercased().replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "",
            options: .regularExpression
        )
    }
}
