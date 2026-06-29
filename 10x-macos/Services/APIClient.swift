import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .unauthorized: return "Session expired. Please sign in again."
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .decodingError(let err): return "Decoding error: \(err.localizedDescription)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

actor APIClient {
    let baseURL: String

    /// Session for standard API requests so UI loads fail fast instead of hanging indefinitely.
    private let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Session with extended timeouts for long-running streams (AI generation, build commands).
    private let streamSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900   // 15 min for first streamed bytes on heavier generations
        config.timeoutIntervalForResource = 1800 // 30 min total for long build / fix loops
        return URLSession(configuration: config)
    }()

    init(baseURL: String = Config.apiBaseURL) {
        self.baseURL = baseURL
    }

    nonisolated static func versioned(_ endpoint: String) -> String {
        prefixedPath("/api/\(Config.apiVersion)", endpoint)
    }

    nonisolated static func builder(_ endpoint: String = "") -> String {
        versioned("/builder" + normalizedSuffix(endpoint))
    }

    nonisolated static func builderSkills(_ endpoint: String = "") -> String {
        versioned("/builder/skills" + normalizedSuffix(endpoint))
    }

    nonisolated static func admin(_ endpoint: String = "") -> String {
        versioned("/admin" + normalizedSuffix(endpoint))
    }

    // MARK: - Standard HTTP Methods

    func get<T: Decodable>(_ endpoint: String, accessToken: String, requestTimeout: TimeInterval? = nil) async throws -> T {
        let request = try buildRequest(endpoint, method: "GET", accessToken: accessToken)
        return try await perform(request, requestTimeout: requestTimeout)
    }

    func post<T: Decodable>(
        _ endpoint: String,
        json: [String: Any]? = nil,
        accessToken: String,
        requestTimeout: TimeInterval? = nil
    ) async throws -> T {
        var request = try buildRequest(endpoint, method: "POST", accessToken: accessToken)
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
        return try await perform(request, requestTimeout: requestTimeout)
    }

    func patch<T: Decodable>(
        _ endpoint: String,
        json: [String: Any],
        accessToken: String,
        requestTimeout: TimeInterval? = nil
    ) async throws -> T {
        var request = try buildRequest(endpoint, method: "PATCH", accessToken: accessToken)
        request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return try await perform(request, requestTimeout: requestTimeout)
    }

    func delete(_ endpoint: String, accessToken: String) async throws {
        let request = try buildRequest(endpoint, method: "DELETE", accessToken: accessToken)
        let (_, response) = try await defaultSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - NDJSON Streaming

    func stream(
        _ endpoint: String,
        method: String = "POST",
        json: [String: Any]? = nil,
        accessToken: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        var request = try buildRequest(endpoint, method: method, accessToken: accessToken)
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }

        let (bytes, response) = try await streamSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            throw APIError.serverError(
                statusCode: httpResponse.statusCode,
                message: parseErrorMessage(from: body.data(using: .utf8))
            )
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            continuation.yield(trimmed)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func buildRequest(_ endpoint: String, method: String, accessToken: String?) throws -> URLRequest {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue(Config.apiVersion, forHTTPHeaderField: "X-10x-Api-Version")
        request.setValue(Config.appVersion, forHTTPHeaderField: "X-10x-App-Version")
        request.setValue(Config.appBuild, forHTTPHeaderField: "X-10x-App-Build")
        request.setValue(Config.platform, forHTTPHeaderField: "X-10x-Platform")
        request.setValue(
            "10x-macos/\(Config.appVersion) (\(Config.appBuild))",
            forHTTPHeaderField: "User-Agent"
        )
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest, requestTimeout: TimeInterval?) async throws -> T {
        let session = session(for: requestTimeout)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseErrorMessage(from: data)
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func parseErrorMessage(from data: Data?) -> String {
        guard let data else { return "Unknown error" }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if let detail = json["detail"] as? [String: Any],
               let message = detail["message"] as? String,
               !message.isEmpty {
                return message
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
        }

        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    private func session(for requestTimeout: TimeInterval?) -> URLSession {
        guard let requestTimeout else {
            return defaultSession
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = max(requestTimeout * 2, requestTimeout)
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    private nonisolated static func prefixedPath(_ prefix: String, _ endpoint: String) -> String {
        let normalizedPrefix = prefix.hasPrefix("/") ? prefix : "/\(prefix)"
        return normalizedPrefix + normalizedSuffix(endpoint)
    }

    private nonisolated static func normalizedSuffix(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }
}
