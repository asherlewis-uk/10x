import XCTest
@testable import TenXAppCore

final class XcodePreviewServiceTests: XCTestCase {
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
