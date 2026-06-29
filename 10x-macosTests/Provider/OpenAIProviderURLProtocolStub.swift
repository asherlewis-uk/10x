import Foundation
import XCTest

/// URLProtocol stub for OpenAI-compatible provider adapter tests.
final class OpenAIProviderURLProtocolStub: URLProtocol {
    static let lock = NSLock()
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var storedRequest: URLRequest?
    static var storedResponseBody: Data?

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        requestHandler = nil
        storedRequest = nil
        storedResponseBody = nil
    }

    static func lastRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    static func setResponseBody(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        storedResponseBody = data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.storedRequest = request
        let handler = Self.requestHandler
        let body = Self.storedResponseBody
        Self.lock.unlock()

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "OpenAIProviderURLProtocolStub", code: 1))
            return
        }

        do {
            let (response, data): (HTTPURLResponse, Data)
            if let handler {
                (response, data) = try handler(request)
            } else {
                let responseBody = body ?? Data()
                response = try XCTUnwrap(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                ))
                data = responseBody
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    var lastRequestURL: URL? {
        Self.lastRequest()?.url
    }

    // MARK: - Helpers

    static func singleChunkCompletion(content: String) -> Data {
        let chunk: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion.chunk",
            "choices": [
                [
                    "index": 0,
                    "delta": ["role": "assistant", "content": content],
                    "finish_reason": NSNull(),
                ]
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: chunk, options: [.sortedKeys])
        return ("data: " + String(data: data, encoding: .utf8)! + "\n\n").data(using: .utf8)!
    }

    static func toolCallCompletion(id: String, name: String, arguments: [String: String]) -> Data {
        let args = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data()
        let argsString = String(data: args, encoding: .utf8) ?? "{}"
        let chunks: [[String: Any]] = [
            [
                "id": "chatcmpl-test",
                "object": "chat.completion.chunk",
                "choices": [
                    [
                        "index": 0,
                        "delta": [
                            "tool_calls": [
                                [
                                    "index": 0,
                                    "id": id,
                                    "type": "function",
                                    "function": ["name": name, "arguments": ""],
                                ]
                            ]
                        ],
                        "finish_reason": NSNull(),
                    ]
                ],
            ],
            [
                "id": "chatcmpl-test",
                "object": "chat.completion.chunk",
                "choices": [
                    [
                        "index": 0,
                        "delta": [
                            "tool_calls": [
                                [
                                    "index": 0,
                                    "function": ["arguments": argsString],
                                ]
                            ]
                        ],
                        "finish_reason": NSNull(),
                    ]
                ],
            ],
            [
                "id": "chatcmpl-test",
                "object": "chat.completion.chunk",
                "choices": [
                    [
                        "index": 0,
                        "delta": [:],
                        "finish_reason": "tool_calls",
                    ]
                ],
            ],
        ]
        var body = Data()
        for chunk in chunks {
            let data = try! JSONSerialization.data(withJSONObject: chunk, options: [.sortedKeys])
            body.append(("data: " + String(data: data, encoding: .utf8)! + "\n\n").data(using: .utf8)!)
        }
        return body
    }
}
