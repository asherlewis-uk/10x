import Foundation
import XCTest
@testable import TenXAppCore

final class LocalEntitlementsTests: XCTestCase {

    // MARK: - Entitlement constants

    func testEntitlementModeIsSingleUserUnlimited() {
        XCTAssertEqual(LocalEntitlements.mode, "single_user_unlimited")
    }

    func testBillingIsDisabled() {
        XCTAssertFalse(LocalEntitlements.billingEnabled)
    }

    func testCreditsAreDisabled() {
        XCTAssertFalse(LocalEntitlements.creditsEnabled)
    }

    func testCreditsRemainingIsInfinite() {
        XCTAssertEqual(LocalEntitlements.creditsRemaining, Double.infinity)
    }

    func testCanGenerateIsTrue() {
        XCTAssertTrue(LocalEntitlements.canGenerate)
    }

    func testCanExportIsTrue() {
        XCTAssertTrue(LocalEntitlements.canExport)
    }

    func testCanUseLocalBackendIsTrue() {
        XCTAssertTrue(LocalEntitlements.canUseLocalBackend)
    }

    func testCanUseHostedVendorBackendIsFalse() {
        XCTAssertFalse(LocalEntitlements.canUseHostedVendorBackend)
    }

    func testCanUseBillingIsFalse() {
        XCTAssertFalse(LocalEntitlements.canUseBilling)
    }

    func testCanPurchaseCreditsIsFalse() {
        XCTAssertFalse(LocalEntitlements.canPurchaseCredits)
    }

    func testPaymentsAreDisabled() {
        XCTAssertFalse(LocalEntitlements.paymentsEnabled)
    }

    func testSignupBonusIsDisabled() {
        XCTAssertFalse(LocalEntitlements.signupBonusEnabled)
    }

    func testBillingTestModeIsTrue() {
        XCTAssertTrue(LocalEntitlements.billingTestMode)
    }

    func testUsageTrackingDoesNotGateFeatures() {
        XCTAssertFalse(LocalEntitlements.usageTrackingGatesFeatures)
    }

    // MARK: - Config integration

    func testConfigPaymentsEnabledMatchesLocalEntitlements() {
        XCTAssertEqual(Config.paymentsEnabled, LocalEntitlements.paymentsEnabled)
    }

    func testConfigSignupBonusEnabledMatchesLocalEntitlements() {
        XCTAssertEqual(Config.signupBonusEnabled, LocalEntitlements.signupBonusEnabled)
    }

    func testConfigBillingTestModeMatchesLocalEntitlements() {
        XCTAssertEqual(Config.billingTestMode, LocalEntitlements.billingTestMode)
    }

    // MARK: - Generation/export are never blocked

    func testGenerationIsNeverBlockedByCredits() {
        // Local entitlement always allows generation
        XCTAssertTrue(LocalEntitlements.canGenerate)
        // Credits are infinite, so no credit exhaustion is possible
        XCTAssertEqual(LocalEntitlements.creditsRemaining, Double.infinity)
        // Credits are disabled, so no credit check can block
        XCTAssertFalse(LocalEntitlements.creditsEnabled)
    }

    func testExportIsNeverBlockedByCredits() {
        // Local entitlement always allows export
        XCTAssertTrue(LocalEntitlements.canExport)
        // Billing is disabled, so no billing check can block
        XCTAssertFalse(LocalEntitlements.billingEnabled)
    }

    // MARK: - No billing/pricing/paywall routes

    func testBillingFlagsAreAllFalse() {
        XCTAssertFalse(LocalEntitlements.billingEnabled)
        XCTAssertFalse(LocalEntitlements.canUseBilling)
        XCTAssertFalse(LocalEntitlements.canPurchaseCredits)
        XCTAssertFalse(LocalEntitlements.paymentsEnabled)
        XCTAssertFalse(LocalEntitlements.signupBonusEnabled)
    }

    func testHostedVendorBackendIsDisabled() {
        XCTAssertFalse(LocalEntitlements.canUseHostedVendorBackend)
    }

    // MARK: - App identity badge

    func testAppIdentityBadgeReflectsUnlimitedLocal() {
        XCTAssertTrue(AppIdentity.localBadgeDetails.contains("Unlimited local"))
        XCTAssertTrue(AppIdentity.localBadgeDetails.contains("Local workspace"))
    }
}
