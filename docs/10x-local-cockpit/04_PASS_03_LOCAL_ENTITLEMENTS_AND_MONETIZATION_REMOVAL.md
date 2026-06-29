# Pass 03 — Local Entitlements and Monetization Removal

## Goal

Replace pricing, credits, billing, paywall, subscriptions, checkout, receipt validation, and Superwall with a local unlimited single-user entitlement model.

## Design

Create one source of truth:

```text
localEntitlements
```

Example shape:

```ts
export const localEntitlements = {
  mode: "single_user_unlimited",
  billingEnabled: false,
  creditsEnabled: false,
  creditsRemaining: Number.POSITIVE_INFINITY,
  canGenerate: true,
  canExport: true,
  canUseLocalBackend: true,
  canUseHostedVendorBackend: false,
  canUseBilling: false,
  canPurchaseCredits: false,
}
```

## Rules

- Do not fake a paid state.
- Do not bypass vendor servers.
- Do not call vendor entitlement APIs.
- Delete or replace the entitlement boundary inside the fork.
- Usage tracking may remain as diagnostics only.
- Credits may remain only as legacy migration text or deleted terminology.
- Runtime UI must not present pricing, credits, subscriptions, paywalls, checkout, or purchase surfaces.

## Remove Completely

```text
Superwall SDK
paywall screens
pricing screens
credit purchase screens
subscription gates
checkout flows
receipt validation
StoreKit purchase flows
RevenueCat integration
Stripe checkout integration
billing analytics
conversion analytics
credit exhaustion errors
```

## Replace With

```text
local unlimited entitlement
local diagnostics usage log
setup guidance for model provider keys
clear local error states
```

## Suggested Searches

```bash
grep -RInE "Superwall|superwall|paywall|pricing|credits?|billing|subscription|purchase|receipt|StoreKit|RevenueCat|Stripe|checkout" .
```

## Tests

Add tests proving:

- No Superwall import remains.
- No billing SDK import remains.
- No paywall route/screen is reachable.
- No pricing route/screen is reachable.
- No credit exhaustion state can block generation.
- Local entitlement allows generation.
- Local entitlement allows export.
- Usage logs do not gate any feature.
- Billing flags are false.
- Hosted vendor backend entitlement is false.

## Acceptance Criteria

- Generation/export are never blocked by credits.
- No pricing/billing/paywall UI remains in runtime navigation.
- No monetization SDK remains in dependencies.
- Local entitlement is the only feature gate.
