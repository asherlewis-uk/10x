import Foundation

enum BuilderGenerationRequestType {
    case neutral
    case plan
    case build
    case liveSetup
}

struct BuilderModeSwitchDecision {
    let mode: ProjectMode
    let detail: String
}

enum BuilderGenerationRequestPlanner {
    static func validateDraft(
        text: String,
        attachments: [BuilderMessageAttachment],
        maxInlineTextAttachmentTokens: Int
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else {
            return "Add a message or attach a file."
        }

        if let secretWarning = ProjectEnvironmentSecurity.secretPasteWarning(in: trimmed) {
            return secretWarning
        }

        let inlineTextTokens = attachments.reduce(0) { partial, attachment in
            partial + (attachment.kind == .text ? attachment.approximateContextTokens : 0)
        }
        if inlineTextTokens > maxInlineTextAttachmentTokens {
            return "These text/code files are within the 5 MB attachment limit but too large to fit in Claude's current context window. Use smaller text files or upload a PDF/image instead."
        }

        return nil
    }

    static func classifyGenerationRequest(
        requestText: String,
        isBuildFix: Bool,
        messageAction: BuilderMessageAction? = nil
    ) -> BuilderGenerationRequestType {
        let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isBuildFix || messageAction == .executePlan {
            return .build
        }
        if isExplicitLiveSetupRequest(trimmed) {
            return .liveSetup
        }
        if isPlanningRequest(trimmed) {
            return .plan
        }
        return .neutral
    }

    static func explicitModeSwitch(
        for messageAction: BuilderMessageAction?,
        currentMode: ProjectMode
    ) -> BuilderModeSwitchDecision? {
        guard messageAction == .executePlan, currentMode != .build else {
            return nil
        }

        return BuilderModeSwitchDecision(
            mode: .build,
            detail: "Start Building was selected, so the project is continuing in build mode."
        )
    }

    static func toolsForGeneration(
        requestType: BuilderGenerationRequestType,
        mode: ProjectMode,
        integrationAvailability: BuilderIntegrationToolAvailability = .none
    ) -> [[String: Any]] {
        _ = requestType
        return BuilderToolDefinitions.tools(
            for: mode,
            integrationAvailability: integrationAvailability
        )
    }

    static func requestOptionsForGeneration(
        requestType: BuilderGenerationRequestType
    ) -> GenerationService.RequestOptions {
        let effort: String
        switch requestType {
        case .neutral:
            effort = "low"
        case .plan:
            effort = "low"
        case .build:
            effort = "medium"
        case .liveSetup:
            effort = "medium"
        }

        let toolChoice = toolChoiceForGeneration(requestType: requestType)

        return GenerationService.RequestOptions(
            toolChoice: toolChoice,
            thinking: toolChoice == nil ? ["type": "adaptive"] : nil,
            outputConfig: ["effort": effort],
            cacheControl: ["type": "ephemeral"]
        )
    }

    static func shouldSuppressIntermediateAssistantText(
        requestType: BuilderGenerationRequestType,
        mode: ProjectMode,
        hasFileTree: Bool
    ) -> Bool {
        _ = requestType
        _ = mode
        _ = hasFileTree
        return false
    }

    static func billingMessagePreview(from text: String) -> String? {
        let trimmed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let collapsed = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(collapsed.prefix(140))
    }

    static func isConnectionFailureMessage(_ message: String) -> Bool {
        matches(
            message,
            patterns: [
                #"\btimed?\s*out\b"#,
                #"\binterrupt(ed|ion)?\b"#,
                #"\bnetwork\b"#,
                #"\bconnection\b"#,
                #"\bstream\s+closed\b"#,
                #"\brequest\s+cancel(l)?ed\b"#,
            ]
        )
    }

    private static func matches(_ text: String, patterns: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let searchRange = NSRange(trimmed.startIndex..., in: trimmed)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            if regex.firstMatch(in: trimmed, options: [], range: searchRange) != nil {
                return true
            }
        }

        return false
    }

    private static func toolChoiceForGeneration(
        requestType: BuilderGenerationRequestType
    ) -> [String: Any]? {
        switch requestType {
        case .liveSetup:
            return [
                "type": "tool",
                "name": "update_project_dependencies",
            ]
        case .neutral, .plan, .build:
            return nil
        }
    }

    private static func isPlanningRequest(_ text: String) -> Bool {
        matches(
            text,
            patterns: [
                #"\bproject\s+plan\b"#,
                #"\broadmap\b"#,
                #"\bplan\s+out\b"#,
                #"\bbrainstorm\b"#,
                #"\bresearch\b"#,
            ]
        )
    }

    private static func isExplicitLiveSetupRequest(_ text: String) -> Bool {
        let mentionsIntegration = matches(
            text,
            patterns: [
                #"\bsupabase\b"#,
                #"\bsuperwall\b"#,
                #"\bauth(?:entication)?\b"#,
                #"\bgoogle\s+sign[\s-]?in\b"#,
                #"\bapple\s+sign[\s-]?in\b"#,
                #"\bmagic\s+link\b"#,
                #"\bemail\s+confirmation\b"#,
                #"\bbackend\b"#,
                #"\bedge\s+function(?:s)?\b"#,
                #"\bpaywall(?:s)?\b"#,
                #"\bsubscription(?:s)?\b"#,
            ]
        )
        guard mentionsIntegration else { return false }

        return matches(
            text,
            patterns: [
                #"\breal\b"#,
                #"\blive\b"#,
                #"\bproduction\b"#,
                #"\bwire(?:d|ing)?(?:\s+in|\s+up)?\b"#,
                #"\bhook(?:ed|ing)?\s+up\b"#,
                #"\bset\s*up\b"#,
                #"\bconnect\b"#,
                #"\bimplement\b"#,
                #"\bworking\b"#,
            ]
        )
    }
}
