import Foundation
import XCTest
@testable import TenXAppCore

final class NoSuperwallRuntimeTests: XCTestCase {
    /// No Swift source file under the runtime targets imports the Superwall module.
    func testNoRuntimeSuperwallImports() throws {
        let packageRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimeDirs = [
            packageRoot.appendingPathComponent("10x-macos"),
            packageRoot.appendingPathComponent("10x-evals"),
        ]
        let fm = FileManager.default
        var offenders: [String] = []
        for dir in runtimeDirs {
            guard fm.fileExists(atPath: dir.path) else { continue }
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let importLines = content.components(separatedBy: CharacterSet.newlines).filter { line in
                    let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
                    return trimmed.hasPrefix("import Superwall")
                }
                if !importLines.isEmpty {
                    offenders.append(fileURL.lastPathComponent)
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Found runtime source files still importing Superwall: \(offenders)")
    }

    /// Package.swift no longer depends on a Superwall product.
    func testPackageManifestHasNoSuperwallDependency() throws {
        let packageRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageSwift = packageRoot.appendingPathComponent("Package.swift")
        let content = try String(contentsOf: packageSwift, encoding: .utf8)
        XCTAssertFalse(content.contains("superwall"), "Package.swift still references Superwall")
    }

    /// Local entitlements block all Superwall/paywall behavior.
    func testLocalEntitlementsBlockSuperwallBehavior() {
        XCTAssertFalse(LocalEntitlements.canUseHostedVendorBackend)
        XCTAssertFalse(LocalEntitlements.canUseBilling)
        XCTAssertFalse(LocalEntitlements.canPurchaseCredits)
        XCTAssertFalse(LocalEntitlements.paymentsEnabled)
    }

    /// No active paywall/pricing route remains in settings.
    func testSettingsHasNoPaywallRoute() {
        let rawValues = Set(SettingsSection.allCases.map(\.rawValue))
        XCTAssertFalse(rawValues.contains("Billing"))
        XCTAssertFalse(rawValues.contains("Plans"))
        XCTAssertFalse(rawValues.contains("Paywall"))
    }

    /// No active Superwall management API endpoint is configured as a default.
    func testConfigHasNoSuperwallEndpointDefault() {
        XCTAssertTrue(Config.hostedAppsBaseURL.isEmpty)
        XCTAssertTrue(Config.sparkleFeedURL.isEmpty)
    }
}
