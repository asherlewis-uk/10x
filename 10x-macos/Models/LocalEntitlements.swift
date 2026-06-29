import Foundation

/// Single source of truth for 11x local unlimited single-user entitlement.
/// Replaces all pricing, credits, billing, paywalls, subscriptions, checkout,
/// receipt validation, StoreKit purchase flows, and Superwall.
enum LocalEntitlements {
    /// The entitlement mode for the local cockpit.
    static let mode = "single_user_unlimited"

    /// Billing is permanently disabled in the local cockpit.
    static let billingEnabled = false

    /// Credits are permanently disabled in the local cockpit.
    static let creditsEnabled = false

    /// Credits are conceptually unlimited; never gate on this value.
    static let creditsRemaining = Double.infinity

    /// Generation is always allowed.
    static let canGenerate = true

    /// Export is always allowed.
    static let canExport = true

    /// Local backend is always available.
    static let canUseLocalBackend = true

    /// Hosted vendor backend is never available.
    static let canUseHostedVendorBackend = false

    /// Billing flows are never available.
    static let canUseBilling = false

    /// Credit purchases are never available.
    static let canPurchaseCredits = false

    /// Payments are permanently disabled.
    static let paymentsEnabled = false

    /// Signup bonus is permanently disabled.
    static let signupBonusEnabled = false

    /// Billing test mode is irrelevant; billing is always off.
    static let billingTestMode = true

    /// Usage tracking is local diagnostics only, never gating.
    static let usageTrackingGatesFeatures = false
}
