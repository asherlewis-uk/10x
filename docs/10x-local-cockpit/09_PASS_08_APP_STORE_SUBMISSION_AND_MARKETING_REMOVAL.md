# Pass 08 — App Store Submission and Marketing Flow Removal

## Goal

Remove app-store/submission-related flows and marketing/asset-generation surfaces tied to the vendor SaaS product.

## Remove or Disable

```text
app-store submission flows
store listing generation tied to vendor pipeline
vendor marketing asset generation
vendor screenshot/metadata pipeline
paid launch flows
submission checklists tied to hosted account
vendor app review automation
public marketing pages inside app
conversion screens
upgrade copy
pricing plan comparison copy
```

## Keep Only If Localized

A feature may remain only if converted into a local non-billing tool, such as:

```text
generate local README
generate local icon assets
generate local screenshots
generate local metadata files
export marketing folder locally
```

It must not depend on:

```text
vendor account
vendor hosting
vendor credits
vendor app submission API
vendor billing
```

## Tests

Add tests proving:

- App-store submission routes/screens are gone or local-only.
- Marketing flows do not mention pricing/credits/vendor upgrade.
- Local asset export works without hosted backend.
- No vendor submission endpoint remains active.

## Acceptance Criteria

- The cockpit is not a vendor SaaS submission funnel.
- Any remaining marketing asset tool is local/export-only.
