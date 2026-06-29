# Pass 11 — Build, Audit, and Release Packaging

## Goal

Produce a clean local build that can run beside the vendor DMG.

## Required Commands

Adapt to the repo's package manager/build system:

```bash
npm install
npm run typecheck
npm run lint
npm test
npm run build
```

or:

```bash
pnpm install
pnpm typecheck
pnpm lint
pnpm test
pnpm build
```

or equivalent.

## macOS App Checks

After building:

```bash
codesign -dv --verbose=4 path/to/10x-local.app 2>&1 || true
codesign --verify -vvv --deep --strict path/to/10x-local.app || true
spctl -a -vvv -t execute path/to/10x-local.app || true
plutil -p path/to/10x-local.app/Contents/Info.plist
```

## Identity Checks

Verify:

```text
App name is not vendor app name
Bundle ID is not vendor bundle ID
App support directory is isolated
Updater is disabled or owned
Keychain namespace is isolated
```

## Runtime Smoke Test

Verify:

```text
launch app
local mode badge visible
no login required
provider setup visible
project can be created
mock/local generation can run
generation persists after reload
asset writes to local filesystem
local export works
```

## Final Report

Create:

```text
FINAL_RESEAT_REPORT.md
```

Required sections:

```markdown
# Final Reseat Report

## Summary

## Commit List

## Files Changed

## Features Removed

## Features Replaced

## SQL Persistence

## Asset Storage

## Provider Adapter

## Local Entitlements

## UX Changes

## Tests Added

## Commands Run

## Results

## Forbidden Audit Results

## Remaining Hard Blockers

## Known Non-Goals
```

## Acceptance Criteria

- Build is separate from vendor DMG.
- Runtime works offline/local-first.
- Final report is complete.
- No unresolved blocker is hidden.
