# Forbidden Audit Commands

Run these after each major pass and before final acceptance.

## Monetization / Billing

```bash
grep -RInE "Superwall|superwall|paywall|pricing|credits?|billing|subscription|purchase|receipt|StoreKit|RevenueCat|Stripe|checkout" . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=dist \
  --exclude-dir=build
```

## Supabase

```bash
grep -RInE "Supabase|supabase|@supabase|SUPABASE|anonKey|service_role|service-role|createClient" . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=dist \
  --exclude-dir=build
```

## Vendor Hosted / Updater / SaaS

```bash
grep -RInE "hosted|vendor|deploy|publish|submit|submission|App Store|app-store|analytics|telemetry|Sparkle|downloads.example|apiBaseURL" . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=dist \
  --exclude-dir=build
```

## Allowed Hits

Only these categories are allowed:

```text
AUDIT_LOCALIZATION.md
FINAL_RESEAT_REPORT.md
migration notes
legacy removal docs
tests asserting absence
comments explaining removed legacy behavior
```

## Active Runtime Violations

Any hit inside active runtime code must be classified as:

```text
delete
replace
stub local-only
test-only
documentation-only
false positive
```

No active violation can remain unresolved before final acceptance.
