import Foundation
import XCTest
@testable import TenXAppCore

final class ProjectBackendStateTests: XCTestCase {
    func testLegacyDecodeDefaultsFailureFields() throws {
        let data = Data(
            """
            {
              "providerID": "supabase",
              "linkedProjectRef": "proj123",
              "linkedProjectURL": "https://proj123.supabase.co",
              "functions": [],
              "secrets": [],
              "recentLogs": [],
              "lastDeploySummary": null,
              "lastUpdatedAt": "2026-04-16T12:00:00Z"
            }
            """.utf8
        )

        let state = try JSONDecoder().decode(ProjectBackendState.self, from: data)

        XCTAssertEqual(state.providerID, .supabase)
        XCTAssertEqual(state.recentFailures, [])
        XCTAssertNil(state.lastStatusRefreshAt)
    }

    func testAttentionSortedFunctionsPrioritizeOpenFailures() {
        let state = ProjectBackendState(
            providerID: .supabase,
            linkedProjectRef: "proj123",
            linkedProjectURL: "https://proj123.supabase.co",
            functions: [
                .init(
                    name: "healthy",
                    summary: "Healthy function",
                    verifyJWT: true,
                    sourcePath: "supabase/functions/healthy/index.ts",
                    updatedAt: "2026-04-16T12:00:00Z",
                    lastDeployedAt: "2026-04-16T12:10:00Z"
                ),
                .init(
                    name: "failing",
                    summary: "Failing function",
                    verifyJWT: true,
                    sourcePath: "supabase/functions/failing/index.ts",
                    updatedAt: "2026-04-16T12:05:00Z",
                    lastDeployedAt: "2026-04-16T12:06:00Z"
                )
            ],
            recentFailures: [
                .init(
                    functionName: "failing",
                    timestamp: "2026-04-16T12:20:00Z",
                    errorSummary: "Returned 500",
                    source: .invoke
                )
            ]
        )

        XCTAssertEqual(state.attentionSortedFunctions.first?.name, "failing")
    }

    func testHasUnsyncedSecretsWhenAnySecretIsPendingRemoteSync() {
        let state = ProjectBackendState(
            secrets: [
                .init(name: "SYNCED", updatedAt: "2026-04-16T12:00:00Z", lastSyncedAt: "2026-04-16T12:01:00Z"),
                .init(name: "PENDING", updatedAt: "2026-04-16T12:02:00Z", lastSyncedAt: nil)
            ]
        )

        XCTAssertTrue(state.hasUnsyncedSecrets)
    }

    func testWithMergedLogsCreatesLogBackedFailure() {
        let state = ProjectBackendState().withMergedLogs([
            .init(
                id: "log_1",
                timestamp: "2026-04-16T12:00:00Z",
                message: "Webhook failed with 500",
                level: "error",
                functionName: "webhook"
            )
        ])

        XCTAssertEqual(state.openFailures.count, 1)
        XCTAssertEqual(state.openFailures.first?.functionName, "webhook")
        XCTAssertEqual(state.openFailures.first?.relatedLogIDs, ["log_1"])
        XCTAssertEqual(state.openFailures.first?.source, .logs)
    }

    func testMarkingFunctionDeployedResolvesMatchingFailures() {
        let state = ProjectBackendState(
            functions: [
                .init(
                    name: "ping",
                    summary: "Health check",
                    verifyJWT: true,
                    sourcePath: "supabase/functions/ping/index.ts",
                    updatedAt: "2026-04-16T12:00:00Z"
                )
            ],
            recentFailures: [
                .init(
                    id: "failure_1",
                    functionName: "ping",
                    timestamp: "2026-04-16T11:00:00Z",
                    errorSummary: "Returned 500",
                    source: .invoke
                )
            ]
        )

        let resolved = state.markingFunctionDeployed(named: "ping", at: "2026-04-16T12:30:00Z")

        XCTAssertEqual(resolved.openFailures.count, 0)
        XCTAssertEqual(resolved.recentFailures.first?.resolvedAt, "2026-04-16T12:30:00Z")
    }
}
