import XCTest
@testable import TenXAppCore

final class ProductionGuideTests: XCTestCase {
    func testSensitiveValuesAreBlankedForDisk() {
        let secret = ProjectEnvironmentVariable(
            key: "OPENAI_API_KEY",
            description: "OpenAI secret",
            value: "sk-test"
        )
        let plain = ProjectEnvironmentVariable(
            key: "PUBLIC_API_BASE_URL",
            description: "Public backend base URL",
            value: "https://api.example.com"
        )

        let sanitizedSecret = ProjectEnvironmentSecurity.sanitizedForDisk(secret)
        let sanitizedPlain = ProjectEnvironmentSecurity.sanitizedForDisk(plain)

        XCTAssertEqual(sanitizedSecret.value, "")
        XCTAssertEqual(sanitizedPlain.value, "https://api.example.com")
    }

    func testProductionGuideMentionsConfiguredKeysAndMinimumProductionInstructions() {
        let guide = ProductionGuideBuilder.build(
            projectName: "Atlas",
            fileTree: [
                "Views/HomeView.swift": "import SwiftUI",
                "Services/APIClient.swift": "import Foundation",
            ],
            environmentVariables: [
                ProjectEnvironmentVariable(key: "OPENAI_API_KEY", value: "sk-test"),
                ProjectEnvironmentVariable(key: "PUBLIC_API_BASE_URL", value: "https://api.example.com"),
                // Superwall removed in 11x local cockpit
            ]
        )

        XCTAssertTrue(guide.markdown.contains(ProductionGuideBuilder.generatedMarker))
        XCTAssertTrue(guide.markdown.contains("`OPENAI_API_KEY`"))
        XCTAssertTrue(guide.markdown.contains("`PUBLIC_API_BASE_URL`"))
        XCTAssertTrue(guide.markdown.contains("where auth, secrets, and durable data should live"))
        XCTAssertTrue(guide.markdown.contains("Supabase"))
        XCTAssertTrue(guide.markdown.contains("Supabase Edge Functions"))
        XCTAssertTrue(guide.markdown.contains("Use 10x Backend When"))
        XCTAssertTrue(guide.markdown.contains("`supabase/functions/<name>/index.ts`"))
        XCTAssertTrue(guide.markdown.contains("Move OpenAI traffic behind your backend"))
        XCTAssertTrue(guide.markdown.contains("Confirm backend secrets are synced remotely before TestFlight"))
        XCTAssertTrue(guide.markdown.contains("TestFlight"))
    }
}
