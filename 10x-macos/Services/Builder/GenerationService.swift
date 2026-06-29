import Foundation

/// Events emitted by the GenerationService to the ViewModel.
/// These replace the old NDJSON events from the API stream.
enum GenerationEvent: Sendable {
    case status(BuilderGenerationStatus)
    case content(delta: String)
    case toolCallStart(toolUseId: String, name: String)
    case toolCallUpdate(toolUseId: String, label: String, inputPreview: String)
    case toolCallEnd(
        toolUseId: String,
        name: String,
        durationMs: Int,
        status: String,
        inputPreview: String,
        outputPreview: String
    )
    case readFile(path: String, content: String)
    case fileChanged(path: String, content: String, action: String)
    case planUpdate(plan: String)
    case tasksUpdate(tasks: String)
    case warningsUpdate(warnings: [BuilderProjectWarning])
    case dependenciesUpdate(manifest: ProjectDependencyManifest)
    case modeChange(mode: String)
    case projectIdentityChange(name: String)
    case askUser(questions: [[String: Any]], toolUseId: String)
    case integrationApprovalRequested(request: IntegrationApprovalRequest, toolUseId: String)
    case done(accumulatedText: String, filesChanged: Bool)
    case error(message: String)
}

enum GenerationRunOutcome: Sendable {
    case completed
    case failed(message: String)
}

/// Client-side generation service that owns the Claude tool loop.
/// Calls the thin API proxy, parses tool_use blocks, executes tools locally,
/// and sends results back — repeating until Claude is done.
actor GenerationService {
    private let api = APIClient()
    private let contextManager = BuilderContextManager()
    private let maxIterations = 80
    private let claudeProxyMaxTokens = 64_000

    struct RequestOptions: @unchecked Sendable {
        let toolChoice: [String: Any]?
        let thinking: [String: Any]?
        let outputConfig: [String: Any]?
        let cacheControl: [String: Any]?

        init(
            toolChoice: [String: Any]? = nil,
            thinking: [String: Any]? = nil,
            outputConfig: [String: Any]? = nil,
            cacheControl: [String: Any]? = nil
        ) {
            self.toolChoice = toolChoice
            self.thinking = thinking
            self.outputConfig = outputConfig
            self.cacheControl = cacheControl
        }
    }

    /// Continuation used to pause the tool loop while waiting for ask_user answers.
    private var askUserContinuation: CheckedContinuation<String, any Error>?

    /// Provide the user's answer to resume a paused ask_user tool call.
    func provideAskUserAnswer(_ answer: String) {
        askUserContinuation?.resume(returning: answer)
        askUserContinuation = nil
    }

    /// Cancel a pending ask_user pause (e.g. when the user stops generation).
    func cancelAskUser() {
        askUserContinuation?.resume(throwing: CancellationError())
        askUserContinuation = nil
    }

    /// Run a full generation loop, streaming events to the caller.
    ///
    /// - Parameters:
    ///   - systemPrompt: The mode-aware system prompt.
    ///   - claudeMessages: Message history to send to Claude.
    ///   - tools: Tool definitions for Claude.
    ///   - toolExecutor: Executes tools against real files.
    ///   - accessToken: JWT for API auth.
    ///   - onEvent: Callback for each event, delivered in order on the main actor.
    func runGeneration(
        systemPrompt: String,
        claudeMessages: [[String: Any]],
        tools: [[String: Any]],
        requestOptions: RequestOptions = RequestOptions(),
        toolExecutor: ToolExecutor,
        accessToken: String,
        accessTokenProvider: (@MainActor @Sendable () async -> String?)? = nil,
        projectId: String?,
        sessionId: String?,
        billingGroupId: String = "",
        billingMessagePreview: String? = nil,
        maxTokens: Int = 64_000,
        onClaudeCallFinished: (@Sendable () async -> Void)? = nil,
        onEvent: @MainActor @Sendable @escaping (GenerationEvent) async -> Void
    ) async -> GenerationRunOutcome {
        var messages = claudeMessages
        var pendingToolChoice = requestOptions.toolChoice
        let effectiveMaxTokens = min(max(maxTokens, 1), claudeProxyMaxTokens)
        print(
            "[billing-debug] generation.run.start billingGroupId=\(billingGroupId) sessionId=\(sessionId ?? "nil") projectId=\(projectId ?? "nil") initialMessageCount=\(messages.count) toolCount=\(tools.count) maxTokens=\(effectiveMaxTokens) preview=\(billingMessagePreview ?? "")"
        )
        // Claude API requires the last message to be role "user".
        // Strip any trailing assistant messages (e.g. from prior generation history).
        while let last = messages.last, (last["role"] as? String) == "assistant" {
            messages.removeLast()
        }

        var accumulatedText = ""
        var iteration = 0

        while iteration < maxIterations {
            iteration += 1
            let iterationRequestOptions = RequestOptions(
                toolChoice: pendingToolChoice,
                thinking: requestOptions.thinking,
                outputConfig: requestOptions.outputConfig,
                cacheControl: requestOptions.cacheControl
            )
            print(
                "[billing-debug] generation.iteration.start billingGroupId=\(billingGroupId) iteration=\(iteration) currentMessageCount=\(messages.count)"
            )

            await onEvent(.status(iteration == 1 ? .reviewingRecentWork : .workingFromLatestResults))

            let contextAccessToken: String
            do {
                contextAccessToken = try await currentAccessToken(
                    fallback: accessToken,
                    provider: accessTokenProvider
                )
            } catch {
                let message = error.localizedDescription
                await onEvent(.error(message: message))
                return .failed(message: message)
            }

            let preparedContext = await prepareRequestContext(
                system: systemPrompt,
                messages: messages,
                tools: tools,
                requestOptions: iterationRequestOptions,
                maxTokens: effectiveMaxTokens,
                accessToken: contextAccessToken
            )
            messages = preparedContext.messages
            print(
                "[10x] Context before iteration \(iteration): approx=\(preparedContext.approximateTokensBefore) exact=\(preparedContext.exactTokensBefore.map(String.init) ?? "n/a") compacted=\(preparedContext.didCompact ? "yes" : "no")."
            )
            if preparedContext.didCompact {
                print(
                    "[10x] Loop context compaction before iteration \(iteration): approx \(preparedContext.approximateTokensBefore) -> \(preparedContext.approximateTokensAfter), exact \(preparedContext.exactTokensBefore.map(String.init) ?? "n/a") -> \(preparedContext.exactTokensAfter.map(String.init) ?? "n/a"); cleared \(preparedContext.clearedToolResultCount) tool results; summarized \(preparedContext.summarizedMessageCount) messages; kept \(preparedContext.keptRecentMessageCount) recent raw messages; strategies=\(preparedContext.appliedStrategies.joined(separator: ","))"
                )
            }

            // Call Claude via the proxy
            let streamResult: StreamResult
            do {
                await onEvent(.status(.choosingNextStep))
                let requestAccessToken = try await currentAccessToken(
                    fallback: accessToken,
                    provider: accessTokenProvider
                )
                print(
                    "[billing-debug] generation.claude_call.begin billingGroupId=\(billingGroupId) iteration=\(iteration) estimatedTokens=\(preparedContext.exactTokensAfter ?? preparedContext.approximateTokensAfter) didCompact=\(preparedContext.didCompact)"
                )
                streamResult = try await callClaudeProxy(
                    system: systemPrompt,
                    messages: messages,
                    tools: tools,
                    requestOptions: iterationRequestOptions,
                    maxTokens: effectiveMaxTokens,
                    accessToken: requestAccessToken,
                    projectId: projectId,
                    sessionId: sessionId,
                    billingGroupId: billingGroupId,
                    billingMessagePreview: billingMessagePreview,
                    onEvent: onEvent
                )
                pendingToolChoice = nil
                if let onClaudeCallFinished {
                    await onClaudeCallFinished()
                }
                let toolSummary = streamResult.toolUses.map { toolUse in
                    let path = toolUse.input["path"] as? String
                    if let path, !path.isEmpty {
                        return "\(toolUse.name):\(path)"
                    }
                    return toolUse.name
                }.joined(separator: ",")
                print(
                    "[billing-debug] generation.claude_call.end billingGroupId=\(billingGroupId) iteration=\(iteration) textChars=\(streamResult.text.count) toolUses=\(streamResult.toolUses.count) tools=[\(toolSummary)]"
                )
            } catch {
                pendingToolChoice = nil
                if let onClaudeCallFinished {
                    await onClaudeCallFinished()
                }
                let message = error.localizedDescription
                print(
                    "[billing-debug] generation.claude_call.error billingGroupId=\(billingGroupId) iteration=\(iteration) error=\(message)"
                )
                await onEvent(.error(message: message))
                return .failed(message: message)
            }

            accumulatedText += streamResult.text

            // No tool calls means Claude is done
            if streamResult.toolUses.isEmpty {
                let hasChanges = await toolExecutor.filesChanged.count > 0
                print(
                    "[billing-debug] generation.run.complete billingGroupId=\(billingGroupId) iterations=\(iteration) filesChanged=\(hasChanges)"
                )
                await onEvent(.done(accumulatedText: accumulatedText, filesChanged: hasChanges))
                return .completed
            }

            // Build assistant message for conversation history
            var assistantContent: [[String: Any]] = []
            if !streamResult.text.isEmpty {
                assistantContent.append(["type": "text", "text": streamResult.text])
            }
            for tu in streamResult.toolUses {
                assistantContent.append([
                    "type": "tool_use",
                    "id": tu.id,
                    "name": tu.name,
                    "input": tu.input,
                ])
            }
            messages.append(["role": "assistant", "content": assistantContent])

            // Execute each tool and collect results
            var toolResultBlocks: [[String: Any]] = []

            for tu in streamResult.toolUses {
                let t0 = Date()
                let inputPreview = BuilderToolPresentation.inputPreview(name: tu.name, input: tu.input)
                await onEvent(.status(BuilderToolPresentation.generationStatus(name: tu.name, input: tu.input)))
                await onEvent(.toolCallStart(toolUseId: tu.id, name: tu.name))
                await onEvent(.toolCallUpdate(
                    toolUseId: tu.id,
                    label: BuilderToolPresentation.detailedLabel(name: tu.name, input: tu.input),
                    inputPreview: inputPreview
                ))

                // ask_user: pause the loop and wait for the user's answer
                if tu.name == "ask_user" {
                    let questions = tu.input["questions"] as? [[String: Any]] ?? []
                    await onEvent(.askUser(questions: questions, toolUseId: tu.id))

                    // Suspend until the ViewModel provides the answer
                    let answer: String
                    do {
                        answer = try await withCheckedThrowingContinuation { continuation in
                            self.askUserContinuation = continuation
                        }
                    } catch {
                        // Generation was cancelled while waiting
                        return .failed(message: "Generation cancelled.")
                    }

                    let durationMs = Int(Date().timeIntervalSince(t0) * 1000)
                    await onEvent(.toolCallEnd(
                        toolUseId: tu.id,
                        name: tu.name,
                        durationMs: durationMs,
                        status: "success",
                        inputPreview: inputPreview,
                        outputPreview: String(answer.prefix(200))
                    ))

                    toolResultBlocks.append([
                        "type": "tool_result",
                        "tool_use_id": tu.id,
                        "content": answer,
                    ])
                    continue
                }

                // Execute the tool
                let result = await executeToolHandlingApproval(
                    toolExecutor: toolExecutor,
                    toolUse: tu,
                    onEvent: onEvent
                )
                let durationMs = Int(Date().timeIntervalSince(t0) * 1000)

                // Emit file events for UI updates
                if let fe = result.fileEvent {
                    await onEvent(.fileChanged(path: fe.path, content: fe.content, action: fe.action))
                }
                if tu.name == "read_files",
                   let paths = tu.input["paths"] as? [String],
                   !result.text.hasPrefix("Error:") {
                    if paths.count == 1, let path = paths.first {
                        await onEvent(.readFile(path: path, content: result.text))
                    } else {
                        for path in paths {
                            let marker = "--- \(path) ---\n"
                            if let range = result.text.range(of: marker) {
                                let afterMarker = result.text[range.upperBound...]
                                let nextMarker = afterMarker.range(of: "\n\n--- ")
                                let content = nextMarker.map { String(afterMarker[..<$0.lowerBound]) } ?? String(afterMarker)
                                if !content.hasPrefix("Error:") {
                                    await onEvent(.readFile(path: path, content: content))
                                }
                            }
                        }
                    }
                }

                if tu.name == "update_project_status" {
                    if let plan = tu.input["plan"] as? String, !plan.isEmpty {
                        await onEvent(.planUpdate(plan: plan))
                    }
                    if let tasks = tu.input["tasks"] as? String, !tasks.isEmpty {
                        await onEvent(.tasksUpdate(tasks: tasks))
                    }
                    if tu.input.keys.contains("warnings"),
                       let warnings = BuilderProjectWarning.decodeList(from: tu.input["warnings"]) {
                        await onEvent(.warningsUpdate(warnings: warnings))
                    }
                }

                if tu.name == "update_project_dependencies",
                   let manifest = ProjectDependencyManifest(toolInput: tu.input) {
                    await onEvent(.dependenciesUpdate(manifest: manifest))
                }

                if let refresh = result.contextRefresh {
                    switch refresh {
                    case .modeChange(let mode):
                        await onEvent(.modeChange(mode: mode))
                    case .projectIdentityChange(let name):
                        await onEvent(.projectIdentityChange(name: name))
                    }
                }

                // Emit tool end event
                await onEvent(.toolCallEnd(
                    toolUseId: tu.id,
                    name: tu.name,
                    durationMs: durationMs,
                    status: result.text.hasPrefix("Error:") ? "error" : "success",
                    inputPreview: inputPreview,
                    outputPreview: String(result.text.prefix(2000))
                ))

                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": tu.id,
                    "content": result.text,
                ])

                if result.contextRefresh != nil {
                    let hasChanges = await toolExecutor.filesChanged.count > 0
                    await onEvent(.done(accumulatedText: accumulatedText, filesChanged: hasChanges))
                    return .completed
                }
            }

            messages.append(["role": "user", "content": toolResultBlocks])
        }

        print("[10x] Generation stopped after reaching max tool iterations (\(maxIterations)).")
        print("[billing-debug] generation.run.max_iterations billingGroupId=\(billingGroupId) iterations=\(maxIterations)")
        let hasChanges = await toolExecutor.filesChanged.count > 0
        await onEvent(.done(accumulatedText: accumulatedText, filesChanged: hasChanges))
        let message = "Generation stopped after \(maxIterations) tool iterations without reaching a final answer. The model was likely looping. Retry with a narrower request if needed."
        await onEvent(.error(message: message))
        return .failed(message: message)
    }

    // MARK: - Claude Proxy Call

    private struct StreamResult {
        var text: String = ""
        var toolUses: [ToolUse] = []
    }

    private func executeToolHandlingApproval(
        toolExecutor: ToolExecutor,
        toolUse: ToolUse,
        onEvent: @MainActor @Sendable @escaping (GenerationEvent) async -> Void
    ) async -> ToolResult {
        let initialResult = await toolExecutor.execute(toolName: toolUse.name, input: toolUse.input)
        guard let approvalRequest = initialResult.approvalRequest else {
            return initialResult
        }

        await onEvent(.status(.needPermissionToContinue))
        await onEvent(.integrationApprovalRequested(request: approvalRequest, toolUseId: toolUse.id))

        let answer: String
        do {
            answer = try await withCheckedThrowingContinuation { continuation in
                self.askUserContinuation = continuation
            }
        } catch {
            return ToolResult(text: "Error: generation cancelled.", fileEvent: nil)
        }

        guard Self.isApprovalGranted(answer) else {
            return ToolResult(
                text: "Error: \(approvalRequest.integrationName) access was not approved by the user.",
                fileEvent: nil
            )
        }

        await toolExecutor.grantIntegrationApproval(approvalRequest)
        let retriedResult = await toolExecutor.execute(toolName: toolUse.name, input: toolUse.input)
        if retriedResult.approvalRequest != nil {
            return ToolResult(
                text: "Error: approval was granted, but the \(approvalRequest.integrationName) action still could not continue.",
                fileEvent: nil
            )
        }
        return retriedResult
    }

    private nonisolated static func isApprovalGranted(_ answer: String) -> Bool {
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.contains("don't allow") || normalized.contains("do not allow") || normalized.contains("deny") || normalized == "no" {
            return false
        }
        return normalized.contains("allow") || normalized.contains("approve") || normalized == "yes"
    }

    private struct PreparedRequestContext {
        let messages: [[String: Any]]
        let approximateTokensBefore: Int
        let approximateTokensAfter: Int
        let exactTokensBefore: Int?
        let exactTokensAfter: Int?
        let didCompact: Bool
        let summarizedMessageCount: Int
        let keptRecentMessageCount: Int
        let clearedToolResultCount: Int
        let appliedStrategies: [String]
    }

    private struct ToolUse {
        let id: String
        let name: String
        let input: [String: Any]
    }

    /// Call the Claude proxy and parse the NDJSON stream into text + tool_use blocks.
    private func callClaudeProxy(
        system: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        requestOptions: RequestOptions,
        maxTokens: Int,
        accessToken: String,
        projectId: String?,
        sessionId: String?,
        billingGroupId: String = "",
        billingMessagePreview: String? = nil,
        onEvent: @MainActor @Sendable @escaping (GenerationEvent) async -> Void
    ) async throws -> StreamResult {
        var body: [String: Any] = [
            "system": system,
            "messages": messages,
            "tools": tools,
            "max_tokens": maxTokens,
            "idempotency_key": UUID().uuidString,
            "billing_group_id": billingGroupId,
        ]
        if let billingMessagePreview, !billingMessagePreview.isEmpty {
            body["billing_message_preview"] = billingMessagePreview
        }
        if let projectId {
            body["project_id"] = projectId
        }
        if let sessionId {
            body["session_id"] = sessionId
        }
        if let toolChoice = requestOptions.toolChoice {
            body["tool_choice"] = toolChoice
        }
        if let thinking = requestOptions.thinking {
            body["thinking"] = thinking
        }
        if let outputConfig = requestOptions.outputConfig {
            body["output_config"] = outputConfig
        }
        if let cacheControl = requestOptions.cacheControl {
            body["cache_control"] = cacheControl
        }

        print(
            "[billing-debug] generation.proxy.request billingGroupId=\(billingGroupId) sessionId=\(sessionId ?? "nil") projectId=\(projectId ?? "nil") messageCount=\(messages.count) toolCount=\(tools.count) maxTokens=\(maxTokens)"
        )

        let rawLines = try await api.stream(
            APIClient.builder("claude/stream"),
            method: "POST",
            json: body,
            accessToken: accessToken
        )

        var result = StreamResult()
        var currentBlockType: String?
        var currentToolId = ""
        var currentToolName = ""
        var currentToolJson = ""

        for try await line in rawLines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }

            switch type {
            case "content_block_start":
                if let block = json["content_block"] as? [String: Any],
                   let blockType = block["type"] as? String {
                    currentBlockType = blockType
                    if blockType == "tool_use" {
                        currentToolId = block["id"] as? String ?? ""
                        currentToolName = block["name"] as? String ?? ""
                        currentToolJson = ""
                        await onEvent(.status(BuilderToolPresentation.generationStatus(name: currentToolName)))
                    }
                }

            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let deltaType = delta["type"] as? String {
                    if deltaType == "text_delta", let text = delta["text"] as? String {
                        result.text += text
                        await onEvent(.content(delta: text))
                    } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                        currentToolJson += partial
                    }
                }

            case "content_block_stop":
                if currentBlockType == "tool_use" {
                    let input: [String: Any]
                    if let data = currentToolJson.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        input = parsed
                    } else {
                        input = [:]
                    }
                    await onEvent(.status(BuilderToolPresentation.generationStatus(name: currentToolName, input: input)))
                    result.toolUses.append(ToolUse(id: currentToolId, name: currentToolName, input: input))
                }
                currentBlockType = nil

            case "error":
                let message = json["message"] as? String ?? "Unknown error"
                throw GenerationError.apiError(message)

            case "message_start":
                await onEvent(.status(.workingThroughRequest))

            case "message_delta":
                if let delta = json["delta"] as? [String: Any],
                   let stopReason = delta["stop_reason"] as? String,
                   stopReason == "max_tokens" {
                    throw GenerationError.apiError("Response was cut off (max tokens reached). Try breaking your request into smaller steps.")
                }

            case "message_stop":
                break

            default:
                break
            }
        }

        print(
            "[billing-debug] generation.proxy.response billingGroupId=\(billingGroupId) textChars=\(result.text.count) toolUses=\(result.toolUses.count)"
        )

        return result
    }

    // MARK: - Helpers

    private func prepareRequestContext(
        system: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        requestOptions: RequestOptions,
        maxTokens: Int,
        accessToken: String
    ) async -> PreparedRequestContext {
        let prepared = await contextManager.prepareLoopContext(
            system: system,
            messages: messages,
            tools: tools,
            requestOptions: requestOptions,
            maxTokens: maxTokens,
            accessToken: accessToken
        )

        return PreparedRequestContext(
            messages: prepared.messages,
            approximateTokensBefore: prepared.approximateInputTokensBefore,
            approximateTokensAfter: prepared.approximateInputTokensAfter,
            exactTokensBefore: prepared.exactInputTokensBefore,
            exactTokensAfter: prepared.exactInputTokensAfter,
            didCompact: prepared.didCompact,
            summarizedMessageCount: prepared.summarizedMessageCount,
            keptRecentMessageCount: prepared.keptRecentMessageCount,
            clearedToolResultCount: prepared.clearedToolResultCount,
            appliedStrategies: prepared.appliedStrategies
        )
    }

    private func currentAccessToken(
        fallback: String,
        provider: (@MainActor @Sendable () async -> String?)?
    ) async throws -> String {
        if let provider {
            guard let accessToken = await provider() else {
                throw APIError.unauthorized
            }
            return accessToken
        }

        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.unauthorized
        }
        return trimmed
    }

}

enum GenerationError: LocalizedError {
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return msg
        }
    }
}
