# Pass 02 — App Identity Isolation

## Goal

Make the forked app unable to collide with the downloaded vendor DMG.

## Required Changes

Change:

```text
Display name
Bundle identifier
App support directory
Preferences namespace
Keychain service namespace
Updater feed
Local storage namespace
Cache namespace
Log directory
Any app group identifiers
Any URL schemes, if needed
```

## Recommended Values

```text
Display name: 11x
Bundle identifier: app.kasey.11x
App support dir: ~/Library/Application Support/11x
Preferences prefix: app.kasey.11x
Keychain service: app.kasey.11x
Updater: disabled
```

## Required UI Signal

Add a visible local/dev indicator:

```text
11x
Single-user cockpit
Local backend
No billing
```

This prevents accidentally mistaking the fork for the vendor DMG.

## Suggested Searches

```bash
grep -RInE "CFBundleIdentifier|PRODUCT_BUNDLE_IDENTIFIER|CFBundleDisplayName|CFBundleName|Bundle Identifier|10x.app|10x" .
```

## Tests

Add tests or static assertions proving:

- Bundle identifier differs from the vendor app.
- App display name differs from the vendor app.
- Keychain namespace differs.
- App support path differs.
- Updater feed is disabled or owned.
- No vendor update URL remains active.

## Acceptance Criteria

- Vendor DMG and local fork can coexist.
- Installing/building the fork does not overwrite `/Applications/10x.app`.
- The local fork has separate storage, cache, preferences, and secrets.
