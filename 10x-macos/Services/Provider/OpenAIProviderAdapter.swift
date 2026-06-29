import Foundation

/// Events emitted by the OpenAI-compatible provider stream.
enum OpenAIProviderStreamEvent: Sendable {
    case textDelta(String)
    case toolCallStart(index: Int, id: String, name: String)
    case toolCallDelta(index: Int, partialArguments: String)
    case toolCallEnd(index: Int, id: String, name: String, arguments: String)
    case error(String)
    case finishReason(String)
}

/// Errors returned by the OpenAI-compatible provider adapter.
enum OpenAIProviderError: LocalizedError {
    case missingConfig(ProviderConfigError)
    case invalidURL(String)
    case requestFailed(statusCode: Int, message: String)
    case streamingError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .missingConfig(let underlying):
            return underlying.errorDescription
        case .invalidURL(let url):
            return "Invalid provider URL: \(url)"
        case .requestFailed(let code, let message):
            return "Provider error \(code): \(message)"
        case .streamingError(let error):
            return "Streaming error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode provider response: \(error.localizedDescription)"
        }
    }
}

/// Adapter that speaks OpenAI-compatible chat completions to a user-owned provider.
/// Secrets are read from the OS keychain; only metadata travels through this boundary.
actor OpenAIProviderAdapter {
    private let configRepository: ProviderConfigRepository
    private let session: URLSession

    /// Injected URLSession enables mocking in tests.
    init(
        configRepository: ProviderConfigRepository = ProviderConfigRepository(),
        session: URLSession = OpenAIProviderAdapter.defaultSession()
    ) {
        self.configRepository = configRepository
        self.session = session
    }

    nonisolated static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }

    /// Stream a chat completion from the configured provider.
    func stream(
        systemPrompt: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        toolChoice: [String: Any]?,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<OpenAIProviderStreamEvent, Error> {
        let (providerConfig, apiKey): (ProviderConfig, String)
        do {
            (providerConfig, apiKey) = try await configRepository.validatedConfig()
        } catch let error as ProviderConfigError {
            throw OpenAIProviderError.missingConfig(error)
        }
        let baseURL = providerConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty,
              let rootURL = URL(string: baseURL),
              let scheme = rootURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              rootURL.host?.isEmpty == false else {
            throw OpenAIProviderError.invalidURL(providerConfig.baseURL)
        }
        let url = rootURL.appendingPathComponent("v1/chat/completions")

        var openAIMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        openAIMessages += messages.map { message in
            normalizeMessageForOpenAI(message)
        }

        var body: [String: Any] = [
            "model": providerConfig.model,
            "messages": openAIMessages,
            "stream": true,
            "max_tokens": maxTokens,
        ]

        let openAITools = tools.map { normalizeToolForOpenAI($0) }
        if !openAITools.isEmpty {
            body["tools"] = openAITools
        }
        if let toolChoice {
            body["tool_choice"] = normalizeToolChoiceForOpenAI(toolChoice)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("11x-macos/\(Config.appVersion) (\(Config.appBuild))", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        logRequest(url: url, body: body, apiKey: apiKey)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIProviderError.requestFailed(statusCode: 0, message: "Invalid response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw OpenAIProviderError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: parseErrorMessage(from: errorBody)
            )
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var toolCallBuffers: [Int: (id: String, name: String, arguments: String)] = [:]
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data: ") else { continue }
                        let payload = String(trimmed.dropFirst("data: ".count))
                        if payload == "[DONE]" {
                            flushRemainingToolCalls(toolCallBuffers, continuation: continuation)
                            continuation.finish()
                            return
                        }
                        parseSSEChunk(
                            payload: payload,
                            toolCallBuffers: &toolCallBuffers,
                            continuation: continuation
                        )
                    }
                    flushRemainingToolCalls(toolCallBuffers, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: OpenAIProviderError.streamingError(error))
                }
            }
        }
    }

    private nonisolated func normalizeMessageForOpenAI(_ message: [String: Any]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        if let role = message["role"] as? String {
            normalized["role"] = role
        } else {
            normalized["role"] = "user"
        }

        if let content = message["content"] {
            normalized["content"] = content
        }

        // Convert Anthropic-style tool_result messages to OpenAI tool messages.
        if let contentBlocks = message["content"] as? [[String: Any]] {
            for block in contentBlocks {
                if (block["type"] as? String) == "tool_result" {
                    normalized["role"] = "tool"
                    normalized["tool_call_id"] = block["tool_use_id"] ?? ""
                    normalized["content"] = block["content"] ?? ""
                }
            }
        }

        return normalized
    }

    private nonisolated func normalizeToolForOpenAI(_ tool: [String: Any]) -> [String: Any] {
        var function: [String: Any] = [:]
        if let name = tool["name"] as? String {
            function["name"] = name
        }
        if let description = tool["description"] as? String {
            function["description"] = description
        }
        if let inputSchema = tool["input_schema"] as? [String: Any] {
            function["parameters"] = inputSchema
        } else if let schema = tool["parameters"] as? [String: Any] {
            function["parameters"] = schema
        }
        return [
            "type": "function",
            "function": function,
        ]
    }

    private nonisolated func normalizeToolChoiceForOpenAI(_ toolChoice: [String: Any]) -> [String: Any] {
        // Anthropic-style: {"type": "tool", "name": "..."}
        if let type = toolChoice["type"] as? String, type == "tool",
           let name = toolChoice["name"] as? String {
            return [
                "type": "function",
                "function": ["name": name],
            ]
        }
        return toolChoice
    }

    private nonisolated func parseSSEChunk(
        payload: String,
        toolCallBuffers: inout [Int: (id: String, name: String, arguments: String)],
        continuation: AsyncThrowingStream<OpenAIProviderStreamEvent, Error>.Continuation
    ) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first else {
            return
        }

        if let delta = choice["delta"] as? [String: Any] {
            if let text = delta["content"] as? String, !text.isEmpty {
                continuation.yield(.textDelta(text))
            }
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    guard let index = call["index"] as? Int else { continue }
                    let id = call["id"] as? String ?? ""
                    let function = call["function"] as? [String: Any] ?? [:]
                    let name = function["name"] as? String ?? ""
                    let arguments = function["arguments"] as? String ?? ""

                    var buffer = toolCallBuffers[index] ?? (id: "", name: "", arguments: "")
                    if !id.isEmpty { buffer.id = id }
                    if !name.isEmpty { buffer.name = name }
                    buffer.arguments += arguments
                    toolCallBuffers[index] = buffer

                    if !id.isEmpty && !name.isEmpty {
                        continuation.yield(.toolCallStart(index: index, id: id, name: name))
                    }
                    if !arguments.isEmpty {
                        continuation.yield(.toolCallDelta(index: index, partialArguments: arguments))
                    }
                }
            }
        }

        if let finishReason = choice["finish_reason"] as? String, !finishReason.isEmpty {
            if finishReason == "tool_calls" || finishReason == "stop" {
                flushRemainingToolCalls(toolCallBuffers, continuation: continuation)
            }
            continuation.yield(.finishReason(finishReason))
        }
    }

    private nonisolated func flushRemainingToolCalls(
        _ toolCallBuffers: [Int: (id: String, name: String, arguments: String)],
        continuation: AsyncThrowingStream<OpenAIProviderStreamEvent, Error>.Continuation
    ) {
        for (index, buffer) in toolCallBuffers.sorted(by: { $0.key < $1.key }) {
            guard !buffer.id.isEmpty, !buffer.name.isEmpty else { continue }
            continuation.yield(.toolCallEnd(index: index, id: buffer.id, name: buffer.name, arguments: buffer.arguments))
        }
    }

    private nonisolated func parseErrorMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return body
    }

    private nonisolated func logRequest(url: URL, body: [String: Any], apiKey: String) {
        let maskedKey = apiKey.count >= 12
            ? String(apiKey.prefix(7)) + "..." + String(apiKey.suffix(4))
            : String(repeating: "*", count: apiKey.count)
        print("[provider-request] \(url.absoluteString) model=\(body["model"] ?? "") apiKeyPrefix=\(maskedKey)")
    }
}
