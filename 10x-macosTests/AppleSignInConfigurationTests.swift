import Foundation
import XCTest

final class AppleSignInConfigurationTests: XCTestCase {
    func testMacOSEntitlementsDoNotRequireNativeSignInWithApple() throws {
        let entitlementsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../10x-macos/10x_macos.entitlements")
            .standardizedFileURL

        let data = try Data(contentsOf: entitlementsURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertNil(plist["com.apple.developer.applesignin"])
    }
}
