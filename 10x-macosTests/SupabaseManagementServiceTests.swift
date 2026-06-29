import Foundation
import XCTest
@testable import TenXAppCore

final class SupabaseManagementServiceTests: XCTestCase {
    func testParseProjectsAllowsEmptyList() throws {
        let data = try XCTUnwrap("[]".data(using: .utf8))

        let projects = try SupabaseManagementService.parseProjects(from: data)

        XCTAssertTrue(projects.isEmpty)
    }

    func testParseProjectsFallsBackToDatabaseHostForRef() throws {
        let data = try XCTUnwrap(
            """
            [
              {
                "id": "project-1",
                "name": "Acme",
                "status": "ACTIVE",
                "region": "us-east-1",
                "database": {
                  "host": "db.acmeproj.supabase.co"
                }
              }
            ]
            """.data(using: .utf8)
        )

        let projects = try SupabaseManagementService.parseProjects(from: data)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.id, "project-1")
        XCTAssertEqual(projects.first?.ref, "acmeproj")
        XCTAssertEqual(projects.first?.apiURL, "https://acmeproj.supabase.co")
    }

    func testParseOrganizationsExtractsNameAndSlug() throws {
        let data = try XCTUnwrap(
            """
            [
              {
                "id": "org-1",
                "name": "Acme",
                "slug": "acme"
              }
            ]
            """.data(using: .utf8)
        )

        let organizations = try SupabaseManagementService.parseOrganizations(from: data)

        XCTAssertEqual(organizations.count, 1)
        XCTAssertEqual(organizations.first?.id, "org-1")
        XCTAssertEqual(organizations.first?.name, "Acme")
        XCTAssertEqual(organizations.first?.slug, "acme")
    }

    func testParseOrganizationsSupportsWrappedPayload() throws {
        let data = try XCTUnwrap(
            """
            {
              "organizations": [
                {
                  "id": "org-2",
                  "slug": "beta"
                }
              ]
            }
            """.data(using: .utf8)
        )

        let organizations = try SupabaseManagementService.parseOrganizations(from: data)

        XCTAssertEqual(organizations.count, 1)
        XCTAssertEqual(organizations.first?.id, "org-2")
        XCTAssertEqual(organizations.first?.name, "beta")
        XCTAssertEqual(organizations.first?.slug, "beta")
    }

    func testParsePublishableKeyPrefersPublishableKey() throws {
        let data = try XCTUnwrap(
            """
            [
              {
                "name": "anon",
                "type": "legacy",
                "api_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.anon"
              },
              {
                "name": "publishable",
                "type": "publishable",
                "api_key": "sb_publishable_live_123"
              }
            ]
            """.data(using: .utf8)
        )

        let key = try SupabaseManagementService.parsePublishableKey(from: data)

        XCTAssertEqual(key, "sb_publishable_live_123")
    }

    func testParsePublishableKeyRejectsNonClientSafeKeys() throws {
        let data = try XCTUnwrap(
            """
            [
              {
                "name": "service_role",
                "type": "secret",
                "api_key": "sb_secret_live_123"
              },
              {
                "name": "service_role",
                "type": "legacy",
                "api_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.service"
              }
            ]
            """.data(using: .utf8)
        )

        XCTAssertThrowsError(try SupabaseManagementService.parsePublishableKey(from: data)) { error in
            guard case SupabaseManagementServiceError.missingPublishableKey = error else {
                return XCTFail("Expected missingPublishableKey, got \(error)")
            }
        }
    }



    func testSupabaseProjectBuildsDashboardAuthLinks() {
        let project = SupabaseManagementProject(
            id: "project-1",
            ref: "abc123",
            name: "Acme",
            status: nil,
            region: nil,
            databaseHost: nil
        )

        XCTAssertEqual(project.dashboardURL?.absoluteString, "https://supabase.com/dashboard/project/abc123")
        XCTAssertEqual(project.authProvidersDashboardURL?.absoluteString, "https://supabase.com/dashboard/project/abc123/auth/providers")
        XCTAssertEqual(project.authURLConfigurationDashboardURL?.absoluteString, "https://supabase.com/dashboard/project/abc123/auth/url-configuration")
        XCTAssertEqual(project.authTemplatesDashboardURL?.absoluteString, "https://supabase.com/dashboard/project/abc123/auth/templates")
    }




    func testProjectRefParsesFromApiUrlAndDatabaseHost() {
        XCTAssertEqual(
            SupabaseManagementService.projectRef(from: "https://abc123.supabase.co"),
            "abc123"
        )
        XCTAssertEqual(
            SupabaseManagementService.projectRef(from: "db.xyz789.supabase.co"),
            "xyz789"
        )
        XCTAssertNil(SupabaseManagementService.projectRef(from: "https://example.com"))
        XCTAssertNil(SupabaseManagementService.projectRef(from: "https://supabase.co"))
    }


}
