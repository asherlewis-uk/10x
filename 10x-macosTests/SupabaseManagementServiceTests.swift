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

    func testParseAuthProvidersExtractsAppleAndGoogleFlags() throws {
        let data = try XCTUnwrap(
            """
            {
              "disable_signup": false,
              "external_email_enabled": true,
              "mailer_autoconfirm": false,
              "external_phone_enabled": true,
              "sms_autoconfirm": true,
              "external_anonymous_users_enabled": false,
              "mailer_secure_email_change_enabled": true,
              "mailer_allow_unverified_email_sign_ins": false,
              "password_min_length": 12,
              "password_hibp_enabled": true,
              "refresh_token_rotation_enabled": true,
              "sessions_single_per_user": false,
              "security_update_password_require_reauthentication": true,
              "rate_limit_email_sent": 3,
              "rate_limit_sms_sent": 30,
              "external_apple_enabled": true,
              "external_google_enabled": false
            }
            """.data(using: .utf8)
        )

        let snapshot = try SupabaseManagementService.parseAuthProviders(from: data)

        XCTAssertEqual(snapshot.signupsEnabled, true)
        XCTAssertEqual(snapshot.emailEnabled, true)
        XCTAssertEqual(snapshot.emailConfirmationsEnabled, true)
        XCTAssertEqual(snapshot.phoneEnabled, true)
        XCTAssertEqual(snapshot.phoneConfirmationsEnabled, false)
        XCTAssertEqual(snapshot.anonymousUsersEnabled, false)
        XCTAssertEqual(snapshot.secureEmailChangeEnabled, true)
        XCTAssertEqual(snapshot.allowUnverifiedEmailSignIns, false)
        XCTAssertEqual(snapshot.passwordMinLength, 12)
        XCTAssertEqual(snapshot.leakedPasswordProtectionEnabled, true)
        XCTAssertEqual(snapshot.refreshTokenRotationEnabled, true)
        XCTAssertEqual(snapshot.singleSessionPerUser, false)
        XCTAssertEqual(snapshot.requireReauthenticationForPasswordChanges, true)
        XCTAssertEqual(snapshot.rateLimitEmailSent, 3)
        XCTAssertEqual(snapshot.rateLimitSMSSent, 30)
        XCTAssertEqual(snapshot.appleEnabled, true)
        XCTAssertEqual(snapshot.googleEnabled, false)
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

    func testRenderAuthProvidersIncludesDashboardLinksAndScopeGuidance() {
        let snapshot = SupabaseAuthProviderSnapshot(
            emailEnabled: true,
            emailConfirmationsEnabled: false,
            phoneEnabled: false,
            phoneConfirmationsEnabled: false,
            anonymousUsersEnabled: false,
            signupsEnabled: true,
            secureEmailChangeEnabled: true,
            allowUnverifiedEmailSignIns: false,
            passwordMinLength: 8,
            leakedPasswordProtectionEnabled: true,
            refreshTokenRotationEnabled: true,
            singleSessionPerUser: false,
            requireReauthenticationForPasswordChanges: false,
            rateLimitEmailSent: 3,
            rateLimitSMSSent: 30,
            appleEnabled: false,
            googleEnabled: false
        )

        let text = SupabaseManagementService.renderAuthProviders(
            snapshot,
            projectRef: "abc123",
            verb: "Current"
        )

        XCTAssertTrue(text.contains("Auth Providers: https://supabase.com/dashboard/project/abc123/auth/providers"))
        XCTAssertTrue(text.contains("URL Configuration: https://supabase.com/dashboard/project/abc123/auth/url-configuration"))
        XCTAssertTrue(text.contains("Email Templates: https://supabase.com/dashboard/project/abc123/auth/templates"))
        XCTAssertTrue(text.contains("App code: native Apple/Google sign-in UI"))
        XCTAssertTrue(text.contains("Supabase dashboard: provider enable toggles"))
        XCTAssertTrue(text.contains("Confirm Email is currently disabled"))
        XCTAssertTrue(text.contains("https://abc123.supabase.co/auth/v1/callback"))
    }

    func testParseSchemaPreviewBuildsTableGroups() throws {
        let data = try XCTUnwrap(
            """
            {
              "result": [
                {
                  "table_schema": "public",
                  "table_name": "profiles",
                  "column_name": "id",
                  "data_type": "uuid",
                  "ordinal_position": 1
                },
                {
                  "table_schema": "public",
                  "table_name": "profiles",
                  "column_name": "email",
                  "data_type": "text",
                  "ordinal_position": 2
                },
                {
                  "table_schema": "storage",
                  "table_name": "objects",
                  "column_name": "id",
                  "data_type": "uuid",
                  "ordinal_position": 1
                },
                {
                  "table_schema": "public",
                  "table_name": "schema_migrations",
                  "column_name": "version",
                  "data_type": "text",
                  "ordinal_position": 1
                }
              ]
            }
            """.data(using: .utf8)
        )

        let preview = try SupabaseManagementService.parseSchemaPreview(from: data)

        XCTAssertEqual(preview.sourceSummary, "Live schema · 1 user table")
        XCTAssertEqual(preview.tables.map(\.displayName), ["profiles"])
        XCTAssertEqual(preview.tables.first?.columns, ["id (uuid)", "email (text)"])
        XCTAssertTrue(preview.migrations.isEmpty)
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

    func testSupabaseTokenSessionRecognizesAllAndPersonalAccessTokens() {
        let allScopes = SupabaseManagementTokenStore.Session(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: nil,
            tokenType: "bearer",
            scope: "all"
        )
        XCTAssertTrue(allScopes.hasScopes(["edge_functions_write", "edge_functions_secrets_write"]))

        let personalToken = SupabaseManagementTokenStore.Session(
            accessToken: "pat",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: nil,
            scope: nil
        )
        XCTAssertTrue(personalToken.hasScopes(["edge_functions_write"]))
    }
}
