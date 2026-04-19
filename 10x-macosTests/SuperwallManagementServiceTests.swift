import Foundation
import XCTest
@testable import TenXAppCore

final class SuperwallManagementServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testBootstrapStarterMonetizationFailsClosedWhenPreviewCampaignCreationFails() async throws {
        URLProtocolStub.requestHandler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/v2/paywalls"):
                return try Self.jsonResponse(for: request, object: [
                    ["id": "pw_1", "name": "Imported Paywall", "identifier": "imported-paywall"],
                ])
            case ("GET", "/v2/paywalls/pw_1"):
                return try Self.jsonResponse(for: request, object: [
                    "id": "pw_1",
                    "name": "Imported Paywall",
                    "identifier": "imported-paywall",
                    "feature_gating": "gated",
                    "products": [],
                    "metadata": ["source": "shared-link"],
                ])
            case ("PATCH", "/v2/paywalls/pw_1"):
                let body = try Self.jsonBody(from: request)
                return try Self.jsonResponse(for: request, object: [
                    "id": "pw_1",
                    "name": body["name"] as? String ?? "Imported Paywall",
                    "identifier": "imported-paywall",
                    "feature_gating": body["feature_gating"] as? String ?? "gated",
                    "products": body["products"] as? [[String: Any]] ?? [],
                    "metadata": body["metadata"] as? [String: Any] ?? [:],
                ])
            case ("GET", "/v2/entitlements"):
                return try Self.jsonResponse(for: request, object: [])
            case ("POST", "/v2/entitlements"):
                return try Self.jsonResponse(for: request, object: [
                    "id": "ent_1",
                    "identifier": "pro",
                    "name": "Pro",
                ])
            case ("GET", "/v2/products"):
                return try Self.jsonResponse(for: request, object: [])
            case ("POST", "/v2/products"):
                return try Self.productResponse(for: request)
            case ("GET", "/v2/campaigns"):
                return try Self.jsonResponse(for: request, object: [])
            case ("POST", "/v2/campaigns"):
                return try Self.jsonResponse(for: request, statusCode: 400, object: [
                    "message": "Invalid audience expression",
                ])
            default:
                return try Self.jsonResponse(for: request, object: [:])
            }
        }

        let service = makeService()
        let state = ProjectSuperwallState(
            projectID: "proj_1",
            applicationID: "app_1",
            paywallID: "pw_1",
            paywallName: "Imported Paywall"
        )

        do {
            _ = try await service.bootstrapStarterMonetization(
                state: state,
                bundleID: "com.example.app",
                placements: ["upgrade_prompt"],
                previewAppUserID: "preview-user",
                apiKeyOverride: "sw_test_key"
            )
            XCTFail("Expected preview campaign creation to fail closed")
        } catch let error as SuperwallManagementServiceError {
            guard case .requestFailed(let statusCode, let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(statusCode, 400)
            XCTAssertTrue(message.contains("Invalid audience expression"))
        }

        let paywallPatchRequests = URLProtocolStub.requests(
            matching: { ($0.httpMethod ?? "GET") == "PATCH" && $0.url?.path == "/v2/paywalls/pw_1" }
        )
        XCTAssertEqual(paywallPatchRequests.count, 1)

        let paywallPatchBody = try Self.jsonBody(from: try XCTUnwrap(paywallPatchRequests.first))
        XCTAssertEqual(paywallPatchBody["name"] as? String, "Imported Paywall")
        XCTAssertNil(paywallPatchBody["identifier"])

        let paywallCreateRequests = URLProtocolStub.requests(
            matching: { ($0.httpMethod ?? "GET") == "POST" && $0.url?.path == "/v2/paywalls" }
        )
        XCTAssertTrue(paywallCreateRequests.isEmpty)
    }

    func testBootstrapStarterMonetizationUsesExplicitSelectedPaywallAndDoesNotCreatePaywall() async throws {
        URLProtocolStub.requestHandler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/v2/paywalls"):
                return try Self.jsonResponse(for: request, object: [
                    ["id": "pw_1", "name": "Example Paywall", "identifier": "example-paywall"],
                    ["id": "pw_2", "name": "Chosen Paywall", "identifier": "chosen-paywall"],
                ])
            case ("GET", "/v2/paywalls/pw_2"):
                return try Self.jsonResponse(for: request, object: [
                    "id": "pw_2",
                    "name": "Chosen Paywall",
                    "identifier": "chosen-paywall",
                    "template": "tmpl_from_dashboard",
                    "feature_gating": "non_gated",
                    "products": [],
                    "metadata": ["source": "dashboard"],
                ])
            case ("PATCH", "/v2/paywalls/pw_2"):
                let body = try Self.jsonBody(from: request)
                return try Self.jsonResponse(for: request, object: [
                    "id": "pw_2",
                    "name": body["name"] as? String ?? "Chosen Paywall",
                    "identifier": "chosen-paywall",
                    "template": "tmpl_from_dashboard",
                    "feature_gating": body["feature_gating"] as? String ?? "non_gated",
                    "products": body["products"] as? [[String: Any]] ?? [],
                    "metadata": body["metadata"] as? [String: Any] ?? [:],
                ])
            case ("GET", "/v2/entitlements"):
                return try Self.jsonResponse(for: request, object: [])
            case ("POST", "/v2/entitlements"):
                return try Self.jsonResponse(for: request, object: [
                    "id": "ent_1",
                    "identifier": "pro",
                    "name": "Pro",
                ])
            case ("GET", "/v2/products"):
                return try Self.jsonResponse(for: request, object: [])
            case ("POST", "/v2/products"):
                return try Self.productResponse(for: request)
            case ("GET", "/v2/campaigns"):
                return try Self.jsonResponse(for: request, object: [])
            case ("POST", "/v2/campaigns"):
                return try Self.jsonResponse(for: request, object: [
                    "id": "camp_1",
                    "description": "10x Starter Preview Campaign",
                    "notes": "Managed by 10x starter preview bootstrap. Preview user: preview-user. Placements: upgrade_prompt.",
                    "placements": [
                        [
                            "event_name": "upgrade_prompt",
                            "enabled": true,
                            "remove_from_other_campaigns": false,
                        ],
                    ],
                    "audiences": [
                        [
                            "enabled": true,
                            "expression": "user.id == 'preview-user'",
                            "description": "10x preview user only.",
                            "variant_optimization": "none",
                            "variants": [
                                [
                                    "type": "treatment",
                                    "paywall": "pw_2",
                                    "percentage": 100,
                                ],
                            ],
                        ],
                    ],
                ])
            case ("PATCH", "/v2/users/preview-user/test-mode"):
                return try Self.jsonResponse(for: request, object: [:])
            default:
                return try Self.jsonResponse(for: request, object: [:])
            }
        }

        let service = makeService()
        let state = ProjectSuperwallState(projectID: "proj_1", applicationID: "app_1")

        let nextState = try await service.bootstrapStarterMonetization(
            state: state,
            bundleID: "com.example.app",
            placements: ["upgrade_prompt"],
            previewAppUserID: "preview-user",
            paywallID: "pw_2",
            apiKeyOverride: "sw_test_key"
        )

        XCTAssertEqual(nextState.paywallID, "pw_2")
        XCTAssertEqual(nextState.paywallName, "Chosen Paywall")
        XCTAssertEqual(nextState.selectedTemplateID, "tmpl_from_dashboard")
        XCTAssertNil(nextState.selectedTemplateName)
        XCTAssertEqual(nextState.campaignID, "camp_1")

        let paywallPatchRequests = URLProtocolStub.requests(
            matching: { ($0.httpMethod ?? "GET") == "PATCH" && $0.url?.path == "/v2/paywalls/pw_2" }
        )
        XCTAssertEqual(paywallPatchRequests.count, 1)

        let paywallPatchBody = try Self.jsonBody(from: try XCTUnwrap(paywallPatchRequests.first))
        XCTAssertEqual(paywallPatchBody["name"] as? String, "Chosen Paywall")
        XCTAssertEqual(paywallPatchBody["feature_gating"] as? String, "non_gated")

        let metadata = try XCTUnwrap(paywallPatchBody["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["source"] as? String, "dashboard")
        XCTAssertEqual(metadata["managed_by"] as? String, "10x")
        XCTAssertEqual(metadata["bootstrap"] as? String, "starter")

        let paywallCreateRequests = URLProtocolStub.requests(
            matching: { ($0.httpMethod ?? "GET") == "POST" && $0.url?.path == "/v2/paywalls" }
        )
        XCTAssertTrue(paywallCreateRequests.isEmpty)
    }

    func testBootstrapStarterMonetizationRequiresExistingPaywallSelection() async throws {
        let service = makeService()
        let state = ProjectSuperwallState(projectID: "proj_1", applicationID: "app_1")

        do {
            _ = try await service.bootstrapStarterMonetization(
                state: state,
                bundleID: "com.example.app",
                placements: ["upgrade_prompt"],
                previewAppUserID: "preview-user",
                apiKeyOverride: "sw_test_key"
            )
            XCTFail("Expected missing paywall selection to abort bootstrap")
        } catch let error as SuperwallManagementServiceError {
            guard case .invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("Choose an existing Superwall paywall first"))
        }

        XCTAssertTrue(URLProtocolStub.requests(matching: { _ in true }).isEmpty)
    }

    func testBootstrapStarterMonetizationFailsWhenSelectedPaywallMissing() async throws {
        URLProtocolStub.requestHandler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/v2/paywalls"):
                return try Self.jsonResponse(for: request, object: [
                    ["id": "pw_1", "name": "Example Paywall", "identifier": "example-paywall"],
                ])
            default:
                return try Self.jsonResponse(for: request, object: [:])
            }
        }

        let service = makeService()
        let state = ProjectSuperwallState(
            projectID: "proj_1",
            applicationID: "app_1",
            paywallID: "pw_missing"
        )

        do {
            _ = try await service.bootstrapStarterMonetization(
                state: state,
                bundleID: "com.example.app",
                placements: ["upgrade_prompt"],
                previewAppUserID: "preview-user",
                apiKeyOverride: "sw_test_key"
            )
            XCTFail("Expected missing paywall to abort bootstrap")
        } catch let error as SuperwallManagementServiceError {
            guard case .invalidInput(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("selected Superwall paywall is no longer available"))
        }

        let sideEffectRequests = URLProtocolStub.requests(
            matching: { request in
                let path = request.url?.path ?? ""
                return path != "/v2/paywalls"
            }
        )
        XCTAssertTrue(sideEffectRequests.isEmpty)
    }

    func testListPaywallsSortsByName() async throws {
        URLProtocolStub.requestHandler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod ?? "GET", path) {
            case ("GET", "/v2/paywalls"):
                return try Self.jsonResponse(for: request, object: [
                    ["id": "pw_b", "name": "Zebra Paywall", "identifier": "zebra"],
                    ["id": "pw_a", "name": "Alpha Paywall", "identifier": "alpha"],
                ])
            default:
                return try Self.jsonResponse(for: request, object: [:])
            }
        }

        let service = makeService()
        let paywalls = try await service.listPaywalls(
            applicationID: "app_1",
            apiKeyOverride: "sw_test_key"
        )

        XCTAssertEqual(paywalls.map(\.id), ["pw_a", "pw_b"])
    }

    func testStatusTextIncludesDashboardLinksAndOwnershipGuidance() async {
        let service = makeService()
        let state = ProjectSuperwallState(
            projectName: "Acme",
            applicationID: "app_1",
            applicationName: "Acme iOS",
            applicationDashboardURL: "https://superwall.com/applications/app_1/rules",
            selectedTemplateName: "Starter Template",
            previewAppUserID: "preview-user",
            products: [
                .init(
                    id: "prod_1",
                    identifier: "com.example.pro.monthly",
                    name: "Pro Monthly",
                    period: "month",
                    trialPeriodDays: 7
                ),
            ],
            paywallID: "pw_1",
            paywallName: "Imported Paywall",
            campaignID: "camp_1",
            campaignName: "10x Starter Preview Campaign",
            placements: ["upgrade_prompt"],
            bootstrapStatus: .starterReady
        )

        let text = await service.statusText(for: state)

        XCTAssertTrue(text.contains("Dashboard: https://superwall.com/applications/app_1/rules"))
        XCTAssertTrue(text.contains("Paywalls: https://superwall.com/applications/app_1/paywalls"))
        XCTAssertTrue(text.contains("Templates: https://superwall.com/applications/app_1/templates"))
        XCTAssertTrue(text.contains("App code / 10x: `SUPERWALL_PUBLIC_API_KEY`"))
        XCTAssertTrue(text.contains("Superwall dashboard: paywall design"))
        XCTAssertTrue(text.contains("Paywall-first setup: create, duplicate, or import the paywall in Superwall first"))
        XCTAssertTrue(text.contains("To edit the paywall, open the linked Superwall dashboard and use the Paywalls section."))
    }

    private func makeService() -> SuperwallManagementService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return SuperwallManagementService(
            session: session,
            tokenStore: SuperwallManagementTokenStore(service: "test.superwall.management")
        )
    }

    private static func productResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let body = try jsonBody(from: request)
        let identifier = body["identifier"] as? String ?? "unknown"
        return try jsonResponse(for: request, object: [
            "id": "prod_\(identifier)",
            "identifier": identifier,
            "name": identifier.contains("monthly") ? "Pro Monthly" : "Pro Yearly",
            "subscription": [
                "period": identifier.contains("monthly") ? "month" : "year",
                "trial_period_days": identifier.contains("yearly") ? 7 : 0,
            ],
        ])
    }

    private static func jsonResponse(
        for request: URLRequest,
        statusCode: Int = 200,
        object: Any
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, data)
    }

    private static func jsonBody(from request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }

            var buffer = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 {
                    throw try XCTUnwrap(stream.streamError)
                }
                if count == 0 {
                    break
                }
                collected.append(buffer, count: count)
            }
            data = collected
        } else {
            return [:]
        }

        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        )
    }
}

private final class URLProtocolStub: URLProtocol {
    static let lock = NSLock()
    static var storedRequests: [URLRequest] = []
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        storedRequests = []
        requestHandler = nil
    }

    static func requests(matching predicate: (URLRequest) -> Bool) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests.filter(predicate)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.storedRequests.append(request)
        let handler = Self.requestHandler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "URLProtocolStub", code: 1))
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
