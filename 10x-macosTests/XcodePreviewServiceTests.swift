import XCTest
@testable import TenXAppCore

final class XcodePreviewServiceTests: XCTestCase {
    func testProjectYmlIncludesSuperwallPackageWhenFileTreeImportsSuperwallKit() {
        let projectYml = XcodePreviewService.testingProjectYmlContents(
            targetName: "PreviewApp",
            bundleId: "com.example.preview",
            displayName: "Preview App",
            fileTree: [
                "Sources/SuperwallService.swift": """
                import Foundation
                import SuperwallKit
                """
            ]
        )

        XCTAssertTrue(projectYml.contains("packages:"))
        XCTAssertTrue(projectYml.contains("Superwall:"))
        XCTAssertTrue(projectYml.contains("https://github.com/superwall/Superwall-iOS"))
        XCTAssertTrue(projectYml.contains("from: '4.0.0'"))
        XCTAssertTrue(projectYml.contains("- package: Superwall"))
        XCTAssertTrue(projectYml.contains("product: SuperwallKit"))
        XCTAssertTrue(projectYml.contains("ONLY_ACTIVE_ARCH: YES"))
    }

    func testProjectYmlIncludesSupabasePackageWhenFileTreeImportsSupabase() {
        let projectYml = XcodePreviewService.testingProjectYmlContents(
            targetName: "PreviewApp",
            bundleId: "com.example.preview",
            displayName: "Preview App",
            fileTree: [
                "Sources/SupabaseService.swift": """
                import Foundation
                import Supabase
                """
            ]
        )

        XCTAssertTrue(projectYml.contains("Supabase:"))
        XCTAssertTrue(projectYml.contains("https://github.com/supabase/supabase-swift"))
        XCTAssertTrue(projectYml.contains("from: '2.0.0'"))
        XCTAssertTrue(projectYml.contains("- package: Supabase"))
        XCTAssertTrue(projectYml.contains("product: Supabase"))
    }

    func testProjectYmlOmitsSuperwallPackageWithoutSuperwallImport() {
        let projectYml = XcodePreviewService.testingProjectYmlContents(
            targetName: "PreviewApp",
            bundleId: "com.example.preview",
            displayName: "Preview App",
            fileTree: [
                "Sources/ContentView.swift": """
                import SwiftUI
                """
            ]
        )

        XCTAssertFalse(projectYml.contains("Superwall:"))
        XCTAssertFalse(projectYml.contains("Superwall-iOS"))
        XCTAssertFalse(projectYml.contains("- package: Superwall"))
    }

    func testCompileCheckPackageIncludesSuperwallDependencyWhenImported() {
        let packageSwift = XcodePreviewService.testingCompileCheckPackageContents(
            fileTree: [
                "Sources/SuperwallService.swift": """
                @_exported import SuperwallKit
                """
            ]
        )

        XCTAssertTrue(packageSwift.contains(".package(url: \"https://github.com/superwall/Superwall-iOS\", from: \"4.0.0\")"))
        XCTAssertTrue(packageSwift.contains(".product(name: \"SuperwallKit\", package: \"Superwall-iOS\")"))
    }

    func testCompileCheckPackageIncludesSupabaseDependencyWhenImported() {
        let packageSwift = XcodePreviewService.testingCompileCheckPackageContents(
            fileTree: [
                "Sources/SupabaseService.swift": """
                import Supabase
                """
            ]
        )

        XCTAssertTrue(packageSwift.contains(".package(url: \"https://github.com/supabase/supabase-swift\", from: \"2.0.0\")"))
        XCTAssertTrue(packageSwift.contains(".product(name: \"Supabase\", package: \"supabase-swift\")"))
    }
}
