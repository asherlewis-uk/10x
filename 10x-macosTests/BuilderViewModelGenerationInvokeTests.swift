import Foundation
import XCTest
@testable import TenXAppCore

final class BuilderViewModelGenerationInvokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        InvokeURLProtocolStub.reset()
    }

    override func tearDown() {
        InvokeURLProtocolStub.reset()
        super.tearDown()
    }

    func testInvokeSupabaseFunctionUsesUserJWTBearerWhenRequested() async throws {
        let session = makeSession()
        InvokeURLProtocolStub.requestHandler = { request in
            try Self.jsonResponse(for: request, object: ["ok": true])
        }

        _ = try await BuilderViewModel.invokeSupabaseFunction(
            projectURL: "https://proj123.supabase.co",
            publicAPIKey: "sb_publishable_test",
            functionName: "ping",
            requestJSON: AnyCodableValue(jsonObject: ["hello": "world"]),
            authMode: .userJWT,
            userAccessToken: "user_jwt_token",
            session: session
        )

        let request = try XCTUnwrap(InvokeURLProtocolStub.lastRequest())
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user_jwt_token")
    }

    func testInvokeSupabaseFunctionUsesAnonBearerWhenRequested() async throws {
        let session = makeSession()
        InvokeURLProtocolStub.requestHandler = { request in
            try Self.jsonResponse(for: request, object: ["ok": true])
        }

        _ = try await BuilderViewModel.invokeSupabaseFunction(
            projectURL: "https://proj123.supabase.co",
            publicAPIKey: "sb_publishable_test",
            functionName: "ping",
            requestJSON: nil,
            authMode: .anon,
            userAccessToken: "user_jwt_token",
            session: session
        )

        let request = try XCTUnwrap(InvokeURLProtocolStub.lastRequest())
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sb_publishable_test")
    }

    func testInvokeSupabaseFunctionOmitsAuthorizationForNoneAuthMode() async throws {
        let session = makeSession()
        InvokeURLProtocolStub.requestHandler = { request in
            try Self.jsonResponse(for: request, object: ["ok": true])
        }

        _ = try await BuilderViewModel.invokeSupabaseFunction(
            projectURL: "https://proj123.supabase.co",
            publicAPIKey: "sb_publishable_test",
            functionName: "ping",
            requestJSON: nil,
            authMode: .none,
            userAccessToken: "user_jwt_token",
            session: session
        )

        let request = try XCTUnwrap(InvokeURLProtocolStub.lastRequest())
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testInvokeSupabaseFunctionRequiresSignedInUserForUserJWTMode() async {
        do {
            _ = try await BuilderViewModel.invokeSupabaseFunction(
                projectURL: "https://proj123.supabase.co",
                publicAPIKey: "sb_publishable_test",
                functionName: "ping",
                requestJSON: nil,
                authMode: .userJWT,
                userAccessToken: nil
            )
            XCTFail("Expected missing user JWT to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("signed-in Supabase user session"))
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InvokeURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonResponse(
        for request: URLRequest,
        object: Any
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, data)
    }
}

private final class InvokeURLProtocolStub: URLProtocol {
    static let lock = NSLock()
    static var storedRequest: URLRequest?
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        storedRequest = nil
        requestHandler = nil
    }

    static func lastRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
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
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "InvokeURLProtocolStub", code: 1, userInfo: nil))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
