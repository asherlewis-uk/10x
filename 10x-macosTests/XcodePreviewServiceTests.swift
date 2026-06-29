import XCTest
@testable import TenXAppCore

final class XcodePreviewServiceTests: XCTestCase {
    func testCompileCheckPackageDoesNotIncludeSupabaseDependencyIn11x() {
        let packageSwift = XcodePreviewService.testingCompileCheckPackageContents(
            fileTree: [
                "Sources/SupabaseService.swift": """
                import Foundation
                """
            ]
        )

        XCTAssertFalse(packageSwift.contains("supabase-swift"))
        XCTAssertFalse(packageSwift.contains(".product(name: \"Supabase\""))
    }
}
