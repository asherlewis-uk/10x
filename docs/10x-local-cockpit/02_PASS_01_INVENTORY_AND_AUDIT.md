# Pass 01 — Inventory and Audit

## Goal

Create a complete map of every vendor, hosted, monetization, Supabase, Superwall, app-store, marketing, and usage-gated dependency before changing behavior.

## Required Output

Create:

```text
AUDIT_LOCALIZATION.md
```

The audit must group findings by feature area.

## Search Terms

Run broad searches for:

```text
Superwall
superwall
pricing
price
credits
credit
billing
subscription
paywall
purchase
receipt
StoreKit
RevenueCat
Stripe
checkout
hosted
deploy
publish
submit
submission
app store
App Store
marketing
analytics
telemetry
apiBaseURL
baseURL
Supabase
supabase
@supabase
SUPABASE
anonKey
service_role
service-role
createClient
OpenAI
OPENAI
updater
Sparkle
downloads
feedURL
```

## Suggested Commands

```bash
grep -RInE "Superwall|superwall|pricing|price|credits?|billing|subscription|paywall|purchase|receipt|StoreKit|RevenueCat|Stripe|checkout" . > audit-monetization.txt || true

grep -RInE "Supabase|supabase|@supabase|SUPABASE|anonKey|service_role|service-role|createClient" . > audit-supabase.txt || true

grep -RInE "hosted|deploy|publish|submit|submission|App Store|app-store|marketing|analytics|telemetry" . > audit-hosted-marketing.txt || true

grep -RInE "apiBaseURL|baseURL|OpenAI|OPENAI|updater|Sparkle|downloads|feedURL" . > audit-config-provider-updater.txt || true
```

## AUDIT_LOCALIZATION.md Structure

```markdown
# Audit Localization

## Summary

## App Identity

## Vendor Backend / Hosted URLs

## Supabase Usage

### Auth

### Database

### Storage

### Realtime

### Edge Functions

### Generated Types

### Environment Variables

## Monetization

### Superwall

### Credits

### Pricing UI

### Billing / Subscription

### StoreKit / Receipt Validation

### Stripe / Checkout

## Hosted Capabilities

### Hosted Deploy

### Publishing

### App Store / Submission

### Marketing Assets / Flows

## Provider Integrations

### OpenAI

### Other Providers

### Secret Handling

## Updater

## Analytics / Telemetry

## Test Coverage Found

## Deletion Candidates

## Reseat Candidates

## Hard Unknowns
```

## Acceptance Criteria

- Every suspicious symbol or file is classified.
- No runtime behavior is changed in this pass.
- The audit distinguishes delete, replace, stub, and keep.
- The audit identifies which database option is least risky: SQLite or Postgres.
