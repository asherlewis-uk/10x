import Foundation

struct BuilderPreparedConversationContext {
    let messages: [[String: Any]]
    let approximateInputTokens: Int
    let exactInputTokens: Int?
    let usedContextMemory: Bool
    let includedRawMessageCount: Int
    let omittedRawMessageCount: Int
    let includedWorkingFileCount: Int
    let contextState: BuilderContextState
}

struct BuilderPreparedLoopContext {
    let messages: [[String: Any]]
    let approximateInputTokensBefore: Int
    let approximateInputTokensAfter: Int
    let exactInputTokensBefore: Int?
    let exactInputTokensAfter: Int?
    let didCompact: Bool
    let keptRecentMessageCount: Int
    let summarizedMessageCount: Int
    let clearedToolResultCount: Int
    let appliedStrategies: [String]
}

final class BuilderContextManager {
    private struct ToolUseReceipt {
        let name: String
        let input: [String: Any]
    }

    private let defaultModel = Config.openAIModel

    private let turnSoftLimitTokens = 34_000
    private let turnTargetTokens = 26_000
    private let loopSoftLimitTokens = 48_000
    private let loopTargetTokens = 34_000
    private let exactCountTriggerTokens = 22_000

    nonisolated init() {}

    func deriveContextState(
        messages: [BuilderMessage],
        timeline: [BuilderChatTimelineItem],
        cachedReadFiles: [String: String],
        cachedReadFileOrder: [String],
        projectPlan: String?,
        projectTasks: String?
    ) -> BuilderContextState {
        let visibleMessages = messages.filter {
            if $0.role == "build_fix" || $0.isInternalRestartNote {
                return false
            }
            return $0.role == "user" || $0.hasVisibleContent
        }

        let userMessages = visibleMessages.filter { $0.role == "user" && !$0.isInternalRestartNote }
        let assistantMessages = visibleMessages.filter { $0.role == "assistant" && $0.hasVisibleContent }

        let recentRequests = Array(
            userMessages
                .compactMap(\.previewText)
                .reversed()
                .prefix(6)
                .reversed()
        )

        var taskOverview: [String] = []
        if let firstRequest = userMessages.first?.previewText {
            taskOverview.append(firstRequest)
        }
        if let latestRequest = userMessages.last?.previewText,
           latestRequest != taskOverview.last {
            taskOverview.append(latestRequest)
        }
        if let planLine = firstMeaningfulLine(in: projectPlan),
           !taskOverview.contains(planLine) {
            taskOverview.append(planLine)
        }

        var currentState: [String] = []
        if let latestAssistant = assistantMessages.last?.previewText {
            currentState.append("Latest assistant state: \(latestAssistant)")
        }
        if !cachedReadFiles.isEmpty {
            currentState.append("Working set contains \(cachedReadFiles.count) cached file snapshot(s).")
        }
        if let taskSummary = firstMeaningfulLine(in: projectTasks) {
            currentState.append("Milestone snapshot: \(taskSummary)")
        }

        let decisions = trimmedBulletItems(from: projectPlan, limit: 4)

        let artifacts = extractArtifacts(from: timeline)
        let blockers = artifacts
            .filter { artifact in
                let normalized = artifact.detail.lowercased()
                return normalized.contains("error:")
                    || normalized.contains("failed")
                    || normalized.contains("timed out")
                    || normalized.contains("not found")
            }
            .map { "\($0.title): \(compact($0.detail, maxLength: 140))" }
            .prefix(4)

        var nextSteps = trimmedChecklistItems(from: projectTasks, limit: 5)
        if nextSteps.isEmpty, let latestRequest = userMessages.last?.previewText {
            nextSteps = ["Continue from the latest user request: \(latestRequest)"]
        }

        let userPreferences = extractPreferenceSnippets(from: userMessages)
        let filesInFocus = Array(
            cachedReadFileOrder
                .reversed()
                .filter { cachedReadFiles[$0] != nil }
                .prefix(8)
                .reversed()
        )

        return BuilderContextState(
            taskOverview: deduplicated(taskOverview).prefix(4).map { $0 },
            currentState: deduplicated(currentState).prefix(6).map { $0 },
            decisions: Array(deduplicated(decisions).prefix(6)),
            blockers: Array(deduplicated(Array(blockers)).prefix(4)),
            nextSteps: Array(deduplicated(nextSteps).prefix(6)),
            userPreferences: Array(deduplicated(userPreferences).prefix(6)),
            filesInFocus: filesInFocus,
            recentRequests: recentRequests,
            artifacts: Array(artifacts.prefix(10)),
            updatedAt: BuilderChat.timestamp()
        )
    }

    func prepareConversationContext(
        system: String,
        messages: [BuilderMessage],
        timeline: [BuilderChatTimelineItem],
        cachedReadFiles: [String: String],
        cachedReadFileOrder: [String],
        projectPlan: String?,
        projectTasks: String?,
        prefixMessages: [String] = [],
        preUserMessages: [String] = [],
        tools: [[String: Any]],
        requestOptions: GenerationService.RequestOptions,
        maxTokens: Int,
        accessToken: String,
        model: String? = nil
    ) async -> BuilderPreparedConversationContext {
        let visibleMessages = messages.filter {
            if $0.role == "build_fix" { return false }
            if $0.role == "user" { return true }
            return $0.hasVisibleContent
        }

        let contextState = deriveContextState(
            messages: messages,
            timeline: timeline,
            cachedReadFiles: cachedReadFiles,
            cachedReadFileOrder: cachedReadFileOrder,
            projectPlan: projectPlan,
            projectTasks: projectTasks
        )

        var recentRawMessageCount = min(10, visibleMessages.count)
        var workingFileCount = min(4, cachedReadFiles.count)
        var workingFileCharBudget = 12_000
        var memoryArtifactLimit = 8

        var assembled = assembleConversationMessages(
            visibleMessages: visibleMessages,
            contextState: contextState,
            cachedReadFiles: cachedReadFiles,
            cachedReadFileOrder: cachedReadFileOrder,
            prefixMessages: prefixMessages,
            preUserMessages: preUserMessages,
            recentRawMessageCount: recentRawMessageCount,
            workingFileCount: workingFileCount,
            workingFileCharBudget: workingFileCharBudget,
            memoryArtifactLimit: memoryArtifactLimit
        )
        var approximateTokens = approximateRequestTokens(
            system: system,
            messages: assembled,
            tools: tools,
            requestOptions: requestOptions,
            maxTokens: maxTokens
        )

        var trimAttempts = 0
        while approximateTokens > turnTargetTokens && trimAttempts < 8 {
            trimAttempts += 1
            if workingFileCharBudget > 8_000 {
                workingFileCharBudget = 8_000
            } else if workingFileCharBudget > 4_000 {
                workingFileCharBudget = 4_000
            } else if workingFileCount > 2 {
                workingFileCount -= 1
            } else if recentRawMessageCount > 6 {
                recentRawMessageCount -= 2
            } else if memoryArtifactLimit > 4 {
                memoryArtifactLimit -= 2
            } else if recentRawMessageCount > 4 {
                recentRawMessageCount -= 1
            } else {
                break
            }

            assembled = assembleConversationMessages(
                visibleMessages: visibleMessages,
                contextState: contextState,
                cachedReadFiles: cachedReadFiles,
                cachedReadFileOrder: cachedReadFileOrder,
                prefixMessages: prefixMessages,
                preUserMessages: preUserMessages,
                recentRawMessageCount: recentRawMessageCount,
                workingFileCount: workingFileCount,
                workingFileCharBudget: workingFileCharBudget,
                memoryArtifactLimit: memoryArtifactLimit
            )
            approximateTokens = approximateRequestTokens(
                system: system,
                messages: assembled,
                tools: tools,
                requestOptions: requestOptions,
                maxTokens: maxTokens
            )
        }

        var exactTokens: Int?
        if approximateTokens >= exactCountTriggerTokens {
            exactTokens = await countTokens(
                system: system,
                messages: assembled,
                tools: tools,
                requestOptions: requestOptions,
                model: model ?? defaultModel,
                accessToken: accessToken
            )

            var exactTrimAttempts = 0
            while let currentExactTokens = exactTokens,
                  currentExactTokens > turnSoftLimitTokens,
                  exactTrimAttempts < 6 {
                exactTrimAttempts += 1
                if workingFileCount > 1 {
                    workingFileCount -= 1
                } else if recentRawMessageCount > 4 {
                    recentRawMessageCount -= 1
                } else if workingFileCharBudget > 0 {
                    workingFileCharBudget = max(0, workingFileCharBudget - 2_000)
                } else {
                    break
                }

                assembled = assembleConversationMessages(
                    visibleMessages: visibleMessages,
                    contextState: contextState,
                    cachedReadFiles: cachedReadFiles,
                    cachedReadFileOrder: cachedReadFileOrder,
                    prefixMessages: prefixMessages,
                    preUserMessages: preUserMessages,
                    recentRawMessageCount: recentRawMessageCount,
                    workingFileCount: workingFileCount,
                    workingFileCharBudget: workingFileCharBudget,
                    memoryArtifactLimit: memoryArtifactLimit
                )
                approximateTokens = approximateRequestTokens(
                    system: system,
                    messages: assembled,
                    tools: tools,
                    requestOptions: requestOptions,
                    maxTokens: maxTokens
                )
                exactTokens = await countTokens(
                    system: system,
                    messages: assembled,
                    tools: tools,
                    requestOptions: requestOptions,
                    model: model ?? defaultModel,
                    accessToken: accessToken
                )
            }
        }

        let omittedRawMessageCount = max(visibleMessages.count - recentRawMessageCount, 0)
        let includedWorkingFileCount = countWorkingFiles(in: assembled)

        return BuilderPreparedConversationContext(
            messages: assembled,
            approximateInputTokens: approximateTokens,
            exactInputTokens: exactTokens,
            usedContextMemory: omittedRawMessageCount > 0 && contextState.hasContent,
            includedRawMessageCount: min(recentRawMessageCount, visibleMessages.count),
            omittedRawMessageCount: omittedRawMessageCount,
            includedWorkingFileCount: includedWorkingFileCount,
            contextState: contextState
        )
    }

    func prepareLoopContext(
        system: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        requestOptions: GenerationService.RequestOptions,
        maxTokens: Int,
        accessToken: String,
        model: String? = nil
    ) async -> BuilderPreparedLoopContext {
        let approximateBefore = approximateRequestTokens(
            system: system,
            messages: messages,
            tools: tools,
            requestOptions: requestOptions,
            maxTokens: maxTokens
        )
        let exactBefore = approximateBefore >= exactCountTriggerTokens
            ? await countTokens(
                system: system,
                messages: messages,
                tools: tools,
                requestOptions: requestOptions,
                model: model ?? defaultModel,
                accessToken: accessToken
            )
            : nil

        let beforeBudget = exactBefore ?? approximateBefore
        guard beforeBudget > loopSoftLimitTokens, messages.count > 4 else {
            return BuilderPreparedLoopContext(
                messages: messages,
                approximateInputTokensBefore: approximateBefore,
                approximateInputTokensAfter: approximateBefore,
                exactInputTokensBefore: exactBefore,
                exactInputTokensAfter: exactBefore,
                didCompact: false,
                keptRecentMessageCount: messages.count,
                summarizedMessageCount: 0,
                clearedToolResultCount: 0,
                appliedStrategies: []
            )
        }

        var workingMessages = messages
        var appliedStrategies: [String] = []

        let toolClearing = clearOlderToolResults(in: workingMessages, keepRecentToolResultMessages: 3)
        if toolClearing.clearedToolResultCount > 0 {
            workingMessages = toolClearing.messages
            appliedStrategies.append("tool_result_receipts")
        }
        let toolClearedMessages = workingMessages

        var approximateAfter = approximateRequestTokens(
            system: system,
            messages: workingMessages,
            tools: tools,
            requestOptions: requestOptions,
            maxTokens: maxTokens
        )

        var keptRecentMessageCount = workingMessages.count
        var summarizedMessageCount = 0

        if approximateAfter > loopTargetTokens {
            let summaryCandidate = compactLoopHistory(
                baseMessages: toolClearedMessages,
                keepOptions: [8, 6, 4],
                system: system,
                tools: tools,
                requestOptions: requestOptions,
                maxTokens: maxTokens
            )

            if summaryCandidate.approximateTokens < approximateAfter {
                workingMessages = summaryCandidate.messages
                approximateAfter = summaryCandidate.approximateTokens
                keptRecentMessageCount = summaryCandidate.keptRecentMessageCount
                summarizedMessageCount = summaryCandidate.summarizedMessageCount
                appliedStrategies.append("structured_loop_summary")
            }
        }

        var exactAfter = approximateAfter >= exactCountTriggerTokens
            ? await countTokens(
                system: system,
                messages: workingMessages,
                tools: tools,
                requestOptions: requestOptions,
                model: model ?? defaultModel,
                accessToken: accessToken
            )
            : nil

        if let currentExactAfter = exactAfter,
           currentExactAfter > loopSoftLimitTokens,
           toolClearedMessages.count > 4 {
            let aggressiveSummary = compactLoopHistory(
                baseMessages: toolClearedMessages,
                keepOptions: [6, 4, 3, 2],
                system: system,
                tools: tools,
                requestOptions: requestOptions,
                maxTokens: maxTokens
            )

            if aggressiveSummary.approximateTokens < approximateAfter {
                workingMessages = aggressiveSummary.messages
                approximateAfter = aggressiveSummary.approximateTokens
                keptRecentMessageCount = aggressiveSummary.keptRecentMessageCount
                summarizedMessageCount = aggressiveSummary.summarizedMessageCount
                if !appliedStrategies.contains("structured_loop_summary") {
                    appliedStrategies.append("structured_loop_summary")
                }
                if !appliedStrategies.contains("exact_budget_trim") {
                    appliedStrategies.append("exact_budget_trim")
                }
                exactAfter = approximateAfter >= exactCountTriggerTokens
                    ? await countTokens(
                        system: system,
                        messages: workingMessages,
                        tools: tools,
                        requestOptions: requestOptions,
                        model: model ?? defaultModel,
                        accessToken: accessToken
                    )
                    : nil
            }
        }

        return BuilderPreparedLoopContext(
            messages: workingMessages,
            approximateInputTokensBefore: approximateBefore,
            approximateInputTokensAfter: approximateAfter,
            exactInputTokensBefore: exactBefore,
            exactInputTokensAfter: exactAfter,
            didCompact: !appliedStrategies.isEmpty,
            keptRecentMessageCount: keptRecentMessageCount,
            summarizedMessageCount: summarizedMessageCount,
            clearedToolResultCount: toolClearing.clearedToolResultCount,
            appliedStrategies: appliedStrategies
        )
    }

    private func assembleConversationMessages(
        visibleMessages: [BuilderMessage],
        contextState: BuilderContextState,
        cachedReadFiles: [String: String],
        cachedReadFileOrder: [String],
        prefixMessages: [String],
        preUserMessages: [String],
        recentRawMessageCount: Int,
        workingFileCount: Int,
        workingFileCharBudget: Int,
        memoryArtifactLimit: Int
    ) -> [[String: Any]] {
        let rawMessages = Array(visibleMessages.suffix(max(recentRawMessageCount, 0)))
        let omittedRawMessageCount = max(visibleMessages.count - rawMessages.count, 0)

        var assembled: [[String: Any]] = prefixMessages.map { message in
            [
                "role": "assistant",
                "content": message,
            ]
        }

        assembled += rawMessages.map {
            [
                "role": $0.role,
                "content": $0.claudeMessageContent(),
            ]
        }

        if omittedRawMessageCount > 0 && contextState.hasContent {
            var compactedState = contextState
            compactedState.artifacts = Array(compactedState.artifacts.prefix(memoryArtifactLimit))
            assembled.insert(
                [
                    "role": "assistant",
                    "content": compactedState.promptBlock(maxArtifactCount: memoryArtifactLimit),
                ],
                at: assembled.startIndex + prefixMessages.count
            )
        }

        for message in preUserMessages {
            let contextMessage: [String: Any] = [
                "role": "assistant",
                "content": message,
            ]
            if let last = assembled.last, (last["role"] as? String) == "user" {
                assembled.insert(contextMessage, at: max(assembled.count - 1, 0))
            } else {
                assembled.append(contextMessage)
            }
        }

        if let workingSetMessage = makeWorkingSetMessage(
            cachedReadFiles: cachedReadFiles,
            cachedReadFileOrder: cachedReadFileOrder,
            maxFiles: workingFileCount,
            maxChars: workingFileCharBudget
        ) {
            let contextMessage: [String: Any] = [
                "role": "assistant",
                "content": workingSetMessage,
            ]
            if let last = assembled.last, (last["role"] as? String) == "user" {
                assembled.insert(contextMessage, at: max(assembled.count - 1, 0))
            } else {
                assembled.append(contextMessage)
            }
        }

        return assembled
    }

    private func makeWorkingSetMessage(
        cachedReadFiles: [String: String],
        cachedReadFileOrder: [String],
        maxFiles: Int,
        maxChars: Int
    ) -> String? {
        guard maxFiles > 0, maxChars > 0, !cachedReadFiles.isEmpty else {
            return nil
        }

        var selected: [(path: String, content: String, full: Bool)] = []
        var remainingChars = maxChars

        for path in cachedReadFileOrder.reversed() {
            guard let content = cachedReadFiles[path], !content.isEmpty else { continue }
            if selected.count >= maxFiles { break }

            let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }

            let reserve = max(800, remainingChars / max(1, maxFiles - selected.count))
            let full = normalized.count <= reserve
            let chosenContent: String
            if full {
                chosenContent = normalized
            } else {
                let prefix = String(normalized.prefix(max(600, reserve)))
                chosenContent = prefix + "\n... [snapshot truncated; re-run read_files before editing if exact contents matter]"
            }

            selected.append((path: path, content: chosenContent, full: full))
            remainingChars -= min(chosenContent.count, remainingChars)
            if remainingChars <= 600 { break }
        }

        guard !selected.isEmpty else { return nil }

        let sections = selected.reversed().map { entry in
            """
            <file path="\(entry.path)" mode="\(entry.full ? "full" : "excerpt")">
            \(entry.content)
            </file>
            """
        }

        let omittedCount = max(cachedReadFiles.count - selected.count, 0)
        let omittedNote = omittedCount > 0
            ? "\n\n\(omittedCount) older cached file snapshot(s) were omitted to stay within prompt limits."
            : ""

        return """
        <working_set>
        Recent file snapshots from prior reads and writes. Treat them as convenience context that may be stale if files changed afterwards. Re-run `read_files` before editing if exact contents matter.

        \(sections.joined(separator: "\n\n"))\(omittedNote)
        </working_set>
        """
    }

    private func countWorkingFiles(in messages: [[String: Any]]) -> Int {
        guard let workingSetMessage = messages.first(where: {
            ($0["content"] as? String)?.contains("<working_set>") == true
        })?["content"] as? String else {
            return 0
        }

        return workingSetMessage.components(separatedBy: "<file path=").count - 1
    }

    private func clearOlderToolResults(
        in messages: [[String: Any]],
        keepRecentToolResultMessages: Int
    ) -> (messages: [[String: Any]], clearedToolResultCount: Int) {
        let toolUseReceipts = toolUseReceiptsByID(from: messages)
        let toolResultMessageIndices = messages.indices.filter { containsToolResult(in: messages[$0]) }
        let indicesToClear = toolResultMessageIndices.dropLast(keepRecentToolResultMessages)

        guard !indicesToClear.isEmpty else {
            return (messages, 0)
        }

        var updatedMessages = messages
        var clearedToolResultCount = 0

        for messageIndex in indicesToClear {
            guard var contentBlocks = updatedMessages[messageIndex]["content"] as? [[String: Any]] else {
                continue
            }

            var changed = false
            for blockIndex in contentBlocks.indices {
                guard (contentBlocks[blockIndex]["type"] as? String) == "tool_result" else {
                    continue
                }
                let toolUseID = contentBlocks[blockIndex]["tool_use_id"] as? String ?? ""
                let toolUse = toolUseReceipts[toolUseID]

                let receipt: String
                if let text = contentBlocks[blockIndex]["content"] as? String {
                    receipt = compactToolResultReceipt(
                        text: text,
                        toolName: toolUse?.name,
                        input: toolUse?.input
                    )
                } else {
                    receipt = "Compacted tool result receipt: structured output omitted from older loop history. Re-run the tool if exact data is needed."
                }

                if (contentBlocks[blockIndex]["content"] as? String) != receipt {
                    contentBlocks[blockIndex]["content"] = receipt
                    changed = true
                    clearedToolResultCount += 1
                }
            }

            if changed {
                updatedMessages[messageIndex]["content"] = contentBlocks
            }
        }

        return (updatedMessages, clearedToolResultCount)
    }

    private func toolUseReceiptsByID(from messages: [[String: Any]]) -> [String: ToolUseReceipt] {
        var receipts: [String: ToolUseReceipt] = [:]

        for message in messages {
            guard let contentBlocks = message["content"] as? [[String: Any]] else { continue }
            for block in contentBlocks where (block["type"] as? String) == "tool_use" {
                let toolUseID = block["id"] as? String ?? ""
                guard !toolUseID.isEmpty else { continue }
                receipts[toolUseID] = ToolUseReceipt(
                    name: block["name"] as? String ?? "tool",
                    input: block["input"] as? [String: Any] ?? [:]
                )
            }
        }

        return receipts
    }

    private func containsToolResult(in message: [String: Any]) -> Bool {
        containsContentBlock(ofType: "tool_result", in: message)
    }

    private func containsToolUse(in message: [String: Any]) -> Bool {
        containsContentBlock(ofType: "tool_use", in: message)
    }

    private func containsContentBlock(ofType type: String, in message: [String: Any]) -> Bool {
        guard let contentBlocks = message["content"] as? [[String: Any]] else {
            return false
        }
        return contentBlocks.contains { ($0["type"] as? String) == type }
    }

    private func adjustedKeepCountForToolLoopBoundary(
        in messages: [[String: Any]],
        requestedKeepCount: Int
    ) -> Int {
        guard requestedKeepCount > 0, messages.count > requestedKeepCount else {
            return min(max(requestedKeepCount, 0), messages.count)
        }

        var splitIndex = messages.count - requestedKeepCount
        while splitIndex > 0,
              splitIndex < messages.count,
              containsToolResult(in: messages[splitIndex]),
              containsToolUse(in: messages[splitIndex - 1]) {
            splitIndex -= 1
        }

        return messages.count - splitIndex
    }

    private func compactToolResultReceipt(
        text: String,
        toolName: String?,
        input: [String: Any]?
    ) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return "Compacted tool result receipt: empty output."
        }
        if normalized.hasPrefix("Compacted tool result receipt:") {
            return normalized
        }
        if normalized.hasPrefix("Error:") {
            return "Compacted tool result receipt: \(compact(normalized, maxLength: 220))"
        }

        switch toolName {
        case "read_files":
            let paths = (input?["paths"] as? [String] ?? []).prefix(3).joined(separator: ", ")
            let pathDescription = paths.isEmpty ? "requested file snapshots" : "file snapshots for \(paths)"
            return "Compacted tool result receipt: read_files returned \(pathDescription) (\(text.count) chars). Re-run read_files if exact contents are needed again."
        case "search_files":
            return "Compacted tool result receipt: \(compact(firstMeaningfulLine(in: text) ?? normalized, maxLength: 200))"
        case "list_files":
            return "Compacted tool result receipt: \(compact(firstMeaningfulLine(in: text) ?? normalized, maxLength: 200))"
        case "run_command":
            let exitCode = firstMatch(in: normalized, pattern: #"exit code:\s*(-?\d+)"#) ?? "unknown"
            let importantLine = firstMeaningfulLine(in: text) ?? ""
            return "Compacted tool result receipt: run_command completed with exit code \(exitCode). \(compact(importantLine, maxLength: 180))"
        case "web_search":
            return "Compacted tool result receipt: web_search returned research notes. \(compact(firstMeaningfulLine(in: text) ?? normalized, maxLength: 180))"
        case "scrape_url":
            return "Compacted tool result receipt: scrape_url returned page notes. \(compact(firstMeaningfulLine(in: text) ?? normalized, maxLength: 180))"
        default:
            return "Compacted tool result receipt: \(compact(normalized, maxLength: 200))"
        }
    }

    private func makeLoopSummaryMessage(from olderMessages: [[String: Any]]) -> String {
        let userRequests = olderMessages
            .filter { ($0["role"] as? String) == "user" }
            .compactMap { summarySnippet(for: $0) }
            .suffix(4)

        let assistantState = olderMessages
            .filter { ($0["role"] as? String) == "assistant" }
            .compactMap { summarySnippet(for: $0) }
            .suffix(4)

        let toolReceipts = olderMessages
            .compactMap(toolReceiptSnippet(for:))
            .suffix(6)

        var sections = [
            "<context_memory>",
            "Earlier tool-loop history was compacted locally to preserve token budget. Use this as authoritative background; recent raw messages below are more detailed."
        ]

        if !userRequests.isEmpty {
            sections.append("""
            ## Earlier user requests
            \(userRequests.enumerated().map { index, item in "- U\(index + 1): \(item)" }.joined(separator: "\n"))
            """)
        }

        if !assistantState.isEmpty {
            sections.append("""
            ## Earlier assistant state
            \(assistantState.enumerated().map { index, item in "- A\(index + 1): \(item)" }.joined(separator: "\n"))
            """)
        }

        if !toolReceipts.isEmpty {
            sections.append("""
            ## Important tool/activity receipts
            \(toolReceipts.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        sections.append("</context_memory>")
        return sections.joined(separator: "\n\n")
    }

    private func compactLoopHistory(
        baseMessages: [[String: Any]],
        keepOptions: [Int],
        system: String,
        tools: [[String: Any]],
        requestOptions: GenerationService.RequestOptions,
        maxTokens: Int
    ) -> (
        messages: [[String: Any]],
        approximateTokens: Int,
        keptRecentMessageCount: Int,
        summarizedMessageCount: Int
    ) {
        let baselineApproximate = approximateRequestTokens(
            system: system,
            messages: baseMessages,
            tools: tools,
            requestOptions: requestOptions,
            maxTokens: maxTokens
        )

        var bestMessages = baseMessages
        var bestApproximate = baselineApproximate
        var bestKeepCount = baseMessages.count
        var bestSummarizedCount = 0

        for requestedKeepCount in keepOptions where baseMessages.count > requestedKeepCount {
            let keepCount = adjustedKeepCountForToolLoopBoundary(
                in: baseMessages,
                requestedKeepCount: requestedKeepCount
            )
            guard baseMessages.count > keepCount else {
                continue
            }

            let olderMessages = Array(baseMessages.dropLast(keepCount))
            let recentMessages = Array(baseMessages.suffix(keepCount))
            let summaryMessage = makeLoopSummaryMessage(from: olderMessages)
            let candidateMessages: [[String: Any]] = [
                [
                    "role": "assistant",
                    "content": summaryMessage,
                ]
            ] + recentMessages

            let candidateApproximate = approximateRequestTokens(
                system: system,
                messages: candidateMessages,
                tools: tools,
                requestOptions: requestOptions,
                maxTokens: maxTokens
            )

            if candidateApproximate < bestApproximate {
                bestMessages = candidateMessages
                bestApproximate = candidateApproximate
                bestKeepCount = recentMessages.count
                bestSummarizedCount = olderMessages.count
            }

            if candidateApproximate <= loopTargetTokens {
                break
            }
        }

        return (
            messages: bestMessages,
            approximateTokens: bestApproximate,
            keptRecentMessageCount: bestKeepCount,
            summarizedMessageCount: bestSummarizedCount
        )
    }

    private func summarySnippet(for message: [String: Any]) -> String? {
        if let content = message["content"] as? String {
            return compact(content, maxLength: 180)
        }

        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        var parts: [String] = []
        for block in blocks.prefix(4) {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String {
                    parts.append(compact(text, maxLength: 140))
                }
            case "tool_use":
                let name = block["name"] as? String ?? "tool"
                parts.append("tool use: \(name)")
            case "tool_result":
                if let text = block["content"] as? String {
                    parts.append(compact(text, maxLength: 120))
                }
            case "document":
                let title = block["title"] as? String ?? "document"
                parts.append("document: \(title)")
            case "image":
                parts.append("image attachment")
            default:
                break
            }
        }

        let joined = parts
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        return joined.isEmpty ? nil : compact(joined, maxLength: 180)
    }

    private func toolReceiptSnippet(for message: [String: Any]) -> String? {
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        for block in blocks where (block["type"] as? String) == "tool_result" {
            if let text = block["content"] as? String {
                return compact(text, maxLength: 180)
            }
        }
        return nil
    }

    private func approximateRequestTokens(
        system: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        requestOptions: GenerationService.RequestOptions,
        maxTokens: Int
    ) -> Int {
        var payload: [String: Any] = [
            "system": system,
            "messages": messages,
            "tools": tools,
            "max_tokens": maxTokens,
        ]
        if let toolChoice = requestOptions.toolChoice {
            payload["tool_choice"] = toolChoice
        }
        if let thinking = requestOptions.thinking {
            payload["thinking"] = thinking
        }
        if let outputConfig = requestOptions.outputConfig {
            payload["output_config"] = outputConfig
        }
        if let cacheControl = requestOptions.cacheControl {
            payload["cache_control"] = cacheControl
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return 0
        }

        return max(1, Int(ceil(Double(data.count) / 4.0)))
    }

    private func countTokens(
        system: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        requestOptions: GenerationService.RequestOptions,
        model: String,
        accessToken: String
    ) async -> Int? {
        // 11x local cockpit: exact token counting no longer depends on a vendor backend.
        // Return a local approximation so context budgets remain bounded.
        _ = model
        _ = accessToken
        return approximateRequestTokens(
            system: system,
            messages: messages,
            tools: tools,
            requestOptions: requestOptions,
            maxTokens: 64_000
        )
    }

    private func extractArtifacts(from timeline: [BuilderChatTimelineItem]) -> [BuilderContextArtifact] {
        var artifacts: [BuilderContextArtifact] = []

        for item in timeline.reversed() {
            guard case .toolSteps(_, let steps) = item else { continue }
            for step in steps.reversed() {
                let detail = [
                    step.inputPreview,
                    step.outputPreview,
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")

                let paths = relatedPaths(from: detail)
                artifacts.append(
                    BuilderContextArtifact(
                        category: artifactCategory(for: step.name),
                        title: step.label,
                        detail: detail,
                        sourceTool: step.name,
                        relatedPaths: paths
                    )
                )
                if artifacts.count >= 10 {
                    return artifacts.reversed()
                }
            }
        }

        return artifacts.reversed()
    }

    private func artifactCategory(for toolName: String) -> BuilderContextArtifactCategory {
        switch toolName {
        case "read_files":
            return .fileRead
        case "write_file", "edit_file", "delete_file":
            return .fileChange
        case "run_command":
            return .command
        case "web_search", "scrape_url":
            return .research
        case "ask_user":
            return .question
        case "update_project_status", "update_project_dependencies", "change_mode", "set_project_identity", "update_app_store_assets", "update_app_store_review_assets":
            return .planning
        case "list_skills", "use_skill":
            return .skill
        default:
            return .other
        }
    }

    private func relatedPaths(from detail: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_\-./]+\.[A-Za-z0-9]+"#)
        let nsRange = NSRange(detail.startIndex..., in: detail)
        let matches = regex?.matches(in: detail, range: nsRange) ?? []
        var paths: [String] = []
        for match in matches {
            if let range = Range(match.range, in: detail) {
                let value = String(detail[range])
                if !paths.contains(value) {
                    paths.append(value)
                }
            }
        }
        return Array(paths.prefix(4))
    }

    private func extractPreferenceSnippets(from messages: [BuilderMessage]) -> [String] {
        let patterns = [
            "prefer",
            "avoid",
            "do not",
            "don't",
            "must",
            "should",
        ]

        var snippets: [String] = []
        for message in messages.reversed() {
            let text = message.displayableContent
            guard !text.isEmpty else { continue }
            let normalized = text.lowercased()
            guard patterns.contains(where: { normalized.contains($0) }) else { continue }
            snippets.append(compact(text, maxLength: 180))
            if snippets.count >= 6 {
                break
            }
        }
        return snippets.reversed()
    }

    private func trimmedBulletItems(from text: String?, limit: Int) -> [String] {
        guard let text else { return [] }
        let items = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("##")
                    && !line.hasPrefix("#")
            }
            .map { line -> String in
                var trimmed = line
                while trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") {
                    trimmed.removeFirst()
                    trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return compact(trimmed, maxLength: 160)
            }
            .filter { !$0.isEmpty }
        return Array(items.prefix(limit))
    }

    private func trimmedChecklistItems(from text: String?, limit: Int) -> [String] {
        guard let text else { return [] }
        let items = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && (line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix("[") || line.range(of: #"^\d+\."#, options: .regularExpression) != nil)
            }
            .map { line in
                compact(line, maxLength: 160)
            }
        return Array(items.prefix(limit))
    }

    private func firstMeaningfulLine(in text: String?) -> String? {
        guard let text else { return nil }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { compact($0, maxLength: 160) }
    }

    private func compact(_ text: String, maxLength: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        guard normalized.count > maxLength else { return normalized }

        let prefix = String(normalized.prefix(maxLength))
        if let lastSpace = prefix.lastIndex(of: " "), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]) + "..."
        }
        return prefix + "..."
    }

    private func deduplicated(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for item in items {
            let normalized = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            if seen.insert(key).inserted {
                output.append(normalized)
            }
        }
        return output
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }
}
