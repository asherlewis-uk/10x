import XCTest
@testable import TenXAppCore

final class AppStoreSubmissionTests: XCTestCase {
    func testFactCollectorDetectsPermissionsBillingAuthAndPrivacyManifestSignals() {
        let snapshot = AppStoreSubmissionProjectSnapshot(
            projectName: "Atlas",
            projectDescription: "A paid app with sign-in and synced workouts.",
            projectPlan: "Uses Supabase auth, StoreKit subscriptions, and camera capture.",
            workspaceDescriptor: ProjectWorkspaceDescriptor(
                workspaceRootRelativePath: "ios/Atlas",
                xcodeContainerRelativePath: nil,
                xcodeContainerKind: nil,
                scheme: "Atlas",
                bundleIdentifier: "com.example.atlas",
                isImported: false
            ),
            fileTree: [
                "ios/Atlas/Info.plist": """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>NSCameraUsageDescription</key>
                    <string>Capture a profile photo.</string>
                    <key>NSMicrophoneUsageDescription</key>
                    <string>Record audio notes.</string>
                </dict>
                </plist>
                """,
                "ios/Atlas/Atlas.entitlements": """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>com.apple.developer.applesignin</key>
                    <array>
                        <string>Default</string>
                    </array>
                </dict>
                </plist>
                """,
                "ios/Atlas/PrivacyInfo.xcprivacy": """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>NSPrivacyTracking</key>
                    <true/>
                    <key>NSPrivacyTrackingDomains</key>
                    <array>
                        <string>ads.example.com</string>
                    </array>
                    <key>NSPrivacyAccessedAPITypes</key>
                    <array>
                        <dict>
                            <key>NSPrivacyAccessedAPIType</key>
                            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
                        </dict>
                    </array>
                </dict>
                </plist>
                """,
                "Views/AuthView.swift": """
                import SwiftUI
                import StoreKit

                struct AuthView: View {
                    var body: some View {
                        SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                    }
                }
                """,
            ],
            environmentValuesByKey: [
                "SUPABASE_URL": "https://example.supabase.co",
                "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
            ],
            dependencyManifest: ProjectDependencyManifest(
                dependencies: [
                    ProjectDependencyRequirement(
                        id: "supabase",
                        title: "Supabase",
                        summary: "Auth and data sync",
                        integrationID: .supabase,
                        envKeys: ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"],
                        safety: .clientRuntime,
                        allowsMockDataUntilConfigured: true
                    ),
                ]
            ),
            backendState: ProjectBackendState(
                providerID: .supabase,
                linkedProjectRef: "atlas",
                linkedProjectURL: "https://example.supabase.co"
            )
        )

        let facts = AppStoreSubmissionFactCollector.collect(from: snapshot)

        XCTAssertEqual(facts.bundleIdentifier, "com.example.atlas")
        XCTAssertEqual(facts.permissionUsageDescriptions["NSCameraUsageDescription"], "Capture a profile photo.")
        XCTAssertEqual(facts.permissionUsageDescriptions["NSMicrophoneUsageDescription"], "Record audio notes.")
        XCTAssertTrue(facts.collectsCameraData)
        XCTAssertTrue(facts.collectsMicrophoneData)
        XCTAssertTrue(facts.usesAccounts)
        XCTAssertTrue(facts.usesSubscriptions)
        XCTAssertTrue(facts.usesTracking)
        XCTAssertEqual(facts.backendProvider, "Supabase")
        XCTAssertEqual(facts.authProvider, "Supabase Auth")
        XCTAssertTrue(facts.entitlementKeys.contains("com.apple.developer.applesignin"))
        XCTAssertEqual(facts.privacyTrackingEnabled, true)
        XCTAssertEqual(facts.privacyTrackingDomains, ["ads.example.com"])
        XCTAssertEqual(
            facts.requiredReasonAPIs,
            ["NSPrivacyAccessedAPICategoryFileTimestamp"]
        )
        XCTAssertTrue(facts.integratedServices.contains("StoreKit"))
        XCTAssertTrue(facts.integratedServices.contains("Supabase"))
    }

    func testBuilderProjectDecodesAppStoreSubmissionDraftFromSettings() {
        let draft = AppStoreSubmissionDraft(
            facts: AppStoreSubmissionFacts(
                appName: "Atlas",
                companyName: "Atlas Labs",
                supportEmail: "support@example.com"
            ),
            generated: AppStoreSubmissionGenerated(
                privacy: AppStoreGeneratedDocument(
                    title: "Privacy Policy",
                    intro: ["Atlas respects your privacy."],
                    sections: [
                        AppStoreDocumentSection(
                            title: "Information We Collect",
                            bullets: ["Account details"]
                        ),
                    ]
                )
            ),
            confirmations: AppStoreSubmissionConfirmations(
                confirmedFields: ["support_contact": true]
            ),
            publish: AppStoreSubmissionPublishState(publicSlug: "atlas")
        )

        let project = BuilderProject(
            id: "project-1",
            userId: "user-1",
            name: "Atlas",
            description: nil,
            slug: "atlas",
            platform: "swiftui",
            status: "active",
            currentVersionId: nil,
            settings: [
                BuilderProject.appStoreSubmissionSettingsKey: AnyCodableValue.encode(draft) ?? .null,
            ],
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )

        XCTAssertEqual(project.appStoreSubmissionDraft, draft)
    }

    func testFactCollectorAvoidsFalsePositiveAccountsAndUGCSignals() {
        let snapshot = AppStoreSubmissionProjectSnapshot(
            projectName: "QuickTranslate",
            projectDescription: "A simple translation app.",
            projectPlan: "Translate text between languages with OpenAI.",
            workspaceDescriptor: ProjectWorkspaceDescriptor(
                workspaceRootRelativePath: "ios/QuickTranslate",
                xcodeContainerRelativePath: nil,
                xcodeContainerKind: nil,
                scheme: "QuickTranslate",
                bundleIdentifier: "com.example.quicktranslate",
                isImported: false
            ),
            fileTree: [
                "Services/TranslationService.swift": """
                import Foundation

                struct TranslationService {
                    func translate() {
                        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                        request.httpMethod = "POST"
                        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
                    }
                }
                """,
                "ViewModels/TranslationViewModel.swift": """
                import SwiftUI

                @Observable
                class TranslationViewModel {
                    var errorMessage: String?
                    var showCopiedFeedback = false
                }
                """,
            ],
            environmentValuesByKey: [:],
            dependencyManifest: nil,
            backendState: .empty
        )

        let facts = AppStoreSubmissionFactCollector.collect(from: snapshot)

        XCTAssertFalse(facts.usesAccounts)
        XCTAssertFalse(facts.hasUserGeneratedContent)
        XCTAssertEqual(facts.authProvider, "")
    }

    func testFactCollectorInfersEmailPasswordAccountsWithoutOAuthSDKs() {
        let snapshot = AppStoreSubmissionProjectSnapshot(
            projectName: "Stride",
            projectDescription: "A FIRE tracker with sign in and account data.",
            projectPlan: "Uses Supabase auth for email and password sign in.",
            workspaceDescriptor: ProjectWorkspaceDescriptor(
                workspaceRootRelativePath: "ios/Stride",
                xcodeContainerRelativePath: nil,
                xcodeContainerKind: nil,
                scheme: "Stride",
                bundleIdentifier: "com.example.stride",
                isImported: false
            ),
            fileTree: [
                "Views/AuthView.swift": """
                import SwiftUI

                struct AuthView: View {
                    @State private var isSignUp = false

                    var body: some View {
                        VStack {
                            Text(isSignUp ? "Create Account" : "Sign In")
                            Button("Sign Out") {}
                        }
                    }
                }
                """,
                "ViewModels/AppState.swift": """
                import SwiftUI

                @Observable
                class AppState {
                    var isAuthenticated = false
                }
                """,
            ],
            environmentValuesByKey: [
                "SUPABASE_URL": "https://example.supabase.co",
            ],
            dependencyManifest: nil,
            backendState: ProjectBackendState(
                providerID: .supabase,
                linkedProjectRef: "stride",
                linkedProjectURL: "https://example.supabase.co"
            )
        )

        let facts = AppStoreSubmissionFactCollector.collect(from: snapshot)

        XCTAssertTrue(facts.usesAccounts)
        XCTAssertEqual(facts.authProvider, "Supabase Auth")
    }

    func testFactCollectorIgnoresNonAuthSignUpCopyInContentData() {
        let snapshot = AppStoreSubmissionProjectSnapshot(
            projectName: "Nearby",
            projectDescription: "A read-only event board.",
            projectPlan: "Browse neighborhood events without accounts or sign in.",
            workspaceDescriptor: ProjectWorkspaceDescriptor(
                workspaceRootRelativePath: "ios/Nearby",
                xcodeContainerRelativePath: nil,
                xcodeContainerKind: nil,
                scheme: "Nearby",
                bundleIdentifier: "com.example.nearby",
                isImported: false
            ),
            fileTree: [
                "Models/Event.swift": """
                import Foundation

                struct Event {
                    let description = "Poets, comedians, singers, and storytellers — sign up at the door or just come to watch."
                }
                """,
                "Views/EventFeedView.swift": """
                import SwiftUI

                struct EventFeedView: View {
                    var body: some View { Text("Events") }
                }
                """,
            ],
            environmentValuesByKey: [:],
            dependencyManifest: nil,
            backendState: .empty
        )

        let facts = AppStoreSubmissionFactCollector.collect(from: snapshot)

        XCTAssertFalse(facts.usesAccounts)
        XCTAssertEqual(facts.authProvider, "")
        XCTAssertFalse(facts.supportsAccountDeletion)
    }

    func testPublishBlockersRequireGeneratedDocsAndConfirmedSupport() {
        let draft = AppStoreSubmissionDraft(
            facts: AppStoreSubmissionFacts(
                appName: "Atlas",
                companyName: "Atlas Labs"
            ),
            publish: AppStoreSubmissionPublishState(publicSlug: "atlas")
        )

        let blockers = draft.publishBlockers()

        XCTAssertTrue(blockers.contains("Generate privacy, terms, and support drafts before publishing."))
        XCTAssertTrue(blockers.contains("Add a support email before publishing."))
        XCTAssertTrue(blockers.contains("Confirm the support contact details before publishing."))
    }
}
